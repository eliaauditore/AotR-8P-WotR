param(
    [int]$ProcessId = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY post-call observer for native WotR join research.
# Dumps the session contract and all 8 rows of session-listed/current Network GameInfo objects.
# No WriteProcessMemory / VirtualAllocEx / CreateRemoteThread.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$SessionGlobalRva  = [int64]0x009E4394
$NetworkGlobalRva  = [int64]0x009E892C
$ActiveGlobalRva   = [int64]0x009E7D6C
$SessionVtableRva  = [int64]0x00854CE0
$GameInfoVtableRva = [int64]0x00854B78

if (-not ('A8PJoinPostRead' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class A8PJoinPostRead {
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
$expectedSessionVt  = [uint32]($base + $SessionVtableRva)
$expectedGameInfoVt = [uint32]($base + $GameInfoVtableRva)

function Read-Bytes([int64]$a,[int]$n) { [A8PJoinPostRead]::Read([uint32]$ProcessId,$a,$n) }
function Read-U32([int64]$a) { [BitConverter]::ToUInt32((Read-Bytes $a 4),0) }
function Read-U16([int64]$a) { [BitConverter]::ToUInt16((Read-Bytes $a 2),0) }
function Format-IPv4BE([uint32]$raw) { '{0}.{1}.{2}.{3}' -f (($raw-shr 24)-band 0xff),(($raw-shr 16)-band 0xff),(($raw-shr 8)-band 0xff),($raw-band 0xff) }
function Format-Endpoint([uint32]$ip,[uint16]$port) { if($ip -eq 0 -and $port -eq 0){'{0,0}'} else { '{0}:{1}' -f (Format-IPv4BE $ip),$port } }

$session = Read-U32 ($base + $SessionGlobalRva)
$network = Read-U32 ($base + $NetworkGlobalRva)
$active  = Read-U32 ($base + $ActiveGlobalRva)

Write-Host '============================================================'
Write-Host ' AOTR WOTR NATIVE JOIN POST-CALL OBSERVER - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID              : {0}" -f $ProcessId)
Write-Host ("Image            : {0}" -f $exe)
Write-Host ("SHA256           : {0}" -f $hash)
Write-Host ("Session          : 0x{0:X8}" -f $session)
Write-Host ("DE892C NetworkGI : 0x{0:X8}" -f $network)
Write-Host ("TheGameInfo      : 0x{0:X8}" -f $active)

if ($session -eq 0) { Write-Host 'SESSION = NULL'; exit 0 }

$svt = Read-U32 ([int64]$session)
$state = Read-U32 ([int64]$session + 0x28)
$list = Read-U32 ([int64]$session + 0x10)
$current = Read-U32 ([int64]$session + 0x44)
$localIp = Read-U32 ([int64]$session + 0x48)
$localPort = Read-U16 ([int64]$session + 0x4C)

Write-Host ("Session vtable   : 0x{0:X8} match={1}" -f $svt,($svt -eq $expectedSessionVt))
Write-Host ("State +0x28      : {0}" -f $state)
Write-Host ("List +0x10       : 0x{0:X8}" -f $list)
Write-Host ("Current +0x44    : 0x{0:X8}" -f $current)
Write-Host ("Local endpoint   : {0}" -f (Format-Endpoint $localIp $localPort))
Write-Host ''

$seen=@{}
$p=[uint32]$list
$idx=0
while($p -ne 0 -and $idx -lt 32){
    $k='{0:X8}' -f $p
    if($seen.ContainsKey($k)){ Write-Host 'CYCLE DETECTED'; break }
    $seen[$k]=$true
    $vt=Read-U32 ([int64]$p)
    $next=Read-U32 ([int64]$p+0xFBC)
    $marks=@(); if($p -eq $current){$marks+='CURRENT'}; if($p -eq $network){$marks+='NETWORK'}
    $mark=if($marks.Count){' '+($marks -join ',')}else{''}
    Write-Host ("GI[{0}] 0x{1:X8}{2} vtOK={3} next=0x{4:X8}" -f $idx,$p,$mark,($vt -eq $expectedGameInfoVt),$next)
    if($vt -eq $expectedGameInfoVt){
        for($i=0;$i -lt 8;$i++){
            $row=Read-U32 ([int64]$p+0x18+($i*4))
            if($row -eq 0){ Write-Host ("  P{0}: <NULL>" -f ($i+1)); continue }
            $type=Read-U32 ([int64]$row+4)
            $ip=Read-U32 ([int64]$row+0x38)
            $port=Read-U16 ([int64]$row+0x3C)
            $localMark=if($type -eq 6 -and $ip -eq $localIp -and $port -eq $localPort){' LOCAL'}else{''}
            Write-Host ("  P{0}: row=0x{1:X8} type={2} endpoint={3}{4}" -f ($i+1),$row,$type,(Format-Endpoint $ip $port),$localMark)
        }
    }
    $p=[uint32]$next
    $idx++
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
