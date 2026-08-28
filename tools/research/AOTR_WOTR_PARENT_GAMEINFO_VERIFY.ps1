param(
    [int]$ProcessId = 24252,
    [Int64]$P1Object = 0x0957567C
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# Verifies the current live lobby-row object array against the constructor layout
# inferred from the static vtable xrefs:
#   parent vtable      @ +0x000 = 0x00C54B78
#   first row object   @ +0x0DC
#   row stride                  = 0x1DC
#   end of 8 rows               = +0xFBC
# No process memory is modified.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ParentVtable = [uint32]0x00C54B78
$RowVtable    = [uint32]0x00C54B5C
$RowOffset    = [int64]0xDC
$Stride       = [int64]0x1DC
$ExpectedTypes = [uint32[]](6,0,3,3,1,1,1,1)

Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class A8PParentVerify {
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr n, out IntPtr got);
  const UInt32 PROCESS_VM_READ=0x10, PROCESS_QUERY_INFORMATION=0x400;
  static byte[] Read(UInt32 pid, Int64 addr, int n) {
    IntPtr h=OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION,false,pid);
    if(h==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
    try { byte[] b=new byte[n]; IntPtr got; if(!ReadProcessMemory(h,new IntPtr(addr),b,new IntPtr(n),out got)||got.ToInt64()!=n) throw new Exception(String.Format("Read failed at 0x{0:X8}",addr)); return b; }
    finally { CloseHandle(h); }
  }
  public static UInt32 U32(UInt32 pid, Int64 a){ return BitConverter.ToUInt32(Read(pid,a,4),0); }
  public static UInt16 U16(UInt32 pid, Int64 a){ return BitConverter.ToUInt16(Read(pid,a,2),0); }
}
"@

$proc = Get-Process -Id $ProcessId -ErrorAction Stop
$exePath = $proc.MainModule.FileName
$hash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw 'HASH MISMATCH - aborted before memory reads.' }

$parent = $P1Object - $RowOffset
$calcEnd = $RowOffset + (8 * $Stride)

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR PARENT / EMBEDDED ROW VERIFY - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID        : {0}" -f $ProcessId)
Write-Host ("Image      : {0}" -f $exePath)
Write-Host ("SHA256     : {0}" -f $hash)
Write-Host ("P1 object  : 0x{0:X8}" -f $P1Object)
Write-Host ("Parent     : 0x{0:X8}" -f $parent)
Write-Host ("Row offset : 0x{0:X}" -f $RowOffset)
Write-Host ("Stride     : 0x{0:X}" -f $Stride)
Write-Host ("0xDC + 8*0x1DC = 0x{0:X}" -f $calcEnd)
Write-Host ''

$pv = [A8PParentVerify]::U32([uint32]$ProcessId, $parent)
$parentIp = [A8PParentVerify]::U32([uint32]$ProcessId, $parent + 0x38)
$parentPort = [A8PParentVerify]::U16([uint32]$ProcessId, $parent + 0x3C)
Write-Host ("Parent vtbl : 0x{0:X8} expected 0x{1:X8} {2}" -f $pv, $ParentVtable, $(if($pv -eq $ParentVtable){'MATCH'}else{'MISMATCH'}))
Write-Host ("Parent +38  : 0x{0:X8}" -f $parentIp)
Write-Host ("Parent +3C  : {0}" -f $parentPort)
Write-Host ''

$allRows = $true
for($i=0;$i -lt 8;$i++) {
    $obj = $parent + $RowOffset + ($i * $Stride)
    $vt = [A8PParentVerify]::U32([uint32]$ProcessId, $obj)
    $ty = [A8PParentVerify]::U32([uint32]$ProcessId, $obj + 4)
    $ok = ($vt -eq $RowVtable -and $ty -eq $ExpectedTypes[$i])
    if(-not $ok){$allRows=$false}
    Write-Host ("P{0}: obj=0x{1:X8} vtbl=0x{2:X8} type={3} expected={4} {5}" -f ($i+1),$obj,$vt,$ty,$ExpectedTypes[$i],$(if($ok){'MATCH'}else{'MISMATCH'}))
}

$tail0 = [A8PParentVerify]::U32([uint32]$ProcessId, $parent + 0xFBC)
$tail1 = [A8PParentVerify]::U32([uint32]$ProcessId, $parent + 0xFC0)
Write-Host ''
Write-Host ("Parent+0xFBC = 0x{0:X8}" -f $tail0)
Write-Host ("Parent+0xFC0 = 0x{0:X8}" -f $tail1)
Write-Host ''

if($pv -eq $ParentVtable -and $allRows -and $calcEnd -eq 0xFBC) {
    Write-Host 'EMBEDDED ARRAY MATCH: PASS' -ForegroundColor Green
    Write-Host 'The live 8-row block is exactly consistent with parent+0xDC and 8 records of stride 0x1DC ending at parent+0xFBC.' -ForegroundColor Green
} else {
    Write-Host 'EMBEDDED ARRAY MATCH: NOT PROVEN' -ForegroundColor Yellow
}
Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
