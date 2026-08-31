param(
    [string]$RepoRef,
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [string]$ExpectedRemoteIp = '192.168.0.224',
    [int]$ExpectedRemotePort = 8086,
    [int]$ObserveSeconds = 8,
    [int]$WatcherTimeoutSeconds = 60,
    [int]$WaitForGameSeconds = 120,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRef)) { throw 'Pass -RepoRef with the exact Git commit SHA.' }
if ($ExpectedRemotePort -lt 1 -or $ExpectedRemotePort -gt 65535) { throw 'ExpectedRemotePort must be 1..65535.' }
if ($ObserveSeconds -lt 1 -or $ObserveSeconds -gt 60) { throw 'ObserveSeconds must be 1..60.' }
if ($WatcherTimeoutSeconds -lt 20 -or $WatcherTimeoutSeconds -gt 120) { throw 'WatcherTimeoutSeconds must be 20..120.' }
if ($WaitForGameSeconds -lt 1 -or $WaitForGameSeconds -gt 600) { throw 'WaitForGameSeconds must be 1..600.' }

New-Item -ItemType Directory -Path $ResearchRoot -Force | Out-Null

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

$ps32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $ps32)) { throw "32-bit Windows PowerShell not found: $ps32" }

function Read-TextSafe {
    param([Parameter(Mandatory=$true)][string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { return '' }
    try { return [string](Get-Content -LiteralPath $FilePath -Raw -ErrorAction Stop) } catch { return '' }
}
function Quote-Arg {
    param([Parameter(Mandatory=$true)][string]$Value)
    if ($Value.Contains('"')) { throw "Quote-Arg does not accept embedded double quotes: $Value" }
    return ('"{0}"' -f $Value)
}
function Stop-ProcSafe {
    param($ProcessObject)
    if ($null -eq $ProcessObject) { return }
    try { if (-not $ProcessObject.HasExited) { $ProcessObject.Kill() } } catch {}
}
function Start-Ps32Hidden {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string[]]$ChildArguments,
        [Parameter(Mandatory=$true)][string]$StdOutPath,
        [Parameter(Mandatory=$true)][string]$StdErrPath
    )
    if ($null -eq $ChildArguments -or $ChildArguments.Count -eq 0) { throw 'Start-Ps32Hidden received no child arguments.' }
    foreach ($item in $ChildArguments) {
        if ($null -eq $item -or [string]::IsNullOrWhiteSpace([string]$item)) { throw 'Start-Ps32Hidden received a null/empty child argument.' }
    }
    return Start-Process -FilePath $ps32 -ArgumentList $ChildArguments -WindowStyle Hidden -RedirectStandardOutput $StdOutPath -RedirectStandardError $StdErrPath -PassThru
}
function Assert-PowerShellSyntax {
    param([Parameter(Mandatory=$true)][string]$FilePath)
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($FilePath,[ref]$tokens,[ref]$parseErrors)
    if ($null -ne $parseErrors -and $parseErrors.Count -gt 0) {
        $text=($parseErrors|ForEach-Object{"line $($_.Extent.StartLineNumber): $($_.Message)"}) -join "`n"
        throw "PowerShell syntax validation failed for $FilePath`n$text"
    }
}

Write-Host '============================================================'
Write-Host ' AOTR WOTR LOWLEVEL JOIN COMPLETION ORCHESTRATOR V5'
Write-Host '============================================================'
Write-Host ("Repo ref       : {0}" -f $RepoRef)
Write-Host ("Image          : {0}" -f $GameDat)
Write-Host ("SHA256         : {0}" -f $hash)
Write-Host ("Expected host  : {0}:{1}" -f $ExpectedRemoteIp,$ExpectedRemotePort)
Write-Host ''

