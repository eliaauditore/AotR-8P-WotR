param(
    [int]$ProcessId = 0,
    [int]$Stride = 0x1DC
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# State A: P1 Host, P2 Open, P3/P4 Soldier, P5-P8 Closed
#          vector 6,0,3,3,1,1,1,1
# State B: change ONLY P2 Open -> Soldier
#          vector 6,3,3,3,1,1,1,1
#
# Locates the live network-GameInfo-derived parent in each state, then finds
# memory slots that point to the parent. Stable pointer-holder addresses that
# change oldParent -> newParent are strong owner/reference candidates.
# No WriteProcessMemory is imported or used.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ExpectedA = [uint32[]](6,0,3,3,1,1,1,1)
$ExpectedB = [uint32[]](6,3,3,3,1,1,1,1)
$RowVtable = [uint32]0x00C54B5C
$ParentVtable = [uint32]0x00C54B78
$RowOffset = 0xDC

if (-not ('A8PGameInfoOwnerDiff' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PGameInfoOwnerDiff
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
    static extern IntPtr VirtualQueryEx(IntPtr hProcess, IntPtr lpAddress,
        out MEMORY_BASIC_INFORMATION lpBuffer, IntPtr dwLength);

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress,
        byte[] lpBuffer, IntPtr nSize, out IntPtr lpNumberOfBytesRead);

    const UInt32 PROCESS_VM_READ = 0x0010;
    const UInt32 PROCESS_QUERY_INFORMATION = 0x0400;
    const UInt32 MEM_COMMIT = 0x1000;
    const UInt32 MEM_PRIVATE = 0x20000;
    const UInt32 MEM_MAPPED = 0x40000;
    const UInt32 MEM_IMAGE = 0x1000000;
    const UInt32 PAGE_GUARD = 0x100;
    const UInt32 PAGE_NOACCESS = 0x01;

    static bool Readable(MEMORY_BASIC_INFORMATION mbi)
    {
        if (mbi.State != MEM_COMMIT) return false;
        if ((mbi.Protect & PAGE_GUARD) != 0) return false;
        if ((mbi.Protect & PAGE_NOACCESS) != 0) return false;
        return mbi.Type == MEM_PRIVATE || mbi.Type == MEM_MAPPED || mbi.Type == MEM_IMAGE;
    }

    static bool WritableData(MEMORY_BASIC_INFORMATION mbi)
    {
        if (!Readable(mbi)) return false;
        UInt32 p = mbi.Protect & 0xFF;
        bool writable = p == 0x04 || p == 0x08 || p == 0x40 || p == 0x80;
        return writable && (mbi.Type == MEM_PRIVATE || mbi.Type == MEM_MAPPED);
    }

    static bool ReadExact(IntPtr h, Int64 addr, byte[] b)
    {
        IntPtr got;
        bool ok = ReadProcessMemory(h, new IntPtr(addr), b, new IntPtr(b.Length), out got);
        return ok && got.ToInt64() == b.Length;
    }

    static bool ReadU32(IntPtr h, Int64 addr, out UInt32 value)
    {
        value = 0;
        byte[] b = new byte[4];
        if (!ReadExact(h, addr, b)) return false;
        value = BitConverter.ToUInt32(b, 0);
        return true;
    }

    public static UInt32 ReadOne(UInt32 pid, Int64 addr)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            UInt32 v;
            if (!ReadU32(h, addr, out v)) throw new Exception("ReadU32 failed");
            return v;
        } finally { CloseHandle(h); }
    }

    public static byte[] ReadBytes(UInt32 pid, Int64 addr, Int32 count)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            byte[] b = new byte[count];
            if (!ReadExact(h, addr, b)) return new byte[0];
            return b;
        } finally { CloseHandle(h); }
    }

    public static List<Int64> FindPattern(UInt32 pid, Int32 stride, UInt32[] expected, UInt32 rowVt, UInt32 parentVt, Int32 rowOffset)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            List<Int64> hits = new List<Int64>();
            Int64 address = 0;
            const Int64 maxAddress = 0x100000000L;
            Int32 mbiSize = Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION));
            const Int32 Chunk = 4 * 1024 * 1024;

            while (address < maxAddress)
            {
                MEMORY_BASIC_INFORMATION mbi;
                if (VirtualQueryEx(h, new IntPtr(address), out mbi, new IntPtr(mbiSize)) == IntPtr.Zero) break;
                Int64 rb = mbi.BaseAddress.ToInt64();
                Int64 rs = unchecked((Int64)mbi.RegionSize.ToUInt64());
                if (rs <= 0) break;
                Int64 next = rb + rs;
                if (next <= address) break;

                if (WritableData(mbi))
                {
                    for (Int64 off = 0; off < rs; off += Chunk)
                    {
                        Int32 want = (Int32)Math.Min((Int64)Chunk, rs - off);
                        byte[] buf = new byte[want];
                        IntPtr got;
                        bool ok = ReadProcessMemory(h, new IntPtr(rb + off), buf, new IntPtr(want), out got);
                        Int32 n = ok ? (Int32)got.ToInt64() : 0;
                        n -= n % 4;

                        for (Int32 i = 0; i <= n - 4; i += 4)
                        {
                            if (BitConverter.ToUInt32(buf, i) != expected[0]) continue;
                            Int64 p1Type = rb + off + i;
                            Int64 p1Obj = p1Type - 4;
                            UInt32 vt;
                            if (!ReadU32(h, p1Obj, out vt) || vt != rowVt) continue;

                            bool match = true;
                            for (Int32 s = 0; s < 8; s++)
                            {
                                Int64 obj = p1Obj + ((Int64)s * stride);
                                UInt32 rowvt, typ;
                                if (!ReadU32(h, obj, out rowvt) || rowvt != rowVt ||
                                    !ReadU32(h, obj + 4, out typ) || typ != expected[s])
                                { match = false; break; }
                            }
                            if (!match) continue;

                            Int64 parent = p1Obj - rowOffset;
                            UInt32 pvt;
                            if (!ReadU32(h, parent, out pvt) || pvt != parentVt) continue;
                            hits.Add(parent);
                        }
                    }
                }
                address = next;
            }
            return hits;
        }
        finally { CloseHandle(h); }
    }

    public static List<Int64> FindRefs(UInt32 pid, UInt32 target)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            List<Int64> hits = new List<Int64>();
            Int64 address = 0;
            const Int64 maxAddress = 0x100000000L;
            Int32 mbiSize = Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION));
            const Int32 Chunk = 4 * 1024 * 1024;

            while (address < maxAddress)
            {
                MEMORY_BASIC_INFORMATION mbi;
                if (VirtualQueryEx(h, new IntPtr(address), out mbi, new IntPtr(mbiSize)) == IntPtr.Zero) break;
                Int64 rb = mbi.BaseAddress.ToInt64();
                Int64 rs = unchecked((Int64)mbi.RegionSize.ToUInt64());
                if (rs <= 0) break;
                Int64 next = rb + rs;
                if (next <= address) break;

                if (Readable(mbi))
                {
                    for (Int64 off = 0; off < rs; off += Chunk)
                    {
                        Int32 want = (Int32)Math.Min((Int64)Chunk, rs - off);
                        byte[] buf = new byte[want];
                        IntPtr got;
                        bool ok = ReadProcessMemory(h, new IntPtr(rb + off), buf, new IntPtr(want), out got);
                        Int32 n = ok ? (Int32)got.ToInt64() : 0;
                        n -= n % 4;
                        for (Int32 i = 0; i <= n - 4; i += 4)
                            if (BitConverter.ToUInt32(buf, i) == target)
                                hits.Add(rb + off + i);
                    }
                }
                address = next;
            }
            return hits;
        }
        finally { CloseHandle(h); }
    }
}
"@
}

