param(
    [ValidateSet(1,3,4)]
    [int]$LocalSlot = 4,

    [ValidateSet('Easy','Medium','Hard','Brutal')]
    [string]$AiDifficulty = 'Medium',

    [int]$ProcessId = 0,
    [int]$TimeoutSeconds = 120,
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# AOTR WOTR PHASE 4D - ROW+0x10 BRIDGE TEST
#
# DRY RUN (default): validates the canonical binary and exact native ABI/seam bytes.
# EXECUTE:
#   1) constructs a private native GameInfo in remote scratch memory,
#   2) verifies AotR's real local resolver on that object,
#   3) transiently patches 0x932F12 so the already-selected GameInfo* in EAX is
#      replaced only for this consumer invocation with the private CompatibilityGameInfo,
#   4) observes the 0x9330B7 -> 0x6BB3B5 LivingWorldPlayer call site,
#   5) restores both code patches.
#
# It DOES NOT write DE892C, DE8930, session+0x44, or game.dat on disk.
# After a successful handoff the private CompatibilityGameInfo allocation is
# intentionally left alive until game.dat exits, avoiding a possible use-after-free
# if downstream LivingWorld code retains references during startup.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ExpectedImageBase = [int64]0x00400000

$GameInfoCtorVA       = [uint32]0x00628B3A
$GameInfoResetVA      = [uint32]0x00801AAF
$PlayerInfoAssignVA   = [uint32]0x008014F1
$GameInfoActivateVA   = [uint32]0x00800B1E
$LocalResolverVA      = [uint32]0x00800B8C
$GameInfoDtorVA       = [uint32]0x00628BBA
$StringCopyCtorVA     = [uint32]0x00436990
$GameInfoVtableVA     = [uint32]0x00BFD668
$EmptyStringVA        = [uint32]0x00DF25F0
$LocalizationGlobalVA = [uint32]0x00DE4B04

$HandoffVA       = [uint32]0x00932F12
$LivingCallVA    = [uint32]0x009330B7
$LivingTargetVA  = [uint32]0x006BB3B5
[byte[]]$HandoffOriginal = 0x8B,0xC8,0x85,0xC9,0x89,0x45,0xE8
[byte[]]$LivingOriginal  = 0xE8,0xF9,0x82,0xD8,0xFF

$GameInfoSize   = 0xE9C
$ScratchSize    = 0x5000
$CodeOffset     = 0x0000
$GameInfoOffset = 0x1000
$ResultOffset   = 0x2000
$EndpointOffset = 0x2200
$HandoffStubOffset = 0x3000
$LivingStubOffset  = 0x3100
$ResultSize     = 0x0200

$ExpectedNativeIndex = $LocalSlot - 1
$AiType = switch ($AiDifficulty) {
    'Easy'   { 2 }
    'Medium' { 3 }
    'Hard'   { 4 }
    'Brutal' { 5 }
    default  { throw 'Unexpected AiDifficulty.' }
}
[int[]]$RowTypes = @(6,$AiType,6,6,1,1,1,1)
[uint32[]]$RowIps = @(
    [uint32]0x0A080001,[uint32]0,[uint32]0x0A080003,[uint32]0x0A080004,
    [uint32]0,[uint32]0,[uint32]0,[uint32]0
)
[uint16[]]$RowPorts = @(
    [uint16]42888,[uint16]0,[uint16]42888,[uint16]42888,
    [uint16]0,[uint16]0,[uint16]0,[uint16]0
)

if (-not ('A8PPhase4BNative' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PPhase4BNative
{
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr addr, byte[] buf, IntPtr size, out IntPtr written);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr addr, UIntPtr size, UInt32 allocType, UInt32 protect);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool VirtualProtectEx(IntPtr hProcess, IntPtr addr, UIntPtr size, UInt32 newProtect, out UInt32 oldProtect);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool FlushInstructionCache(IntPtr hProcess, IntPtr addr, UIntPtr size);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr CreateRemoteThread(IntPtr hProcess, IntPtr attrs, UIntPtr stackSize, IntPtr start, IntPtr param, UInt32 flags, out UInt32 tid);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern UInt32 WaitForSingleObject(IntPtr hHandle, UInt32 milliseconds);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool GetExitCodeThread(IntPtr hThread, out UInt32 exitCode);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenThread(UInt32 access, bool inherit, UInt32 tid);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern UInt32 SuspendThread(IntPtr hThread);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern UInt32 ResumeThread(IntPtr hThread);

    public static void ThrowLast(string what)
    {
        throw new Win32Exception(Marshal.GetLastWin32Error(), what);
    }
}
"@
}

