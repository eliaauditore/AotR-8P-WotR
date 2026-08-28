param(
    [string]$RepoRef,
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [string]$ExpectedRemoteIp = '192.168.0.224',
    [int]$ExpectedRemotePort = 8086,
    [int]$ObserveSeconds = 8,
    [int]$WatcherTimeoutSeconds = 30,
    [int]$WaitForGameSeconds = 120,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRef)) { throw 'Pass -RepoRef with the exact Git commit SHA.' }
New-Item -ItemType Directory -Path $ResearchRoot -Force | Out-Null

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

$ps32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $ps32)) { throw "32-bit Windows PowerShell not found: $ps32" }

function Read-TextSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    try { return [string](Get-Content -LiteralPath $Path -Raw -ErrorAction Stop) } catch { return '' }
}
function Quote([string]$s) { return ('"{0}"' -f $s) }
function Stop-ProcSafe($p) { if ($null -eq $p) { return }; try { if (-not $p.HasExited) { $p.Kill() } } catch {} }
function Start-Ps32Hidden([string[]]$Args,[string]$Out,[string]$Err) {
    return Start-Process -FilePath $ps32 -ArgumentList ($Args -join ' ') -WindowStyle Hidden -RedirectStandardOutput $Out -RedirectStandardError $Err -PassThru
}

Write-Host '============================================================'
Write-Host ' AOTR WOTR LOWLEVEL JOIN COMPLETION ORCHESTRATOR V3'
Write-Host '============================================================'
Write-Host ("Repo ref       : {0}" -f $RepoRef)
Write-Host ("Image          : {0}" -f $GameDat)
Write-Host ("SHA256         : {0}" -f $hash)
Write-Host ("Expected host  : {0}:{1}" -f $ExpectedRemoteIp,$ExpectedRemotePort)
Write-Host ''

$deadline = [DateTime]::UtcNow.AddSeconds($WaitForGameSeconds)
$pid32 = 0
$announcedWait = $false
while ([DateTime]::UtcNow -lt $deadline) {
    $games = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'game.dat' -and $_.ExecutablePath -ieq $GameDat })
    if ($games.Count -gt 1) { throw "Expected at most one game.dat at '$GameDat', found $($games.Count)." }
    if ($games.Count -eq 1) { $pid32 = [int]$games[0].ProcessId; break }
    if (-not $announcedWait) { Write-Host 'WAITING_FOR_GAME - start AotR on the VM and enter the normal game browser.' -ForegroundColor Yellow; $announcedWait = $true }
    Start-Sleep -Milliseconds 500
}
if ($pid32 -le 0) { throw "No game.dat appeared within $WaitForGameSeconds seconds." }
Write-Host ("GAME_FOUND PID={0}" -f $pid32) -ForegroundColor Green
Write-Host 'PRECONDITION: host lobby visible in VM browser; do NOT click Join.'
Write-Host ''

$baseRaw = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $RepoRef + '/tools/research/'
$watchPath   = Join-Path $ResearchRoot 'AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V4.ps1'
$joinPath    = Join-Path $ResearchRoot 'AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1'
$wrapperPath = Join-Path $ResearchRoot 'AOTR_WOTR_NATIVE_JOIN_CALL_POC_PS51_WRAPPER.ps1'

function Download-Tool([string]$Name,[string]$Dest) {
    Invoke-WebRequest -UseBasicParsing -Uri ($baseRaw + $Name) -OutFile $Dest
    $i = Get-Item -LiteralPath $Dest -ErrorAction Stop
    if ($i.Length -lt 100) { throw "Downloaded tool looks invalid: $Name len=$($i.Length)" }
}

Download-Tool 'AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V4.ps1' $watchPath
Download-Tool 'AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1' $joinPath
Download-Tool 'AOTR_WOTR_NATIVE_JOIN_CALL_POC_PS51_WRAPPER.ps1' $wrapperPath

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$preOut    = Join-Path $ResearchRoot "PREFLIGHT_$stamp.out.txt"
$preErr    = Join-Path $ResearchRoot "PREFLIGHT_$stamp.err.txt"
$readyFile = Join-Path $ResearchRoot "STATE8_READY_$stamp.txt"
$stopFile  = Join-Path $ResearchRoot "STATE8_STOP_$stamp.txt"
$statusFile= Join-Path $ResearchRoot "STATE8_STATUS_$stamp.txt"
$watchOut  = Join-Path $ResearchRoot "STATE8_WATCH_$stamp.out.txt"
$watchErr  = Join-Path $ResearchRoot "STATE8_WATCH_$stamp.err.txt"
$joinOut   = Join-Path $ResearchRoot "LOWLEVEL_JOIN_$stamp.out.txt"
$joinErr   = Join-Path $ResearchRoot "LOWLEVEL_JOIN_$stamp.err.txt"
$combined  = Join-Path $ResearchRoot "LOWLEVEL_JOIN_COMPLETION_COMBINED_$stamp.txt"
foreach ($f in @($preOut,$preErr,$readyFile,$stopFile,$statusFile,$watchOut,$watchErr,$joinOut,$joinErr,$combined)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }

