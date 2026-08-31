param(
    [int]$ProcessId = 0,
    [int]$Stride = 0x1DC
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# Finds the current compact WotR lobby block by semantic vector
#   6,0,3,3,1,1,1,1
# at stride 0x1DC, then inspects each row as a possible PlayerInfo-like object:
#   object+0x00 : vtable-like DWORD (field address - 4)
#   object+0x04 : PlayerType (the located semantic field)
#   object+0x38 : raw endpoint/IP-like DWORD
#   object+0x3C : port-like WORD
# No WriteProcessMemory is imported or used.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$Expected = [uint32[]](6,0,3,3,1,1,1,1)

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PRelocatingPlayerInfoVerify
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

    static bool ReadExact(IntPtr h, Int64 address, byte[] b)
    {
        IntPtr got;
        bool ok = ReadProcessMemory(h, new IntPtr(address), b, new IntPtr(b.Length), out got);
        return ok && got.ToInt64() == b.Length;
    }

    static bool ReadU32(IntPtr h, Int64 address, out UInt32 value)
    {
        value = 0;
        byte[] b = new byte[4];
        if (!ReadExact(h, address, b)) return false;
        value = BitConverter.ToUInt32(b, 0);
        return true;
    }

    public sealed class Result
    {
        public List<Int64> Hits = new List<Int64>();
        public Int64 Regions;
        public Int64 Bytes;
        public Int64 SixSeeds;
    }

    public static Result Find(UInt32 pid, Int32 stride, UInt32[] expected)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess failed");

        try
        {
            Result r = new Result();
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
                            if (BitConverter.ToUInt32(buf, i) != expected[0]) continue;
                            Int64 p1Field = regionBase + off + i;
                            r.SixSeeds++;

                            bool match = true;
                            for (Int32 slot = 0; slot < expected.Length; slot++)
                            {
                                UInt32 v;
                                if (!ReadU32(h, p1Field + ((Int64)slot * stride), out v) || v != expected[slot])
                                {
                                    match = false;
                                    break;
                                }
                            }

                            if (match) r.Hits.Add(p1Field);
                        }
                    }
                }

                address = next;
            }

            return r;
        }
        finally { CloseHandle(h); }
    }

    public static UInt32 ReadU32One(UInt32 pid, Int64 address)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess failed");
        try
        {
            UInt32 v;
            if (!ReadU32(h, address, out v))
                throw new Exception(String.Format("ReadU32 failed at 0x{0:X8}", address));
            return v;
        }
        finally { CloseHandle(h); }
    }

    public static UInt16 ReadU16One(UInt32 pid, Int64 address)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess failed");
        try
        {
            byte[] b = new byte[2];
            if (!ReadExact(h, address, b))
                throw new Exception(String.Format("ReadU16 failed at 0x{0:X8}", address));
            return BitConverter.ToUInt16(b, 0);
        }
        finally { CloseHandle(h); }
    }
}
"@

function Format-IPv4BE([uint32]$v) {
    '{0}.{1}.{2}.{3}' -f (($v -shr 24) -band 255), (($v -shr 16) -band 255), (($v -shr 8) -band 255), ($v -band 255)
}

function Type-Name([uint32]$v) {
    switch ($v) {
        0 { 'Open' }
        1 { 'Closed' }
        2 { 'Peasant' }
        3 { 'Soldier' }
        4 { 'Captain' }
        5 { 'Death March' }
        6 { 'Network Human' }
        default { 'Unknown' }
    }
}

if ($ProcessId -le 0) {
    $games = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.MainModule.FileName -match '\\game\.dat$' } catch { $false }
    })
    if ($games.Count -ne 1) {
        throw "Expected exactly one running game.dat. Found $($games.Count). Pass -ProcessId explicitly."
    }
    $ProcessId = [int]$games[0].Id
}

$proc = Get-Process -Id $ProcessId -ErrorAction Stop
$exePath = $proc.MainModule.FileName
$hash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToUpperInvariant()
$moduleBase = $proc.MainModule.BaseAddress.ToInt64()
$moduleSize = [int64]$proc.MainModule.ModuleMemorySize
$moduleEnd = $moduleBase + $moduleSize

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR RELOCATING PLAYERINFO VERIFY - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID          : {0}" -f $ProcessId)
Write-Host ("Image        : {0}" -f $exePath)
Write-Host ("SHA256       : {0}" -f $hash)
Write-Host ("Module       : 0x{0:X8}..0x{1:X8}" -f $moduleBase, $moduleEnd)
Write-Host ("Stride       : 0x{0:X} ({1})" -f $Stride, $Stride)
Write-Host 'Expected     : 6,0,3,3,1,1,1,1'
Write-Host ''

if ($hash -ne $ExpectedHash) {
    throw 'HASH MISMATCH - aborted before memory scan.'
}

$r = [A8PRelocatingPlayerInfoVerify]::Find([uint32]$ProcessId, $Stride, $Expected)
Write-Host ("Pattern hits : {0}" -f $r.Hits.Count)
Write-Host ("DWORD==6 seeds: {0:N0}" -f $r.SixSeeds)
Write-Host ''

if ($r.Hits.Count -ne 1) {
    Write-Host 'Expected exactly one live semantic block. Stop here; do not infer object layout.' -ForegroundColor Yellow
    Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
    return
}

$p1Field = [int64]$r.Hits[0]
Write-Host ("Located P1 type field: 0x{0:X8}" -f $p1Field) -ForegroundColor Green
Write-Host ''

$vtables = New-Object System.Collections.Generic.List[uint32]
for ($slot = 0; $slot -lt 8; $slot++) {
    $typeAddr = $p1Field + ([int64]$slot * $Stride)
    $obj = $typeAddr - 4
    $vtable = [A8PRelocatingPlayerInfoVerify]::ReadU32One([uint32]$ProcessId, $obj)
    $type = [A8PRelocatingPlayerInfoVerify]::ReadU32One([uint32]$ProcessId, $obj + 0x04)
    $epRaw = [A8PRelocatingPlayerInfoVerify]::ReadU32One([uint32]$ProcessId, $obj + 0x38)
    $port = [A8PRelocatingPlayerInfoVerify]::ReadU16One([uint32]$ProcessId, $obj + 0x3C)
    $inImage = ([int64]$vtable -ge $moduleBase -and [int64]$vtable -lt $moduleEnd)
    $vtables.Add($vtable)

    Write-Host ("P{0}: obj=0x{1:X8} vtbl=0x{2:X8} inImage={3} Type={4} {5} EPraw=0x{6:X8} EPbe={7}:{8}" -f `
        ($slot+1), $obj, $vtable, $inImage, $type, (Type-Name $type), $epRaw, (Format-IPv4BE $epRaw), $port)
}

$unique = @($vtables | Sort-Object -Unique)
Write-Host ''
Write-Host ("Unique vtable values: {0}" -f $unique.Count)
foreach ($v in $unique) {
    Write-Host ("  0x{0:X8}" -f $v)
}

if ($unique.Count -eq 1 -and ([int64]$unique[0] -ge $moduleBase) -and ([int64]$unique[0] -lt $moduleEnd)) {
    Write-Host 'VTABLE UNIFORMITY: PASS' -ForegroundColor Green
    Write-Host 'All eight rows look like instances of the same in-module C++ object type, with PlayerType at +0x04.' -ForegroundColor Green
} else {
    Write-Host 'VTABLE UNIFORMITY: NOT PROVEN' -ForegroundColor Yellow
    Write-Host 'Do not treat field-4 as a confirmed object base unless the vtable pattern is coherent.'
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
