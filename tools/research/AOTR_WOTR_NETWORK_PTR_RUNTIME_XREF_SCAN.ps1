param(
    [int]$ProcessId = 0,
    [int]$MaxHits = 256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# Finds private committed process-memory DWORD references to the current live
# pre-start Network GameInfo pointer from global RVA 0x009E892C.
# Intended to locate heap/container/map ownership of the standalone 0x1080
# Network-GameInfo path without assuming a manager base address.
# No WriteProcessMemory is imported or used.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$NetworkGlobalRva = [int64]0x009E892C
$ActiveGlobalRva  = [int64]0x009E7D6C

if (-not ('A8PPrivatePtrScan' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PPrivatePtrScan
{
    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORY_BASIC_INFORMATION {
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
    static extern IntPtr VirtualQueryEx(IntPtr hProcess, IntPtr lpAddress,
        out MEMORY_BASIC_INFORMATION lpBuffer, IntPtr dwLength);

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress,
        byte[] lpBuffer, IntPtr nSize, out IntPtr lpNumberOfBytesRead);

    const UInt32 PROCESS_VM_READ = 0x0010;
    const UInt32 PROCESS_QUERY_INFORMATION = 0x0400;
    const UInt32 MEM_COMMIT = 0x1000;
    const UInt32 MEM_PRIVATE = 0x20000;
    const UInt32 PAGE_NOACCESS = 0x01;
    const UInt32 PAGE_GUARD = 0x100;

    static bool IsReadable(MEMORY_BASIC_INFORMATION m) {
        if (m.State != MEM_COMMIT || m.Type != MEM_PRIVATE) return false;
        if ((m.Protect & PAGE_GUARD) != 0) return false;
        if ((m.Protect & 0xFF) == PAGE_NOACCESS || (m.Protect & 0xFF) == 0) return false;
        return true;
    }

    public static UInt32 ReadU32(UInt32 pid, Int64 addr) {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            byte[] b = new byte[4]; IntPtr got;
            if (!ReadProcessMemory(h, new IntPtr(addr), b, new IntPtr(4), out got) || got.ToInt64() != 4)
                throw new Exception("ReadU32 failed at 0x" + addr.ToString("X8"));
            return BitConverter.ToUInt32(b,0);
        } finally { CloseHandle(h); }
    }

    public static byte[] ReadBytes(UInt32 pid, Int64 addr, Int32 count) {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            byte[] b = new byte[count]; IntPtr got;
            if (!ReadProcessMemory(h, new IntPtr(addr), b, new IntPtr(count), out got)) return new byte[0];
            if (got.ToInt64() == count) return b;
            byte[] s = new byte[Math.Max(0,(int)got.ToInt64())]; Array.Copy(b,s,s.Length); return s;
        } finally { CloseHandle(h); }
    }

    public static Int64[] ScanPrivate(UInt32 pid, UInt32 needle, Int32 maxHits) {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            List<Int64> hits = new List<Int64>();
            byte[] pat = BitConverter.GetBytes(needle);
            UInt64 addr = 0;
            UInt64 maxAddr = 0x7FFFFFFFUL;
            int mbiSize = Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION));
            const int CHUNK = 4 * 1024 * 1024;

            while (addr < maxAddr && hits.Count < maxHits) {
                MEMORY_BASIC_INFORMATION m;
                IntPtr q = VirtualQueryEx(h, new IntPtr((long)addr), out m, new IntPtr(mbiSize));
                if (q == IntPtr.Zero) break;
                UInt64 baseAddr = (UInt64)m.BaseAddress.ToInt64();
                UInt64 region = m.RegionSize.ToUInt64();
                if (region == 0) { addr += 0x1000; continue; }

                if (IsReadable(m)) {
                    UInt64 off = 0;
                    byte[] carry = new byte[0];
                    while (off < region && hits.Count < maxHits) {
                        int want = (int)Math.Min((UInt64)CHUNK, region - off);
                        byte[] buf = new byte[want]; IntPtr got;
                        bool ok = ReadProcessMemory(h, new IntPtr((long)(baseAddr + off)), buf, new IntPtr(want), out got);
                        int n = ok ? (int)got.ToInt64() : 0;
                        if (n <= 0) { off += (UInt64)want; carry = new byte[0]; continue; }

                        int total = carry.Length + n;
                        byte[] scan = new byte[total];
                        if (carry.Length > 0) Array.Copy(carry, 0, scan, 0, carry.Length);
                        Array.Copy(buf, 0, scan, carry.Length, n);
                        UInt64 scanBase = baseAddr + off - (UInt64)carry.Length;

                        for (int i=0; i<=total-4 && hits.Count < maxHits; i++) {
                            if (scan[i]==pat[0] && scan[i+1]==pat[1] && scan[i+2]==pat[2] && scan[i+3]==pat[3])
                                hits.Add((Int64)(scanBase + (UInt64)i));
                        }

                        int keep = Math.Min(3,total);
                        carry = new byte[keep];
                        if (keep>0) Array.Copy(scan,total-keep,carry,0,keep);
                        off += (UInt64)n;
                        if (n < want) off += (UInt64)(want-n);
                    }
                }

                UInt64 next = baseAddr + region;
                if (next <= addr) break;
                addr = next;
            }
            return hits.ToArray();
        } finally { CloseHandle(h); }
    }
}
"@
}

