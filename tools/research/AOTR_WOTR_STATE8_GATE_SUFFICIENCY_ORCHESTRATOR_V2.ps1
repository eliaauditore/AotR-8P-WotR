param(
    [string]$CombinedResult = '',
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [int]$ObserveMilliseconds = 2000,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedHash   = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$WatcherRef     = 'b35d207898ea7e730a8e5d176e8e3e7754f7e923'
$WatcherName    = 'AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V5.ps1'
$SessionGlobal  = [uint32]0x00DE4394
$NetworkGlobal  = [uint32]0x00DE892C
$SessionVtable  = [uint32]0x00C54CE0
$GameInfoVtable = [uint32]0x00C54B78

if ($ObserveMilliseconds -lt 500 -or $ObserveMilliseconds -gt 5000) { throw 'ObserveMilliseconds must be 500..5000.' }
New-Item -ItemType Directory -Path $ResearchRoot -Force | Out-Null
if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash got $hash" }

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
function Assert-PowerShellSyntax {
    param([Parameter(Mandatory=$true)][string]$FilePath)
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($FilePath,[ref]$tokens,[ref]$parseErrors)
    if ($null -ne $parseErrors -and $parseErrors.Count -gt 0) {
        $text=($parseErrors|ForEach-Object{"line $($_.Extent.StartLineNumber): $($_.Message)"}) -join "`n"
        throw "PowerShell syntax validation failed for $FilePath`n$text"
    }
}
function Stop-ProcSafe {
    param($ProcessObject)
    if ($null -eq $ProcessObject) { return }
    try { if (-not $ProcessObject.HasExited) { $ProcessObject.Kill() } } catch {}
}

$ps32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $ps32)) { throw "32-bit Windows PowerShell not found: $ps32" }
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

if ([string]::IsNullOrWhiteSpace($CombinedResult)) {
    $latest = Get-ChildItem (Join-Path $ResearchRoot 'LOWLEVEL_JOIN_COMPLETION_COMBINED_*.txt') -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) { throw 'No LOWLEVEL_JOIN_COMPLETION_COMBINED_*.txt result found.' }
    $CombinedResult = $latest.FullName
}
if (-not (Test-Path -LiteralPath $CombinedResult -PathType Leaf)) { throw "Combined result not found: $CombinedResult" }
$log = Get-Content -LiteralPath $CombinedResult -Raw

foreach ($required in @('TEST_VALID_FOR_STATE8','WATCHER_CLEAN_EXIT','JOIN_STATE_OBSERVED','CURRENT_C54B78','DE892C_STAYED_NULL')) {
    if ($log -notmatch ('(?m)^'+[regex]::Escape($required)+'\s+:\s+YES\s*$')) { throw "Source log is not marked $required=YES." }
}
$pidMatch = [regex]::Match($log, '(?m)^Game PID\s+:\s+(\d+)\s*$')
if (-not $pidMatch.Success) { throw 'Could not parse Game PID from combined result.' }
$GamePid = [int]$pidMatch.Groups[1].Value

$ownerMatches = [regex]::Matches($log, '(?m)^ECX_OWNER=(0x[0-9A-Fa-f]{8}) OWNER_6A4=(\d+) OWNER_304=(\d+) CURRENT_IS_C54B78=(YES|NO)\s*$')
if ($ownerMatches.Count -le 0) { throw 'No callback owner-state records found in source log.' }
$ownerStrings = @($ownerMatches | ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() } | Select-Object -Unique)
if ($ownerStrings.Count -ne 1) { throw "Source log contains multiple distinct frontend owners: $($ownerStrings -join ', ')" }
$badOwnerRecords = @($ownerMatches | Where-Object { $_.Groups[2].Value -ne '1' -or $_.Groups[3].Value -ne '1' -or $_.Groups[4].Value -ne 'YES' })
if ($badOwnerRecords.Count -ne 0) { throw "Source log contains $($badOwnerRecords.Count) owner-state records outside the proven 6A4=1/304=1/Current=C54 contract." }
$Owner = [uint32]::Parse($ownerStrings[0].Substring(2), [Globalization.NumberStyles]::HexNumber)

