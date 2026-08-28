param(
    [string]$RepoRef,
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [string]$ExpectedRemoteIp = '192.168.0.224',
    [int]$ExpectedRemotePort = 8086,
    [int]$ObserveSeconds = 8,
    [int]$WatcherTimeoutSeconds = 20,
    [int]$ArmTimeoutSeconds = 10,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ONE-COMMAND ORCHESTRATOR V2.
# No manual timing and no second console.
# V2 uses a sidecar readiness file written by the debugger itself immediately after
# DR0/DR1 are armed. It does NOT wait for redirected stdout from Watch(), because
# that stdout is only emitted after the C# Watch() method returns.

if ([string]::IsNullOrWhiteSpace($RepoRef)) {
    throw 'Pass -RepoRef with the exact Git commit SHA supplied for this test.'
}
if ($ExpectedRemotePort -lt 1 -or $ExpectedRemotePort -gt 65535) { throw 'ExpectedRemotePort must be 1..65535.' }
if ($ObserveSeconds -lt 1 -or $ObserveSeconds -gt 60) { throw 'ObserveSeconds must be 1..60.' }
if ($WatcherTimeoutSeconds -lt 10 -or $WatcherTimeoutSeconds -gt 120) { throw 'WatcherTimeoutSeconds must be 10..120.' }
if ($ArmTimeoutSeconds -lt 2 -or $ArmTimeoutSeconds -gt 30) { throw 'ArmTimeoutSeconds must be 2..30.' }

New-Item -ItemType Directory -Path $ResearchRoot -Force | Out-Null

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

$ps32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $ps32)) { throw "32-bit Windows PowerShell not found: $ps32" }

$games = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -ieq 'game.dat' -and $_.ExecutablePath -eq $GameDat
})
if ($games.Count -ne 1) { throw "Expected exactly one game.dat at '$GameDat', found $($games.Count)." }
$pid32 = [int]$games[0].ProcessId

$baseRaw = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $RepoRef + '/tools/research/'
$watchPath   = Join-Path $ResearchRoot 'AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V2.ps1'
$joinPath    = Join-Path $ResearchRoot 'AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1'
$wrapperPath = Join-Path $ResearchRoot 'AOTR_WOTR_NATIVE_JOIN_CALL_POC_PS51_WRAPPER.ps1'

function Download-Tool([string]$name,[string]$dest) {
    $url = $baseRaw + $name
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest
    if (-not (Test-Path -LiteralPath $dest)) { throw "Download failed: $name" }
    $item = Get-Item -LiteralPath $dest
    if ($item.Length -lt 100) { throw "Downloaded tool looks too small: $name len=$($item.Length)" }
}

Download-Tool 'AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V2.ps1' $watchPath
Download-Tool 'AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1' $joinPath
Download-Tool 'AOTR_WOTR_NATIVE_JOIN_CALL_POC_PS51_WRAPPER.ps1' $wrapperPath

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$readyFile = Join-Path $ResearchRoot ("STATE8_READY_{0}.txt" -f $stamp)
$watchOut  = Join-Path $ResearchRoot ("STATE8_WATCH_{0}.out.txt" -f $stamp)
$watchErr  = Join-Path $ResearchRoot ("STATE8_WATCH_{0}.err.txt" -f $stamp)
$joinOut   = Join-Path $ResearchRoot ("LOWLEVEL_JOIN_{0}.out.txt" -f $stamp)
$joinErr   = Join-Path $ResearchRoot ("LOWLEVEL_JOIN_{0}.err.txt" -f $stamp)
$combined  = Join-Path $ResearchRoot ("LOWLEVEL_JOIN_COMPLETION_COMBINED_{0}.txt" -f $stamp)

foreach ($path in @($readyFile,$watchOut,$watchErr,$joinOut,$joinErr,$combined)) {
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}

