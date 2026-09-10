param(
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [string]$ExpectedRemoteIp = '192.168.0.224',
    [int]$ExpectedRemotePort = 8086,
    [int]$ObserveSeconds = 8,
    [int]$WatcherTimeoutSeconds = 45,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Controlled one-variable experiment.
# Authorized mutation: exactly frontendOwner+0x6A4 from 1 to 8 immediately before
# the already-proven native session->vtable+0x40 join call.
# No direct write to DE892C, DE8930, session+0x44, GameInfo, PlayerInfo, or game.dat.

$ExpectedHash      = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$PinnedToolRef     = 'b35d207898ea7e730a8e5d176e8e3e7754f7e923'
$OwnerGlobal       = [uint32]0x00DE8D90
$SessionGlobal     = [uint32]0x00DE4394
$NetworkGlobal     = [uint32]0x00DE892C
$SessionVtable     = [uint32]0x00C54CE0
$GameInfoVtable    = [uint32]0x00C54B78
$OwnerStateOffset  = [uint32]0x000006A4
$Owner304Offset    = [uint32]0x00000304

if ([Environment]::Is64BitProcess) {
    throw 'Run under 32-bit Windows PowerShell: C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
}
if ($ExpectedRemotePort -lt 1 -or $ExpectedRemotePort -gt 65535) { throw 'ExpectedRemotePort must be 1..65535.' }
if ($ObserveSeconds -lt 2 -or $ObserveSeconds -gt 30) { throw 'ObserveSeconds must be 2..30.' }
if ($WatcherTimeoutSeconds -lt 20 -or $WatcherTimeoutSeconds -gt 120) { throw 'WatcherTimeoutSeconds must be 20..120.' }

New-Item -ItemType Directory -Path $ResearchRoot -Force | Out-Null
if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

function F32([uint32]$Value) { return ('0x{0:X8}' -f $Value) }
function Read-TextSafe {
    param([Parameter(Mandatory=$true)][string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { return '' }
    try { return [string](Get-Content -LiteralPath $FilePath -Raw -ErrorAction Stop) } catch { return '' }
}
function Quote-Arg {
    param([Parameter(Mandatory=$true)][string]$Value)
    if ($Value.Contains('"')) { throw "Quote-Arg rejects embedded quotes: $Value" }
    return ('"{0}"' -f $Value)
}
function Assert-PowerShellSyntax {
    param([Parameter(Mandatory=$true)][string]$FilePath)
    $tokens=$null
    $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($FilePath,[ref]$tokens,[ref]$parseErrors)
    if ($null -ne $parseErrors -and $parseErrors.Count -gt 0) {
        $text = ($parseErrors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join "`n"
        throw "PowerShell syntax validation failed for $FilePath`n$text"
    }
}

$games = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -ieq 'game.dat' -and $_.ExecutablePath -ieq $GameDat
})
if ($games.Count -ne 1) { throw "Expected exactly one game.dat at '$GameDat'. Found $($games.Count)." }
$GamePid = [int]$games[0].ProcessId

if (-not ('AotrState8PreJoinMem32V2' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class AotrState8PreJoinMem32V2 {
    const uint VMOP=0x0008, VMR=0x0010, VMW=0x0020, QI=0x0400, ACCESS=VMOP|VMR|VMW|QI;
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint a,bool i,uint p);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h,IntPtr a,byte[] b,UIntPtr n,out UIntPtr g);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool WriteProcessMemory(IntPtr h,IntPtr a,byte[] b,UIntPtr n,out UIntPtr w);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    static IntPtr A(uint a){ return new IntPtr(unchecked((int)a)); }
    public static uint R(int pid,uint addr){
        IntPtr h=OpenProcess(ACCESS,false,(uint)pid); if(h==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error(),"OpenProcess failed");
        try{byte[] b=new byte[4];UIntPtr g;if(!ReadProcessMemory(h,A(addr),b,new UIntPtr(4u),out g)||g.ToUInt64()!=4)throw new Win32Exception(Marshal.GetLastWin32Error(),"ReadProcessMemory failed at 0x"+addr.ToString("X8"));return BitConverter.ToUInt32(b,0);}finally{CloseHandle(h);}
    }
    public static void W(int pid,uint addr,uint value){
        IntPtr h=OpenProcess(ACCESS,false,(uint)pid); if(h==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error(),"OpenProcess failed");
        try{byte[] b=BitConverter.GetBytes(value);UIntPtr w;if(!WriteProcessMemory(h,A(addr),b,new UIntPtr(4u),out w)||w.ToUInt64()!=4)throw new Win32Exception(Marshal.GetLastWin32Error(),"WriteProcessMemory failed at 0x"+addr.ToString("X8"));}finally{CloseHandle(h);}
    }
}
'@
}

function Read32([uint32]$Address) { return [uint32][AotrState8PreJoinMem32V2]::R($GamePid,$Address) }
function Write32([uint32]$Address,[uint32]$Value) { [AotrState8PreJoinMem32V2]::W($GamePid,$Address,$Value) }
function Get-LiveState {
    $o=Read32 $OwnerGlobal
    $s6=if($o-ne 0){Read32 ([uint32]($o+$OwnerStateOffset))}else{[uint32]0xFFFFFFFF}
    $o3=if($o-ne 0){Read32 ([uint32]($o+$Owner304Offset))}else{[uint32]0xFFFFFFFF}
    $s=Read32 $SessionGlobal
    $sv=if($s-ne 0){Read32 $s}else{[uint32]0}
    $s28=if($s-ne 0){Read32 ([uint32]($s+0x28))}else{[uint32]0xFFFFFFFF}
    $c=if($s-ne 0){Read32 ([uint32]($s+0x44))}else{[uint32]0}
    $cv=if($c-ne 0){Read32 $c}else{[uint32]0}
    $n=Read32 $NetworkGlobal
    [pscustomobject]@{Owner=$o;State6A4=$s6;Owner304=$o3;Session=$s;SessionVt=$sv;State28=$s28;Current=$c;CurrentVt=$cv;Net=$n}
}
function Assert-Fresh {
    param([Parameter(Mandatory=$true)]$X,[uint32]$ExpectedOwner=0,[string]$Stage='PREJOIN')
    if($X.Owner-eq 0){throw "$Stage: DE8D90 is NULL."}
    if($ExpectedOwner-ne 0 -and $X.Owner-ne $ExpectedOwner){throw ("{0}: owner changed {1}->{2}."-f $Stage,(F32 $ExpectedOwner),(F32 $X.Owner))}
    if($X.State6A4-ne 1 -or $X.Owner304-ne 1){throw "$Stage: owner state is $($X.State6A4)/$($X.Owner304), expected 1/1."}
    if($X.Session-eq 0 -or $X.SessionVt-ne $SessionVtable){throw ("{0}: session/vtable mismatch {1}/{2}."-f $Stage,(F32 $X.Session),(F32 $X.SessionVt))}
    if($X.State28-ne 0 -and $X.State28-ne 2){throw "$Stage: session+0x28=$($X.State28), expected 0 or 2."}
    if($X.Current-ne 0){throw ("{0}: session+0x44 already {1}."-f $Stage,(F32 $X.Current))}
    if($X.Net-ne 0){throw ("{0}: DE892C already {1}."-f $Stage,(F32 $X.Net))}
}

Write-Host '============================================================'
Write-Host ' AOTR WOTR STATE8 PREJOIN NATIVE JOIN ORCHESTRATOR V2'
Write-Host '============================================================'
Write-Host ("PID             : {0}" -f $GamePid)
Write-Host ("SHA256          : {0}" -f $hash)
Write-Host ("Expected host   : {0}:{1}" -f $ExpectedRemoteIp,$ExpectedRemotePort)
Write-Host ("Pinned tools    : {0}" -f $PinnedToolRef)
Write-Host 'WRITE CONTRACT  : exactly owner+0x6A4 1->8; no other game-state write'
Write-Host ''

$initial=Get-LiveState
Assert-Fresh -X $initial -Stage 'INITIAL_PREJOIN'
$Owner=[uint32]$initial.Owner
$StateAddr=[uint32]($Owner+$OwnerStateOffset)
Write-Host ("OWNER_LOCATOR_RUNTIME_PASS [DE8D90]={0}" -f (F32 $Owner)) -ForegroundColor Green
Write-Host ("owner+0x6A4={0} value=1; owner+0x304=1" -f (F32 $StateAddr))
Write-Host ("session={0} vt={1}; current=NULL; DE892C=NULL" -f (F32 $initial.Session),(F32 $initial.SessionVt))

$raw='https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/'+$PinnedToolRef+'/tools/research/'
$watchPath=Join-Path $ResearchRoot 'AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V5.ps1'
$joinPath=Join-Path $ResearchRoot 'AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1'
$wrapperPath=Join-Path $ResearchRoot 'AOTR_WOTR_NATIVE_JOIN_CALL_POC_PS51_WRAPPER.ps1'
foreach($pair in @(
    @('AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V5.ps1',$watchPath),
    @('AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1',$joinPath),
    @('AOTR_WOTR_NATIVE_JOIN_CALL_POC_PS51_WRAPPER.ps1',$wrapperPath)
)){
    Invoke-WebRequest -UseBasicParsing -Uri ($raw+$pair[0]) -OutFile $pair[1]
    if((Get-Item -LiteralPath $pair[1]).Length-lt 100){throw "Invalid download: $($pair[0])"}
    Assert-PowerShellSyntax $pair[1]
}
Write-Host 'PINNED_TOOLS_DOWNLOAD_AND_SYNTAX_PASS' -ForegroundColor Green

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$ready=Join-Path $ResearchRoot "STATE8_PREJOIN_READY_$stamp.txt"
$stop=Join-Path $ResearchRoot "STATE8_PREJOIN_STOP_$stamp.txt"
$status=Join-Path $ResearchRoot "STATE8_PREJOIN_STATUS_$stamp.txt"
$wout=Join-Path $ResearchRoot "STATE8_PREJOIN_WATCH_$stamp.out.txt"
$werr=Join-Path $ResearchRoot "STATE8_PREJOIN_WATCH_$stamp.err.txt"
$cout=Join-Path $ResearchRoot "STATE8_PREJOIN_CLR_$stamp.out.txt"
$cerr=Join-Path $ResearchRoot "STATE8_PREJOIN_CLR_$stamp.err.txt"
$p1log=Join-Path $ResearchRoot "STATE8_PREJOIN_PREFLIGHT1_$stamp.txt"
$p2log=Join-Path $ResearchRoot "STATE8_PREJOIN_PREFLIGHT2_$stamp.txt"
$jlog=Join-Path $ResearchRoot "STATE8_PREJOIN_JOIN_$stamp.txt"
$rlog=Join-Path $ResearchRoot "STATE8_PREJOIN_RESULT_$stamp.txt"
foreach($f in @($ready,$stop,$status,$wout,$werr,$cout,$cerr,$p1log,$p2log,$jlog,$rlog)){Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}

$ps32=Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
if(-not(Test-Path -LiteralPath $ps32)){throw "Missing $ps32"}

Write-Host 'PHASE 1/6 CLR SELFTEST...'
$cargs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-Arg $watchPath),'-CompileOnly')
$cp=Start-Process -FilePath $ps32 -ArgumentList $cargs -WindowStyle Hidden -RedirectStandardOutput $cout -RedirectStandardError $cerr -PassThru
if(-not $cp.WaitForExit(15000)){throw 'CLR_SELFTEST_TIMEOUT; no debugger/write/join attempted.'}
$ct=Read-TextSafe $cout
if($ct-notmatch 'CLR_LAYOUT_SELFTEST_PASS DEBUG_EVENT_SIZE=96 HTHREAD_OFFSET=12 EXADDR_OFFSET=24' -or $ct-notmatch 'COMPILE_ONLY_COMPLETE'){
    throw ("CLR_SELFTEST_FAILED; no debugger/write/join attempted.`nOUT={0}`nERR={1}"-f $ct,(Read-TextSafe $cerr))
}
Write-Host 'CLR_LAYOUT_SELFTEST_PASS DEBUG_EVENT_SIZE=96 HTHREAD_OFFSET=12 EXADDR_OFFSET=24' -ForegroundColor Green