Write-Host 'PHASE 0/5 TOOLING SELFTEST - validating hidden 32-bit PowerShell child launch...'
$selfStamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$selfOut=Join-Path $ResearchRoot "ORCH_SELFTEST_$selfStamp.out.txt"
$selfErr=Join-Path $ResearchRoot "ORCH_SELFTEST_$selfStamp.err.txt"
Remove-Item -LiteralPath $selfOut,$selfErr -Force -ErrorAction SilentlyContinue
$selfArgs=@('-NoProfile','-Command',(Quote-Arg "Write-Output 'PS32_CHILD_OK'"))
$selfProc=Start-Ps32Hidden -ChildArguments $selfArgs -StdOutPath $selfOut -StdErrPath $selfErr
if (-not $selfProc.WaitForExit(5000)) { Stop-ProcSafe -ProcessObject $selfProc; throw 'TOOLING_SELFTEST_TIMEOUT. No debugger or game call was attempted.' }
$selfText=Read-TextSafe -FilePath $selfOut
$selfErrText=Read-TextSafe -FilePath $selfErr
if ($selfText.Trim() -ne 'PS32_CHILD_OK') { throw ("TOOLING_SELFTEST_FAILED. No debugger or game call was attempted.`n--- OUT ---`n{0}`n--- ERR ---`n{1}" -f $selfText,$selfErrText) }
Write-Host 'TOOLING_SELFTEST_PASS' -ForegroundColor Green

$deadline=[DateTime]::UtcNow.AddSeconds($WaitForGameSeconds)
$pid32=0; $announcedWait=$false
while([DateTime]::UtcNow -lt $deadline){
    $games=@(Get-CimInstance Win32_Process|Where-Object{$_.Name -ieq 'game.dat' -and $_.ExecutablePath -ieq $GameDat})
    if($games.Count -gt 1){throw "Expected at most one game.dat at '$GameDat', found $($games.Count)."}
    if($games.Count -eq 1){$pid32=[int]$games[0].ProcessId;break}
    if(-not $announcedWait){Write-Host 'WAITING_FOR_GAME - start AotR on the VM and enter the normal game browser.' -ForegroundColor Yellow;$announcedWait=$true}
    Start-Sleep -Milliseconds 500
}
if($pid32 -le 0){throw "No game.dat appeared within $WaitForGameSeconds seconds."}
Write-Host ("GAME_FOUND PID={0}" -f $pid32) -ForegroundColor Green
Write-Host 'PRECONDITION: host lobby visible in VM browser; do NOT click Join.'
Write-Host ''

$baseRaw='https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/'+$RepoRef+'/tools/research/'
$watchPath=Join-Path $ResearchRoot 'AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V5.ps1'
$joinPath=Join-Path $ResearchRoot 'AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1'
$wrapperPath=Join-Path $ResearchRoot 'AOTR_WOTR_NATIVE_JOIN_CALL_POC_PS51_WRAPPER.ps1'
function Download-Tool {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$Destination)
    Invoke-WebRequest -UseBasicParsing -Uri ($baseRaw+$Name) -OutFile $Destination
    $item=Get-Item -LiteralPath $Destination -ErrorAction Stop
    if($item.Length -lt 100){throw "Downloaded tool looks invalid: $Name len=$($item.Length)"}
    Assert-PowerShellSyntax -FilePath $Destination
}
Download-Tool -Name 'AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V5.ps1' -Destination $watchPath
Download-Tool -Name 'AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1' -Destination $joinPath
Download-Tool -Name 'AOTR_WOTR_NATIVE_JOIN_CALL_POC_PS51_WRAPPER.ps1' -Destination $wrapperPath
Write-Host 'DOWNLOADED_TOOLS_SYNTAX_PASS' -ForegroundColor Green