function Read-TextSafe([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    try { return [string](Get-Content -LiteralPath $path -Raw -ErrorAction Stop) }
    catch { return '' }
}
function Add-QuotedArg([System.Collections.Generic.List[string]]$list,[string]$value) {
    $list.Add(('"{0}"' -f $value))
}
function Stop-ChildSafe($proc) {
    if ($null -eq $proc) { return }
    try { if (-not $proc.HasExited) { $proc.Kill() } } catch {}
}

Write-Host '============================================================'
Write-Host ' AOTR WOTR LOWLEVEL JOIN COMPLETION ORCHESTRATOR V2'
Write-Host '============================================================'
Write-Host ("Repo ref       : {0}" -f $RepoRef)
Write-Host ("Game PID       : {0}" -f $pid32)
Write-Host ("Image          : {0}" -f $GameDat)
Write-Host ("SHA256         : {0}" -f $hash)
Write-Host ("Expected host  : {0}:{1}" -f $ExpectedRemoteIp,$ExpectedRemotePort)
Write-Host ''
Write-Host 'PRECONDITION: VM is in normal game browser, host lobby visible, Join NOT clicked.'
Write-Host 'From here the test is fully automatic.'
Write-Host ''

$watchProc = $null
$joinProc = $null
try {
    $watchArgs = New-Object 'System.Collections.Generic.List[string]'
    $watchArgs.Add('-NoProfile')
    $watchArgs.Add('-ExecutionPolicy'); $watchArgs.Add('Bypass')
    $watchArgs.Add('-File'); Add-QuotedArg $watchArgs $watchPath
    $watchArgs.Add('-ProcessId'); $watchArgs.Add([string]$pid32)
    $watchArgs.Add('-GameDat'); Add-QuotedArg $watchArgs $GameDat
    $watchArgs.Add('-TimeoutSeconds'); $watchArgs.Add([string]$WatcherTimeoutSeconds)
    $watchArgs.Add('-ReadyFile'); Add-QuotedArg $watchArgs $readyFile

    $watchProc = Start-Process -FilePath $ps32 -ArgumentList ($watchArgs -join ' ') -RedirectStandardOutput $watchOut -RedirectStandardError $watchErr -PassThru
    Write-Host ("WATCHER_STARTED PID={0}" -f $watchProc.Id)

    $armDeadline = [DateTime]::UtcNow.AddSeconds($ArmTimeoutSeconds)
    $ready = $false
    $armedCount = 0
    $readyText = ''

    while ([DateTime]::UtcNow -lt $armDeadline) {
        Start-Sleep -Milliseconds 50
        $readyText = Read-TextSafe $readyFile
        if ($readyText -match 'STATUS=READY') {
            if ($readyText -match 'ARMED_THREADS=(\d+)') { $armedCount = [int]$Matches[1] }
            if ($armedCount -gt 0) { $ready = $true; break }
        }
        if ($readyText -match 'STATUS=FAIL') { break }
        if ($watchProc.HasExited) { break }
    }

    if (-not $ready) {
        $wo = Read-TextSafe $watchOut
        $we = Read-TextSafe $watchErr
        Stop-ChildSafe $watchProc
        throw ("WATCHER_READY_FAILED`n--- READY ---`n{0}`n--- WATCH OUT ---`n{1}`n--- WATCH ERR ---`n{2}" -f $readyText,$wo,$we)
    }

    Write-Host ("WATCHER_READY ARMED_THREADS={0}" -f $armedCount) -ForegroundColor Green

    # Only after the debugger has explicitly signaled readiness do we launch the join.
    $joinArgs = New-Object 'System.Collections.Generic.List[string]'
    $joinArgs.Add('-NoProfile')
    $joinArgs.Add('-ExecutionPolicy'); $joinArgs.Add('Bypass')
    $joinArgs.Add('-File'); Add-QuotedArg $joinArgs $wrapperPath
    $joinArgs.Add('-SourcePath'); Add-QuotedArg $joinArgs $joinPath
    $joinArgs.Add('-ProcessId'); $joinArgs.Add([string]$pid32)
    $joinArgs.Add('-ExpectedRemoteIp'); Add-QuotedArg $joinArgs $ExpectedRemoteIp
    $joinArgs.Add('-ExpectedRemotePort'); $joinArgs.Add([string]$ExpectedRemotePort)
    $joinArgs.Add('-ObserveSeconds'); $joinArgs.Add([string]$ObserveSeconds)
    $joinArgs.Add('-Execute')

    $joinProc = Start-Process -FilePath $ps32 -ArgumentList ($joinArgs -join ' ') -RedirectStandardOutput $joinOut -RedirectStandardError $joinErr -PassThru
    Write-Host ("JOIN_STARTED PID={0}" -f $joinProc.Id)
    $joinProc.WaitForExit()
    Write-Host ("JOIN_EXIT_CODE={0}" -f $joinProc.ExitCode)

    # Watcher either stops at the completion breakpoint or expires at its own timeout.
    $watchWaitMs = ($WatcherTimeoutSeconds + 8) * 1000
    if (-not $watchProc.WaitForExit($watchWaitMs)) {
        Stop-ChildSafe $watchProc
        throw "Watcher exceeded expected completion window ($watchWaitMs ms)."
    }
    Write-Host ("WATCHER_EXIT_CODE={0}" -f $watchProc.ExitCode)

    $jo = Read-TextSafe $joinOut
    $je = Read-TextSafe $joinErr
    $wo = Read-TextSafe $watchOut
    $we = Read-TextSafe $watchErr

    $joinReturned      = ($jo -match 'NATIVE \+0x40 CALL RETURNED = YES')
    $joinObserved      = ($jo -match 'NATIVE_JOIN_STATE_OBSERVED = YES')
    $currentC54        = ($jo -match 'current vtable\s+:\s+0x00C54B78.*match=True')
    $de892cStayedNull  = ($jo -match 'DE892C after\s+:\s+0x00000000')
    $callbackHit       = if ($wo -match 'CALLBACK_8496C2_HIT=(YES|NO)') { $Matches[1] } else { 'MISSING' }
    $completionHit     = if ($wo -match 'COMPLETION_84944F_HIT=(YES|NO)') { $Matches[1] } else { 'MISSING' }
    $valid             = $joinReturned -and $joinObserved -and $currentC54 -and $de892cStayedNull

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('============================================================')
    $lines.Add(' AOTR WOTR LOWLEVEL JOIN COMPLETION - COMBINED RESULT V2')
    $lines.Add('============================================================')
    $lines.Add(("Timestamp               : {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    $lines.Add(("RepoRef                 : {0}" -f $RepoRef))
    $lines.Add(("Game PID                : {0}" -f $pid32))
    $lines.Add(("SHA256                  : {0}" -f $hash))
    $lines.Add(("ARMED_THREADS           : {0}" -f $armedCount))
    $lines.Add('')
    $lines.Add('================ AUTOMATED VERDICT INPUTS ================')
    $lines.Add(("JOIN_RETURNED            : {0}" -f $(if($joinReturned){'YES'}else{'NO'})))
    $lines.Add(("JOIN_STATE_OBSERVED      : {0}" -f $(if($joinObserved){'YES'}else{'NO'})))
    $lines.Add(("CURRENT_C54B78           : {0}" -f $(if($currentC54){'YES'}else{'NO'})))
    $lines.Add(("DE892C_STAYED_NULL       : {0}" -f $(if($de892cStayedNull){'YES'}else{'NO'})))
    $lines.Add(("TEST_VALID_FOR_STATE8    : {0}" -f $(if($valid){'YES'}else{'NO'})))
    $lines.Add(("CALLBACK_8496C2_HIT      : {0}" -f $callbackHit))
    $lines.Add(("COMPLETION_84944F_HIT    : {0}" -f $completionHit))
    $lines.Add('')
    $lines.Add('================ WATCHER READY ================')
    $lines.Add($readyText.TrimEnd())
    $lines.Add('')
    $lines.Add('================ JOIN STDOUT ================')
    $lines.Add($jo.TrimEnd())
    if (-not [string]::IsNullOrWhiteSpace($je)) {
        $lines.Add('')
        $lines.Add('================ JOIN STDERR ================')
        $lines.Add($je.TrimEnd())
    }
    $lines.Add('')
    $lines.Add('================ WATCHER STDOUT ================')
    $lines.Add($wo.TrimEnd())
    if (-not [string]::IsNullOrWhiteSpace($we)) {
        $lines.Add('')
        $lines.Add('================ WATCHER STDERR ================')
        $lines.Add($we.TrimEnd())
    }

    $lines | Set-Content -LiteralPath $combined -Encoding UTF8
    Write-Host ''
    Write-Host ("COMBINED_RESULT={0}" -f $combined) -ForegroundColor Green
    Write-Host ''
    Get-Content -LiteralPath $combined
}
finally {
    # Never leave helper processes behind if any stage fails.
    Stop-ChildSafe $joinProc
    Stop-ChildSafe $watchProc
}