$p = Get-CimInstance Win32_Process -Filter "ProcessId=$GamePid"
if (-not $p) { throw "Original game PID $GamePid is no longer running. This test intentionally refuses a different process." }
if ($p.ExecutablePath -ine $GameDat) { throw "PID $GamePid path mismatch: $($p.ExecutablePath)" }

if (-not ('AotrState8Mem32V2' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AotrState8Mem32V2 {
    const uint PROCESS_ACCESS=0x001F0FFF;
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint a,bool i,uint p);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h,IntPtr a,byte[] b,UIntPtr n,out UIntPtr g);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool WriteProcessMemory(IntPtr h,IntPtr a,byte[] b,UIntPtr n,out UIntPtr w);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    static IntPtr A(uint a){ return new IntPtr((long)a); }
    public static uint Read32(int pid,uint addr){
        IntPtr h=OpenProcess(PROCESS_ACCESS,false,(uint)pid); if(h==IntPtr.Zero)throw new Exception("OpenProcess failed "+Marshal.GetLastWin32Error());
        try{byte[] b=new byte[4];UIntPtr g;if(!ReadProcessMemory(h,A(addr),b,new UIntPtr(4u),out g)||g.ToUInt64()!=4)throw new Exception("ReadProcessMemory failed at 0x"+addr.ToString("X8")+" win32="+Marshal.GetLastWin32Error());return BitConverter.ToUInt32(b,0);}finally{CloseHandle(h);}
    }
    public static void Write32(int pid,uint addr,uint value){
        IntPtr h=OpenProcess(PROCESS_ACCESS,false,(uint)pid); if(h==IntPtr.Zero)throw new Exception("OpenProcess failed "+Marshal.GetLastWin32Error());
        try{byte[] b=BitConverter.GetBytes(value);UIntPtr w;if(!WriteProcessMemory(h,A(addr),b,new UIntPtr(4u),out w)||w.ToUInt64()!=4)throw new Exception("WriteProcessMemory failed at 0x"+addr.ToString("X8")+" win32="+Marshal.GetLastWin32Error());}finally{CloseHandle(h);}
    }
}
'@
}
function Read32([uint32]$Address) { return [uint32][AotrState8Mem32V2]::Read32($GamePid,$Address) }
function Write32([uint32]$Address,[uint32]$Value) { [AotrState8Mem32V2]::Write32($GamePid,$Address,$Value) }
function Get-LiveState {
    $session = Read32 $SessionGlobal
    $sessionVt = if ($session -ne 0) { Read32 $session } else { 0 }
    $current = if ($session -ne 0) { Read32 ([uint32]($session + 0x44)) } else { 0 }
    $currentVt = if ($current -ne 0) { Read32 $current } else { 0 }
    $net = Read32 $NetworkGlobal
    $state = Read32 ([uint32]($Owner + 0x6A4))
    $owner304 = Read32 ([uint32]($Owner + 0x304))
    [pscustomobject]@{Session=$session;SessionVt=$sessionVt;Current=$current;CurrentVt=$currentVt;Net=$net;State=$state;Owner304=$owner304}
}

$live = Get-LiveState
if ($live.Session -eq 0 -or $live.SessionVt -ne $SessionVtable) { throw ('Live session precondition failed: session=0x{0:X8} vt=0x{1:X8}' -f $live.Session,$live.SessionVt) }
if ($live.Current -eq 0 -or $live.CurrentVt -ne $GameInfoVtable) { throw ('Live current precondition failed: current=0x{0:X8} vt=0x{1:X8}' -f $live.Current,$live.CurrentVt) }
if ($live.Net -ne 0) { throw ('DE892C already non-NULL (0x{0:X8}); refusing isolated State8 test.' -f $live.Net) }
if ($live.State -ne 1 -or $live.Owner304 -ne 1) { throw "Owner live precondition failed: +6A4=$($live.State) +304=$($live.Owner304), expected 1/1." }

