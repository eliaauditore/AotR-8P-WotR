param(
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [string]$ExpectedRemoteIp = '192.168.0.224',
    [int]$ExpectedRemotePort = 8086,
    [int]$ObserveSeconds = 8,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# CONTROLLED RUNTIME EXPERIMENT.
# Reproduces the normal client sequence more faithfully than the older low-level PoC:
#   1) exactly one explicit game-state write: frontendOwner+0x6A4 1 -> 8
#   2) one remote x86 thread performs, in order:
#        ECX=session; push zeroEndpoint; push remoteGI; call [session.vt+0x40]
#        ECX=frontendOwner; call 0x008472BF
#   3) observe native completion/publication and owner UI flags.
# No direct write to DE892C, DE8930, session+0x44, owner+0x6BC, GameInfo, or PlayerInfo.
# game.dat on disk is never modified.

$ExpectedHash       = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$OwnerGlobal        = [uint32]0x00DE8D90
$SessionGlobal      = [uint32]0x00DE4394
$NetworkGlobal      = [uint32]0x00DE892C
$ActiveGlobal       = [uint32]0x00DE7D6C
$SessionVtable      = [uint32]0x00C54CE0
$GameInfoVtable     = [uint32]0x00C54B78
$JoinMethod         = [uint32]0x0084CB34
$PostJoinMethod     = [uint32]0x008472BF
$OwnerStateOffset   = [uint32]0x000006A4
$Owner304Offset     = [uint32]0x00000304
$OwnerFlagsOffset   = [uint32]0x000006BC

if ([Environment]::Is64BitProcess) {
    throw 'Run under 32-bit Windows PowerShell: C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
}
if ($ExpectedRemotePort -lt 1 -or $ExpectedRemotePort -gt 65535) { throw 'ExpectedRemotePort must be 1..65535.' }
if ($ObserveSeconds -lt 2 -or $ObserveSeconds -gt 30) { throw 'ObserveSeconds must be 2..30.' }
if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }
New-Item -ItemType Directory -Path $ResearchRoot -Force | Out-Null

$games = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -ieq 'game.dat' -and $_.ExecutablePath -ieq $GameDat
})
if ($games.Count -ne 1) { throw "Expected exactly one game.dat at '$GameDat'. Found $($games.Count)." }
$GamePid = [int]$games[0].ProcessId

