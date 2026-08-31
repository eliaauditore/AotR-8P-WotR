param(
    [int]$ProcessId = 0,
    [string]$ExpectedRemoteIp = '192.168.0.224',
    [int]$ExpectedRemotePort = 8086,
    [int]$ObserveSeconds = 8,
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# CONTROLLED RUNTIME MUTATION POC.
# This script does NOT modify game.dat on disk.
# With -Execute it allocates a tiny temporary page in the target process and starts
# one x86 thread stub that reproduces the proven native call:
#
#   ECX = session singleton [0x00DE4394]
#   arg1 = session-listed remote Network GameInfo
#   arg2 = pointer to a 6-byte {0,0} endpoint sentinel
#   call [session->vtable + 0x40]  ; 0x0084CB34 for the exact baseline
#
# The native method constructs/sends message ID 0x03. The stub is freed after return.
# No slot/player bytes are patched directly.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'

$SessionGlobalRva  = [int64]0x009E4394   # VA 0x00DE4394
$NetworkGlobalRva  = [int64]0x009E892C   # VA 0x00DE892C
$ActiveGlobalRva   = [int64]0x009E7D6C   # VA 0x00DE7D6C
$SessionVtableRva  = [int64]0x00854CE0   # VA 0x00C54CE0
$GameInfoVtableRva = [int64]0x00854B78   # VA 0x00C54B78
$JoinMethodRva     = [int64]0x0044CB34   # VA 0x0084CB34

if (-not ('A8PNativeJoinCall' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PNativeJoinCall
{
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress,
        byte[] lpBuffer, IntPtr nSize, out IntPtr lpNumberOfBytesRead);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress,
        byte[] lpBuffer, IntPtr nSize, out IntPtr lpNumberOfBytesWritten);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr lpAddress,
        UIntPtr dwSize, UInt32 flAllocationType, UInt32 flProtect);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool VirtualFreeEx(IntPtr hProcess, IntPtr lpAddress,
        UIntPtr dwSize, UInt32 dwFreeType);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool FlushInstructionCache(IntPtr hProcess, IntPtr lpBaseAddress,
        UIntPtr dwSize);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr CreateRemoteThread(IntPtr hProcess, IntPtr lpThreadAttributes,
        UIntPtr dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, UInt32 dwCreationFlags,
        out UInt32 lpThreadId);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern UInt32 WaitForSingleObject(IntPtr hHandle, UInt32 dwMilliseconds);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool GetExitCodeThread(IntPtr hThread, out UInt32 lpExitCode);

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

$MEM_COMMIT  = [uint32]0x1000
$MEM_RESERVE = [uint32]0x2000
$MEM_RELEASE = [uint32]0x8000
$PAGE_EXECUTE_READWRITE = [uint32]0x40
$WAIT_OBJECT_0 = [uint32]0
$WAIT_TIMEOUT  = [uint32]258

if ($ObserveSeconds -lt 1 -or $ObserveSeconds -gt 60) {
    throw 'ObserveSeconds must be between 1 and 60.'
}
if ($ExpectedRemotePort -lt 1 -or $ExpectedRemotePort -gt 65535) {
    throw 'ExpectedRemotePort must be 1..65535.'
}

if ($ProcessId -le 0) {
    $games = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -ieq 'game.dat' -and $_.ExecutablePath -match '\\game\.dat$'
    })
    if ($games.Count -ne 1) {
        throw "Expected exactly one game.dat. Found $($games.Count). Pass -ProcessId."
    }
    $ProcessId = [int]$games[0].ProcessId
}

$proc = Get-Process -Id $ProcessId -ErrorAction Stop
$exe = $proc.MainModule.FileName
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) {
    throw "HASH MISMATCH - expected $ExpectedHash, got $hash"
}

$base = $proc.MainModule.BaseAddress.ToInt64()
$expectedSessionVt  = [uint32]($base + $SessionVtableRva)
$expectedGameInfoVt = [uint32]($base + $GameInfoVtableRva)
$expectedJoinMethod = [uint32]($base + $JoinMethodRva)

$hProcess = [A8PNativeJoinCall]::OpenProcess($Access,$false,[uint32]$ProcessId)
if ($hProcess -eq [IntPtr]::Zero) {
    [A8PNativeJoinCall]::ThrowLast('OpenProcess failed')
}

