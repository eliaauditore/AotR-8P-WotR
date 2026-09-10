param(
    [int]$ProcessId = 0,
    [uint32]$OldValue = 3,
    [uint32]$NewValue = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# Purpose: find live lobby state by controlled value transition.
# Default test for current WotR UI:
#   Soldier -> Captain
# expected PlayerType-like DWORD transition:
#   3 -> 4
#
# The script:
#   1. scans committed writable private/mapped memory for aligned DWORD OldValue
#   2. waits while the user changes exactly one lobby row
#   3. rescans for aligned DWORD NewValue at the SAME addresses
#   4. reports intersections only
#
# It never calls WriteProcessMemory.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PLobbyValueDiff
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
        UInt32 baseProtect = p & 0xFF;
        return baseProtect == PAGE_READWRITE ||
               baseProtect == PAGE_WRITECOPY ||
               baseProtect == PAGE_EXECUTE_READWRITE ||
               baseProtect == PAGE_EXECUTE_WRITECOPY;
    }

    static bool Eligible(MEMORY_BASIC_INFORMATION mbi)
    {
        if (mbi.State != MEM_COMMIT) return false;
        if ((mbi.Protect & PAGE_GUARD) != 0) return false;
        if ((mbi.Protect & PAGE_NOACCESS) != 0) return false;
        if (!IsWritable(mbi.Protect)) return false;
        if (mbi.Type != MEM_PRIVATE && mbi.Type != MEM_MAPPED) return false;
        return true;
    }

    static Int64 ToI64(IntPtr p)
    {
        return p.ToInt64();
    }

    public sealed class ScanResult
    {
        public HashSet<Int64> Addresses = new HashSet<Int64>();
        public Int64 Regions;
        public Int64 Bytes;
    }

    public sealed class CompareResult
    {
        public List<Int64> Hits = new List<Int64>();
        public Int64 Regions;
        public Int64 Bytes;
    }

    public static ScanResult Capture(UInt32 pid, UInt32 value)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess failed");
        try
        {
            ScanResult result = new ScanResult();
            Int64 address = 0;
            Int64 maxAddress = 0x100000000L;
            Int32 mbiSize = Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION));
            const Int32 Chunk = 4 * 1024 * 1024;

            while (address < maxAddress)
            {
                MEMORY_BASIC_INFORMATION mbi;
                IntPtr q = VirtualQueryEx(h, new IntPtr(address), out mbi, new IntPtr(mbiSize));
                if (q == IntPtr.Zero) break;

                Int64 regionBase = ToI64(mbi.BaseAddress);
                Int64 regionSize = unchecked((Int64)mbi.RegionSize.ToUInt64());
                if (regionSize <= 0) break;
                Int64 next = regionBase + regionSize;
                if (next <= address) break;

                if (Eligible(mbi))
                {
                    result.Regions++;
                    result.Bytes += regionSize;
                    for (Int64 off = 0; off < regionSize; off += Chunk)
                    {
                        Int32 want = (Int32)Math.Min((Int64)Chunk, regionSize - off);
                        byte[] buf = new byte[want];
                        IntPtr got;
                        bool ok = ReadProcessMemory(h, new IntPtr(regionBase + off), buf, new IntPtr(want), out got);
                        Int32 n = ok ? (Int32)got.ToInt64() : 0;
                        n -= (n % 4);
                        for (Int32 i = 0; i <= n - 4; i += 4)
                        {
                            UInt32 v = BitConverter.ToUInt32(buf, i);
                            if (v == value) result.Addresses.Add(regionBase + off + i);
                        }
                    }
                }

                address = next;
            }
            return result;
        }
        finally { CloseHandle(h); }
    }

    public static CompareResult FindTransitions(UInt32 pid, UInt32 newValue, HashSet<Int64> oldAddresses)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess failed");
        try
        {
            CompareResult result = new CompareResult();
            Int64 address = 0;
            Int64 maxAddress = 0x100000000L;
            Int32 mbiSize = Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION));
            const Int32 Chunk = 4 * 1024 * 1024;

            while (address < maxAddress)
            {
                MEMORY_BASIC_INFORMATION mbi;
                IntPtr q = VirtualQueryEx(h, new IntPtr(address), out mbi, new IntPtr(mbiSize));
                if (q == IntPtr.Zero) break;

                Int64 regionBase = ToI64(mbi.BaseAddress);
                Int64 regionSize = unchecked((Int64)mbi.RegionSize.ToUInt64());
                if (regionSize <= 0) break;
                Int64 next = regionBase + regionSize;
                if (next <= address) break;

                if (Eligible(mbi))
                {
                    result.Regions++;
                    result.Bytes += regionSize;
                    for (Int64 off = 0; off < regionSize; off += Chunk)
                    {
                        Int32 want = (Int32)Math.Min((Int64)Chunk, regionSize - off);
                        byte[] buf = new byte[want];
                        IntPtr got;
                        bool ok = ReadProcessMemory(h, new IntPtr(regionBase + off), buf, new IntPtr(want), out got);
                        Int32 n = ok ? (Int32)got.ToInt64() : 0;
                        n -= (n % 4);
                        for (Int32 i = 0; i <= n - 4; i += 4)
                        {
                            UInt32 v = BitConverter.ToUInt32(buf, i);
                            if (v != newValue) continue;
                            Int64 a = regionBase + off + i;
                            if (oldAddresses.Contains(a)) result.Hits.Add(a);
                        }
                    }
                }

                address = next;
            }
            return result;
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
    $candidates = @(
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object {
                try { $_.MainModule.FileName -match '\\game\.dat$' }
                catch { $false }
            }
    )
    if ($candidates.Count -ne 1) {
        throw "Expected exactly one running game.dat. Found $($candidates.Count). Pass -ProcessId explicitly."
    }
    $ProcessId = [int]$candidates[0].Id
}

