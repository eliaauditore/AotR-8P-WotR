param(
    [int]$ProcessId = 0,
    [uint32]$OldValue = 3,
    [uint32]$NewValue = 4,
    [string]$TargetRow = 'P3',
    [string]$OldLabel = 'Soldier',
    [string]$NewLabel = 'Captain'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# Three-state differential:
#   A: target row OldValue
#   B: target row NewValue
#   C: target row OldValue again
# A candidate survives only if the SAME aligned DWORD follows:
#   Old -> New -> Old
# with short stability checks at B and C.
# No WriteProcessMemory is imported or called.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PLobbyTripleDiffV2
{
    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORY_BASIC_INFORMATION
    {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public UInt32 AllocationProtect;
        public UIntPtr RegionSize;
        public UInt32 State;
        public UInt32 Protect;
        public UInt32 Type;
    }

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr VirtualQueryEx(
        IntPtr hProcess,
        IntPtr lpAddress,
        out MEMORY_BASIC_INFORMATION lpBuffer,
        IntPtr dwLength);

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool ReadProcessMemory(
        IntPtr hProcess,
        IntPtr lpBaseAddress,
        byte[] lpBuffer,
        IntPtr nSize,
        out IntPtr lpNumberOfBytesRead);

    const UInt32 PROCESS_VM_READ = 0x0010;
    const UInt32 PROCESS_QUERY_INFORMATION = 0x0400;
    const UInt32 MEM_COMMIT = 0x1000;
    const UInt32 MEM_PRIVATE = 0x20000;
    const UInt32 MEM_MAPPED = 0x40000;
    const UInt32 PAGE_GUARD = 0x100;
    const UInt32 PAGE_NOACCESS = 0x01;
    const UInt32 PAGE_READWRITE = 0x04;
    const UInt32 PAGE_WRITECOPY = 0x08;
    const UInt32 PAGE_EXECUTE_READWRITE = 0x40;
    const UInt32 PAGE_EXECUTE_WRITECOPY = 0x80;

    static bool IsWritable(UInt32 p)
    {
        UInt32 b = p & 0xFF;
        return b == PAGE_READWRITE || b == PAGE_WRITECOPY ||
               b == PAGE_EXECUTE_READWRITE || b == PAGE_EXECUTE_WRITECOPY;
    }

    static bool Eligible(MEMORY_BASIC_INFORMATION mbi)
    {
        if (mbi.State != MEM_COMMIT) return false;
        if ((mbi.Protect & PAGE_GUARD) != 0) return false;
        if ((mbi.Protect & PAGE_NOACCESS) != 0) return false;
        if (!IsWritable(mbi.Protect)) return false;
        return mbi.Type == MEM_PRIVATE || mbi.Type == MEM_MAPPED;
    }

    public sealed class ScanResult
    {
        public HashSet<Int64> Addresses = new HashSet<Int64>();
        public Int64 Regions;
        public Int64 Bytes;
    }

    public static ScanResult Capture(UInt32 pid, UInt32 value)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess failed");
        try
        {
            ScanResult r = new ScanResult();
            Int64 address = 0;
            const Int64 maxAddress = 0x100000000L;
            Int32 mbiSize = Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION));
            const Int32 Chunk = 4 * 1024 * 1024;

            while (address < maxAddress)
            {
                MEMORY_BASIC_INFORMATION mbi;
                IntPtr q = VirtualQueryEx(h, new IntPtr(address), out mbi, new IntPtr(mbiSize));
                if (q == IntPtr.Zero) break;

                Int64 regionBase = mbi.BaseAddress.ToInt64();
                Int64 regionSize = unchecked((Int64)mbi.RegionSize.ToUInt64());
                if (regionSize <= 0) break;
                Int64 next = regionBase + regionSize;
                if (next <= address) break;

                if (Eligible(mbi))
                {
                    r.Regions++;
                    r.Bytes += regionSize;
                    for (Int64 off = 0; off < regionSize; off += Chunk)
                    {
                        Int32 want = (Int32)Math.Min((Int64)Chunk, regionSize - off);
                        byte[] buf = new byte[want];
                        IntPtr got;
                        bool ok = ReadProcessMemory(h, new IntPtr(regionBase + off), buf, new IntPtr(want), out got);
                        Int32 n = ok ? (Int32)got.ToInt64() : 0;
                        n -= n % 4;
                        for (Int32 i = 0; i <= n - 4; i += 4)
                        {
                            if (BitConverter.ToUInt32(buf, i) == value)
                                r.Addresses.Add(regionBase + off + i);
                        }
                    }
                }
                address = next;
            }
            return r;
        }
        finally { CloseHandle(h); }
    }

    public static List<Int64> FilterValue(UInt32 pid, IEnumerable<Int64> addresses, UInt32 expected)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess failed");
        try
        {
            List<Int64> hits = new List<Int64>();
            byte[] b = new byte[4];
            foreach (Int64 a in addresses)
            {
                IntPtr got;
                bool ok = ReadProcessMemory(h, new IntPtr(a), b, new IntPtr(4), out got);
                if (ok && got.ToInt64() == 4 && BitConverter.ToUInt32(b, 0) == expected)
                    hits.Add(a);
            }
            return hits;
        }
        finally { CloseHandle(h); }
    }

    public static byte[] ReadContext(UInt32 pid, Int64 address, Int32 before, Int32 after)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess failed");
        try
        {
            Int64 start = address - before;
            Int32 len = before + 4 + after;
            byte[] buf = new byte[len];
            IntPtr got;
            bool ok = ReadProcessMemory(h, new IntPtr(start), buf, new IntPtr(len), out got);
            if (!ok || got.ToInt64() != len) return new byte[0];
            return buf;
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

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR LOBBY TRIPLE DIFF V2 - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID          : {0}" -f $ProcessId)
Write-Host ("Image        : {0}" -f $exePath)
Write-Host ("SHA256       : {0}" -f $hash)
Write-Host ("Target       : {0} {1}->{2}->{1}" -f $TargetRow, $OldLabel, $NewLabel)
Write-Host ("DWORD path   : {0}->{1}->{0}" -f $OldValue, $NewValue)
Write-Host ''

if ($hash -ne $ExpectedHash) {
    throw 'HASH MISMATCH - aborted before memory scan.'
}

Write-Host ("STATE A: make sure {0} visibly shows {1}." -f $TargetRow, $OldLabel) -ForegroundColor Yellow
[void](Read-Host 'Press ENTER when STATE A is visible')

Write-Host ("Capturing all aligned writable DWORD == {0} ..." -f $OldValue)
$a = [A8PLobbyTripleDiffV2]::Capture([uint32]$ProcessId, $OldValue)
Write-Host ("A regions     : {0}" -f $a.Regions)
Write-Host ("A bytes       : {0:N0}" -f $a.Bytes)
Write-Host ("A addresses   : {0:N0}" -f $a.Addresses.Count)

Write-Host ''
Write-Host ("STATE B: change ONLY {0}: {1} -> {2}." -f $TargetRow, $OldLabel, $NewLabel) -ForegroundColor Yellow
[void](Read-Host 'After STATE B is visibly updated, press ENTER')

$b = [A8PLobbyTripleDiffV2]::FilterValue([uint32]$ProcessId, $a.Addresses, $NewValue)
Write-Host ("A->B hits     : {0}" -f $b.Count)
Start-Sleep -Milliseconds 1000
$bStable = [A8PLobbyTripleDiffV2]::FilterValue([uint32]$ProcessId, $b, $NewValue)
Write-Host ("B stable 1s   : {0}" -f $bStable.Count)

Write-Host ''
Write-Host ("STATE C: change ONLY {0}: {1} -> {2}." -f $TargetRow, $NewLabel, $OldLabel) -ForegroundColor Yellow
[void](Read-Host 'After STATE C is visibly updated, press ENTER')

$c = [A8PLobbyTripleDiffV2]::FilterValue([uint32]$ProcessId, $bStable, $OldValue)
Write-Host ("A->B->C hits  : {0}" -f $c.Count)
Start-Sleep -Milliseconds 1000
$cStable = [A8PLobbyTripleDiffV2]::FilterValue([uint32]$ProcessId, $c, $OldValue)
Write-Host ("C stable 1s   : {0}" -f $cStable.Count)

Write-Host ''
Write-Host '============================================================'
Write-Host ("FINAL SURVIVORS {0}->{1}->{0}: {2}" -f $OldValue, $NewValue, $cStable.Count)
Write-Host '============================================================'

$idx = 0
foreach ($addr in ($cStable | Sort-Object)) {
    $idx++
    $ctx = [A8PLobbyTripleDiffV2]::ReadContext([uint32]$ProcessId, [int64]$addr, 48, 48)
    $hex = if ($ctx.Length -gt 0) { ([BitConverter]::ToString($ctx) -replace '-', ' ') } else { '<context unreadable>' }
    Write-Host ("SURVIVOR #{0} @ 0x{1:X8}" -f $idx, $addr)
    Write-Host ("  Context -0x30..+0x33: {0}" -f $hex)
}

Write-Host ''
if ($cStable.Count -eq 0) {
    Write-Host 'No stable reverse-confirmed DWORD survived.' -ForegroundColor Yellow
    Write-Host 'The lobby value may use another representation, or all first-pass 3->4 hits were unrelated runtime churn.'
}
elseif ($cStable.Count -eq 1) {
    Write-Host 'ONE stable reverse-confirmed candidate. High value; next proof is the same test on a second row.' -ForegroundColor Green
}
else {
    Write-Host 'Multiple reverse-confirmed candidates remain. Run the same V2 test on P4; row-to-row structural comparison will isolate the real field.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
