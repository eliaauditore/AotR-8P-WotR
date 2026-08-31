param(
    [int]$ProcessId = 0,
    [string]$Label = 'NODE'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY RUNTIME SNAPSHOT.
# Captures the host/client values relevant to PATH_C ID5 reasons 8, 6, 4 and 2.
# Imports only OpenProcess / ReadProcessMemory / CloseHandle.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$SessionGlobalRva  = [int64]0x009E4394 # VA 0x00DE4394
$ManagerGlobalRva  = [int64]0x009E4364 # VA 0x00DE4364
$SessionVtableRva  = [int64]0x00854CE0 # VA 0x00C54CE0
$GameInfoVtableRva = [int64]0x00854B78 # VA 0x00C54B78

if (-not ('A8PJoinFailureRead' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class A8PJoinFailureRead {
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
$expectedSessionVt=[uint32]($base+$SessionVtableRva)
$expectedGiVt=[uint32]($base+$GameInfoVtableRva)

function RBytes([int64]$a,[int]$n) { [A8PJoinFailureRead]::Read([uint32]$ProcessId,$a,$n) }
function RU32([int64]$a) { [BitConverter]::ToUInt32((RBytes $a 4),0) }
function RU16([int64]$a) { [BitConverter]::ToUInt16((RBytes $a 2),0) }
function RU8([int64]$a) { (RBytes $a 1)[0] }
function HexBytes([byte[]]$b) { (($b | ForEach-Object { $_.ToString('X2') }) -join '') }
function IPv4([uint32]$x) { '{0}.{1}.{2}.{3}' -f (($x-shr 24)-band 255),(($x-shr 16)-band 255),(($x-shr 8)-band 255),($x-band 255) }
function EP([uint32]$ip,[uint16]$port) { if($ip-eq 0 -and $port-eq 0){'{0,0}'}else{('{0}:{1}' -f (IPv4 $ip),$port)} }

$session=RU32 ($base+$SessionGlobalRva)
$manager=RU32 ($base+$ManagerGlobalRva)

Write-Host '============================================================'
Write-Host ' AOTR WOTR JOIN FAILURE RUNTIME SNAPSHOT - READ ONLY'
Write-Host '============================================================'
Write-Host ("Label                : {0}" -f $Label)
Write-Host ("PID                  : {0}" -f $ProcessId)
Write-Host ("Image                : {0}" -f $exe)
Write-Host ("SHA256               : {0}" -f $hash)
Write-Host ("Runtime base         : 0x{0:X8}" -f $base)
Write-Host ("Session              : 0x{0:X8}" -f $session)
Write-Host ("DE4364 manager       : 0x{0:X8}" -f $manager)
Write-Host ''

if($session-eq 0){ throw 'Session singleton is NULL.' }
$svt=RU32 $session
$state28=RU32 ([int64]$session+0x28)
$flag41=RU8 ([int64]$session+0x41)
$current=RU32 ([int64]$session+0x44)
$lip=RU32 ([int64]$session+0x48)
$lport=RU16 ([int64]$session+0x4C)

Write-Host '================ SESSION / REASON-8 GATES ================'
Write-Host ("session vtable       : 0x{0:X8} expected=0x{1:X8} match={2}" -f $svt,$expectedSessionVt,($svt-eq $expectedSessionVt))
Write-Host ("state +0x28          : {0}" -f $state28)
Write-Host ("flag  +0x41          : {0}  (PATH_C reason8 if nonzero)" -f $flag41)
Write-Host ("current GI +0x44     : 0x{0:X8}  (PATH_C reason8 if NULL)" -f $current)
Write-Host ("local endpoint       : {0}" -f (EP $lip $lport))

if($current-ne 0){
    $gvt=RU32 $current
    $gi11=RU8 ([int64]$current+0x11)
    $r0=RU32 ([int64]$current+0x18)
    $r0ip=RU32 ([int64]$current+0x114)
    $r0port=RU16 ([int64]$current+0x118)
    $epmatch=($r0ip-eq $lip -and $r0port-eq $lport)
    Write-Host ("current GI vtable   : 0x{0:X8} expected=0x{1:X8} match={2}" -f $gvt,$expectedGiVt,($gvt-eq $expectedGiVt))
    Write-Host ("GI flag +0x11       : {0}  (PATH_C reason6 if nonzero after reason8 gates)" -f $gi11)
    Write-Host ("row0 pointer        : 0x{0:X8}" -f $r0)
    Write-Host ("GI+0x114 endpoint   : {0}" -f (EP $r0ip $r0port))
    Write-Host ("row0/local EP match : {0}  (PATH_C reason8 if False)" -f $epmatch)
    Write-Host ''

    Write-Host '================ CURRENT GI ROW TYPES / REASON-2 CHECK ================'
    $type0=0
    for($i=0;$i-lt 8;$i++){
        $row=RU32 ([int64]$current+0x18+(4*$i))
        if($row-eq 0){ Write-Host ("P{0}: row=NULL" -f ($i+1)); continue }
        $t=RU32 ([int64]$row+4)
        $ip=RU32 ([int64]$row+0x38)
        $po=RU16 ([int64]$row+0x3C)
        if($t-eq 0){$type0++}
        Write-Host ("P{0}: row=0x{1:X8} type={2} endpoint={3}" -f ($i+1),$row,$t,(EP $ip $po))
    }
    Write-Host ("Type0 rows          : {0}" -f $type0)
    Write-Host 'Note: PATH_C reason2 occurs only if the proven 0x4512D7 first-free scan reaches index 8.'
    Write-Host ''
}

Write-Host '================ DE4364 COMPATIBILITY METADATA / REASON-4 ================'
if($manager-eq 0){
    Write-Host 'DE4364 manager is NULL.'
}else{
    $b04=RU32 ([int64]$manager+0xB04)
    $b08=RBytes ([int64]$manager+0xB08) 16
    $b38=RU32 ([int64]$manager+0xB38)
    Write-Host ("+0xB04              : 0x{0:X8}" -f $b04)
    Write-Host ("+0xB08[16]          : {0}" -f (HexBytes $b08))
    Write-Host ("+0xB38              : 0x{0:X8}" -f $b38)
    Write-Host ("META_FINGERPRINT   : B04={0:X8};B08={1};B38={2:X8}" -f $b04,(HexBytes $b08),$b38)
    Write-Host 'Reason4 static contract: incoming ID3 fields sourced from the client equivalents are checked against these host-side values.'
}

Write-Host ''
Write-Host '================ STATIC REASON MAP (CORRECTED) ================'
Write-Host 'reason 8 : early session/current-GI/local-endpoint gate failure'
Write-Host 'reason 6 : current GameInfo +0x11 is nonzero'
Write-Host 'reason 4 : compatibility/identity metadata check fails'
Write-Host 'reason 5 : existing-slot 23-byte identity conflict (alternate push/pop write; missed by V1 scanner)'
Write-Host 'reason 3 : duplicate existing Type6 name matches incoming message+4'
Write-Host 'reason 2 : first-free scan exhausts all 8 rows'
Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
