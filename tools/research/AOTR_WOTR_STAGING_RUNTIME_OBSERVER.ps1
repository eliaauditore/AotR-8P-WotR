param(
    [int]$ProcessId = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# Observes the separate pre-start/staging GameInfo-like object installed in
# DE8930/DE892C. No process or file writes.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$NetworkGiRva    = [int64]0x009E892C
$NetworkGiAltRva = [int64]0x009E8930
$SessionRva      = [int64]0x009E4394
$ActiveRva       = [int64]0x009E7D6C
$StagingVtableRva = [int64](0x00BFD668 - 0x00400000)

if (-not ('A8PStagingRead' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class A8PStagingRead {
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(UInt32 a,bool i,UInt32 p);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h,IntPtr a,byte[] b,IntPtr n,out IntPtr g);
    const UInt32 PROCESS_VM_READ=0x10, PROCESS_QUERY_INFORMATION=0x400;
    public static byte[] Read(UInt32 pid, Int64 addr, Int32 count) {
        IntPtr h=OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION,false,pid);
        if(h==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try { byte[] b=new byte[count]; IntPtr g; if(!ReadProcessMemory(h,new IntPtr(addr),b,new IntPtr(count),out g)||g.ToInt64()!=count) throw new Exception("ReadProcessMemory failed at 0x"+addr.ToString("X8")); return b; }
        finally { CloseHandle(h); }
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
$expectedStagingVt = [uint32]($base + $StagingVtableRva)

function Read-Bytes([int64]$a,[int]$n) { [A8PStagingRead]::Read([uint32]$ProcessId,$a,$n) }
function Read-U32([int64]$a) { [BitConverter]::ToUInt32((Read-Bytes $a 4),0) }
function Read-U16([int64]$a) { [BitConverter]::ToUInt16((Read-Bytes $a 2),0) }
function Format-IPv4BE([uint32]$raw) { '{0}.{1}.{2}.{3}' -f (($raw-shr 24)-band 0xff),(($raw-shr 16)-band 0xff),(($raw-shr 8)-band 0xff),($raw-band 0xff) }
function Format-Endpoint([uint32]$ip,[uint16]$port) { if($ip -eq 0 -and $port -eq 0){'{0,0}'} else { '{0}:{1}' -f (Format-IPv4BE $ip),$port } }

$session = Read-U32 ($base + $SessionRva)
$net     = Read-U32 ($base + $NetworkGiRva)
$alt     = Read-U32 ($base + $NetworkGiAltRva)
$active  = Read-U32 ($base + $ActiveRva)
$current = if($session -ne 0){ Read-U32 ([int64]$session + 0x44) } else { 0 }

Write-Host '============================================================'
Write-Host ' AOTR WOTR STAGING RUNTIME OBSERVER - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID              : {0}" -f $ProcessId)
Write-Host ("Image            : {0}" -f $exe)
Write-Host ("SHA256           : {0}" -f $hash)
Write-Host ("Session          : 0x{0:X8}" -f $session)
Write-Host ("Session +0x44    : 0x{0:X8}" -f $current)
Write-Host ("DE8930 staging   : 0x{0:X8}" -f $alt)
Write-Host ("DE892C NetworkGI : 0x{0:X8}" -f $net)
Write-Host ("TheGameInfo      : 0x{0:X8}" -f $active)
Write-Host ("DE8930==DE892C   : {0}" -f ($alt -eq $net))
Write-Host ''

if($alt -eq 0){
    Write-Host 'STAGING = NULL'
    Write-Host ''
    Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
    exit 0
}

$vt = Read-U32 ([int64]$alt)
Write-Host ("Staging vtable   : 0x{0:X8} match_BFD668={1}" -f $vt,($vt -eq $expectedStagingVt))
Write-Host ("Flag +0x10       : {0}" -f (Read-Bytes ([int64]$alt + 0x10) 1)[0])
Write-Host ("Field +0x14      : 0x{0:X8}" -f (Read-U32 ([int64]$alt + 0x14)))
Write-Host ''

for($i=0;$i -lt 8;$i++){
    $rowPtr = Read-U32 ([int64]$alt + 0x18 + ($i*4))
    $inline = [uint32]([int64]$alt + 0xDC + ($i*0x1B8))
    if($rowPtr -eq 0){
        Write-Host ("P{0}: ptr=<NULL> inline=0x{1:X8}" -f ($i+1),$inline)
        continue
    }
    $type = Read-U32 ([int64]$rowPtr + 4)
    $ip   = Read-U32 ([int64]$rowPtr + 0x38)
    $port = Read-U16 ([int64]$rowPtr + 0x3C)
    Write-Host ("P{0}: ptr=0x{1:X8} inline=0x{2:X8} ptr_is_inline={3} type={4} endpoint={5}" -f ($i+1),$rowPtr,$inline,($rowPtr -eq $inline),$type,(Format-Endpoint $ip $port))
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
