param(
    [int]$ProcessId = 0,
    [int]$MaxHits = 256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# Finds live process-memory occurrences of the manager vtable 0x00C2FC58.
# For each candidate, inspects the known embedded Network-GameInfo relation at +0x674
# and a small set of manager/container fields. No WriteProcessMemory is imported or used.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ManagerVtableRva = [int64]0x0082FC58   # static VA 0x00C2FC58 - ImageBase 0x00400000
$NetworkVtableRva = [int64]0x00854B78   # static VA 0x00C54B78 - ImageBase 0x00400000
$NetworkGlobalRva = [int64]0x009E892C   # static VA 0x00DE892C
$ActiveGlobalRva  = [int64]0x009E7D6C   # static VA 0x00DE7D6C
$EmbeddedOffset   = [int64]0x674

if (-not ('A8PManagerRuntimeScan' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PManagerRuntimeScan
{
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress,
        byte[] lpBuffer, IntPtr nSize, out IntPtr lpNumberOfBytesRead);

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr VirtualQueryEx(IntPtr hProcess, IntPtr lpAddress,
        out MEMORY_BASIC_INFORMATION lpBuffer, IntPtr dwLength);

    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORY_BASIC_INFORMATION
    {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public UInt32 AllocationProtect;
        public IntPtr RegionSize;
        public UInt32 State;
        public UInt32 Protect;
        public UInt32 Type;
    }

    const UInt32 PROCESS_VM_READ = 0x0010;
    const UInt32 PROCESS_QUERY_INFORMATION = 0x0400;
    const UInt32 MEM_COMMIT = 0x1000;
    const UInt32 PAGE_NOACCESS = 0x01;
    const UInt32 PAGE_GUARD = 0x100;

    static bool IsReadable(UInt32 state, UInt32 protect)
    {
        if (state != MEM_COMMIT) return false;
        if ((protect & PAGE_GUARD) != 0) return false;
        if ((protect & 0xFF) == PAGE_NOACCESS) return false;
        return true;
    }

    static IntPtr Open(UInt32 pid)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        return h;
    }

    public static UInt32 ReadU32(UInt32 pid, Int64 addr)
    {
        IntPtr h = Open(pid);
        try {
            byte[] b = new byte[4];
            IntPtr got;
            bool ok = ReadProcessMemory(h, new IntPtr(addr), b, new IntPtr(4), out got);
            if (!ok || got.ToInt64() != 4) throw new Exception("ReadU32 failed at 0x" + addr.ToString("X8"));
            return BitConverter.ToUInt32(b, 0);
        }
        finally { CloseHandle(h); }
    }

    public static UInt32[] ScanDword(UInt32 pid, UInt32 needle, Int32 maxHits)
    {
        List<UInt32> hits = new List<UInt32>();
        IntPtr h = Open(pid);
        try {
            byte[] pat = BitConverter.GetBytes(needle);
            Int64 addr = 0x10000;
            Int64 maxAddr = 0x7FFF0000;
            int mbiSize = Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION));
            const int chunk = 1024 * 1024;

            while (addr < maxAddr && hits.Count < maxHits)
            {
                MEMORY_BASIC_INFORMATION mbi;
                IntPtr q = VirtualQueryEx(h, new IntPtr(addr), out mbi, new IntPtr(mbiSize));
                if (q == IntPtr.Zero) break;

                Int64 regionBase = mbi.BaseAddress.ToInt64();
                Int64 regionSize = mbi.RegionSize.ToInt64();
                if (regionSize <= 0) break;
                Int64 next = regionBase + regionSize;

                if (IsReadable(mbi.State, mbi.Protect))
                {
                    Int64 pos = regionBase;
                    byte[] tail = new byte[3];
                    int tailLen = 0;
                    while (pos < next && hits.Count < maxHits)
                    {
                        int want = (int)Math.Min((Int64)chunk, next - pos);
                        byte[] b = new byte[want];
                        IntPtr gotPtr;
                        bool ok = ReadProcessMemory(h, new IntPtr(pos), b, new IntPtr(want), out gotPtr);
                        int got = ok ? (int)gotPtr.ToInt64() : 0;
                        if (got <= 0) break;

                        byte[] scan;
                        Int64 scanBase;
                        if (tailLen > 0)
                        {
                            scan = new byte[tailLen + got];
                            Buffer.BlockCopy(tail, 0, scan, 0, tailLen);
                            Buffer.BlockCopy(b, 0, scan, tailLen, got);
                            scanBase = pos - tailLen;
                        }
                        else
                        {
                            scan = b;
                            scanBase = pos;
                        }

                        for (int i = 0; i + 4 <= scan.Length && hits.Count < maxHits; i++)
                        {
                            if (scan[i] == pat[0] && scan[i+1] == pat[1] && scan[i+2] == pat[2] && scan[i+3] == pat[3])
                            {
                                Int64 haddr = scanBase + i;
                                if (haddr >= 0 && haddr <= UInt32.MaxValue)
                                    hits.Add((UInt32)haddr);
                            }
                        }

                        tailLen = Math.Min(3, got);
                        if (tailLen > 0) Buffer.BlockCopy(b, got - tailLen, tail, 0, tailLen);
                        pos += got;
                        if (got < want) break;
                    }
                }

                if (next <= addr) break;
                addr = next;
            }
        }
        finally { CloseHandle(h); }
        return hits.ToArray();
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
$managerVtable = [uint32]($base + $ManagerVtableRva)
$networkVtable = [uint32]($base + $NetworkVtableRva)
$networkGlobalVA = $base + $NetworkGlobalRva
$activeGlobalVA = $base + $ActiveGlobalRva

function Read-U32([int64]$addr) {
    try { return [A8PManagerRuntimeScan]::ReadU32([uint32]$ProcessId, $addr) }
    catch { return [uint32]0 }
}

$network = Read-U32 $networkGlobalVA
$active = Read-U32 $activeGlobalVA
$derivedBase = if ($network -ge $EmbeddedOffset) { [uint32]($network - $EmbeddedOffset) } else { [uint32]0 }

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR MANAGER RUNTIME VTABLE SCAN - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID                  : {0}" -f $ProcessId)
Write-Host ("Image                : {0}" -f $exe)
Write-Host ("SHA256               : {0}" -f $hash)
Write-Host ("Runtime base         : 0x{0:X8}" -f $base)
Write-Host ("Manager vtable       : 0x{0:X8}" -f $managerVtable)
Write-Host ("Network vtable       : 0x{0:X8}" -f $networkVtable)
Write-Host ("Network global ptr   : 0x{0:X8}" -f $network)
Write-Host ("TheGameInfo ptr      : 0x{0:X8}" -f $active)
Write-Host ("Network - 0x674      : 0x{0:X8}" -f $derivedBase)
Write-Host ''

$hits = [A8PManagerRuntimeScan]::ScanDword([uint32]$ProcessId, $managerVtable, $MaxHits)
Write-Host ("Manager-vtable hits  : {0}" -f $hits.Count)
Write-Host ''

$idx = 0
foreach ($p in $hits) {
    $idx++
    $embedded = [uint32]([uint64]$p + [uint64]$EmbeddedOffset)
    $embeddedVt = Read-U32 $embedded
    $f24 = Read-U32 ([int64]$p + 0x24)
    $f28 = Read-U32 ([int64]$p + 0x28)
    $f2C = Read-U32 ([int64]$p + 0x2C)
    $f30 = Read-U32 ([int64]$p + 0x30)

    $isDerived = ($p -eq $derivedBase)
    $embeddedIsNetwork = ($embeddedVt -eq $networkVtable)
    $embeddedEqualsNetwork = ($embedded -eq $network)

    Write-Host ("HIT #{0}: manager=0x{1:X8}" -f $idx,$p)
    Write-Host ("  +0x24..+0x30       : {0:X8} {1:X8} {2:X8} {3:X8}" -f $f24,$f28,$f2C,$f30)
    Write-Host ("  manager+0x674      : 0x{0:X8}" -f $embedded)
    Write-Host ("  [manager+0x674]    : 0x{0:X8} networkVtableMatch={1}" -f $embeddedVt,$embeddedIsNetwork)
    Write-Host ("  base==network-0x674: {0}" -f $isDerived)
    Write-Host ("  +0x674==network ptr: {0}" -f $embeddedEqualsNetwork)
    Write-Host ''
}

if ($hits.Count -ge $MaxHits) {
    Write-Host ("WARNING: hit cap {0} reached; raise -MaxHits if needed." -f $MaxHits) -ForegroundColor Yellow
}

if ($derivedBase -ne 0) {
    $derivedVt = Read-U32 $derivedBase
    Write-Host '================ DIRECT DERIVED-BASE CHECK ================'
    Write-Host ("Candidate             : 0x{0:X8}" -f $derivedBase)
    Write-Host ("[candidate]           : 0x{0:X8}" -f $derivedVt)
    Write-Host ("Manager-vtable match  : {0}" -f ($derivedVt -eq $managerVtable))
    Write-Host ("candidate+0x674       : 0x{0:X8}" -f ([uint32]([uint64]$derivedBase + [uint64]$EmbeddedOffset)))
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
