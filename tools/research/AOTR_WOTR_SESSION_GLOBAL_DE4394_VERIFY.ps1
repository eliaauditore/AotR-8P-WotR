param(
    [int]$ProcessId = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# Verifies whether global 0x00DE4394 points to the live C54CE0 session object
# and whether that object links to the current pre-start Network GameInfo.
# No WriteProcessMemory is imported or used.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$SessionGlobalRva = [int64]0x009E4394   # 0x00DE4394 - 0x00400000
$NetworkGlobalRva = [int64]0x009E892C   # 0x00DE892C - 0x00400000
$ActiveGlobalRva  = [int64]0x009E7D6C   # 0x00DE7D6C - 0x00400000
$SessionVtableRva = [int64]0x00854CE0   # 0x00C54CE0 - 0x00400000
$NetworkVtableRva = [int64]0x00854B78   # 0x00C54B78 - 0x00400000

if (-not ('A8PSessionGlobalRead' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PSessionGlobalRead
{
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CloseHandle(IntPtr hObject);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress,
        byte[] lpBuffer, IntPtr nSize, out IntPtr lpNumberOfBytesRead);

    const UInt32 PROCESS_VM_READ = 0x0010;
    const UInt32 PROCESS_QUERY_INFORMATION = 0x0400;

    public static UInt32 ReadU32(UInt32 pid, Int64 addr)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            byte[] b = new byte[4]; IntPtr got;
            if (!ReadProcessMemory(h, new IntPtr(addr), b, new IntPtr(4), out got) || got.ToInt64() != 4)
                throw new Exception("ReadU32 failed at 0x" + addr.ToString("X8"));
            return BitConverter.ToUInt32(b,0);
        } finally { CloseHandle(h); }
    }
}
"@
}

if ($ProcessId -le 0) {
    $games = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -ieq 'game.dat' -and $_.ExecutablePath -match '\\game\.dat$'
    })
    if ($games.Count -ne 1) { throw "Expected one game.dat. Found $($games.Count). Pass -ProcessId." }
    $ProcessId = [int]$games[0].ProcessId
}

$proc = Get-Process -Id $ProcessId -ErrorAction Stop
$exe = $proc.MainModule.FileName
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH - expected $ExpectedHash, got $hash" }

$base = $proc.MainModule.BaseAddress.ToInt64()
$sessionGlobalAddr = $base + $SessionGlobalRva
$networkGlobalAddr = $base + $NetworkGlobalRva
$activeGlobalAddr  = $base + $ActiveGlobalRva
$expectedSessionVt = [uint32]($base + $SessionVtableRva)
$expectedNetworkVt = [uint32]($base + $NetworkVtableRva)

function Read-U32([int64]$addr) {
    [A8PSessionGlobalRead]::ReadU32([uint32]$ProcessId,$addr)
}

function Format-IPv4BE([uint32]$raw) {
    return ('{0}.{1}.{2}.{3}' -f (($raw -shr 24)-band 0xFF),(($raw -shr 16)-band 0xFF),(($raw -shr 8)-band 0xFF),($raw-band 0xFF))
}

$session = Read-U32 $sessionGlobalAddr
$network = Read-U32 $networkGlobalAddr
$active  = Read-U32 $activeGlobalAddr

Write-Host '============================================================'
Write-Host ' AOTR WOTR SESSION GLOBAL 0xDE4394 VERIFY - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID                  : {0}" -f $ProcessId)
Write-Host ("Image                : {0}" -f $exe)
Write-Host ("SHA256               : {0}" -f $hash)
Write-Host ("Runtime base         : 0x{0:X8}" -f $base)
Write-Host ("Session global VA    : 0x{0:X8}" -f $sessionGlobalAddr)
Write-Host ("[Session global]     : 0x{0:X8}" -f $session)
Write-Host ("Network global ptr   : 0x{0:X8}" -f $network)
Write-Host ("TheGameInfo ptr      : 0x{0:X8}" -f $active)
Write-Host ''

if ($session -eq 0) {
    Write-Host 'SESSION GLOBAL IS NULL' -ForegroundColor Yellow
    Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
    exit 0
}

$vt   = Read-U32 ([int64]$session)
$p10  = Read-U32 ([int64]$session + 0x10)
$p44  = Read-U32 ([int64]$session + 0x44)
$ep   = Read-U32 ([int64]$session + 0x48)
$p4c  = Read-U32 ([int64]$session + 0x4C)
$p50  = Read-U32 ([int64]$session + 0x50)

Write-Host ("Session vtable       : 0x{0:X8} expected=0x{1:X8} match={2}" -f $vt,$expectedSessionVt,($vt -eq $expectedSessionVt))
Write-Host ("Session +0x10        : 0x{0:X8} networkMatch={1}" -f $p10,($p10 -eq $network))
Write-Host ("Session +0x44        : 0x{0:X8} networkMatch={1}" -f $p44,($p44 -eq $network))
Write-Host ("Session +0x48        : 0x{0:X8} endpointBE={1}" -f $ep,(Format-IPv4BE $ep))
Write-Host ("Session +0x4C        : 0x{0:X8} low16={1}" -f $p4c,($p4c -band 0xFFFF))
Write-Host ("Session +0x50        : 0x{0:X8}" -f $p50)

if ($network -ne 0) {
    $nvt = Read-U32 ([int64]$network)
    Write-Host ("Network vtable       : 0x{0:X8} expected=0x{1:X8} match={2}" -f $nvt,$expectedNetworkVt,($nvt -eq $expectedNetworkVt))
}

Write-Host ''
$pass = ($vt -eq $expectedSessionVt) -and ($network -ne 0) -and ($p10 -eq $network) -and ($p44 -eq $network)
Write-Host ("GLOBAL->SESSION->GAMEINFO PROVENANCE : {0}" -f ($(if ($pass) {'PASS'} else {'NOT PROVEN'}))) -ForegroundColor ($(if ($pass) {'Green'} else {'Yellow'}))
Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
