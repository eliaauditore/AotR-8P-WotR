param(
    [int]$ProcessId = 0,
    [int]$Stride = 0x1DC
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# Relocates the live compact 8-row WotR lobby representation after UI changes
# that may rebuild/move the backing block.
# Current expected UI vector:
#   P1 Host, P2 Open, P3 Soldier, P4 Soldier, P5-P8 Closed
# Numeric vector:
#   6,0,3,3,1,1,1,1

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$Expected = [uint32[]](6,0,3,3,1,1,1,1)

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PCompactRelocate
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

    static bool ReadU32(IntPtr h, Int64 address, out UInt32 value)
    {
        value = 0;
        byte[] b = new byte[4];
        IntPtr got;
        bool ok = ReadProcessMemory(h, new IntPtr(address), b, new IntPtr(4), out got);
        if (!ok || got.ToInt64() != 4) return false;
        value = BitConverter.ToUInt32(b, 0);
        return true;
    }

    public sealed class Hit
    {
        public Int64 P1;
        public UInt32[] Values;
    }

    public sealed class Result
    {
        public List<Hit> Hits = new List<Hit>();
        public Int64 Regions;
        public Int64 Bytes;
        public Int64 SixCandidates;
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
                            Int64 p1 = regionBase + off + i;
                            r.SixCandidates++;

                            UInt32[] vals = new UInt32[expected.Length];
                            bool match = true;
                            for (Int32 slot = 0; slot < expected.Length; slot++)
                            {
                                UInt32 v;
                                if (!ReadU32(h, p1 + ((Int64)slot * stride), out v))
                                {
                                    match = false;
                                    break;
                                }
                                vals[slot] = v;
                                if (v != expected[slot])
                                {
                                    match = false;
                                    break;
                                }
                            }

                            if (match)
                                r.Hits.Add(new Hit { P1 = p1, Values = vals });
                        }
                    }
                }

                address = next;
            }

            return r;
        }
        finally { CloseHandle(h); }
    }

    public static UInt32 ReadOne(UInt32 pid, Int64 address)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess failed");
        try
        {
            UInt32 v;
            if (!ReadU32(h, address, out v))
                throw new Exception(String.Format("Read failed at 0x{0:X8}", address));
            return v;
        }
        finally { CloseHandle(h); }
    }
}
"@

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

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR COMPACT ROW RELOCATOR - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID       : {0}" -f $ProcessId)
Write-Host ("Image     : {0}" -f $exePath)
Write-Host ("SHA256    : {0}" -f $hash)
Write-Host ("Stride    : 0x{0:X} ({1})" -f $Stride, $Stride)
Write-Host 'Expected  : 6,0,3,3,1,1,1,1'
Write-Host ''

if ($hash -ne $ExpectedHash) {
    throw 'HASH MISMATCH - aborted before memory scan.'
}

$r = [A8PCompactRelocate]::Find([uint32]$ProcessId, $Stride, $Expected)

Write-Host ("Regions scanned : {0}" -f $r.Regions)
Write-Host ("Bytes scanned   : {0:N0}" -f $r.Bytes)
Write-Host ("DWORD==6 seeds  : {0:N0}" -f $r.SixCandidates)
Write-Host ("Pattern hits    : {0}" -f $r.Hits.Count)
Write-Host ''

$idx = 0
foreach ($hit in $r.Hits) {
    $idx++
    Write-Host ("HIT #{0} P1 field @ 0x{1:X8}" -f $idx, $hit.P1)
    for ($slot = 0; $slot -lt 8; $slot++) {
        $addr = [int64]$hit.P1 + ([int64]$slot * $Stride)
        $v = [A8PCompactRelocate]::ReadOne([uint32]$ProcessId, $addr)
        Write-Host ("  P{0}: 0x{1:X8} = {2}" -f ($slot+1), $addr, $v)
    }
}

Write-Host ''
if ($r.Hits.Count -eq 1) {
    Write-Host 'RELOCATION PASS: exactly one live compact 8-row block matches the current lobby vector.' -ForegroundColor Green
    Write-Host 'Do not assume this address is stable across further UI changes; locate by structure/vector, not by absolute address.'
}
elseif ($r.Hits.Count -eq 0) {
    Write-Host 'No live block matched 6,0,3,3,1,1,1,1 at stride 0x1DC.' -ForegroundColor Yellow
    Write-Host 'Either the backing representation changed, the current visible lobby vector differs, or 0x1DC was specific to the previous allocation.'
}
else {
    Write-Host 'Multiple matching blocks found. Treat as mirrors/copies until another controlled mutation isolates the authoritative one.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
