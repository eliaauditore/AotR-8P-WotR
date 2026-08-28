param(
    [int]$ProcessId = 0,
    [string]$Label = 'NODE'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY RUNTIME SPLIT.
# Uses the proven writer formula for the observed B04 state:
#   B04 = componentA + componentB (mod 2^32)
# where componentB is the cached DWORD at [DE3D84]+0x200 returned by 0x61F300.
# Therefore componentA can be recovered as B04 - componentB (mod 2^32).
# Imports only OpenProcess / ReadProcessMemory / CloseHandle.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ManagerGlobalRva = [int64]0x009E4364   # VA 0x00DE4364
$CompBGlobalRva   = [int64]0x009E3D84   # VA 0x00DE3D84

if (-not ('A8PB04SplitRead' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class A8PB04SplitRead {
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr n, out IntPtr got);
    const UInt32 PROCESS_VM_READ=0x0010, PROCESS_QUERY_INFORMATION=0x0400;
    public static byte[] Read(UInt32 pid, Int64 addr, Int32 count) {
        IntPtr h=OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION,false,pid);
        if(h==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            byte[] b=new byte[count]; IntPtr got;
            if(!ReadProcessMemory(h,new IntPtr(addr),b,new IntPtr(count),out got) || got.ToInt64()!=count)
                throw new Exception("ReadProcessMemory failed at 0x"+addr.ToString("X8")+" len="+count);
            return b;
        } finally { CloseHandle(h); }
    }
}
"@
}

if ($ProcessId -le 0) {
    $games = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'game.dat' -and $_.ExecutablePath -match '\\game\.dat$' })
    if ($games.Count -ne 1) { throw "Expected exactly one game.dat. Found $($games.Count). Pass -ProcessId." }
    $ProcessId = [int]$games[0].ProcessId
}

$proc = Get-Process -Id $ProcessId -ErrorAction Stop
$exe = $proc.MainModule.FileName
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH - expected $ExpectedHash, got $hash" }
$base = $proc.MainModule.BaseAddress.ToInt64()

function RBytes([int64]$a,[int]$n) { [A8PB04SplitRead]::Read([uint32]$ProcessId,$a,$n) }
function RU32([int64]$a) { [BitConverter]::ToUInt32((RBytes $a 4),0) }
function RU8([int64]$a) { (RBytes $a 1)[0] }

$manager = RU32 ($base + $ManagerGlobalRva)
$compObj = RU32 ($base + $CompBGlobalRva)
if ($manager -eq 0) { throw 'DE4364 manager is NULL.' }
if ($compObj -eq 0) { throw 'DE3D84 object is NULL.' }

$b04 = RU32 ([int64]$manager + 0xB04)
$b38 = RU32 ([int64]$manager + 0xB38)
$componentB = RU32 ([int64]$compObj + 0x200)
$derivedA64 = (([uint64]$b04 + [uint64]4294967296 - [uint64]$componentB) % [uint64]4294967296)
$componentA = [uint32]$derivedA64

$listBegin = RU32 ([int64]$compObj + 0x17C)
$listEnd   = RU32 ([int64]$compObj + 0x180)
$lazyFlag  = RU8  ([int64]$compObj + 0x1E8)
$accCount  = RU32 ([int64]$compObj + 0x160)
$listCount = '<invalid>'
if ($listEnd -ge $listBegin) {
    $diff = [uint64]$listEnd - [uint64]$listBegin
    if (($diff % 4) -eq 0) { $listCount = [string]($diff / 4) }
}

Write-Host '============================================================'
Write-Host ' AOTR WOTR B04 RUNTIME COMPONENT SPLIT - READ ONLY'
Write-Host '============================================================'
Write-Host ("Label                : {0}" -f $Label)
Write-Host ("PID                  : {0}" -f $ProcessId)
Write-Host ("Image                : {0}" -f $exe)
Write-Host ("SHA256               : {0}" -f $hash)
Write-Host ("Runtime base         : 0x{0:X8}" -f $base)
Write-Host ("DE4364 manager       : 0x{0:X8}" -f $manager)
Write-Host ("DE3D84 object        : 0x{0:X8}" -f $compObj)
Write-Host ''
Write-Host '================ PROVEN FORMULA SPLIT ================'
Write-Host ("B04 live             : 0x{0:X8}" -f $b04)
Write-Host ("B38 live             : 0x{0:X8}" -f $b38)
Write-Host ("component B +0x200   : 0x{0:X8}" -f $componentB)
Write-Host ("derived component A  : 0x{0:X8}" -f $componentA)
Write-Host 'Formula               : A = (B04 - B) mod 2^32'
Write-Host ''
Write-Host '================ COMPONENT-B OBJECT STATE ================'
Write-Host ("list +0x17C begin    : 0x{0:X8}" -f $listBegin)
Write-Host ("list +0x180 end      : 0x{0:X8}" -f $listEnd)
Write-Host ("list DWORD count     : {0}" -f $listCount)
Write-Host ("lazy flag +0x1E8     : {0}" -f $lazyFlag)
Write-Host ("acc/count +0x160     : 0x{0:X8}" -f $accCount)
Write-Host ''
Write-Host ("COMPARISON_KEY       : B04={0:X8};A={1:X8};B={2:X8};B38={3:X8};LISTCOUNT={4};FLAG={5};ACC={6:X8}" -f $b04,$componentA,$componentB,$b38,$listCount,$lazyFlag,$accCount)
Write-Host ''
Write-Host 'Interpretation:'
Write-Host '  - Same A, different B -> mismatch is in the DE3D84/+0x200 component path.'
Write-Host '  - Different A, same B -> mismatch is in the indirect [ebp-0x28] component path.'
Write-Host '  - Both differ -> both sources contribute to the host/client B04 mismatch.'
Write-Host '  - This split assumes the observed live B04 came from the proven 0x63C809/0x63C820 producer path and was not overwritten afterward.'
Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