function Hex-Bytes([byte[]]$b) {
    if (-not $b -or $b.Length -eq 0) { return '<unreadable>' }
    return (($b | ForEach-Object { $_.ToString('X2') }) -join ' ')
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
$moduleBase = $proc.MainModule.BaseAddress.ToInt64()
$moduleEnd = $moduleBase + [int64]$proc.MainModule.ModuleMemorySize

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR GAMEINFO OWNER POINTER DIFF - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID      : {0}" -f $ProcessId)
Write-Host ("Image    : {0}" -f $exe)
Write-Host ("SHA256   : {0}" -f $hash)
Write-Host 'STATE A  : 6,0,3,3,1,1,1,1  (P2 Open)'
Write-Host 'STATE B  : 6,3,3,3,1,1,1,1  (P2 Soldier)'
Write-Host ''

if ($hash -ne $ExpectedHash) { throw 'HASH MISMATCH - aborted.' }

$aHits = [A8PGameInfoOwnerDiff]::FindPattern([uint32]$ProcessId, $Stride, $ExpectedA, $RowVtable, $ParentVtable, $RowOffset)
Write-Host ("STATE A parent hits: {0}" -f $aHits.Count)
if ($aHits.Count -ne 1) { throw 'Expected exactly one STATE A parent. Ensure P2 is Open and other rows match.' }
$parentA = [uint32]$aHits[0]
Write-Host ("STATE A parent     : 0x{0:X8}" -f $parentA) -ForegroundColor Green

$refsA = @([A8PGameInfoOwnerDiff]::FindRefs([uint32]$ProcessId, $parentA))
Write-Host ("Pointers -> parentA : {0}" -f $refsA.Count)
foreach ($r in $refsA) {
    $inMod = ([int64]$r -ge $moduleBase -and [int64]$r -lt $moduleEnd)
    Write-Host ("  AREF 0x{0:X8} inModule={1}" -f [int64]$r, $inMod)
}

Write-Host ''
Write-Host 'NOW change exactly ONE lobby field:' -ForegroundColor Yellow
Write-Host '  P2: Open -> Soldier'
Write-Host 'Do not touch P3/P4 or P5-P8.'
Read-Host 'When P2 visibly shows Soldier, press ENTER'

$bHits = [A8PGameInfoOwnerDiff]::FindPattern([uint32]$ProcessId, $Stride, $ExpectedB, $RowVtable, $ParentVtable, $RowOffset)
Write-Host ''
Write-Host ("STATE B parent hits: {0}" -f $bHits.Count)
if ($bHits.Count -ne 1) { throw 'Expected exactly one STATE B parent. Ensure only P2 changed to Soldier.' }
$parentB = [uint32]$bHits[0]
Write-Host ("STATE B parent     : 0x{0:X8}" -f $parentB) -ForegroundColor Green
Write-Host ("Relocated          : {0}" -f ($parentA -ne $parentB))

$refsB = @([A8PGameInfoOwnerDiff]::FindRefs([uint32]$ProcessId, $parentB))
Write-Host ("Pointers -> parentB : {0}" -f $refsB.Count)

$stable = New-Object System.Collections.Generic.List[Int64]
foreach ($r in $refsA) {
    try {
        $now = [A8PGameInfoOwnerDiff]::ReadOne([uint32]$ProcessId, [int64]$r)
        if ($now -eq $parentB) { $stable.Add([int64]$r) }
    } catch { }
}

Write-Host ''
Write-Host ("STABLE OWNER/REFERENCE CANDIDATES oldParent->newParent: {0}" -f $stable.Count)
foreach ($r in $stable) {
    $inMod = ($r -ge $moduleBase -and $r -lt $moduleEnd)
    $ctxStart = [Math]::Max([int64]0, $r - 0x20)
    $ctx = [A8PGameInfoOwnerDiff]::ReadBytes([uint32]$ProcessId, $ctxStart, 0x44)
    Write-Host ("  CANDIDATE 0x{0:X8} inModule={1}" -f $r, $inMod) -ForegroundColor Green
    Write-Host ("    context@0x{0:X8}: {1}" -f $ctxStart, (Hex-Bytes $ctx))
}

Write-Host ''
if ($stable.Count -eq 0) {
    Write-Host 'No stable holder address followed the relocation. The live object may be passed transiently or referenced indirectly.' -ForegroundColor Yellow
} elseif ($stable.Count -eq 1) {
    Write-Host 'OWNER POINTER DIFF: one stable holder followed the relocation.' -ForegroundColor Green
} else {
    Write-Host 'OWNER POINTER DIFF: multiple stable holders followed the relocation; treat as owner/alias set until consumers are traced.' -ForegroundColor Yellow
}

Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
