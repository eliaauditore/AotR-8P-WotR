param(
    [int]$ProcessId = 0,
    [UInt64]$P3Address = 0x095930F8,
    [UInt64]$Stride = 0x1DC
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# Runtime hypothesis from controlled P3/P4 triple-diff:
#   P3 field = 0x095930F8
#   P4 field = 0x095932D4
#   delta    = 0x1DC
# If this is an 8-row lobby staging array, predicted field addresses are:
#   P1 = P3 - 2*stride
#   P2 = P3 - 1*stride
#   P3 = P3
#   P4 = P3 + 1*stride
#   ... P8 = P3 + 5*stride
# Current expected lobby state for this proof:
#   P1 human(6), P2/P3/P4 Soldier(3), P5-P8 Closed(1)
# No WriteProcessMemory is imported or called.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'

Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PCompactRowVerify
{
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool ReadProcessMemory(
        IntPtr hProcess,
        IntPtr lpBaseAddress,
        byte[] lpBuffer,
        IntPtr nSize,
        out IntPtr lpNumberOfBytesRead);

    const UInt32 PROCESS_VM_READ = 0x0010;
    const UInt32 PROCESS_QUERY_INFORMATION = 0x0400;

    public static UInt32 ReadU32(UInt32 pid, Int64 address)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess failed");
        try
        {
            byte[] b = new byte[4];
            IntPtr got;
            bool ok = ReadProcessMemory(h, new IntPtr(address), b, new IntPtr(4), out got);
            if (!ok || got.ToInt64() != 4)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "ReadProcessMemory failed");
            return BitConverter.ToUInt32(b, 0);
        }
        finally { CloseHandle(h); }
    }

    public static byte[] ReadBytes(UInt32 pid, Int64 address, Int32 count)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess failed");
        try
        {
            byte[] b = new byte[count];
            IntPtr got;
            bool ok = ReadProcessMemory(h, new IntPtr(address), b, new IntPtr(count), out got);
            if (!ok || got.ToInt64() != count) return new byte[0];
            return b;
        }
        finally { CloseHandle(h); }
    }
}
"@

if ($ProcessId -le 0) {
    $games = @(
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object {
                try { $_.MainModule.FileName -match '\\game\.dat$' }
                catch { $false }
            }
    )
    if ($games.Count -ne 1) {
        throw "Expected exactly one running game.dat. Found $($games.Count). Pass -ProcessId explicitly."
    }
    $ProcessId = [int]$games[0].Id
}

$proc = Get-Process -Id $ProcessId -ErrorAction Stop
$exePath = $proc.MainModule.FileName
$hash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw 'HASH MISMATCH - aborted before memory read.' }

$expected = @(6,3,3,3,1,1,1,1)
$base = [Int64]$P3Address - (2 * [Int64]$Stride)

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR COMPACT ROW STRIDE VERIFY - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID      : {0}" -f $ProcessId)
Write-Host ("Image    : {0}" -f $exePath)
Write-Host ("SHA256   : {0}" -f $hash)
Write-Host ("P3 field : 0x{0:X8}" -f $P3Address)
Write-Host ("Stride   : 0x{0:X} ({1})" -f $Stride,$Stride)
Write-Host ("P1 field : 0x{0:X8}" -f $base)
Write-Host ''

$allMatch = $true
for ($i=0; $i -lt 8; $i++) {
    $addr = $base + ($i * [Int64]$Stride)
    $v = [A8PCompactRowVerify]::ReadU32([uint32]$ProcessId,$addr)
    $want = [uint32]$expected[$i]
    $ok = ($v -eq $want)
    if (-not $ok) { $allMatch = $false }

    $label = switch ($v) {
        0 { 'Open' }
        1 { 'Closed' }
        2 { 'Peasant' }
        3 { 'Soldier' }
        4 { 'Captain' }
        5 { 'Death March' }
        6 { 'Network Human' }
        default { 'Unknown' }
    }

    Write-Host ("P{0}: addr=0x{1:X8} value={2} {3} expected={4} {5}" -f ($i+1),$addr,$v,$label,$want,$(if($ok){'MATCH'}else{'MISMATCH'}))
}

Write-Host ''
if ($allMatch) {
    Write-Host 'VECTOR MATCH: PASS' -ForegroundColor Green
    Write-Host 'Observed 8-row vector matches expected lobby state 6,3,3,3,1,1,1,1.' -ForegroundColor Green
    Write-Host 'This strongly supports 0x1DC as the live compact row stride for this representation.' -ForegroundColor Green
} else {
    Write-Host 'VECTOR MATCH: FAIL' -ForegroundColor Yellow
    Write-Host 'Do not treat this representation as proven. Keep read-only.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