$pre=@{SourcePath=$joinPath;ProcessId=$GamePid;ExpectedRemoteIp=$ExpectedRemoteIp;ExpectedRemotePort=$ExpectedRemotePort;ObserveSeconds=$ObserveSeconds}
Write-Host 'PHASE 2/6 NATIVE JOIN DRY-RUN PREFLIGHT...'
$t1=(@(& $wrapperPath @pre 6>&1 2>&1)|Out-String)
Set-Content -LiteralPath $p1log -Value $t1 -Encoding UTF8
if($t1-notmatch 'CALL_POC_READY = YES'){throw "PREFLIGHT1_FAILED; no debugger/write/join attempted.`n$t1"}
Write-Host 'PREFLIGHT1_PASS' -ForegroundColor Green

$watchProc=$null
$stateIssued=$false
$stateRestored=$false
$watchClean=$false
$joinReturned=$false
$detachConfirmed=$false
try{
    Write-Host 'PHASE 3/6 WATCHER ATTACH + ARM...'
    $wargs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-Arg $watchPath),'-ProcessId',[string]$GamePid,'-GameDat',(Quote-Arg $GameDat),'-TimeoutSeconds',[string]$WatcherTimeoutSeconds,'-ReadyFile',(Quote-Arg $ready),'-StopFile',(Quote-Arg $stop),'-StatusFile',(Quote-Arg $status))
    $watchProc=Start-Process -FilePath $ps32 -ArgumentList $wargs -WindowStyle Hidden -RedirectStandardOutput $wout -RedirectStandardError $werr -PassThru
    $deadline=[DateTime]::UtcNow.AddSeconds(10);$armed=0;$rt=''
    while([DateTime]::UtcNow-lt $deadline){
        Start-Sleep -Milliseconds 25
        $rt=Read-TextSafe $ready
        if($rt-match 'STATUS=READY' -and $rt-match 'ARMED_THREADS=(\d+)'){$armed=[int]$Matches[1];if($armed-gt 0){break}}
        if($rt-match 'STATUS=FAIL' -or $watchProc.HasExited){break}
    }
    if($armed-le 0){throw ("WATCHER_READY_FAILED; no write/join attempted.`nREADY={0}`nSTATUS={1}`nERR={2}"-f $rt,(Read-TextSafe $status),(Read-TextSafe $werr))}
    Write-Host ("WATCHER_READY ARMED_THREADS={0}"-f $armed) -ForegroundColor Green

    Write-Host 'PHASE 4/6 REVALIDATE AFTER WATCHER READY...'
    $t2=(@(& $wrapperPath @pre 6>&1 2>&1)|Out-String)
    Set-Content -LiteralPath $p2log -Value $t2 -Encoding UTF8
    if($t2-notmatch 'CALL_POC_READY = YES'){throw "PREFLIGHT2_FAILED; no write/join attempted.`n$t2"}
    $pw=Get-LiveState
    Assert-Fresh -X $pw -ExpectedOwner $Owner -Stage 'PREWRITE_REVALIDATION'
    Write-Host 'PREWRITE_CONTRACT_PASS' -ForegroundColor Green

    Write-Host 'PHASE 5/6 STATE8 1->8 THEN IMMEDIATE NATIVE +0x40...'
    Write32 $StateAddr ([uint32]8)
    $stateIssued=$true
    if((Read32 $StateAddr)-ne 8){throw 'STATE8 write readback failed.'}
    Write-Host 'STATE8_WRITE_API_PASS readback=8' -ForegroundColor Green

    # Inline in this already-running 32-bit shell: no second-shell startup delay.
    $exec=@{SourcePath=$joinPath;ProcessId=$GamePid;ExpectedRemoteIp=$ExpectedRemoteIp;ExpectedRemotePort=$ExpectedRemotePort;ObserveSeconds=$ObserveSeconds;Execute=$true}
    $jt=(@(& $wrapperPath @exec 6>&1 2>&1)|Out-String)
    Set-Content -LiteralPath $jlog -Value $jt -Encoding UTF8
    Write-Host $jt
    if($jt-notmatch 'NATIVE \+0x40 CALL RETURNED = YES'){throw 'Native +0x40 call returned without expected marker.'}
    $joinReturned=$true
    Start-Sleep -Milliseconds 1000

    Write-Host 'PHASE 6/6 REQUEST CLEAN WATCHER DETACH...'
    Set-Content -LiteralPath $stop -Value 'STOP=1' -Encoding ASCII
    if(-not $watchProc.WaitForExit(10000)){throw 'WATCHER_TEARDOWN_TIMEOUT; do not run another debugger test in this game process.'}
    if((Read-TextSafe $status)-notmatch 'CLEAN_DETACH=YES'){throw "WATCHER_CLEAN_DETACH_NOT_CONFIRMED.`n$(Read-TextSafe $status)"}
    $watchClean=$true
    $detachConfirmed=$true
    Write-Host 'WATCHER_CLEAN_EXIT=YES' -ForegroundColor Green
}
finally{
    if($null-eq $watchProc){
        $detachConfirmed=$true
    } elseif(-not $detachConfirmed){
        try{Set-Content -LiteralPath $stop -Value 'STOP=1' -Encoding ASCII -ErrorAction SilentlyContinue}catch{}
        try{if(-not $watchProc.HasExited){[void]$watchProc.WaitForExit(7000)}}catch{}
        if($watchProc.HasExited -and (Read-TextSafe $status)-match 'CLEAN_DETACH=YES'){
            $detachConfirmed=$true
            $watchClean=$true
        }
    }

    # Restore only after confirmed clean debugger detach. Never mutate while debugger
    # ownership/DR state is uncertain.
    if($stateIssued -and $detachConfirmed){
        try{
            $oNow=Read32 $OwnerGlobal
            $nNow=Read32 $NetworkGlobal
            if($oNow-eq $Owner){
                $sNow=Read32 $StateAddr
                if($sNow-eq 8 -and $nNow-eq 0){
                    Write32 $StateAddr ([uint32]1)
                    if((Read32 $StateAddr)-eq 1){$stateRestored=$true;Write-Host 'SAFE_FAILURE_RESTORE_VERIFIED 8->1' -ForegroundColor Yellow}
                }
            }
        }catch{Write-Host ("SAFE_RESTORE_NOT_CONFIRMED: {0}"-f $_.Exception.Message) -ForegroundColor Yellow}
    }

    if($null-ne $watchProc -and -not $detachConfirmed){
        throw 'WATCHER CLEAN DETACH COULD NOT BE CONFIRMED. No restore was attempted. Restart game.dat before any further debugger/runtime mutation test.'
    }
}