Write-Host 'PHASE 1/5 CLR SELFTEST - loading watcher C# and validating x86 DEBUG_EVENT layout...'
$clrStamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$clrOut=Join-Path $ResearchRoot "WATCHER_CLR_SELFTEST_$clrStamp.out.txt"
$clrErr=Join-Path $ResearchRoot "WATCHER_CLR_SELFTEST_$clrStamp.err.txt"
Remove-Item -LiteralPath $clrOut,$clrErr -Force -ErrorAction SilentlyContinue
$clrArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-Arg $watchPath),'-CompileOnly')
$clrProc=Start-Ps32Hidden -ChildArguments $clrArgs -StdOutPath $clrOut -StdErrPath $clrErr
if(-not $clrProc.WaitForExit(15000)){
    Stop-ProcSafe -ProcessObject $clrProc
    throw 'WATCHER_CLR_SELFTEST_TIMEOUT. No debugger or join was started.'
}
$clrText=Read-TextSafe -FilePath $clrOut
$clrErrText=Read-TextSafe -FilePath $clrErr
$clrExpected='CLR_LAYOUT_SELFTEST_PASS DEBUG_EVENT_SIZE=96 HTHREAD_OFFSET=12 EXADDR_OFFSET=24'
if($clrText -notmatch [regex]::Escape($clrExpected) -or $clrText -notmatch 'COMPILE_ONLY_COMPLETE'){
    throw ("WATCHER_CLR_SELFTEST_FAILED - no debugger/join executed.`n--- OUT ---`n{0}`n--- ERR ---`n{1}" -f $clrText,$clrErrText)
}
Write-Host $clrExpected -ForegroundColor Green
Write-Host 'WATCHER_CLR_SELFTEST_PASS' -ForegroundColor Green

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$preOut=Join-Path $ResearchRoot "PREFLIGHT_$stamp.out.txt"; $preErr=Join-Path $ResearchRoot "PREFLIGHT_$stamp.err.txt"
$readyFile=Join-Path $ResearchRoot "STATE8_READY_$stamp.txt"; $stopFile=Join-Path $ResearchRoot "STATE8_STOP_$stamp.txt"; $statusFile=Join-Path $ResearchRoot "STATE8_STATUS_$stamp.txt"
$watchOut=Join-Path $ResearchRoot "STATE8_WATCH_$stamp.out.txt"; $watchErr=Join-Path $ResearchRoot "STATE8_WATCH_$stamp.err.txt"
$joinOut=Join-Path $ResearchRoot "LOWLEVEL_JOIN_$stamp.out.txt"; $joinErr=Join-Path $ResearchRoot "LOWLEVEL_JOIN_$stamp.err.txt"
$combined=Join-Path $ResearchRoot "LOWLEVEL_JOIN_COMPLETION_COMBINED_$stamp.txt"
foreach($file in @($preOut,$preErr,$readyFile,$stopFile,$statusFile,$watchOut,$watchErr,$joinOut,$joinErr,$combined)){Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue}

Write-Host 'PHASE 2/5 PREFLIGHT - validating pre-join contract...'
$preArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-Arg $wrapperPath),'-SourcePath',(Quote-Arg $joinPath),'-ProcessId',[string]$pid32,'-ExpectedRemoteIp',(Quote-Arg $ExpectedRemoteIp),'-ExpectedRemotePort',[string]$ExpectedRemotePort,'-ObserveSeconds',[string]$ObserveSeconds)
$preProc=Start-Ps32Hidden -ChildArguments $preArgs -StdOutPath $preOut -StdErrPath $preErr
if(-not $preProc.WaitForExit(15000)){Stop-ProcSafe -ProcessObject $preProc;throw 'PREFLIGHT_TIMEOUT. No debugger or join was started.'}
$preText=Read-TextSafe -FilePath $preOut; $preErrText=Read-TextSafe -FilePath $preErr
if($preText -notmatch 'CALL_POC_READY = YES'){throw ("PREFLIGHT_FAILED - no debugger/join executed.`n--- OUT ---`n{0}`n--- ERR ---`n{1}" -f $preText,$preErrText)}
Write-Host 'PREFLIGHT_PASS' -ForegroundColor Green

