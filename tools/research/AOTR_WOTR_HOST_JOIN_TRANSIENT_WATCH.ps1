param(
    [int]$ProcessId = 0,
    [string]$ExpectedClientIp = '192.168.0.57',
    [int]$ExpectedClientPort = 8086,
    [int]$WatchSeconds = 20,
    [int]$PollMilliseconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY runtime watcher.
# Purpose: catch even short-lived host GameInfo slot changes while a client issues
# one controlled native join call. No process memory is modified.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$SessionGlobalRva = [int64]0x009E4394
$NetworkGlobalRva = [int64]0x009E892C
$ExpectedSessionVtableRva = [int64]0x00854CE0
$ExpectedGameInfoVtableRva = [int64]0x00854B78

if ($WatchSeconds -lt 1 -or $WatchSeconds -gt 120) { throw 'WatchSeconds must be 1..120.' }
if ($PollMilliseconds -lt 5 -or $PollMilliseconds -gt 1000) { throw 'PollMilliseconds must be 5..1000.' }

if (-not ('A8PHostJoinTransientRead' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class A8PHostJoinTransientRead {
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr got);
    const UInt32 PROCESS_VM_READ=0x10, PROCESS_QUERY_INFORMATION=0x400;
    public static IntPtr Open(UInt32 pid) {
        IntPtr h=OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION,false,pid);
        if(h==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        return h;
    }
    public static byte[] Read(IntPtr h, Int64 addr, Int32 count) {
        byte[] b=new byte[count]; IntPtr got;
        if(!ReadProcessMemory(h,new IntPtr(addr),b,new IntPtr(count),out got) || got.ToInt64()!=count)
            throw new Exception("ReadProcessMemory failed at 0x"+addr.ToString("X8"));
        return b;
    }
    public static void Close(IntPtr h) { if(h!=IntPtr.Zero) CloseHandle(h); }
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
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH - got $hash" }
$base = $proc.MainModule.BaseAddress.ToInt64()
$sessionGlobal = $base + $SessionGlobalRva
$networkGlobal = $base + $NetworkGlobalRva
$expectedSessionVt = [uint32]($base + $ExpectedSessionVtableRva)
$expectedGameInfoVt = [uint32]($base + $ExpectedGameInfoVtableRva)

$h = [IntPtr]::Zero
try {
    $h = [A8PHostJoinTransientRead]::Open([uint32]$ProcessId)
    function Read-U32([int64]$a) { [BitConverter]::ToUInt32([A8PHostJoinTransientRead]::Read($h,$a,4),0) }
    function Read-U16([int64]$a) { [BitConverter]::ToUInt16([A8PHostJoinTransientRead]::Read($h,$a,2),0) }
    function IpText([uint32]$raw) { '{0}.{1}.{2}.{3}' -f (($raw-shr 24)-band 255),(($raw-shr 16)-band 255),(($raw-shr 8)-band 255),($raw-band 255) }
    function EndpointText([uint32]$ip,[uint16]$port) { if($ip-eq 0 -and $port-eq 0){'{0,0}'}else{"$(IpText $ip):$port"} }

    $session = Read-U32 $sessionGlobal
    if ($session -eq 0) { throw 'Session singleton is NULL.' }
    $svt = Read-U32 ([int64]$session)
    if ($svt -ne $expectedSessionVt) { throw ('Session vtable mismatch 0x{0:X8}' -f $svt) }
    $gi = Read-U32 $networkGlobal
    if ($gi -eq 0) { throw 'DE892C Network GameInfo is NULL.' }
    $gvt = Read-U32 ([int64]$gi)
    if ($gvt -ne $expectedGameInfoVt) { throw ('GameInfo vtable mismatch 0x{0:X8}' -f $gvt) }

    Write-Host '============================================================'
    Write-Host ' AOTR WOTR HOST JOIN TRANSIENT WATCH - READ ONLY'
    Write-Host '============================================================'
    Write-Host ("PID              : {0}" -f $ProcessId)
    Write-Host ("Network GameInfo : 0x{0:X8}" -f $gi)
    Write-Host ("Expected client  : {0}:{1}" -f $ExpectedClientIp,$ExpectedClientPort)
    Write-Host ("Watch            : {0}s @ {1}ms" -f $WatchSeconds,$PollMilliseconds)
    Write-Host ''
    Write-Host 'WATCH ARMED. Run exactly ONE client -Execute call now.' -ForegroundColor Green

    $last = @{}
    $sawTarget = $false
    $sawAnyChange = $false
    $iterations = [int][Math]::Ceiling(($WatchSeconds*1000.0)/$PollMilliseconds)

    for ($n=0; $n -lt $iterations; $n++) {
        $now = [DateTime]::UtcNow.ToString('HH:mm:ss.fff')
        for ($i=0; $i -lt 8; $i++) {
            $row = Read-U32 ([int64]$gi + 0x18 + ($i*4))
            if ($row -eq 0) { $state = '<NULL>' }
            else {
                $type = Read-U32 ([int64]$row + 4)
                $ip = Read-U32 ([int64]$row + 0x38)
                $port = Read-U16 ([int64]$row + 0x3C)
                $ep = EndpointText $ip $port
                $state = "type=$type endpoint=$ep"
                if ($type -eq 6 -and (IpText $ip) -eq $ExpectedClientIp -and $port -eq $ExpectedClientPort) {
                    if (-not $sawTarget) { Write-Host ("[{0}] TARGET TYPE6 OBSERVED at P{1}: {2}" -f $now,($i+1),$state) -ForegroundColor Green }
                    $sawTarget = $true
                }
            }
            $k = [string]$i
            if (-not $last.ContainsKey($k)) { $last[$k] = $state }
            elseif ($last[$k] -ne $state) {
                Write-Host ("[{0}] P{1} CHANGE: {2} -> {3}" -f $now,($i+1),$last[$k],$state) -ForegroundColor Yellow
                $last[$k] = $state
                $sawAnyChange = $true
            }
        }
        Start-Sleep -Milliseconds $PollMilliseconds
    }

    Write-Host ''
    Write-Host '================ RESULT ================'
    Write-Host ("Any slot change     : {0}" -f $sawAnyChange)
    Write-Host ("Client Type6 seen   : {0}" -f $sawTarget)
    if ($sawTarget) { Write-Host 'HOST_PATH_C_COMMIT_OBSERVED = YES' -ForegroundColor Green }
    else { Write-Host 'HOST_PATH_C_COMMIT_OBSERVED = NO' -ForegroundColor Yellow }
    Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
}
finally {
    [A8PHostJoinTransientRead]::Close($h)
}