$wt=Read-TextSafe $wout
$final=Get-LiveState
$cb=@();$co=@();$pc=$false;$po=$false
foreach($line in ($wt-split "`r?`n")){
    if($line-eq 'CALLBACK_8496C2_HIT=YES'){$pc=$true;continue}
    if($line-eq 'COMPLETION_84944F_HIT=YES'){$po=$true;continue}
    $m=[regex]::Match($line,'^ECX_OWNER=(0x[0-9A-Fa-f]{8}) OWNER_6A4=(\d+) OWNER_304=(\d+) CURRENT_IS_C54B78=(YES|NO)$')
    if($m.Success){
        $q=[pscustomobject]@{Owner=$m.Groups[1].Value.ToUpperInvariant();State=[int]$m.Groups[2].Value;Owner304=[int]$m.Groups[3].Value;C54=$m.Groups[4].Value}
        if($pc){$cb+=,$q};if($po){$co+=,$q};$pc=$false;$po=$false
    }
}
$ownerText=F32 $Owner
$cb8=@($cb|Where-Object{$_.Owner-eq $ownerText -and $_.State-eq 8 -and $_.Owner304-eq 1}).Count
$co8=@($co|Where-Object{$_.Owner-eq $ownerText -and $_.State-eq 8}).Count
$curOK=($final.Current-ne 0 -and $final.CurrentVt-eq $GameInfoVtable)
$pub=($curOK -and $final.Net-eq $final.Current)

