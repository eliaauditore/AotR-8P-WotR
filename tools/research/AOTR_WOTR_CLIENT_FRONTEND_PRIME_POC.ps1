param(
    [int]$ProcessId = 0,
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Runtime-only controlled PoC for the missing client frontend transition.
# Hypothesis under test:
#   the real native join path primes frontend state with 0x00917C2D(1,1)
#   before session vtable +0x40 / 0x0084CB34. Our older native-join PoC skips
#   this call. This tool invokes ONLY 0x00917C2D(1,1) so it can be tested as
#   a one-variable A/B after a proven native join.
#
# Disk game.dat is never modified.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$FrontendPrimeRva = [int64]0x00517C2D   # VA 0x00917C2D at base 0x00400000
$SessionGlobalRva = [int64]0x009E4394
$ActiveGlobalRva  = [int64]0x009E7D6C
$NetworkGlobalRva = [int64]0x009E892C
$UiManagerGlobalRva = [int64]0x009EA110
$UiIndexGlobalRva   = [int64]0x009EA114

if (-not ('A8PFrontendPrime' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PFrontendPrime {
    [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(UInt32 a, bool i, UInt32 p);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr n, out IntPtr g);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr n, out IntPtr w);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr a, IntPtr n, UInt32 t, UInt32 p);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool VirtualFreeEx(IntPtr h, IntPtr a, IntPtr n, UInt32 t);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr sa, UInt32 ss, IntPtr start, IntPtr param, UInt32 flags, out UInt32 tid);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern UInt32 WaitForSingleObject(IntPtr h, UInt32 ms);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetExitCodeThread(IntPtr h, out UInt32 code);

    public const UInt32 PROCESS_CREATE_THREAD=0x0002;
    public const UInt32 PROCESS_QUERY_INFORMATION=0x0400;
    public const UInt32 PROCESS_VM_OPERATION=0x0008;
    public const UInt32 PROCESS_VM_READ=0x0010;
    public const UInt32 PROCESS_VM_WRITE=0x0020;
    public const UInt32 MEM_COMMIT=0x1000;
    public const UInt32 MEM_RESERVE=0x2000;
    public const UInt32 MEM_RELEASE=0x8000;
    public const UInt32 PAGE_EXECUTE_READWRITE=0x40;
}
"@
}