Write-Host 'PHASE 3/5 WATCHER - attaching and arming hidden debugger...'
$watchArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-Arg $watchPath),'-ProcessId',[string]$pid32,'-GameDat',(Quote-Arg $GameDat),'-TimeoutSeconds',[string]$WatcherTimeoutSeconds,'-ReadyFile',(Quote-Arg $readyFile),'-StopFile',(Quote-Arg $stopFile),'-StatusFile',(Quote-Arg $statusFile))
$watchProc=Start-Ps32Hidden -ChildArguments $watchArgs -StdOutPath $watchOut -StdErrPath $watchErr
Write-Host ("WATCHER_STARTED PID={0}" -f $watchProc.Id)
$readyDeadline=[DateTime]::UtcNow.AddSeconds(10); $armedCount=0; $readyText=''
while([DateTime]::UtcNow -lt $readyDeadline){
    Start-Sleep -Milliseconds 50
    $readyText=Read-TextSafe -FilePath $readyFile
    if($readyText -match 'STATUS=READY' -and $readyText -match 'ARMED_THREADS=(\d+)'){$armedCount=[int]$Matches[1];if($armedCount -gt 0){break}}
    if($readyText -match 'STATUS=FAIL' -or $watchProc.HasExited){break}
}
if($armedCount -le 0){
    Set-Content -LiteralPath $stopFile -Value 'STOP=1' -Encoding ASCII -ErrorAction SilentlyContinue
    [void]$watchProc.WaitForExit(5000); Stop-ProcSafe -ProcessObject $watchProc
    throw ("WATCHER_READY_FAILED - join was NOT started.`n--- READY ---`n{0}`n--- STATUS ---`n{1}`n--- OUT ---`n{2}`n--- ERR ---`n{3}" -f $readyText,(Read-TextSafe -FilePath $statusFile),(Read-TextSafe -FilePath $watchOut),(Read-TextSafe -FilePath $watchErr))
}
Write-Host ("WATCHER_READY ARMED_THREADS={0}" -f $armedCount) -ForegroundColor Green

Write-Host 'PHASE 4/5 JOIN - executing one native +0x40 call...'
$joinArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-Arg $wrapperPath),'-SourcePath',(Quote-Arg $joinPath),'-ProcessId',[string]$pid32,'-ExpectedRemoteIp',(Quote-Arg $ExpectedRemoteIp),'-ExpectedRemotePort',[string]$ExpectedRemotePort,'-ObserveSeconds',[string]$ObserveSeconds,'-Execute')
$joinProc=Start-Ps32Hidden -ChildArguments $joinArgs -StdOutPath $joinOut -StdErrPath $joinErr
Write-Host ("JOIN_STARTED PID={0}" -f $joinProc.Id)
if(-not $joinProc.WaitForExit(25000)){
    Set-Content -LiteralPath $stopFile -Value 'STOP=1' -Encoding ASCII
    [void]$watchProc.WaitForExit(6000); Stop-ProcSafe -ProcessObject $joinProc; Stop-ProcSafe -ProcessObject $watchProc
    throw ("JOIN_TIMEOUT. Watcher stop requested.`nWATCH_STATUS={0}" -f (Read-TextSafe -FilePath $statusFile))
}
Write-Host 'JOIN_PROCESS_EXITED=YES'

Write-Host 'PHASE 5/5 TEARDOWN - requesting debugger disarm/detach...'
Start-Sleep -Milliseconds 1000
Set-Content -LiteralPath $stopFile -Value 'STOP=1' -Encoding ASCII
Write-Host 'WATCHER_STOP_REQUESTED'
if(-not $watchProc.WaitForExit(10000)){
    $statusText=Read-TextSafe -FilePath $statusFile; $watchOutText=Read-TextSafe -FilePath $watchOut; $watchErrText=Read-TextSafe -FilePath $watchErr
    Stop-ProcSafe -ProcessObject $watchProc
    throw ("WATCHER_TEARDOWN_FAILED. Restart game.dat before any further debugger test.`n--- STATUS ---`n{0}`n--- OUT ---`n{1}`n--- ERR ---`n{2}" -f $statusText,$watchOutText,$watchErrText)
}
Write-Host 'WATCHER_PROCESS_EXITED=YES'