$verdict=if($cb8-gt 0 -and $co.Count-gt 0 -and $pub){'PASS'}elseif($cb8-gt 0 -and $co.Count-eq 0){'STATE8_CALLBACK_REACHED_BUT_COMPLETION_BLOCKED'}elseif($cb.Count-gt 0 -and $cb8-eq 0){'CALLBACK_RAN_WITHOUT_STATE8'}elseif($joinReturned -and $cb.Count-eq 0){'JOIN_RETURNED_NO_CALLBACK'}else{'INCONCLUSIVE'}

$out=@(
'============================================================',
' AOTR WOTR STATE8 PREJOIN NATIVE JOIN - FINAL VERDICT',
'============================================================',
("Game PID                    : {0}"-f $GamePid),
("Frontend owner              : {0}"-f $ownerText),
("STATE8_WRITE_ISSUED         : {0}"-f $(if($stateIssued){'YES'}else{'NO'})),
("JOIN_RETURNED               : {0}"-f $(if($joinReturned){'YES'}else{'NO'})),
("WATCHER_CLEAN_EXIT          : {0}"-f $(if($watchClean){'YES'}else{'NO'})),
("CALLBACK_8496C2_HIT_COUNT   : {0}"-f $cb.Count),
("CALLBACK_AT_OWNER_STATE8    : {0}"-f $cb8),
("COMPLETION_84944F_HIT_COUNT : {0}"-f $co.Count),
("COMPLETION_AT_OWNER_STATE8  : {0}"-f $co8),
("CURRENT_AFTER               : {0}"-f (F32 $final.Current)),
("CURRENT_VTABLE_AFTER        : {0}"-f (F32 $final.CurrentVt)),
("DE892C_AFTER                : {0}"-f (F32 $final.Net)),
("OWNER_6A4_AFTER             : {0}"-f $final.State6A4),
("OWNER_304_AFTER             : {0}"-f $final.Owner304),
("CURRENT_C54B78              : {0}"-f $(if($curOK){'YES'}else{'NO'})),
("DE892C_EQUALS_CURRENT       : {0}"-f $(if($pub){'YES'}else{'NO'})),
("FAILURE_STATE_RESTORED      : {0}"-f $(if($stateRestored){'YES'}else{'NO'})),
'',
("STATE8_PREJOIN_CAUSAL_RESULT = {0}"-f $verdict)
)-join "`r`n"
Set-Content -LiteralPath $rlog -Value $out -Encoding UTF8
Write-Host ''
Write-Host $out
Write-Host ''
Write-Host ("RESULT_FILE : {0}"-f $rlog)
Write-Host ("WATCH_LOG   : {0}"-f $wout)
Write-Host ("JOIN_LOG    : {0}"-f $jlog)
if(-not[string]::IsNullOrWhiteSpace((Read-TextSafe $werr))){Write-Host 'WATCHER STDERR NON-EMPTY:' -ForegroundColor Yellow;Write-Host (Read-TextSafe $werr)}