$PROCESS_CREATE_THREAD     = [uint32]0x0002
$PROCESS_VM_OPERATION      = [uint32]0x0008
$PROCESS_VM_READ           = [uint32]0x0010
$PROCESS_VM_WRITE          = [uint32]0x0020
$PROCESS_QUERY_INFORMATION = [uint32]0x0400
$Access = $PROCESS_CREATE_THREAD -bor $PROCESS_VM_OPERATION -bor $PROCESS_VM_READ -bor $PROCESS_VM_WRITE -bor $PROCESS_QUERY_INFORMATION
$THREAD_SUSPEND_RESUME = [uint32]0x0002
$MEM_COMMIT  = [uint32]0x1000
$MEM_RESERVE = [uint32]0x2000
$PAGE_EXECUTE_READWRITE = [uint32]0x40
$WAIT_OBJECT_0 = [uint32]0
$WAIT_TIMEOUT  = [uint32]258

if ($ProcessId -le 0) {
    $games = @(Get-Process -Name 'game.dat' -ErrorAction SilentlyContinue)
    if ($games.Count -ne 1) { throw "Expected exactly one game.dat process; found $($games.Count). Pass -ProcessId explicitly." }
    $ProcessId = [int]$games[0].Id
}

$proc = Get-Process -Id $ProcessId -ErrorAction Stop
$exe = $proc.MainModule.FileName
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH - expected $ExpectedHash, got $hash" }
$base = $proc.MainModule.BaseAddress.ToInt64()
if ($base -ne $ExpectedImageBase) { throw ("Unexpected image base 0x{0:X8}" -f $base) }

$hProcess = [A8PPhase4BNative]::OpenProcess($Access,$false,[uint32]$ProcessId)
if ($hProcess -eq [IntPtr]::Zero) { [A8PPhase4BNative]::ThrowLast('OpenProcess failed') }