# Phase 1: dry-run the exact join contract BEFORE attaching any debugger.
Write-Host 'PHASE 1/3 PREFLIGHT - validating pre-join contract...'
$preArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote $wrapperPath),'-SourcePath',(Quote $joinPath),'-ProcessId',[string]$pid32,'-ExpectedRemoteIp',(Quote $ExpectedRemoteIp),'-ExpectedRemotePort',[string]$ExpectedRemotePort,'-ObserveSeconds',[string]$ObserveSeconds)
$pre = Start-Ps32Hidden $preArgs $preOut $preErr
if (-not $pre.WaitForExit(15000)) { Stop-ProcSafe $pre; throw 'PREFLIGHT_TIMEOUT. No debugger or join was started.' }
$preText = Read-TextSafe $preOut
$preErrText = Read-TextSafe $preErr
if ($pre.ExitCode -ne 0 -or $preText -notmatch 'CALL_POC_READY = YES') {
    throw ("PREFLIGHT_FAILED - no debugger/join executed.`n--- OUT ---`n{0}`n--- ERR ---`n{1}" -f $preText,$preErrText)
}
Write-Host 'PREFLIGHT_PASS' -ForegroundColor Green

# Phase 2: attach and arm watcher. No join is allowed before explicit READY.
Write-Host 'PHASE 2/3 WATCHER - attaching and arming hidden debugger...'
$watchArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote $watchPath),'-ProcessId',[string]$pid32,'-GameDat',(Quote $GameDat),'-TimeoutSeconds',[string]$WatcherTimeoutSeconds,'-ReadyFile',(Quote $readyFile),'-StopFile',(Quote $stopFile),'-StatusFile',(Quote $statusFile))
$watch = Start-Ps32Hidden $watchArgs $watchOut $watchErr
Write-Host ("WATCHER_STARTED PID={0}" -f $watch.Id)

$readyDeadline = [DateTime]::UtcNow.AddSeconds(10)
$armedCount = 0
$readyText = ''
while ([DateTime]::UtcNow -lt $readyDeadline) {
    Start-Sleep -Milliseconds 50
    $readyText = Read-TextSafe $readyFile
    if ($readyText -match 'STATUS=READY' -and $readyText -match 'ARMED_THREADS=(\d+)') { $armedCount = [int]$Matches[1]; if ($armedCount -gt 0) { break } }
    if ($readyText -match 'STATUS=FAIL' -or $watch.HasExited) { break }
}
if ($armedCount -le 0) {
    Set-Content -LiteralPath $stopFile -Value 'STOP=1' -Encoding ASCII -ErrorAction SilentlyContinue
    [void]$watch.WaitForExit(5000)
    Stop-ProcSafe $watch
    throw ("WATCHER_READY_FAILED - join was NOT started.`n--- READY ---`n{0}`n--- STATUS ---`n{1}`n--- OUT ---`n{2}`n--- ERR ---`n{3}" -f $readyText,(Read-TextSafe $statusFile),(Read-TextSafe $watchOut),(Read-TextSafe $watchErr))
}
Write-Host ("WATCHER_READY ARMED_THREADS={0}" -f $armedCount) -ForegroundColor Green

# Phase 3: execute exactly one native join; after its observation window, request clean watcher teardown.
Write-Host 'PHASE 3/3 JOIN - executing one native +0x40 call...'
$joinArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote $wrapperPath),'-SourcePath',(Quote $joinPath),'-ProcessId',[string]$pid32,'-ExpectedRemoteIp',(Quote $ExpectedRemoteIp),'-ExpectedRemotePort',[string]$ExpectedRemotePort,'-ObserveSeconds',[string]$ObserveSeconds,'-Execute')
$join = Start-Ps32Hidden $joinArgs $joinOut $joinErr
Write-Host ("JOIN_STARTED PID={0}" -f $join.Id)
if (-not $join.WaitForExit(25000)) {
    Set-Content -LiteralPath $stopFile -Value 'STOP=1' -Encoding ASCII
    [void]$watch.WaitForExit(6000)
    Stop-ProcSafe $join; Stop-ProcSafe $watch
    throw ("JOIN_TIMEOUT. Watcher stop requested.`nWATCH_STATUS={0}" -f (Read-TextSafe $statusFile))
}
Write-Host ("JOIN_EXIT_CODE={0}" -f $join.ExitCode)
Start-Sleep -Milliseconds 1000
Set-Content -LiteralPath $stopFile -Value 'STOP=1' -Encoding ASCII
Write-Host 'WATCHER_STOP_REQUESTED'

