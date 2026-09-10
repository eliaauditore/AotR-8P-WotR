param(
    [int]$ProcessId = 0,
    [int]$MaxHits = 256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# Runtime classifier for the two object types discovered while tracing references
# to the current native pre-start Network GameInfo:
#   vtable 0x00C54CE0 - larger network/session object
#   vtable 0x00C508A0 - 12-byte polymorphic wrapper object
#
# The script:
#   1) locates live MEM_PRIVATE instances of both vtables,
#   2) decodes fields known from static constructors,
#   3) marks fields that equal the current Network GameInfo pointer,
#   4) scans MEM_PRIVATE for references to each matching C54CE0 session object.
# No WriteProcessMemory import exists.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$NetworkGlobalRva = [int64]0x009E892C
$ActiveGlobalRva  = [int64]0x009E7D6C
$SessionVtableRva = [int64]0x00854CE0   # static VA 0x00C54CE0 - 0x00400000
$SmallVtableRva   = [int64]0x008508A0   # static VA 0x00C508A0 - 0x00400000

if (-not ('A8PSessionOwnerRead' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PSessionOwnerRead
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
            int n=(int)got.ToInt64();
            if (n == count) return b;
            if (n <= 0) return new byte[0];
            byte[] s=new byte[n]; Array.Copy(b,s,n); return s;
        } finally { CloseHandle(h); }
    }

    public static Int64[] ScanPrivate(UInt32 pid, UInt32 needle, Int32 maxHits) {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            List<Int64> hits = new List<Int64>();
            byte[] pat = BitConverter.GetBytes(needle);
            UInt64 addr = 0, maxAddr = 0x7FFFFFFFUL;
            int mbiSize = Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION));
            const int CHUNK = 4 * 1024 * 1024;

            while (addr < maxAddr && hits.Count < maxHits) {
                MEMORY_BASIC_INFORMATION m;
                IntPtr q = VirtualQueryEx(h, new IntPtr((long)addr), out m, new IntPtr(mbiSize));
                if (q == IntPtr.Zero) break;
                UInt64 baseAddr=(UInt64)m.BaseAddress.ToInt64();
                UInt64 region=m.RegionSize.ToUInt64();
                if (region == 0) { addr += 0x1000; continue; }

                if (IsReadable(m)) {
                    UInt64 off=0; byte[] carry=new byte[0];
                    while (off < region && hits.Count < maxHits) {
                        int want=(int)Math.Min((UInt64)CHUNK,region-off);
                        byte[] buf=new byte[want]; IntPtr got;
                        bool ok=ReadProcessMemory(h,new IntPtr((long)(baseAddr+off)),buf,new IntPtr(want),out got);
                        int n=ok ? (int)got.ToInt64() : 0;
                        if (n <= 0) { off += (UInt64)want; carry=new byte[0]; continue; }

                        int total=carry.Length+n;
                        byte[] scan=new byte[total];
                        if (carry.Length>0) Array.Copy(carry,0,scan,0,carry.Length);
                        Array.Copy(buf,0,scan,carry.Length,n);
                        UInt64 scanBase=baseAddr+off-(UInt64)carry.Length;
                        for (int i=0;i<=total-4 && hits.Count<maxHits;i++) {
                            if (scan[i]==pat[0] && scan[i+1]==pat[1] && scan[i+2]==pat[2] && scan[i+3]==pat[3])
                                hits.Add((Int64)(scanBase+(UInt64)i));
                        }
                        int keep=Math.Min(3,total); carry=new byte[keep];
                        if (keep>0) Array.Copy(scan,total-keep,carry,0,keep);
                        off += (UInt64)n;
                        if (n < want) off += (UInt64)(want-n);
                    }
                }
                UInt64 next=baseAddr+region;
                if (next <= addr) break;
                addr=next;
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
$activeGlobalAddr = $base + $ActiveGlobalRva
$sessionVtable = [uint32]($base + $SessionVtableRva)
$smallVtable = [uint32]($base + $SmallVtableRva)
$networkPtr = [A8PSessionOwnerRead]::ReadU32([uint32]$ProcessId,$networkGlobalAddr)
$activePtr = [A8PSessionOwnerRead]::ReadU32([uint32]$ProcessId,$activeGlobalAddr)
if ($networkPtr -eq 0) { throw 'Network GameInfo global is NULL. Enter native WotR host lobby first.' }

function Read-U32([int64]$a) { [A8PSessionOwnerRead]::ReadU32([uint32]$ProcessId,$a) }
function Format-IPv4BE([uint32]$raw) {
    return ('{0}.{1}.{2}.{3}' -f (($raw -shr 24)-band 255),(($raw -shr 16)-band 255),(($raw -shr 8)-band 255),($raw-band 255))
}
function Dump-Context([int64]$addr,[int]$before=0x20,[int]$after=0x20) {
    $start=$addr-$before
    $count=$before+$after+4
    $b=[A8PSessionOwnerRead]::ReadBytes([uint32]$ProcessId,$start,$count)
    for ($o=0; $o+4 -le $b.Length; $o+=4) {
        $a=$start+$o; $v=[BitConverter]::ToUInt32($b,$o)
        $m=if ($a -eq $addr) {'>>'} else {'  '}
        Write-Host ("  {0} 0x{1:X8}: 0x{2:X8}" -f $m,$a,$v)
    }
}

Write-Host '============================================================'
Write-Host ' AOTR WOTR SESSION OBJECT RUNTIME OWNER SCAN - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID                  : {0}" -f $ProcessId)
Write-Host ("Image                : {0}" -f $exe)
Write-Host ("SHA256               : {0}" -f $hash)
Write-Host ("Runtime base         : 0x{0:X8}" -f $base)
Write-Host ("Network GameInfo     : 0x{0:X8}" -f $networkPtr)
Write-Host ("TheGameInfo          : 0x{0:X8}" -f $activePtr)
Write-Host ("C54CE0 runtime vtable: 0x{0:X8}" -f $sessionVtable)
Write-Host ("C508A0 runtime vtable: 0x{0:X8}" -f $smallVtable)
Write-Host ''

$sessionHits=[A8PSessionOwnerRead]::ScanPrivate([uint32]$ProcessId,$sessionVtable,$MaxHits)
Write-Host ("================ C54CE0 LIVE CANDIDATES ({0}) ================" -f $sessionHits.Count)
$matchingSessions=@()
$i=0
foreach ($h in $sessionHits) {
    $i++
    try {
        $f10=Read-U32 ($h+0x10)
        $f44=Read-U32 ($h+0x44)
        $f48=Read-U32 ($h+0x48)
        $f4c=Read-U32 ($h+0x4C)
        $f50=Read-U32 ($h+0x50)
        $m10=($f10 -eq $networkPtr); $m44=($f44 -eq $networkPtr)
        if ($m10 -or $m44) { $matchingSessions += [int64]$h }
        Write-Host ("C54CE0 #{0}: base=0x{1:X8}" -f $i,$h)
        Write-Host ("  +0x10 = 0x{0:X8} networkMatch={1}" -f $f10,$m10)
        Write-Host ("  +0x44 = 0x{0:X8} networkMatch={1}" -f $f44,$m44)
        Write-Host ("  +0x48 = 0x{0:X8} endpointBE={1}" -f $f48,(Format-IPv4BE $f48))
        Write-Host ("  +0x4C = 0x{0:X8} decimal={1}" -f $f4c,$f4c)
        Write-Host ("  +0x50 = 0x{0:X8}" -f $f50)
    } catch {
        Write-Host ("C54CE0 #{0}: base=0x{1:X8} READ ERROR: {2}" -f $i,$h,$_.Exception.Message)
    }
    Write-Host ''
}

$smallHits=[A8PSessionOwnerRead]::ScanPrivate([uint32]$ProcessId,$smallVtable,$MaxHits)
Write-Host ("================ C508A0 12-BYTE OBJECTS ({0}) ================" -f $smallHits.Count)
$i=0
foreach ($h in $smallHits) {
    $i++
    try {
        $tag=Read-U32 ($h+4)
        $ptr=Read-U32 ($h+8)
        Write-Host ("C508A0 #{0}: base=0x{1:X8} tag=0x{2:X8} ({2}) value=0x{3:X8} networkMatch={4}" -f $i,$h,$tag,$ptr,($ptr -eq $networkPtr))
    } catch {
        Write-Host ("C508A0 #{0}: base=0x{1:X8} READ ERROR" -f $i,$h)
    }
}
Write-Host ''

Write-Host '================ REFERENCES TO MATCHING C54CE0 OBJECTS ================'
if ($matchingSessions.Count -eq 0) {
    Write-Host 'No C54CE0 object currently points to the Network GameInfo at +0x10 or +0x44.'
}
foreach ($obj in $matchingSessions) {
    Write-Host ("SESSION OBJECT 0x{0:X8}" -f $obj)
    $refs=[A8PSessionOwnerRead]::ScanPrivate([uint32]$ProcessId,[uint32]$obj,$MaxHits)
    Write-Host ("  MEM_PRIVATE refs: {0}" -f $refs.Count)
    $n=0
    foreach ($r in $refs) {
        $n++
        Write-Host ("  REF #{0}: 0x{1:X8}" -f $n,$r)
        Dump-Context $r 0x18 0x18
    }
    Write-Host ''
}

Write-Host 'Interpretation:'
Write-Host '  - Static constructor 0x0084C76D writes C54CE0 to [this], so a MEM_PRIVATE C54CE0 hit is a real class-instance candidate.'
Write-Host '  - Static 0x0081C852/0x0081D390/0x00847118 paths establish C508A0 as a separate 12-byte polymorphic object with fields +4 and +8.'
Write-Host '  - A C54CE0 object with Network GameInfo at +0x10/+0x44 plus local endpoint at +0x48/+0x4C is the strongest current native session-object candidate.'
Write-Host '  - References to that exact object can reveal its owner/global without relying on offset coincidences.'
Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