function Read-Bytes([int64]$Address,[int]$Count) {
    $buf = New-Object byte[] $Count
    $got = [IntPtr]::Zero
    if (-not [A8PPhase4BNative]::ReadProcessMemory($hProcess,[IntPtr]$Address,$buf,[IntPtr]$Count,[ref]$got) -or $got.ToInt64() -ne $Count) {
        [A8PPhase4BNative]::ThrowLast(("ReadProcessMemory 0x{0:X8}" -f $Address))
    }
    return $buf
}
function Read-U32([int64]$Address) { return [BitConverter]::ToUInt32((Read-Bytes $Address 4),0) }
function Read-I32([int64]$Address) { return [BitConverter]::ToInt32((Read-Bytes $Address 4),0) }
function Read-U16([int64]$Address) { return [BitConverter]::ToUInt16((Read-Bytes $Address 2),0) }
function Write-Bytes([int64]$Address,[byte[]]$Bytes) {
    $w=[IntPtr]::Zero
    if (-not [A8PPhase4BNative]::WriteProcessMemory($hProcess,[IntPtr]$Address,$Bytes,[IntPtr]$Bytes.Length,[ref]$w) -or $w.ToInt64() -ne $Bytes.Length) {
        [A8PPhase4BNative]::ThrowLast(("WriteProcessMemory 0x{0:X8}" -f $Address))
    }
}
function Hex([byte[]]$Bytes) { return (($Bytes | ForEach-Object {$_.ToString('X2')}) -join ' ') }
function Assert-Exact([uint32]$Address,[byte[]]$Expected,[string]$Name) {
    $actual=Read-Bytes $Address $Expected.Length
    if ((Hex $actual) -ne (Hex $Expected)) { throw "$Name byte guard failed. Expected $(Hex $Expected), got $(Hex $actual)" }
    Write-Host "PASS bytes $Name @ $('0x{0:X8}' -f $Address)"
}
function Assert-Hex([uint32]$Address,[string]$ExpectedHex,[string]$Name) {
    [byte[]]$expected=@($ExpectedHex.Split(' ',[System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object {[Convert]::ToByte($_,16)})
    Assert-Exact $Address $expected $Name
}
function Rel32([uint32]$FromAfter,[uint32]$To) {
    $d=[int64]$To-[int64]$FromAfter
    if ($d -lt [int32]::MinValue -or $d -gt [int32]::MaxValue) { throw 'rel32 target out of range' }
    return [BitConverter]::GetBytes([int32]$d)
}
function Format-Endpoint([uint32]$Ip,[uint16]$Port) {
    if ($Ip -eq 0 -and $Port -eq 0) { return '{0,0}' }
    return ('{0}.{1}.{2}.{3}:{4}' -f (($Ip -shr 24)-band 255),(($Ip -shr 16)-band 255),(($Ip -shr 8)-band 255),($Ip-band 255),$Port)
}

$threadHandles = New-Object 'System.Collections.Generic.List[System.IntPtr]'
function Suspend-GameThreads {
    $threadHandles.Clear()
    $p=Get-Process -Id $ProcessId -ErrorAction Stop
    foreach($t in $p.Threads) {
        $h=[A8PPhase4BNative]::OpenThread($THREAD_SUSPEND_RESUME,$false,[uint32]$t.Id)
        if ($h -ne [IntPtr]::Zero) {
            $r=[A8PPhase4BNative]::SuspendThread($h)
            if ($r -ne [uint32]::MaxValue) { [void]$threadHandles.Add($h) }
            else { [void][A8PPhase4BNative]::CloseHandle($h) }
        }
    }
}
function Resume-GameThreads {
    foreach($h in $threadHandles) {
        [void][A8PPhase4BNative]::ResumeThread($h)
        [void][A8PPhase4BNative]::CloseHandle($h)
    }
    $threadHandles.Clear()
}
function Make-Writable([uint32]$Address,[int]$Length) {
    [uint32]$old=0
    if (-not [A8PPhase4BNative]::VirtualProtectEx($hProcess,[IntPtr]$Address,[UIntPtr]::new([uint64]$Length),$PAGE_EXECUTE_READWRITE,[ref]$old)) {
        [A8PPhase4BNative]::ThrowLast(("VirtualProtectEx 0x{0:X8}" -f $Address))
    }
    return $old
}
function Restore-Protect([uint32]$Address,[int]$Length,[uint32]$Old) {
    [uint32]$tmp=0
    [void][A8PPhase4BNative]::VirtualProtectEx($hProcess,[IntPtr]$Address,[UIntPtr]::new([uint64]$Length),$Old,[ref]$tmp)
}

$remote=[IntPtr]::Zero
$thread=[IntPtr]::Zero
$patchedHandoff=$false
$patchedLiving=$false
$injected=$false

try {
    Write-Host '============================================================'
    Write-Host ' AOTR PHASE 4D - ROW+0x10 BRIDGE TEST'
    Write-Host '============================================================'
    Write-Host ("Mode       : {0}" -f ($(if($Execute){'EXECUTE'}else{'DRY RUN'})))
    Write-Host ("PID        : {0}" -f $ProcessId)
    Write-Host ("Image      : {0}" -f $exe)
    Write-Host ("SHA256     : {0}" -f $hash)
    Write-Host ("Image base : 0x{0:X8}" -f $base)
    Write-Host ("Local slot : P{0} (expected native index {1})" -f $LocalSlot,$ExpectedNativeIndex)

    Assert-Hex $GameInfoCtorVA '55 8B EC 6A FF 68 A0 15 B6 00' 'GameInfo ctor'
    Assert-Hex $GameInfoResetVA '55 8B EC 83 EC 0C 53 56 57 8B F9' 'GameInfo reset'
    Assert-Hex $PlayerInfoAssignVA '55 8B EC 51 53 56 57 8B F9' 'PlayerInfo assign'
    Assert-Hex $GameInfoActivateVA '55 8B EC 56 8B F1 8B 4E 08 85 C9' 'GameInfo activate'
    Assert-Hex $LocalResolverVA '55 8B EC 53 56 8B F1 57 8B 4E 10' 'Local resolver'
    Assert-Hex $GameInfoDtorVA '55 8B EC 56 8B F1 C7 06 68 D6 BF 00' 'GameInfo dtor'
    Assert-Hex $StringCopyCtorVA '55 8B EC 8B 55 08 56 8B F1 85 D2' 'String copy ctor'
    Assert-Exact $HandoffVA $HandoffOriginal '0x932F12 handoff seam'
    Assert-Exact $LivingCallVA $LivingOriginal '0x9330B7 LivingWorld call'

    if((Read-U32 $GameInfoVtableVA)-ne $GameInfoDtorVA -or (Read-U32 ([int64]$GameInfoVtableVA+0x28))-ne $GameInfoResetVA -or (Read-U32 ([int64]$GameInfoVtableVA+0x34))-ne $LocalResolverVA){throw 'BFD668 vtable guard failed'}
    Write-Host 'PASS BFD668 vtable'
    $loc=Read-U32 $LocalizationGlobalVA
    if($loc -eq 0){throw 'Localization singleton is NULL'}
    Write-Host ("PASS localization singleton 0x{0:X8}" -f $loc)

    if(-not $Execute){
        Write-Host ''
        Write-Host 'PHASE4D_STATIC_GATES=PASS'
        Write-Host 'CONSUMER_INJECTION=NOT_RUN'
        return
    }

    $remote=[A8PPhase4BNative]::VirtualAllocEx($hProcess,[IntPtr]::Zero,[UIntPtr]::new([uint64]$ScratchSize),$MEM_COMMIT -bor $MEM_RESERVE,$PAGE_EXECUTE_READWRITE)
    if($remote -eq [IntPtr]::Zero){[A8PPhase4BNative]::ThrowLast('VirtualAllocEx failed')}
    $rb=[uint32]$remote.ToInt64()
    $codeAddr=[uint32]($rb+$CodeOffset)
    $giAddr=[uint32]($rb+$GameInfoOffset)
    $result=[uint32]($rb+$ResultOffset)
    $epBase=[uint32]($rb+$EndpointOffset)
    $handoffStub=[uint32]($rb+$HandoffStubOffset)
    $livingStub=[uint32]($rb+$LivingStubOffset)

    Write-Bytes $result (New-Object byte[] $ResultSize)
    for($i=0;$i -lt 8;$i++){
        $eb=New-Object byte[] 8
        [Array]::Copy([BitConverter]::GetBytes($RowIps[$i]),0,$eb,0,4)
        [Array]::Copy([BitConverter]::GetBytes($RowPorts[$i]),0,$eb,4,2)
        Write-Bytes ([uint32]($epBase+($i*8))) $eb
    }

    $stub=New-Object 'System.Collections.Generic.List[byte]'
    function Emit([byte[]]$Bytes){foreach($b in $Bytes){[void]$stub.Add($b)}}
    function Emit-U32([uint32]$Value){Emit ([BitConverter]::GetBytes($Value))}
    function Emit-MovEaxImm([uint32]$Value){Emit ([byte[]]@(0xB8));Emit-U32 $Value}
    function Emit-CallEax(){Emit ([byte[]]@(0xFF,0xD0))}
    function Emit-StoreEaxAbs([uint32]$Address){Emit ([byte[]]@(0xA3));Emit-U32 $Address}
    function Emit-StoreImm32Abs([uint32]$Address,[uint32]$Value){Emit ([byte[]]@(0xC7,0x05));Emit-U32 $Address;Emit-U32 $Value}

    Emit ([byte[]]@(0x55,0x8B,0xEC,0x53,0x56,0x57))
    Emit ([byte[]]@(0xBE));Emit-U32 $giAddr
    Emit ([byte[]]@(0x8B,0xCE));Emit-MovEaxImm $GameInfoCtorVA;Emit-CallEax
    Emit ([byte[]]@(0x8B,0xCE));Emit-MovEaxImm $GameInfoResetVA;Emit-CallEax

    for($i=0;$i -lt 8;$i++) {
        $rowDisp=[byte](0x18+($i*4))
        $epAddr=[uint32]($epBase+($i*8))
        $type=[byte]$RowTypes[$i]
        Emit ([byte[]]@(0x8B,0x7E,$rowDisp))
        Emit ([byte[]]@(0x68));Emit-U32 $epAddr
        Emit ([byte[]]@(0x83,0xEC,0x04))
        Emit ([byte[]]@(0x8B,0xCC))
        Emit ([byte[]]@(0x68));Emit-U32 $EmptyStringVA
        Emit-MovEaxImm $StringCopyCtorVA;Emit-CallEax
        Emit ([byte[]]@(0x6A,$type))
        Emit ([byte[]]@(0x8B,0xCF));Emit-MovEaxImm $PlayerInfoAssignVA;Emit-CallEax
    }

    $localEpAddr=[uint32]($epBase+(($LocalSlot-1)*8))
    Emit ([byte[]]@(0xA1));Emit-U32 $localEpAddr
    Emit ([byte[]]@(0x89,0x46,0x38))
    Emit ([byte[]]@(0x0F,0xB7,0x05));Emit-U32 ([uint32]($localEpAddr+4))
    Emit ([byte[]]@(0x66,0x89,0x46,0x3C))
    Emit ([byte[]]@(0x8B,0xCE));Emit-MovEaxImm $GameInfoActivateVA;Emit-CallEax

    Emit ([byte[]]@(0x8B,0xCE));Emit-MovEaxImm $LocalResolverVA;Emit-CallEax
    Emit-StoreEaxAbs ([uint32]($result+0x04))
    Emit-StoreImm32Abs ([uint32]($result+0x00)) ([uint32]0x34475242)
    Emit ([byte[]]@(0x8B,0x06));Emit-StoreEaxAbs ([uint32]($result+0x1C))
    Emit ([byte[]]@(0x5F,0x5E,0x5B,0x5D,0x33,0xC0,0xC2,0x04,0x00))

    [byte[]]$stubBytes=$stub.ToArray()
    if($stubBytes.Length -ge $GameInfoOffset){throw 'Construction stub overlaps GameInfo.'}
    Write-Bytes $codeAddr $stubBytes
    [void][A8PPhase4BNative]::FlushInstructionCache($hProcess,[IntPtr]$codeAddr,[UIntPtr]::new([uint64]$stubBytes.Length))

    [uint32]$tid=0
    $thread=[A8PPhase4BNative]::CreateRemoteThread($hProcess,[IntPtr]::Zero,[UIntPtr]::Zero,[IntPtr]$codeAddr,[IntPtr]::Zero,0,[ref]$tid)
    if($thread -eq [IntPtr]::Zero){[A8PPhase4BNative]::ThrowLast('CreateRemoteThread failed')}
    $wait=[A8PPhase4BNative]::WaitForSingleObject($thread,10000)
    if($wait -eq $WAIT_TIMEOUT){throw 'CompatibilityGameInfo construction timed out.'}
    if($wait -ne $WAIT_OBJECT_0){throw "Unexpected construction wait code $wait"}
    [void][A8PPhase4BNative]::CloseHandle($thread);$thread=[IntPtr]::Zero

    $magic=Read-U32 $result
    $nativeIndex=Read-I32 ([int64]$result+0x04)
    $gvt=Read-U32 ([int64]$result+0x1C)
    if($magic -ne [uint32]0x34475242){throw 'Construction result magic mismatch.'}
    if($nativeIndex -ne $ExpectedNativeIndex){throw "Pre-handoff native resolver mismatch: expected $ExpectedNativeIndex, got $nativeIndex"}
    if($gvt -ne $GameInfoVtableVA){throw ("CompatibilityGameInfo vtable mismatch: 0x{0:X8}" -f $gvt)}

    Write-Host ''
    Write-Host ("CompatibilityGameInfo : 0x{0:X8}" -f $giAddr)
    Write-Host ("Native resolver       : {0} PASS" -f $nativeIndex)

    # Handoff hook:
    #   - record native selected GameInfo* from EAX
    #   - copy ONLY PlayerInfo+0x10 from native rows P1-P4 into the private
    #     CompatibilityGameInfo. Phase 4C proved these four active compat rows
    #     were all -1 while native rows were non-negative.
    #   - replace EAX with CompatibilityGameInfo
    #   - execute the original 7 bytes so ECX and [EBP-18] receive our pointer.
    #
    # No global GameInfo publication is changed.
    $h=New-Object 'System.Collections.Generic.List[byte]'
    function HE([byte[]]$x){foreach($v in $x){[void]$h.Add($v)}}
    function HU([uint32]$x){HE ([BitConverter]::GetBytes($x))}
    HE ([byte[]]@(0xFF,0x05));HU ([uint32]($result+0x08))
    HE ([byte[]]@(0xA3));HU ([uint32]($result+0x0C))

    HE ([byte[]]@(0x52))
    HE ([byte[]]@(0x8B,0xD0))

    for($i=0;$i -lt 4;$i++) {
        $row10=[uint32](0xDC+($i*0x1B8)+0x10)
        $compatRow10=[uint32]($giAddr+$row10)
        HE ([byte[]]@(0x8B,0x82));HU $row10
        HE ([byte[]]@(0xA3));HU $compatRow10
    }

    HE ([byte[]]@(0x5A))
    HE ([byte[]]@(0xB8));HU $giAddr
    HE ([byte[]]@(0xA3));HU ([uint32]($result+0x10))
    HE $HandoffOriginal
    HE ([byte[]]@(0xE9));HE (Rel32 ([uint32]($handoffStub+$h.Count+4)) ([uint32]($HandoffVA+7)))
    [byte[]]$hb=$h.ToArray()

    $l=New-Object 'System.Collections.Generic.List[byte]'
    function LE([byte[]]$x){foreach($v in $x){[void]$l.Add($v)}}
    function LU([uint32]$x){LE ([BitConverter]::GetBytes($x))}
    LE ([byte[]]@(0x9C))
    LE ([byte[]]@(0xFF,0x05));LU ([uint32]($result+0x14))
    LE ([byte[]]@(0x89,0x35));LU ([uint32]($result+0x18))
    LE ([byte[]]@(0x9D))
    LE ([byte[]]@(0xE9));LE (Rel32 ([uint32]($livingStub+$l.Count+4)) $LivingTargetVA)
    [byte[]]$lb=$l.ToArray()

    Write-Bytes $handoffStub $hb
    Write-Bytes $livingStub $lb
    [byte[]]$patchH=@(0xE9)+(Rel32 ([uint32]($HandoffVA+5)) $handoffStub)+@(0x90,0x90)
    [byte[]]$patchL=@(0xE8)+(Rel32 ([uint32]($LivingCallVA+5)) $livingStub)

    Suspend-GameThreads
    try {
        $oldH=Make-Writable $HandoffVA $HandoffOriginal.Length
        $oldL=Make-Writable $LivingCallVA $LivingOriginal.Length
        Write-Bytes $HandoffVA $patchH
        Write-Bytes $LivingCallVA $patchL
        [void][A8PPhase4BNative]::FlushInstructionCache($hProcess,[IntPtr]$HandoffVA,[UIntPtr]::new([uint64]$HandoffOriginal.Length))
        [void][A8PPhase4BNative]::FlushInstructionCache($hProcess,[IntPtr]$LivingCallVA,[UIntPtr]::new([uint64]$LivingOriginal.Length))
        Restore-Protect $HandoffVA $HandoffOriginal.Length $oldH
        Restore-Protect $LivingCallVA $LivingOriginal.Length $oldL
        $patchedHandoff=$true;$patchedLiving=$true
    } finally { Resume-GameThreads }

    Write-Host ''
    Write-Host 'CONSUMER_INJECTOR=ARMED'
    Write-Host 'Waiting for the WotR startup consumer...'

    $sw=[Diagnostics.Stopwatch]::StartNew()
    $firstHitAt=$null
    while($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if($proc.HasExited){throw 'game.dat exited while injector was armed.'}
        $hits=Read-U32 ([int64]$result+0x08)
        $living=Read-U32 ([int64]$result+0x14)
        if($hits -gt 0 -and $null -eq $firstHitAt){$firstHitAt=$sw.Elapsed.TotalSeconds}
        if($hits -gt 0 -and $living -gt 0){break}
        if($null -ne $firstHitAt -and ($sw.Elapsed.TotalSeconds-$firstHitAt) -ge 8){break}
        Start-Sleep -Milliseconds 100
    }

    $hits=Read-U32 ([int64]$result+0x08)
    $originalGi=Read-U32 ([int64]$result+0x0C)
    $injectedGi=Read-U32 ([int64]$result+0x10)
    $living=Read-U32 ([int64]$result+0x14)
    $lastPi=Read-U32 ([int64]$result+0x18)
    $injected=($hits -gt 0)

    Write-Host ''
    Write-Host '================ PHASE 4D RESULT ================'
    Write-Host "932F12 hits          : $hits"
    Write-Host ("Original GameInfo*   : 0x{0:X8}" -f $originalGi)
    Write-Host ("Injected GameInfo*   : 0x{0:X8}" -f $injectedGi)
    Write-Host ("Expected private GI  : 0x{0:X8}" -f $giAddr)
    Write-Host "6BB3B5 call count    : $living"
    Write-Host ("Last PlayerInfo*      : 0x{0:X8}" -f $lastPi)
    Write-Host ''
    Write-Host 'Compatibility active-row +0x10 after handoff:'
    for($i=0;$i -lt 4;$i++) {
        $row=[uint32]($giAddr+0xDC+($i*0x1B8))
        $v=Read-I32 ([int64]$row+0x10)
        Write-Host ("  P{0}: {1}" -f ($i+1),$v)
    }

    if($hits -gt 0 -and $injectedGi -eq $giAddr){Write-Host 'CONSUMER_LOCAL_GAMEINFO=PASS'}else{Write-Host 'CONSUMER_LOCAL_GAMEINFO=FAIL'}
    if($living -gt 0){Write-Host 'LIVINGWORLD_CONSUMED_BRIDGE=PASS'}else{Write-Host 'LIVINGWORLD_CONSUMED_BRIDGE=NOT_REACHED'}
}
finally {
    if($hProcess -ne [IntPtr]::Zero) {
        try {
            if(($patchedHandoff -or $patchedLiving) -and -not $proc.HasExited) {
                Suspend-GameThreads
                try {
                    if($patchedHandoff) {
                        $old=Make-Writable $HandoffVA $HandoffOriginal.Length
                        Write-Bytes $HandoffVA $HandoffOriginal
                        [void][A8PPhase4BNative]::FlushInstructionCache($hProcess,[IntPtr]$HandoffVA,[UIntPtr]::new([uint64]$HandoffOriginal.Length))
                        Restore-Protect $HandoffVA $HandoffOriginal.Length $old
                    }
                    if($patchedLiving) {
                        $old=Make-Writable $LivingCallVA $LivingOriginal.Length
                        Write-Bytes $LivingCallVA $LivingOriginal
                        [void][A8PPhase4BNative]::FlushInstructionCache($hProcess,[IntPtr]$LivingCallVA,[UIntPtr]::new([uint64]$LivingOriginal.Length))
                        Restore-Protect $LivingCallVA $LivingOriginal.Length $old
                    }
                } finally { Resume-GameThreads }
                Write-Host 'PATCH_RESTORE=PASS'
            }
        } catch {
            Write-Warning ("Patch restore problem: "+$_.Exception.Message)
        }
        if($remote -ne [IntPtr]::Zero) {
            if($injected) {
                Write-Host ("REMOTE_COMPAT_GI=LEFT_ALIVE_UNTIL_GAME_EXIT @ 0x{0:X8}" -f ([uint32]$remote.ToInt64()+$GameInfoOffset))
            } else {
                Write-Warning 'Remote CompatibilityGameInfo was constructed but not injected; allocation is left to game.dat process cleanup.'
            }
        }
        [void][A8PPhase4BNative]::CloseHandle($hProcess)
    }
}