if (-not ('AotrJoinPost8472V1' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class AotrJoinPost8472V1 {
    [DllImport("kernel32.dll",SetLastError=true)] public static extern IntPtr OpenProcess(uint a,bool i,uint p);
    [DllImport("kernel32.dll",SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll",SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr h,IntPtr a,byte[] b,UIntPtr n,out UIntPtr g);
    [DllImport("kernel32.dll",SetLastError=true)] public static extern bool WriteProcessMemory(IntPtr h,IntPtr a,byte[] b,UIntPtr n,out UIntPtr w);
    [DllImport("kernel32.dll",SetLastError=true)] public static extern IntPtr VirtualAllocEx(IntPtr h,IntPtr a,UIntPtr n,uint t,uint p);
    [DllImport("kernel32.dll",SetLastError=true)] public static extern bool VirtualFreeEx(IntPtr h,IntPtr a,UIntPtr n,uint t);
    [DllImport("kernel32.dll",SetLastError=true)] public static extern bool FlushInstructionCache(IntPtr h,IntPtr a,UIntPtr n);
    [DllImport("kernel32.dll",SetLastError=true)] public static extern IntPtr CreateRemoteThread(IntPtr h,IntPtr sa,UIntPtr ss,IntPtr start,IntPtr arg,uint flags,out uint tid);
    [DllImport("kernel32.dll",SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h,uint ms);
    [DllImport("kernel32.dll",SetLastError=true)] public static extern bool GetExitCodeThread(IntPtr h,out uint code);
    public static void ThrowLast(string what){ throw new Win32Exception(Marshal.GetLastWin32Error(),what); }
}
'@
}

$PROCESS_CREATE_THREAD     = [uint32]0x0002
$PROCESS_VM_OPERATION      = [uint32]0x0008
$PROCESS_VM_READ           = [uint32]0x0010
$PROCESS_VM_WRITE          = [uint32]0x0020
$PROCESS_QUERY_INFORMATION = [uint32]0x0400
$Access = $PROCESS_CREATE_THREAD -bor $PROCESS_VM_OPERATION -bor $PROCESS_VM_READ -bor $PROCESS_VM_WRITE -bor $PROCESS_QUERY_INFORMATION
$MEM_COMMIT  = [uint32]0x1000
$MEM_RESERVE = [uint32]0x2000
$MEM_RELEASE = [uint32]0x8000
$PAGE_EXECUTE_READWRITE = [uint32]0x40
$WAIT_OBJECT_0 = [uint32]0
$WAIT_TIMEOUT = [uint32]258

$hProcess = [AotrJoinPost8472V1]::OpenProcess($Access,$false,[uint32]$GamePid)
if ($hProcess -eq [IntPtr]::Zero) { [AotrJoinPost8472V1]::ThrowLast('OpenProcess failed') }

function F32([uint32]$v){ '0x{0:X8}' -f $v }
function Read-Bytes([uint32]$addr,[int]$count){
    $b=New-Object byte[] $count; $got=[UIntPtr]::Zero
    if(-not [AotrJoinPost8472V1]::ReadProcessMemory($hProcess,[IntPtr]([int64]$addr),$b,[UIntPtr]$count,[ref]$got) -or $got.ToUInt64()-ne [uint64]$count){
        [AotrJoinPost8472V1]::ThrowLast(('ReadProcessMemory failed at 0x{0:X8}' -f $addr))
    }
    $b
}
function Read-U32([uint32]$addr){ [BitConverter]::ToUInt32((Read-Bytes $addr 4),0) }
function Read-U16([uint32]$addr){ [BitConverter]::ToUInt16((Read-Bytes $addr 2),0) }
function Write-Bytes([uint32]$addr,[byte[]]$bytes){
    $w=[UIntPtr]::Zero
    if(-not [AotrJoinPost8472V1]::WriteProcessMemory($hProcess,[IntPtr]([int64]$addr),$bytes,[UIntPtr]$bytes.Length,[ref]$w) -or $w.ToUInt64()-ne [uint64]$bytes.Length){
        [AotrJoinPost8472V1]::ThrowLast(('WriteProcessMemory failed at 0x{0:X8}' -f $addr))
    }
}
function Write-U32([uint32]$addr,[uint32]$value){ Write-Bytes $addr ([BitConverter]::GetBytes($value)) }
function Add-Imm32([System.Collections.Generic.List[byte]]$list,[uint32]$value){ foreach($b in [BitConverter]::GetBytes($value)){[void]$list.Add($b)} }
function Format-IPv4BE([uint32]$raw){ '{0}.{1}.{2}.{3}' -f (($raw-shr 24)-band 0xFF),(($raw-shr 16)-band 0xFF),(($raw-shr 8)-band 0xFF),($raw-band 0xFF) }
function Format-Endpoint([uint32]$ip,[uint16]$port){ if($ip-eq 0 -and $port-eq 0){'{0,0}'}else{'{0}:{1}' -f (Format-IPv4BE $ip),$port} }

$remotePage=[IntPtr]::Zero
$thread=[IntPtr]::Zero
$freeRemote=$false
$stateWriteIssued=$false
$stateRestored=$false
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$resultFile=Join-Path $ResearchRoot ("STATE8_JOIN_POST8472_RESULT_$stamp.txt")
$lines=New-Object System.Collections.Generic.List[string]
function Log([string]$s){ Write-Host $s; [void]$lines.Add($s) }

try {
    Log '============================================================'
    Log ' AOTR STATE8 + NATIVE JOIN + ORIGINAL POSTJOIN 0x8472BF V1'
    Log '============================================================'
    Log ("PID                  : {0}" -f $GamePid)
    Log ("Image                : {0}" -f $GameDat)
    Log ("SHA256               : {0}" -f $hash)
    Log ("Expected host        : {0}:{1}" -f $ExpectedRemoteIp,$ExpectedRemotePort)
    Log 'WRITE CONTRACT       : exactly owner+0x6A4 1->8; no direct writes to publication/UI flags'
    Log ''

    $owner=Read-U32 $OwnerGlobal
    if($owner-eq 0){throw 'Safety gate: DE8D90 frontend owner is NULL.'}
    $stateAddr=[uint32]($owner+$OwnerStateOffset)
    $flagsAddr=[uint32]($owner+$OwnerFlagsOffset)
    $ownerState=Read-U32 $stateAddr
    $owner304=Read-U32 ([uint32]($owner+$Owner304Offset))
    $flagsBefore=Read-U32 $flagsAddr
    $session=Read-U32 $SessionGlobal
    $netBefore=Read-U32 $NetworkGlobal
    $activeBefore=Read-U32 $ActiveGlobal

    if($ownerState-ne 1 -or $owner304-ne 1){throw "Safety gate: owner state=$ownerState/$owner304; expected 1/1."}
    if(($flagsBefore -band [uint32]3) -ne 3){throw ('Safety gate: owner+0x6BC lower bits are 0x{0:X}; expected both EnableCreate/EnableJoin bits set (3).' -f ($flagsBefore-band 3))}
    if($session-eq 0){throw 'Safety gate: session singleton NULL.'}
    $sessionVt=Read-U32 $session
    if($sessionVt-ne $SessionVtable){throw ('Safety gate: session vtable {0} != {1}' -f (F32 $sessionVt),(F32 $SessionVtable))}
    $sessionState=Read-U32 ([uint32]($session+0x28))
    $currentBefore=Read-U32 ([uint32]($session+0x44))
    if($sessionState-ne 0 -and $sessionState-ne 2){throw "Safety gate: session+0x28=$sessionState; expected 0 or 2."}
    if($currentBefore-ne 0){throw ('Safety gate: session+0x44 already {0}.' -f (F32 $currentBefore))}
    if($netBefore-ne 0){throw ('Safety gate: DE892C already {0}.' -f (F32 $netBefore))}
    $joinTarget=Read-U32 ([uint32]($sessionVt+0x40))
    if($joinTarget-ne $JoinMethod){throw ('Safety gate: session.vt+0x40 {0} != {1}' -f (F32 $joinTarget),(F32 $JoinMethod))}

    $localIp=Read-U32 ([uint32]($session+0x48))
    $localPort=Read-U16 ([uint32]($session+0x4C))
    $listHead=Read-U32 ([uint32]($session+0x10))

    Log '================ PRE-CALL CONTRACT ================'
    Log ("owner                : {0}" -f (F32 $owner))
    Log ("owner+0x6A4         : {0} value=1" -f (F32 $stateAddr))
    Log ("owner+0x304         : 1")
    Log ("owner+0x6BC         : {0} lowerBits={1} (Create+Join enabled)" -f (F32 $flagsBefore),($flagsBefore-band 3))
    Log ("session              : {0} vt={1}" -f (F32 $session),(F32 $sessionVt))
    Log ("session+0x28        : {0}" -f $sessionState)
    Log ("session+0x44        : NULL")
    Log ("DE892C              : NULL")
    Log ("local endpoint      : {0}" -f (Format-Endpoint $localIp $localPort))
    Log ("join target         : {0}" -f (F32 $joinTarget))
    Log ("postjoin target     : {0}" -f (F32 $PostJoinMethod))
    Log ''

    $matches=@(); $seen=@{}; $p=[uint32]$listHead; $idx=0
    while($p-ne 0 -and $idx-lt 32){
        $k=F32 $p; if($seen.ContainsKey($k)){throw 'Safety gate: cycle in session GameInfo list.'}; $seen[$k]=$true
        $vt=Read-U32 $p; $next=Read-U32 ([uint32]($p+0xFBC)); $row0=Read-U32 ([uint32]($p+0x18))
        $type=[uint32]::MaxValue; $ip=[uint32]0; $port=[uint16]0
        if($row0-ne 0){$type=Read-U32 ([uint32]($row0+4));$ip=Read-U32 ([uint32]($row0+0x38));$port=Read-U16 ([uint32]($row0+0x3C))}
        $match=($vt-eq $GameInfoVtable -and $row0-ne 0 -and $type-eq 6 -and (Format-IPv4BE $ip)-eq $ExpectedRemoteIp -and $port-eq $ExpectedRemotePort)
        Log ("[{0}] GI={1} vtOK={2} type={3} endpoint={4} targetMatch={5}" -f $idx,(F32 $p),($vt-eq $GameInfoVtable),$type,(Format-Endpoint $ip $port),$match)
        if($match){$matches += [uint32]$p}
        $p=[uint32]$next; $idx++
    }
    if($matches.Count-ne 1){throw "Safety gate: expected exactly one remote GameInfo match; found $($matches.Count)."}
    $arg1=[uint32]$matches[0]

    # Revalidate immediately before the one authorized state write.
    if((Read-U32 $OwnerGlobal)-ne $owner){throw 'Prewrite gate: frontend owner changed.'}
    if((Read-U32 $stateAddr)-ne 1){throw 'Prewrite gate: owner+0x6A4 no longer 1.'}
    if(((Read-U32 $flagsAddr)-band [uint32]3)-ne 3){throw 'Prewrite gate: Create/Join enable bits changed.'}
    if((Read-U32 ([uint32]($session+0x44)))-ne 0){throw 'Prewrite gate: session current became non-NULL.'}
    if((Read-U32 $NetworkGlobal)-ne 0){throw 'Prewrite gate: DE892C became non-NULL.'}
    if((Read-U32 $arg1)-ne $GameInfoVtable){throw 'Prewrite gate: selected GameInfo vtable changed.'}

    $remotePage=[AotrJoinPost8472V1]::VirtualAllocEx($hProcess,[IntPtr]::Zero,[UIntPtr]0x1000,($MEM_COMMIT-bor$MEM_RESERVE),$PAGE_EXECUTE_READWRITE)
    if($remotePage-eq [IntPtr]::Zero){[AotrJoinPost8472V1]::ThrowLast('VirtualAllocEx failed')}
    $rb64=$remotePage.ToInt64(); if($rb64-lt 0 -or $rb64-gt [uint32]::MaxValue){throw 'Remote allocation outside 32-bit address space.'}
    $rb=[uint32]$rb64; $endpoint=$rb; $stubAddr=[uint32]($rb+0x20); $freeRemote=$true
    Write-Bytes $endpoint ([byte[]](0,0,0,0,0,0))

    # Exact ordered x86 stub:
    #   mov ecx,session
    #   push endpoint
    #   push arg1
    #   mov eax,[ecx]
    #   call [eax+0x40]
    #   mov ecx,owner
    #   mov eax,0x008472BF
    #   call eax
    #   xor eax,eax
    #   ret 4
    $stub=New-Object 'System.Collections.Generic.List[byte]'
    [void]$stub.Add(0xB9); Add-Imm32 $stub $session
    [void]$stub.Add(0x68); Add-Imm32 $stub $endpoint
    [void]$stub.Add(0x68); Add-Imm32 $stub $arg1
    [void]$stub.Add(0x8B); [void]$stub.Add(0x01)
    [void]$stub.Add(0xFF); [void]$stub.Add(0x50); [void]$stub.Add(0x40)
    [void]$stub.Add(0xB9); Add-Imm32 $stub $owner
    [void]$stub.Add(0xB8); Add-Imm32 $stub $PostJoinMethod
    [void]$stub.Add(0xFF); [void]$stub.Add(0xD0)
    [void]$stub.Add(0x33); [void]$stub.Add(0xC0)
    [void]$stub.Add(0xC2); [void]$stub.Add(0x04); [void]$stub.Add(0x00)
    $stubBytes=$stub.ToArray()
    Write-Bytes $stubAddr $stubBytes
    [void][AotrJoinPost8472V1]::FlushInstructionCache($hProcess,[IntPtr]([int64]$stubAddr),[UIntPtr]$stubBytes.Length)

    Log ''
    Log '================ CONTROLLED EXECUTION ================'
    Write-U32 $stateAddr ([uint32]8)
    $stateWriteIssued=$true
    $rbState=Read-U32 $stateAddr
    if($rbState-ne 8){throw "STATE8_WRITE_READBACK_FAILED value=$rbState"}
    Log 'STATE8_WRITE_API_PASS readback=8'
    Log ("remote page          : {0}" -f (F32 $rb))
    Log ("thread stub          : {0} ({1} bytes)" -f (F32 $stubAddr),$stubBytes.Length)
    Log 'ORDER                : State8 -> session+0x40 -> owner/0x8472BF'

    $tid=[uint32]0
    $thread=[AotrJoinPost8472V1]::CreateRemoteThread($hProcess,[IntPtr]::Zero,[UIntPtr]::Zero,[IntPtr]([int64]$stubAddr),[IntPtr]::Zero,0,[ref]$tid)
    if($thread-eq [IntPtr]::Zero){[AotrJoinPost8472V1]::ThrowLast('CreateRemoteThread failed')}
    Log ("remote thread id     : {0}" -f $tid)
    $wait=[AotrJoinPost8472V1]::WaitForSingleObject($thread,10000)
    if($wait-eq $WAIT_TIMEOUT){$freeRemote=$false;throw 'Remote thread timeout; page intentionally left allocated.'}
    if($wait-ne $WAIT_OBJECT_0){$freeRemote=$false;throw ('WaitForSingleObject returned 0x{0:X8}; page left allocated.' -f $wait)}
    $exit=[uint32]0; if(-not [AotrJoinPost8472V1]::GetExitCodeThread($thread,[ref]$exit)){[AotrJoinPost8472V1]::ThrowLast('GetExitCodeThread failed')}
    Log ("thread exit code     : 0x{0:X8}" -f $exit)
    Log 'JOIN_AND_POSTJOIN_THREAD_RETURNED=YES'

    $deadline=[DateTime]::UtcNow.AddSeconds($ObserveSeconds)
    do {
        Start-Sleep -Milliseconds 50
        $current=Read-U32 ([uint32]($session+0x44))
        $net=Read-U32 $NetworkGlobal
        $st=Read-U32 $stateAddr
        if($current-ne 0 -and $net-eq $current -and $st-eq 9){break}
    } while([DateTime]::UtcNow-lt $deadline)

    $currentAfter=Read-U32 ([uint32]($session+0x44))
    $currentVt=if($currentAfter-ne 0){Read-U32 $currentAfter}else{[uint32]0}
    $netAfter=Read-U32 $NetworkGlobal
    $activeAfter=Read-U32 $ActiveGlobal
    $stateAfter=Read-U32 $stateAddr
    $flagsAfter=Read-U32 $flagsAddr
    $flagsLowAfter=[uint32]($flagsAfter-band 3)

    Log ''
    Log '================ FINAL STATE ================'
    Log ("CURRENT_AFTER               : {0}" -f (F32 $currentAfter))
    Log ("CURRENT_VTABLE_AFTER        : {0}" -f (F32 $currentVt))
    Log ("DE892C_AFTER                : {0}" -f (F32 $netAfter))
    Log ("TheGameInfo_AFTER           : {0}" -f (F32 $activeAfter))
    Log ("OWNER_6A4_AFTER             : {0}" -f $stateAfter)
    Log ("OWNER_6BC_AFTER             : {0} lowerBits={1}" -f (F32 $flagsAfter),$flagsLowAfter)
    Log ("CURRENT_C54B78              : {0}" -f ($(if($currentVt-eq $GameInfoVtable){'YES'}else{'NO'})))
    Log ("DE892C_EQUALS_CURRENT       : {0}" -f ($(if($currentAfter-ne 0 -and $netAfter-eq $currentAfter){'YES'}else{'NO'})))
    Log ("POSTJOIN_CREATE_JOIN_BITS_0 : {0}" -f ($(if($flagsLowAfter-eq 0){'YES'}else{'NO'})))

    $pass=($currentAfter-ne 0 -and $currentVt-eq $GameInfoVtable -and $netAfter-eq $currentAfter -and $stateAfter-eq 9 -and $flagsLowAfter-eq 0)
    if($pass){
        Log ''
        Log 'STATE8_JOIN_POST8472_RESULT = PASS_NATIVE_POSTJOIN_SHAPE'
        Log 'NEXT_MANUAL_ACTION = Select exactly one WotR territory on the VM and report whether game stays open.'
    } else {
        Log ''
        Log 'STATE8_JOIN_POST8472_RESULT = INCOMPLETE_OR_FAILED'
    }
}
catch {
    $msg=$_.Exception.Message
    Log ''
    Log ("ERROR: {0}" -f $msg)
    # Restore only the one explicit state write if nothing joined/published and state is still exactly 8.
    try {
        if($stateWriteIssued){
            $s=Read-U32 $stateAddr; $cur=Read-U32 ([uint32]($session+0x44)); $net=Read-U32 $NetworkGlobal
            if($s-eq 8 -and $cur-eq 0 -and $net-eq 0){Write-U32 $stateAddr ([uint32]1); if((Read-U32 $stateAddr)-eq 1){$stateRestored=$true;Log 'SAFE_FAILURE_RESTORE_VERIFIED 8->1'}}
        }
    } catch { Log ("RESTORE_CHECK_ERROR: {0}" -f $_.Exception.Message) }
    throw
}
finally {
    try { if($thread-ne [IntPtr]::Zero){[void][AotrJoinPost8472V1]::CloseHandle($thread)} } catch {}
    try { if($freeRemote -and $remotePage-ne [IntPtr]::Zero){[void][AotrJoinPost8472V1]::VirtualFreeEx($hProcess,$remotePage,[UIntPtr]::Zero,$MEM_RELEASE)} } catch {}
    try { [void][AotrJoinPost8472V1]::CloseHandle($hProcess) } catch {}
    try { Set-Content -LiteralPath $resultFile -Value ($lines -join "`r`n") -Encoding UTF8 } catch {}
    Write-Host ''
    Write-Host ("RESULT_FILE : {0}" -f $resultFile)
}