if (-not $watch.WaitForExit(8000)) {
    $status = Read-TextSafe $statusFile
    $wo = Read-TextSafe $watchOut
    $we = Read-TextSafe $watchErr
    Stop-ProcSafe $watch
    throw ("WATCHER_TEARDOWN_FAILED. Restart game.dat before any further debugger test.`n--- STATUS ---`n{0}`n--- OUT ---`n{1}`n--- ERR ---`n{2}" -f $status,$wo,$we)
}
Write-Host ("WATCHER_EXIT_CODE={0}" -f $watch.ExitCode)

$jo = Read-TextSafe $joinOut
$je = Read-TextSafe $joinErr
$wo = Read-TextSafe $watchOut
$we = Read-TextSafe $watchErr
$status = Read-TextSafe $statusFile

$joinReturned     = ($jo -match 'NATIVE \+0x40 CALL RETURNED = YES')
$joinObserved     = ($jo -match 'NATIVE_JOIN_STATE_OBSERVED = YES')
$currentC54       = ($jo -match 'current vtable\s+:\s+0x00C54B78.*match=True')
$de892cStayedNull = ($jo -match 'DE892C after\s+:\s+0x00000000')
$callbackHit      = if ($wo -match 'CALLBACK_8496C2_HIT=(YES|NO)') { $Matches[1] } else { 'MISSING' }
$completionHit    = if ($wo -match 'COMPLETION_84944F_HIT=(YES|NO)') { $Matches[1] } else { 'MISSING' }
$watchDone        = ($status -match 'STAGE=DONE')
$valid = $joinReturned -and $joinObserved -and $currentC54 -and $de892cStayedNull -and $watchDone

$lines = New-Object 'System.Collections.Generic.List[string]'
$lines.Add('============================================================')
$lines.Add(' AOTR WOTR LOWLEVEL JOIN COMPLETION - COMBINED RESULT V3')
$lines.Add('============================================================')
$lines.Add(("RepoRef                  : {0}" -f $RepoRef))
$lines.Add(("Game PID                 : {0}" -f $pid32))
$lines.Add(("ARMED_THREADS            : {0}" -f $armedCount))
$lines.Add('')
$lines.Add('================ VERDICT INPUTS ================')
$lines.Add(("PREFLIGHT_PASS            : YES"))
$lines.Add(("JOIN_RETURNED             : {0}" -f $(if($joinReturned){'YES'}else{'NO'})))
$lines.Add(("JOIN_STATE_OBSERVED       : {0}" -f $(if($joinObserved){'YES'}else{'NO'})))
$lines.Add(("CURRENT_C54B78            : {0}" -f $(if($currentC54){'YES'}else{'NO'})))
$lines.Add(("DE892C_STAYED_NULL        : {0}" -f $(if($de892cStayedNull){'YES'}else{'NO'})))
$lines.Add(("WATCHER_CLEAN_EXIT        : {0}" -f $(if($watchDone){'YES'}else{'NO'})))
$lines.Add(("TEST_VALID_FOR_STATE8     : {0}" -f $(if($valid){'YES'}else{'NO'})))
$lines.Add(("CALLBACK_8496C2_HIT       : {0}" -f $callbackHit))
$lines.Add(("COMPLETION_84944F_HIT     : {0}" -f $completionHit))
$lines.Add('')
$lines.Add('================ WATCHER STATUS ================')
$lines.Add($status.TrimEnd())
$lines.Add('')
$lines.Add('================ JOIN STDOUT ================')
$lines.Add($jo.TrimEnd())
if ($je.Trim()) { $lines.Add(''); $lines.Add('================ JOIN STDERR ================'); $lines.Add($je.TrimEnd()) }
$lines.Add('')
$lines.Add('================ WATCHER STDOUT ================')
$lines.Add($wo.TrimEnd())
if ($we.Trim()) { $lines.Add(''); $lines.Add('================ WATCHER STDERR ================'); $lines.Add($we.TrimEnd()) }
$lines | Set-Content -LiteralPath $combined -Encoding UTF8

Write-Host ''
Write-Host ("COMBINED_RESULT={0}" -f $combined) -ForegroundColor Green
Write-Host ''
Get-Content -LiteralPath $combined