$proc = Get-Process -Id $ProcessId -ErrorAction Stop
$exePath = $proc.MainModule.FileName
$hash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToUpperInvariant()

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR LIVE LOBBY VALUE DIFF - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID             : {0}" -f $ProcessId)
Write-Host ("Image           : {0}" -f $exePath)
Write-Host ("SHA256          : {0}" -f $hash)
Write-Host ("Expected change : DWORD {0} -> {1}" -f $OldValue, $NewValue)
Write-Host ''

if ($hash -ne $ExpectedHash) {
    throw "HASH MISMATCH - aborted before memory scan."
}

Write-Host ("Capturing baseline addresses whose aligned DWORD == {0} ..." -f $OldValue)
$baseline = [A8PLobbyValueDiff]::Capture([uint32]$ProcessId, $OldValue)
Write-Host ("Baseline regions : {0}" -f $baseline.Regions)
Write-Host ("Baseline bytes   : {0:N0}" -f $baseline.Bytes)
Write-Host ("Value addresses  : {0:N0}" -f $baseline.Addresses.Count)
Write-Host ''
Write-Host 'NOW change exactly ONE lobby field:' -ForegroundColor Yellow
Write-Host '  P3: Soldier -> Captain' -ForegroundColor Yellow
Write-Host 'Do not change team, army, captain, color, handicap, ready, scenario, or any other row.' -ForegroundColor Yellow
Write-Host ''
[void](Read-Host 'After the UI visibly shows P3 = Captain, return here and press ENTER')

Write-Host ''
Write-Host ("Rescanning for the SAME addresses now containing DWORD {0} ..." -f $NewValue)
$compare = [A8PLobbyValueDiff]::FindTransitions([uint32]$ProcessId, $NewValue, $baseline.Addresses)

Write-Host ''
Write-Host '============================================================'
Write-Host ("Transitions {0}->{1}: {2}" -f $OldValue, $NewValue, $compare.Hits.Count)
Write-Host '============================================================'

$index = 0
foreach ($a in $compare.Hits) {
    $index++
    $ctx = [A8PLobbyValueDiff]::ReadContext([uint32]$ProcessId, [int64]$a, 32, 32)
    $hex = if ($ctx.Length -gt 0) { ([BitConverter]::ToString($ctx) -replace '-', ' ') } else { '<context unreadable>' }
    Write-Host ("HIT #{0} @ 0x{1:X8}" -f $index, $a)
    Write-Host ("  DWORD address : 0x{0:X8}" -f $a)
    Write-Host ("  Context -0x20..+0x23: {0}" -f $hex)
}

Write-Host ''
if ($compare.Hits.Count -eq 0) {
    Write-Host 'No aligned writable-memory DWORD followed the expected 3->4 transition.' -ForegroundColor Yellow
    Write-Host 'That would mean either the UI labels do not map 3->4 at this staging layer, or the live field uses another representation.'
}
elseif ($compare.Hits.Count -eq 1) {
    Write-Host 'Exactly one transition hit. This is a HIGH-VALUE candidate, but still needs a reverse transition or second-row differential before any write test.' -ForegroundColor Green
}
else {
    Write-Host 'Multiple transition hits found. Use a reverse transition and/or a separate P4-only change to isolate the true lobby field.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