if ($ProcessId -le 0) {
    $games = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.MainModule.FileName -match '\\game\.dat$' } catch { $false }
    })
    if ($games.Count -ne 1) { throw "Expected one game.dat. Found $($games.Count). Pass -ProcessId." }
    $ProcessId = [int]$games[0].Id
}

$proc = Get-Process -Id $ProcessId -ErrorAction Stop
$exe = $proc.MainModule.FileName
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH - expected $ExpectedHash, got $hash" }

$base = $proc.MainModule.BaseAddress.ToInt64()
$networkGlobalAddr = $base + $NetworkGlobalRva
$activeGlobalAddr  = $base + $ActiveGlobalRva
$networkPtr = [A8PPrivatePtrScan]::ReadU32([uint32]$ProcessId,$networkGlobalAddr)
$activePtr  = [A8PPrivatePtrScan]::ReadU32([uint32]$ProcessId,$activeGlobalAddr)
if ($networkPtr -eq 0) { throw 'Network GameInfo global is NULL. Enter the native WotR host lobby first.' }

Write-Host '============================================================'
Write-Host ' AOTR WOTR NETWORK PTR RUNTIME XREF SCAN - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID                : {0}" -f $ProcessId)
Write-Host ("Image              : {0}" -f $exe)
Write-Host ("SHA256             : {0}" -f $hash)
Write-Host ("Runtime base       : 0x{0:X8}" -f $base)
Write-Host ("Network global VA  : 0x{0:X8}" -f $networkGlobalAddr)
Write-Host ("Network GameInfo   : 0x{0:X8}" -f $networkPtr)
Write-Host ("TheGameInfo        : 0x{0:X8}" -f $activePtr)
Write-Host ''
Write-Host 'Scanning MEM_PRIVATE committed readable regions for exact DWORD references...'

$hits = [A8PPrivatePtrScan]::ScanPrivate([uint32]$ProcessId,[uint32]$networkPtr,$MaxHits)
Write-Host ("Private pointer refs: {0}" -f $hits.Count)
Write-Host ''

$i=0
foreach ($h in $hits) {
    $i++
    $ctxStart = [int64]$h - 0x20
    $bytes = [A8PPrivatePtrScan]::ReadBytes([uint32]$ProcessId,$ctxStart,0x44)
    $dwords = @()
    for ($o=0; $o+4 -le $bytes.Length; $o+=4) {
        $v = [BitConverter]::ToUInt32($bytes,$o)
        $a = $ctxStart + $o
        $mark = if ($a -eq $h) { '>>' } else { '  ' }
        $dwords += ("{0} 0x{1:X8}: 0x{2:X8}" -f $mark,$a,$v)
    }
    Write-Host ("HIT #{0}: ref=0x{1:X8}" -f $i,$h)
    Write-Host ("  delta from network object : {0:+#;-#;0} (0x{1:X})" -f ([int64]$h-[int64]$networkPtr), [math]::Abs([int64]$h-[int64]$networkPtr))
    foreach ($line in $dwords) { Write-Host ('  ' + $line) }
    Write-Host ''
}

Write-Host 'Known image-global reference (not part of MEM_PRIVATE scan):'
Write-Host ("  [0x{0:X8}] = 0x{1:X8}" -f $networkGlobalAddr,$networkPtr)
Write-Host ''
Write-Host 'Interpretation:'
Write-Host '  - Heap/container ownership should normally appear among MEM_PRIVATE hits.'
Write-Host '  - Stack copies may also appear; classify by surrounding pointer structure and stability.'
Write-Host '  - A map/tree value node holding the exact GameInfo pointer is especially interesting because 0x00787C09 stores EDI via [EAX] returned from helper 0x007871FC.'
Write-Host '  - Do not write to any hit; this probe is provenance-only.'
Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