function Resolve-GameProcess {
    if ($ProcessId -gt 0) { return Get-Process -Id $ProcessId -ErrorAction Stop }
    $games = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'game.dat' -and $_.ExecutablePath -match '\\rotwk\\game\.dat$' })
    if ($games.Count -ne 1) {
        $text = $games | ForEach-Object { 'PID={0} Path={1}' -f $_.ProcessId,$_.ExecutablePath }
        throw "Expected exactly one rotwk\\game.dat. Found $($games.Count). Pass -ProcessId.`n$($text -join "`n")"
    }
    return Get-Process -Id ([int]$games[0].ProcessId) -ErrorAction Stop
}

$proc = Resolve-GameProcess
$exe = $proc.MainModule.FileName
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "Unsupported game.dat build. Expected $ExpectedHash Actual $hash Path $exe" }
$base = $proc.MainModule.BaseAddress.ToInt64()
$target = [uint32]($base + $FrontendPrimeRva)

$access = [A8PFrontendPrime]::PROCESS_QUERY_INFORMATION -bor [A8PFrontendPrime]::PROCESS_VM_READ
if ($Execute) {
    $access = $access -bor [A8PFrontendPrime]::PROCESS_CREATE_THREAD -bor [A8PFrontendPrime]::PROCESS_VM_OPERATION -bor [A8PFrontendPrime]::PROCESS_VM_WRITE
}
$h = [A8PFrontendPrime]::OpenProcess([uint32]$access,$false,[uint32]$proc.Id)
if ($h -eq [IntPtr]::Zero) { throw "OpenProcess failed Win32=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }

function Read-Bytes([int64]$addr,[int]$count) {
    $b = New-Object byte[] $count
    $got=[IntPtr]::Zero
    if (-not [A8PFrontendPrime]::ReadProcessMemory($h,[IntPtr]$addr,$b,[IntPtr]$count,[ref]$got) -or $got.ToInt64() -ne $count) {
        throw ('ReadProcessMemory failed at 0x{0:X8}' -f $addr)
    }
    return $b
}
function Read-U32([int64]$addr) { [BitConverter]::ToUInt32((Read-Bytes $addr 4),0) }
function Snapshot-State([string]$label) {
    $session=Read-U32 ($base+$SessionGlobalRva)
    $active=Read-U32 ($base+$ActiveGlobalRva)
    $network=Read-U32 ($base+$NetworkGlobalRva)
    $ui=Read-U32 ($base+$UiManagerGlobalRva)
    $idx=Read-U32 ($base+$UiIndexGlobalRva)
    $sessionCurrent=[uint32]0
    $sessionState=[uint32]0
    if($session -ne 0){
        $sessionState=Read-U32 ([int64]$session+0x28)
        $sessionCurrent=Read-U32 ([int64]$session+0x44)
    }
    $uiDirty=$null
    if($ui -ne 0){ try { $uiDirty=(Read-Bytes ([int64]$ui+0x29C) 1)[0] } catch {} }
    Write-Host ("{0}:" -f $label)
    Write-Host ("  Session          : 0x{0:X8}" -f $session)
    Write-Host ("  Session +0x28    : {0}" -f $sessionState)
    Write-Host ("  Session +0x44    : 0x{0:X8}" -f $sessionCurrent)
    Write-Host ("  DE892C NetworkGI : 0x{0:X8}" -f $network)
    Write-Host ("  TheGameInfo      : 0x{0:X8}" -f $active)
    Write-Host ("  UI manager       : 0x{0:X8}" -f $ui)
    Write-Host ("  UI index DEA114  : {0}" -f $idx)
    Write-Host ("  UI +0x29C dirty  : {0}" -f ($(if($null -eq $uiDirty){'<unreadable>'}else{$uiDirty})))
}

try {
    Write-Host '============================================================'
    Write-Host ' AOTR WOTR CLIENT FRONTEND PRIME POC'
    Write-Host ' Runtime-only; disk game.dat unchanged'
    Write-Host '============================================================'
    Write-Host ("Mode             : {0}" -f $(if($Execute){'EXECUTE'}else{'OBSERVE ONLY'}))
    Write-Host ("PID              : {0}" -f $proc.Id)
    Write-Host ("Image            : {0}" -f $exe)
    Write-Host ("SHA256           : {0}" -f $hash)
    Write-Host ("Frontend prime VA: 0x{0:X8}" -f $target)
    Write-Host ''
    Snapshot-State 'BEFORE'

    if (-not $Execute) {
        Write-Host ''
        Write-Host 'OBSERVE ONLY. Re-run with -Execute to invoke exactly 0x00917C2D(1,1).'
        return
    }

    # Safety gate: this PoC is intended only after native join succeeded but before TheGameInfo handoff.
    $session=Read-U32 ($base+$SessionGlobalRva)
    if($session -eq 0){ throw 'Session is NULL.' }
    $current=Read-U32 ([int64]$session+0x44)
    if($current -eq 0){ throw 'Session +0x44 is NULL. Native join is not established; aborting.' }
    $active=Read-U32 ($base+$ActiveGlobalRva)
    if($active -ne 0){ throw ('TheGameInfo already non-NULL (0x{0:X8}); aborting to avoid changing a later phase.' -f $active) }

    # x86 stub: push 1; push 1; mov eax,target; call eax; add esp,8; xor eax,eax; ret
    $stub = New-Object System.Collections.Generic.List[byte]
    $stub.AddRange([byte[]](0x6A,0x01,0x6A,0x01,0xB8))
    $stub.AddRange([BitConverter]::GetBytes([uint32]$target))
    $stub.AddRange([byte[]](0xFF,0xD0,0x83,0xC4,0x08,0x33,0xC0,0xC3))
    $code=$stub.ToArray()

    $remote=[A8PFrontendPrime]::VirtualAllocEx($h,[IntPtr]::Zero,[IntPtr]$code.Length,([A8PFrontendPrime]::MEM_COMMIT -bor [A8PFrontendPrime]::MEM_RESERVE),[A8PFrontendPrime]::PAGE_EXECUTE_READWRITE)
    if($remote -eq [IntPtr]::Zero){ throw "VirtualAllocEx failed Win32=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    try {
        $written=[IntPtr]::Zero
        if(-not [A8PFrontendPrime]::WriteProcessMemory($h,$remote,$code,[IntPtr]$code.Length,[ref]$written) -or $written.ToInt64() -ne $code.Length){ throw 'WriteProcessMemory for temporary stub failed.' }
        [uint32]$tid=0
        $th=[A8PFrontendPrime]::CreateRemoteThread($h,[IntPtr]::Zero,0,$remote,[IntPtr]::Zero,0,[ref]$tid)
        if($th -eq [IntPtr]::Zero){ throw "CreateRemoteThread failed Win32=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
        try {
            $wait=[A8PFrontendPrime]::WaitForSingleObject($th,5000)
            if($wait -ne 0){ throw "Remote thread did not complete cleanly. Wait=$wait" }
            [uint32]$exit=0
            [void][A8PFrontendPrime]::GetExitCodeThread($th,[ref]$exit)
            Write-Host ''
            Write-Host ("Remote frontend-prime call returned. ThreadId={0} Exit={1}" -f $tid,$exit)
        } finally { [void][A8PFrontendPrime]::CloseHandle($th) }
    } finally {
        [void][A8PFrontendPrime]::VirtualFreeEx($h,$remote,[IntPtr]::Zero,[A8PFrontendPrime]::MEM_RELEASE)
    }

    Start-Sleep -Milliseconds 300
    Write-Host ''
    Snapshot-State 'AFTER'
    Write-Host ''
    Write-Host 'MANUAL VISUAL CHECK:' -ForegroundColor Yellow
    Write-Host '  Did the VM leave the browser and enter the Strategic lobby / Ready-capable screen?'
    Write-Host '  Do not click Start Game yet.'
} finally {
    [void][A8PFrontendPrime]::CloseHandle($h)
}