function Read-Bytes([int64]$addr,[int]$count) {
    $b = New-Object byte[] $count
    $got = [IntPtr]::Zero
    if (-not [A8PNativeJoinCall]::ReadProcessMemory($hProcess,[IntPtr]$addr,$b,[IntPtr]$count,[ref]$got) -or $got.ToInt64() -ne $count) {
        [A8PNativeJoinCall]::ThrowLast(("ReadProcessMemory failed at 0x{0:X8} len={1}" -f $addr,$count))
    }
    return $b
}
function Read-U32([int64]$addr) { [BitConverter]::ToUInt32((Read-Bytes $addr 4),0) }
function Read-U16([int64]$addr) { [BitConverter]::ToUInt16((Read-Bytes $addr 2),0) }
function Read-U8([int64]$addr)  { (Read-Bytes $addr 1)[0] }
function Format-IPv4BE([uint32]$raw) {
    return ('{0}.{1}.{2}.{3}' -f (($raw -shr 24)-band 0xFF),(($raw -shr 16)-band 0xFF),(($raw -shr 8)-band 0xFF),($raw-band 0xFF))
}
function Format-Endpoint([uint32]$ip,[uint16]$port) {
    if ($ip -eq 0 -and $port -eq 0) { return '{0,0}' }
    return ('{0}:{1}' -f (Format-IPv4BE $ip),$port)
}
function Write-Bytes([int64]$addr,[byte[]]$bytes) {
    $written = [IntPtr]::Zero
    if (-not [A8PNativeJoinCall]::WriteProcessMemory($hProcess,[IntPtr]$addr,$bytes,[IntPtr]$bytes.Length,[ref]$written) -or $written.ToInt64() -ne $bytes.Length) {
        [A8PNativeJoinCall]::ThrowLast(("WriteProcessMemory failed at 0x{0:X8} len={1}" -f $addr,$bytes.Length))
    }
}
function Add-Imm32([System.Collections.Generic.List[byte]]$list,[uint32]$value) {
    foreach ($b in [BitConverter]::GetBytes($value)) { $list.Add($b) }
}
function Show-GameInfoRows([uint32]$gi,[uint32]$localIp,[uint16]$localPort) {
    Write-Host ("GameInfo 0x{0:X8} rows:" -f $gi)
    for ($i=0; $i -lt 8; $i++) {
        $row = Read-U32 ([int64]$gi + 0x18 + ($i*4))
        if ($row -eq 0) {
            Write-Host ("  P{0}: <NULL>" -f ($i+1))
            continue
        }
        $type = Read-U32 ([int64]$row + 4)
        $ip = Read-U32 ([int64]$row + 0x38)
        $port = Read-U16 ([int64]$row + 0x3C)
        $mark = if ($type -eq 6 -and $ip -eq $localIp -and $port -eq $localPort) { ' LOCAL' } else { '' }
        Write-Host ("  P{0}: row=0x{1:X8} type={2} endpoint={3}{4}" -f ($i+1),$row,$type,(Format-Endpoint $ip $port),$mark)
    }
}

$remotePage = [IntPtr]::Zero
$thread = [IntPtr]::Zero
$freeRemotePage = $false