$joinText=Read-TextSafe -FilePath $joinOut; $joinErrText=Read-TextSafe -FilePath $joinErr
$watchText=Read-TextSafe -FilePath $watchOut; $watchErrText=Read-TextSafe -FilePath $watchErr; $statusText=Read-TextSafe -FilePath $statusFile
$joinReturned=($joinText -match 'NATIVE \+0x40 CALL RETURNED = YES')
$joinObserved=($joinText -match 'NATIVE_JOIN_STATE_OBSERVED = YES')
$currentC54=($joinText -match 'current vtable\s+:\s+0x00C54B78.*match=True')
$de892cStayedNull=($joinText -match 'DE892C after\s+:\s+0x00000000')
$callbackHit=if($watchText -match 'CALLBACK_8496C2_HIT=(YES|NO)'){$Matches[1]}else{'MISSING'}
$completionHit=if($watchText -match 'COMPLETION_84944F_HIT=(YES|NO)'){$Matches[1]}else{'MISSING'}
$watchDone=($statusText -match 'STAGE=DONE') -and ($statusText -match 'CLEAN_DETACH=YES')
$valid=$joinReturned -and $joinObserved -and $currentC54 -and $de892cStayedNull -and $watchDone -and ($callbackHit -ne 'MISSING') -and ($completionHit -ne 'MISSING')

$lines=New-Object 'System.Collections.Generic.List[string]'
$lines.Add('============================================================');$lines.Add(' AOTR WOTR LOWLEVEL JOIN COMPLETION - COMBINED RESULT V5');$lines.Add('============================================================')
$lines.Add(("RepoRef                  : {0}" -f $RepoRef));$lines.Add(("Game PID                 : {0}" -f $pid32));$lines.Add(("ARMED_THREADS            : {0}" -f $armedCount));$lines.Add('')
$lines.Add('================ VERDICT INPUTS ================');$lines.Add('TOOLING_SELFTEST_PASS     : YES');$lines.Add('WATCHER_CLR_SELFTEST_PASS : YES');$lines.Add('PREFLIGHT_PASS            : YES')
$lines.Add(("JOIN_RETURNED             : {0}" -f $(if($joinReturned){'YES'}else{'NO'})));$lines.Add(("JOIN_STATE_OBSERVED       : {0}" -f $(if($joinObserved){'YES'}else{'NO'})));$lines.Add(("CURRENT_C54B78            : {0}" -f $(if($currentC54){'YES'}else{'NO'})));$lines.Add(("DE892C_STAYED_NULL        : {0}" -f $(if($de892cStayedNull){'YES'}else{'NO'})));$lines.Add(("WATCHER_CLEAN_EXIT        : {0}" -f $(if($watchDone){'YES'}else{'NO'})));$lines.Add(("TEST_VALID_FOR_STATE8     : {0}" -f $(if($valid){'YES'}else{'NO'})));$lines.Add(("CALLBACK_8496C2_HIT       : {0}" -f $callbackHit));$lines.Add(("COMPLETION_84944F_HIT     : {0}" -f $completionHit));$lines.Add('')
$lines.Add('================ WATCHER STATUS ================');$lines.Add($statusText.TrimEnd());$lines.Add('');$lines.Add('================ JOIN STDOUT ================');$lines.Add($joinText.TrimEnd())
if(-not [string]::IsNullOrWhiteSpace($joinErrText)){$lines.Add('');$lines.Add('================ JOIN STDERR ================');$lines.Add($joinErrText.TrimEnd())}
$lines.Add('');$lines.Add('================ WATCHER STDOUT ================');$lines.Add($watchText.TrimEnd())
if(-not [string]::IsNullOrWhiteSpace($watchErrText)){$lines.Add('');$lines.Add('================ WATCHER STDERR ================');$lines.Add($watchErrText.TrimEnd())}
$lines|Set-Content -LiteralPath $combined -Encoding UTF8
Write-Host '';Write-Host ("COMBINED_RESULT={0}" -f $combined) -ForegroundColor Green;Write-Host '';Get-Content -LiteralPath $combined