$watchPath = Join-Path $ResearchRoot $WatcherName
$watchUrl = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$WatcherRef/tools/research/$WatcherName"
Invoke-WebRequest -UseBasicParsing -Uri $watchUrl -OutFile $watchPath
if ((Get-Item -LiteralPath $watchPath).Length -lt 1000) { throw 'Downloaded watcher looks invalid.' }
Assert-PowerShellSyntax -FilePath $watchPath

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$clrOut=Join-Path $ResearchRoot "STATE8_SUFF_CLR_$stamp.out.txt"; $clrErr=Join-Path $ResearchRoot "STATE8_SUFF_CLR_$stamp.err.txt"
$readyFile=Join-Path $ResearchRoot "STATE8_SUFF_READY_$stamp.txt"; $stopFile=Join-Path $ResearchRoot "STATE8_SUFF_STOP_$stamp.txt"; $statusFile=Join-Path $ResearchRoot "STATE8_SUFF_STATUS_$stamp.txt"
$watchOut=Join-Path $ResearchRoot "STATE8_SUFF_WATCH_$stamp.out.txt"; $watchErr=Join-Path $ResearchRoot "STATE8_SUFF_WATCH_$stamp.err.txt"
$resultFile=Join-Path $ResearchRoot "STATE8_SUFF_RESULT_$stamp.txt"
foreach($f in @($clrOut,$clrErr,$readyFile,$stopFile,$statusFile,$watchOut,$watchErr,$resultFile)){Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}

Write-Host '============================================================'
Write-Host ' AOTR WOTR STATE8 GATE SUFFICIENCY ORCHESTRATOR V2'
Write-Host '============================================================'
Write-Host ("Source result    : {0}" -f $CombinedResult)
Write-Host ("Game PID         : {0}" -f $GamePid)
Write-Host ("Owner            : 0x{0:X8}" -f $Owner)
Write-Host ("Source owner hits: {0} (all 6A4=1, 304=1, Current=C54)" -f $ownerMatches.Count)
Write-Host ("Current          : 0x{0:X8}" -f $live.Current)
Write-Host 'Mutation         : exactly one DWORD owner+0x6A4, 1 -> 8'
Write-Host 'No DE892C/session/GameInfo write and no direct game-function call.'
Write-Host ''

$clrArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-Arg $watchPath),'-CompileOnly')
$clrProc=Start-Ps32Hidden -ChildArguments $clrArgs -StdOutPath $clrOut -StdErrPath $clrErr
if(-not $clrProc.WaitForExit(15000)){Stop-ProcSafe $clrProc;throw 'WATCHER_CLR_SELFTEST_TIMEOUT. No state write was attempted.'}
$clrText=Read-TextSafe $clrOut; $clrErrText=Read-TextSafe $clrErr
if($clrText -notmatch 'CLR_LAYOUT_SELFTEST_PASS DEBUG_EVENT_SIZE=96 HTHREAD_OFFSET=12 EXADDR_OFFSET=24' -or $clrText -notmatch 'COMPILE_ONLY_COMPLETE'){
    throw ("WATCHER_CLR_SELFTEST_FAILED. No state write was attempted.`n--- OUT ---`n{0}`n--- ERR ---`n{1}" -f $clrText,$clrErrText)
}
Write-Host 'WATCHER_CLR_SELFTEST_PASS' -ForegroundColor Green

$watchArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-Arg $watchPath),'-ProcessId',[string]$GamePid,'-GameDat',(Quote-Arg $GameDat),'-TimeoutSeconds','30','-ReadyFile',(Quote-Arg $readyFile),'-StopFile',(Quote-Arg $stopFile),'-StatusFile',(Quote-Arg $statusFile))
$watchProc=$null
$stateIssued=$false
$stateRestored=$false
$cleanStop=$false
try {
    $watchProc=Start-Ps32Hidden -ChildArguments $watchArgs -StdOutPath $watchOut -StdErrPath $watchErr
    Write-Host ("WATCHER_STARTED PID={0}" -f $watchProc.Id)
    $readyDeadline=[DateTime]::UtcNow.AddSeconds(10); $armed=0; $readyText=''
    while([DateTime]::UtcNow -lt $readyDeadline){
        Start-Sleep -Milliseconds 25
        $readyText=Read-TextSafe $readyFile
        if($readyText -match 'STATUS=READY' -and $readyText -match 'ARMED_THREADS=(\d+)'){$armed=[int]$Matches[1];if($armed -gt 0){break}}
        if($readyText -match 'STATUS=FAIL' -or $watchProc.HasExited){break}
    }
    if($armed -le 0){throw ("WATCHER_READY_FAILED. No state write was attempted.`nREADY={0}`nSTATUS={1}`nERR={2}" -f $readyText,(Read-TextSafe $statusFile),(Read-TextSafe $watchErr))}
    Write-Host ("WATCHER_READY ARMED_THREADS={0}" -f $armed) -ForegroundColor Green

    $preWrite=Get-LiveState
    if($preWrite.Current -ne $live.Current -or $preWrite.CurrentVt -ne $GameInfoVtable -or $preWrite.Net -ne 0 -or $preWrite.State -ne 1 -or $preWrite.Owner304 -ne 1){
        throw ('PREWRITE_CONTRACT_CHANGED. No state write attempted. Current=0x{0:X8} VT=0x{1:X8} DE892C=0x{2:X8} State={3} Owner304={4}' -f $preWrite.Current,$preWrite.CurrentVt,$preWrite.Net,$preWrite.State,$preWrite.Owner304)
    }
    Write-Host 'PREWRITE_CONTRACT_PASS' -ForegroundColor Green

    $stateAddress=[uint32]($Owner + 0x6A4)
    Write32 $stateAddress 8
    $stateIssued=$true
    $postWriteReadback=Read32 $stateAddress
    Write-Host ("STATE8_WRITE_API_PASS post-write-readback={0}" -f $postWriteReadback) -ForegroundColor Yellow

    $stateTransitions=New-Object System.Collections.Generic.List[string]
    if($postWriteReadback -ne 1){$stateTransitions.Add(("immediate owner+6A4 1->{0}" -f $postWriteReadback))}
    $lastState=$postWriteReadback
    $deadline=[DateTime]::UtcNow.AddMilliseconds($ObserveMilliseconds)
    while([DateTime]::UtcNow -lt $deadline){
        Start-Sleep -Milliseconds 10
        $s=Get-LiveState
        if($s.State -ne $lastState){$stateTransitions.Add(("{0:HH:mm:ss.fff} owner+6A4 {1}->{2}" -f (Get-Date),$lastState,$s.State));$lastState=$s.State}
        if($s.Net -ne 0 -and $s.Net -eq $s.Current){break}
    }

    $afterObserve=Get-LiveState
    if($afterObserve.Net -eq 0 -and $afterObserve.State -eq 8){
        Write32 $stateAddress 1
        if((Read32 $stateAddress) -ne 1){throw 'STATE8_FAILURE_RESTORE_VERIFY_FAILED. Restart game.dat before further work.'}
        $stateRestored=$true
        Write-Host 'STATE8_FAILURE_RESTORE_VERIFIED 8 -> 1' -ForegroundColor Yellow
    }

    Set-Content -LiteralPath $stopFile -Value 'STOP=1' -Encoding ASCII
    Write-Host 'WATCHER_STOP_REQUESTED'
    if(-not $watchProc.WaitForExit(10000)){Stop-ProcSafe $watchProc;throw 'WATCHER_TEARDOWN_FAILED. Restart game.dat before further debugger work.'}
    $cleanStop=$true

    $watchText=Read-TextSafe $watchOut; $watchErrText=Read-TextSafe $watchErr; $statusText=Read-TextSafe $statusFile
    $watchLines=@($watchText -split "`r?`n")
    $callbackHit=($watchText -match 'CALLBACK_8496C2_HIT=YES')
    $completionHit=($watchText -match 'COMPLETION_84944F_HIT=YES')
    $completionAtState8=$false
    for($i=0;$i -lt $watchLines.Count;$i++){
        if($watchLines[$i] -eq 'COMPLETION_84944F_HIT=YES'){
            for($j=$i+1;$j -le [Math]::Min($i+10,$watchLines.Count-1);$j++){
                if($watchLines[$j] -match '^ECX_OWNER=0x[0-9A-Fa-f]{8} OWNER_6A4=8 OWNER_304=\d+ CURRENT_IS_C54B78=YES$'){$completionAtState8=$true;break}
            }
        }
        if($completionAtState8){break}
    }
    $watchClean=($statusText -match 'STAGE=DONE') -and ($statusText -match 'CLEAN_DETACH=YES')
    $final=Get-LiveState
    $published=($final.Current -ne 0 -and $final.Net -eq $final.Current)
    $sufficiency=$stateIssued -and $completionHit -and $completionAtState8 -and $published -and $watchClean

    $lines=New-Object System.Collections.Generic.List[string]
    $lines.Add('============================================================');$lines.Add(' AOTR WOTR STATE8 GATE SUFFICIENCY RESULT V2');$lines.Add('============================================================')
    $lines.Add(("SOURCE_RESULT              : {0}" -f $CombinedResult));$lines.Add(("GAME_PID                   : {0}" -f $GamePid));$lines.Add(("OWNER                      : 0x{0:X8}" -f $Owner));$lines.Add(("SOURCE_OWNER_HITS          : {0}" -f $ownerMatches.Count));$lines.Add('')
    $lines.Add('================ VERDICT ================')
    $lines.Add('PREWRITE_CONTRACT_PASS     : YES');$lines.Add(("STATE8_WRITE_API_PASS       : {0}" -f $(if($stateIssued){'YES'}else{'NO'})));$lines.Add(("POSTWRITE_STATE_READBACK    : {0}" -f $postWriteReadback));$lines.Add(("CALLBACK_8496C2_HIT         : {0}" -f $(if($callbackHit){'YES'}else{'NO'})));$lines.Add(("COMPLETION_84944F_HIT       : {0}" -f $(if($completionHit){'YES'}else{'NO'})));$lines.Add(("COMPLETION_AT_OWNER_STATE8  : {0}" -f $(if($completionAtState8){'YES'}else{'NO'})));$lines.Add(("DE892C_EQUALS_CURRENT       : {0}" -f $(if($published){'YES'}else{'NO'})));$lines.Add(("WATCHER_CLEAN_EXIT          : {0}" -f $(if($watchClean){'YES'}else{'NO'})));$lines.Add(("STATE8_SUFFICIENCY_PROVEN   : {0}" -f $(if($sufficiency){'YES'}else{'NO'})));$lines.Add(("FAILURE_STATE_RESTORED      : {0}" -f $(if($stateRestored){'YES'}else{'NO'})));$lines.Add('')
    $lines.Add('================ FINAL LIVE STATE ================');$lines.Add(("OWNER_6A4_AFTER             : {0}" -f $final.State));$lines.Add(("OWNER_304_AFTER             : {0}" -f $final.Owner304));$lines.Add(("CURRENT_AFTER               : 0x{0:X8}" -f $final.Current));$lines.Add(("DE892C_AFTER                : 0x{0:X8}" -f $final.Net));
    if($stateTransitions.Count -gt 0){$lines.Add('');$lines.Add('================ OBSERVED STATE TRANSITIONS ================');foreach($t in $stateTransitions){$lines.Add($t)}}
    if(-not [string]::IsNullOrWhiteSpace($watchErrText)){$lines.Add('');$lines.Add('================ WATCHER STDERR ================');$lines.Add($watchErrText.TrimEnd())}
    $lines | Set-Content -LiteralPath $resultFile -Encoding UTF8
    Write-Host '';Write-Host ("RESULT_FILE={0}" -f $resultFile) -ForegroundColor Green;Write-Host '';Get-Content -LiteralPath $resultFile
}
finally {
    if($stateIssued -and -not $cleanStop){
        try{$s=Get-LiveState;if($s.Net -eq 0 -and $s.State -eq 8){Write32 ([uint32]($Owner+0x6A4)) 1;$stateRestored=$true}}catch{}
    }
    if($null -ne $watchProc){
        try{if(-not $watchProc.HasExited){Set-Content -LiteralPath $stopFile -Value 'STOP=1' -Encoding ASCII -ErrorAction SilentlyContinue;[void]$watchProc.WaitForExit(8000)}}catch{}
        Stop-ProcSafe $watchProc
    }
}