try {
    $sessionGlobalAddr = $base + $SessionGlobalRva
    $networkGlobalAddr = $base + $NetworkGlobalRva
    $activeGlobalAddr  = $base + $ActiveGlobalRva

    $session = Read-U32 $sessionGlobalAddr
    $networkBefore = Read-U32 $networkGlobalAddr
    $activeBefore = Read-U32 $activeGlobalAddr

    Write-Host '============================================================'
    Write-Host ' AOTR WOTR NATIVE JOIN +0x40 CALL POC'
    Write-Host '============================================================'
    Write-Host ("Mode                 : {0}" -f ($(if ($Execute) {'EXECUTE - controlled runtime call'} else {'DRY RUN - no mutation'})))
    Write-Host ("PID                  : {0}" -f $ProcessId)
    Write-Host ("Image                : {0}" -f $exe)
    Write-Host ("SHA256               : {0}" -f $hash)
    Write-Host ("Expected remote      : {0}:{1}" -f $ExpectedRemoteIp,$ExpectedRemotePort)
    Write-Host ("Session global       : 0x{0:X8} -> 0x{1:X8}" -f $sessionGlobalAddr,$session)
    Write-Host ''

    if ($session -eq 0) { throw 'Safety gate: session singleton is NULL.' }

    $sessionVt = Read-U32 ([int64]$session)
    $state28 = Read-U32 ([int64]$session + 0x28)
    $listHead = Read-U32 ([int64]$session + 0x10)
    $current44 = Read-U32 ([int64]$session + 0x44)
    $localIp = Read-U32 ([int64]$session + 0x48)
    $localPort = Read-U16 ([int64]$session + 0x4C)

    if ($sessionVt -ne $expectedSessionVt) {
        throw ("Safety gate: session vtable mismatch 0x{0:X8} != 0x{1:X8}" -f $sessionVt,$expectedSessionVt)
    }
    $joinMethod = Read-U32 ([int64]$sessionVt + 0x40)
    if ($joinMethod -ne $expectedJoinMethod) {
        throw ("Safety gate: vtable+0x40 mismatch 0x{0:X8} != 0x{1:X8}" -f $joinMethod,$expectedJoinMethod)
    }
    if ($state28 -ne 0 -and $state28 -ne 2) {
        throw ("Safety gate: session+0x28={0}; expected 0 or 2." -f $state28)
    }
    if ($current44 -ne 0) {
        throw ("Safety gate: session+0x44 is already non-NULL (0x{0:X8}). This PoC is only for pre-join client browser state." -f $current44)
    }

    Write-Host '================ PRE-CALL CONTRACT ================'
    Write-Host ("session vtable       : 0x{0:X8} PASS" -f $sessionVt)
    Write-Host ("vtable +0x40        : 0x{0:X8} PASS" -f $joinMethod)
    Write-Host ("session state +0x28 : {0} PASS" -f $state28)
    Write-Host ("session +0x44       : 0x{0:X8} PASS (pre-join)" -f $current44)
    Write-Host ("local endpoint      : {0}" -f (Format-Endpoint $localIp $localPort))
    Write-Host ("list head +0x10     : 0x{0:X8}" -f $listHead)
    Write-Host ''

    $matches = @()
    $seen = @{}
    $p = [uint32]$listHead
    $idx = 0
    while ($p -ne 0 -and $idx -lt 32) {
        $key = ('{0:X8}' -f $p)
        if ($seen.ContainsKey($key)) { throw 'Safety gate: cycle detected in session GameInfo list.' }
        $seen[$key] = $true

        $vt = Read-U32 ([int64]$p)
        $next = Read-U32 ([int64]$p + 0xFBC)
        $row0 = Read-U32 ([int64]$p + 0x18)

        $type = [uint32]::MaxValue
        $ip = [uint32]0
        $port = [uint16]0
        if ($row0 -ne 0) {
            $type = Read-U32 ([int64]$row0 + 4)
            $ip = Read-U32 ([int64]$row0 + 0x38)
            $port = Read-U16 ([int64]$row0 + 0x3C)
        }
        $ipText = Format-IPv4BE $ip
        $isMatch = ($vt -eq $expectedGameInfoVt) -and ($row0 -ne 0) -and ($type -eq 6) -and ($ipText -eq $ExpectedRemoteIp) -and ($port -eq $ExpectedRemotePort)

        Write-Host ("[{0}] GI=0x{1:X8} vtOK={2} row0=0x{3:X8} type={4} endpoint={5} targetMatch={6}" -f $idx,$p,($vt -eq $expectedGameInfoVt),$row0,$type,(Format-Endpoint $ip $port),$isMatch)
        if ($isMatch) {
            $matches += [pscustomobject]@{ Ptr=[uint32]$p; Row0=[uint32]$row0; Ip=[uint32]$ip; Port=[uint16]$port }
        }

        $p = [uint32]$next
        $idx++
    }

    if ($matches.Count -ne 1) {
        throw ("Safety gate: expected exactly one remote GameInfo matching {0}:{1}, found {2}." -f $ExpectedRemoteIp,$ExpectedRemotePort,$matches.Count)
    }

    $arg1 = [uint32]$matches[0].Ptr
    Write-Host ''
    Write-Host ("SELECTED arg1        : 0x{0:X8}" -f $arg1) -ForegroundColor Green
    Write-Host 'SELECTED arg2        : temporary remote pointer to 6-byte {0,0}'

    if (-not $Execute) {
        Write-Host ''
        Write-Host 'CALL_POC_READY = YES' -ForegroundColor Green
        Write-Host 'DRY RUN COMPLETE. No process memory was modified.'
        Write-Host 'Re-run with -Execute to perform exactly one native vtable+0x40 call.'
        return
    }

    # Revalidate the selected object immediately before mutation.
    if ((Read-U32 ([int64]$session)) -ne $expectedSessionVt) { throw 'Safety gate changed: session vtable no longer matches.' }
    if ((Read-U32 ([int64]$session + 0x44)) -ne 0) { throw 'Safety gate changed: session+0x44 became non-NULL before call.' }
    if ((Read-U32 ([int64]$arg1)) -ne $expectedGameInfoVt) { throw 'Safety gate changed: arg1 vtable no longer matches.' }
    $row0Now = Read-U32 ([int64]$arg1 + 0x18)
    if ($row0Now -eq 0) { throw 'Safety gate changed: arg1 row0 is NULL.' }
    $row0TypeNow = Read-U32 ([int64]$row0Now + 4)
    $row0IpNow = Read-U32 ([int64]$row0Now + 0x38)
    $row0PortNow = Read-U16 ([int64]$row0Now + 0x3C)
    if ($row0TypeNow -ne 6 -or (Format-IPv4BE $row0IpNow) -ne $ExpectedRemoteIp -or $row0PortNow -ne $ExpectedRemotePort) {
        throw 'Safety gate changed: selected remote GameInfo row0 no longer matches expected host endpoint/type.'
    }

    # One page: endpoint at +0x00, x86 thread stub at +0x20.
    $remotePage = [A8PNativeJoinCall]::VirtualAllocEx($hProcess,[IntPtr]::Zero,[UIntPtr]0x1000,($MEM_COMMIT -bor $MEM_RESERVE),$PAGE_EXECUTE_READWRITE)
    if ($remotePage -eq [IntPtr]::Zero) { [A8PNativeJoinCall]::ThrowLast('VirtualAllocEx failed') }
    $remoteBase64 = $remotePage.ToInt64()
    if ($remoteBase64 -lt 0 -or $remoteBase64 -gt [uint32]::MaxValue) {
        throw ("Remote allocation is outside 32-bit address space: 0x{0:X}" -f $remoteBase64)
    }
    $remoteBase = [uint32]$remoteBase64
    $endpointPtr = $remoteBase
    $stubAddr = [uint32]($remoteBase + 0x20)
    $freeRemotePage = $true

    Write-Bytes ([int64]$endpointPtr) ([byte[]](0,0,0,0,0,0))

    # x86 stub:
    # B9 <session>       mov ecx,session
    # 68 <endpointPtr>   push arg2
    # 68 <arg1>          push arg1
    # 8B 01              mov eax,[ecx]
    # FF 50 40           call dword ptr [eax+0x40]
    # 33 C0              xor eax,eax
    # C2 04 00           ret 4   ; LPTHREAD_START_ROUTINE argument
    $stub = New-Object 'System.Collections.Generic.List[byte]'
    $stub.Add([byte]0xB9); Add-Imm32 $stub ([uint32]$session)
    $stub.Add([byte]0x68); Add-Imm32 $stub ([uint32]$endpointPtr)
    $stub.Add([byte]0x68); Add-Imm32 $stub ([uint32]$arg1)
    $stub.Add([byte]0x8B); $stub.Add([byte]0x01)
    $stub.Add([byte]0xFF); $stub.Add([byte]0x50); $stub.Add([byte]0x40)
    $stub.Add([byte]0x33); $stub.Add([byte]0xC0)
    $stub.Add([byte]0xC2); $stub.Add([byte]0x04); $stub.Add([byte]0x00)
    $stubBytes = $stub.ToArray()

    Write-Bytes ([int64]$stubAddr) $stubBytes
    [void][A8PNativeJoinCall]::FlushInstructionCache($hProcess,[IntPtr]([int64]$stubAddr),[UIntPtr]$stubBytes.Length)

    Write-Host ''
    Write-Host '================ EXECUTE ONE NATIVE JOIN CALL ================'
    Write-Host ("remote page          : 0x{0:X8}" -f $remoteBase)
    Write-Host ("arg2 zero endpoint   : 0x{0:X8}" -f $endpointPtr)
    Write-Host ("thread stub          : 0x{0:X8} ({1} bytes)" -f $stubAddr,$stubBytes.Length)
    Write-Host ("ECX session          : 0x{0:X8}" -f $session)
    Write-Host ("arg1 remote GameInfo : 0x{0:X8}" -f $arg1)
    Write-Host ("call target          : [vtable+0x40] = 0x{0:X8}" -f $joinMethod)

    $tid = [uint32]0
    $thread = [A8PNativeJoinCall]::CreateRemoteThread($hProcess,[IntPtr]::Zero,[UIntPtr]::Zero,[IntPtr]([int64]$stubAddr),[IntPtr]::Zero,0,[ref]$tid)
    if ($thread -eq [IntPtr]::Zero) { [A8PNativeJoinCall]::ThrowLast('CreateRemoteThread failed') }
    Write-Host ("remote thread id     : {0}" -f $tid)

    $wait = [A8PNativeJoinCall]::WaitForSingleObject($thread,10000)
    if ($wait -eq $WAIT_TIMEOUT) {
        $freeRemotePage = $false
        throw ("Remote thread timed out. Remote page 0x{0:X8} intentionally left allocated so executing code is not freed." -f $remoteBase)
    }
    if ($wait -ne $WAIT_OBJECT_0) {
        $freeRemotePage = $false
        throw ("WaitForSingleObject returned 0x{0:X8}. Remote page intentionally left allocated." -f $wait)
    }

    $exitCode = [uint32]0
    if (-not [A8PNativeJoinCall]::GetExitCodeThread($thread,[ref]$exitCode)) {
        [A8PNativeJoinCall]::ThrowLast('GetExitCodeThread failed')
    }
    Write-Host ("thread exit code     : 0x{0:X8}" -f $exitCode)
    Write-Host 'NATIVE +0x40 CALL RETURNED = YES' -ForegroundColor Green

    # The network response is asynchronous. Poll native state only; no further writes.
    Write-Host ''
    Write-Host ("Observing native state for up to {0}s..." -f $ObserveSeconds)
    $deadline = [DateTime]::UtcNow.AddSeconds($ObserveSeconds)
    $observedCurrent = [uint32]0
    $observedNetwork = [uint32]0
    do {
        Start-Sleep -Milliseconds 250
        $observedCurrent = Read-U32 ([int64]$session + 0x44)
        $observedNetwork = Read-U32 $networkGlobalAddr
        if ($observedCurrent -ne 0) { break }
    } while ([DateTime]::UtcNow -lt $deadline)

    Write-Host ''
    Write-Host '================ POST-CALL NATIVE OBSERVATION ================'
    Write-Host ("session +0x44 before : 0x{0:X8}" -f $current44)
    Write-Host ("session +0x44 after  : 0x{0:X8}" -f $observedCurrent)
    Write-Host ("DE892C before        : 0x{0:X8}" -f $networkBefore)
    Write-Host ("DE892C after         : 0x{0:X8}" -f $observedNetwork)
    Write-Host ("TheGameInfo before   : 0x{0:X8}" -f $activeBefore)
    Write-Host ("TheGameInfo after    : 0x{0:X8}" -f (Read-U32 $activeGlobalAddr))

    if ($observedCurrent -ne 0) {
        $afterVt = Read-U32 ([int64]$observedCurrent)
        Write-Host ("current vtable       : 0x{0:X8} expected=0x{1:X8} match={2}" -f $afterVt,$expectedGameInfoVt,($afterVt -eq $expectedGameInfoVt))
        if ($afterVt -eq $expectedGameInfoVt) {
            Show-GameInfoRows $observedCurrent $localIp $localPort
        }
        Write-Host 'NATIVE_JOIN_STATE_OBSERVED = YES' -ForegroundColor Green
    }
    else {
        Write-Host 'NATIVE_JOIN_STATE_OBSERVED = NO' -ForegroundColor Yellow
        Write-Host 'The +0x40 call itself returned, but no non-NULL session+0x44 was observed in the polling window.'
    }
}
finally {
    if ($thread -ne [IntPtr]::Zero) {
        [void][A8PNativeJoinCall]::CloseHandle($thread)
    }
    if ($remotePage -ne [IntPtr]::Zero -and $freeRemotePage) {
        [void][A8PNativeJoinCall]::VirtualFreeEx($hProcess,$remotePage,[UIntPtr]::Zero,$MEM_RELEASE)
    }
    if ($hProcess -ne [IntPtr]::Zero) {
        [void][A8PNativeJoinCall]::CloseHandle($hProcess)
    }
}
