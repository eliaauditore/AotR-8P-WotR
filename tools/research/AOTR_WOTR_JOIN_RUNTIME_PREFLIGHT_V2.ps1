param(
    [int]$ProcessId = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY RUNTIME PREFLIGHT V2.
# PowerShell 7-safe version of the native C54CE0 +0x40 join-call preflight.
# No WriteProcessMemory / VirtualAllocEx / CreateRemoteThread is imported or used.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'

$SessionGlobalRva  = [int64]0x009E4394   # VA 0x00DE4394
$NetworkGlobalRva  = [int64]0x009E892C   # VA 0x00DE892C
$ActiveGlobalRva   = [int64]0x009E7D6C   # VA 0x00DE7D6C
$SessionVtableRva  = [int64]0x00854CE0   # VA 0x00C54CE0
$GameInfoVtableRva = [int64]0x00854B78   # VA 0x00C54B78
$JoinMethodRva     = [int64]0x0044CB34   # VA 0x0084CB34

if (-not ('A8PJoinRuntimeReadV2' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PJoinRuntimeReadV2
{
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CloseHandle(IntPtr hObject);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress,
        byte[] lpBuffer, IntPtr nSize, out IntPtr lpNumberOfBytesRead);

    const UInt32 PROCESS_VM_READ = 0x0010;
    const UInt32 PROCESS_QUERY_INFORMATION = 0x0400;

    public static byte[] Read(UInt32 pid, Int64 addr, Int32 count)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            byte[] b = new byte[count];
            IntPtr got;
            if (!ReadProcessMemory(h, new IntPtr(addr), b, new IntPtr(count), out got) || got.ToInt64() != count)
                throw new Exception("ReadProcessMemory failed at 0x" + addr.ToString("X8") + " len=" + count);
            return b;
        }
        finally { CloseHandle(h); }
    }
}
"@
}

if ($ProcessId -le 0) {
    $games = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -ieq 'game.dat' -and $_.ExecutablePath -match '\\game\.dat$'
    })
    if ($games.Count -ne 1) {
        throw "Expected exactly one game.dat. Found $($games.Count). Pass -ProcessId."
    }
    $ProcessId = [int]$games[0].ProcessId
}

$proc = Get-Process -Id $ProcessId -ErrorAction Stop
$exe = $proc.MainModule.FileName
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) {
    throw "HASH MISMATCH - expected $ExpectedHash, got $hash"
}

$base = $proc.MainModule.BaseAddress.ToInt64()
$expectedSessionVt  = [uint32]($base + $SessionVtableRva)
$expectedGameInfoVt = [uint32]($base + $GameInfoVtableRva)
$joinMethod         = [uint32]($base + $JoinMethodRva)

function Read-Bytes([int64]$addr,[int]$count) {
    [A8PJoinRuntimeReadV2]::Read([uint32]$ProcessId,$addr,$count)
}
function Read-U32([int64]$addr) { [BitConverter]::ToUInt32((Read-Bytes $addr 4),0) }
function Read-U16([int64]$addr) { [BitConverter]::ToUInt16((Read-Bytes $addr 2),0) }
function Read-U8([int64]$addr)  { (Read-Bytes $addr 1)[0] }
function Format-IPv4BE([uint32]$raw) {
    return ('{0}.{1}.{2}.{3}' -f (($raw -shr 24)-band 0xFF),(($raw -shr 16)-band 0xFF),(($raw -shr 8)-band 0xFF),($raw-band 0xFF))
}
function Format-Endpoint([uint32]$ip,[uint16]$port) {
    if ($ip -eq 0 -and $port -eq 0) { return '{0,0}' }
    return ('{0}:{1}' -f (Format-IPv4BE $ip),$port)
}
function Safe-U32([int64]$addr,[ref]$ok) {
    try {
        $ok.Value = $true
        return (Read-U32 $addr)
    }
    catch {
        $ok.Value = $false
        return [uint32]0
    }
}

$sessionGlobalAddr = $base + $SessionGlobalRva
$networkGlobalAddr = $base + $NetworkGlobalRva
$activeGlobalAddr  = $base + $ActiveGlobalRva

$session = Read-U32 $sessionGlobalAddr
$network = Read-U32 $networkGlobalAddr
$active  = Read-U32 $activeGlobalAddr

Write-Host '============================================================'
Write-Host ' AOTR WOTR NATIVE JOIN RUNTIME PREFLIGHT V2 - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID                  : {0}" -f $ProcessId)
Write-Host ("Image                : {0}" -f $exe)
Write-Host ("SHA256               : {0}" -f $hash)
Write-Host ("Runtime base         : 0x{0:X8}" -f $base)
Write-Host ("Join method          : 0x{0:X8} (C54CE0 vtable +0x40)" -f $joinMethod)
Write-Host ("Session global       : 0x{0:X8} -> 0x{1:X8}" -f $sessionGlobalAddr,$session)
Write-Host ("Network GameInfo     : 0x{0:X8}" -f $network)
Write-Host ("TheGameInfo          : 0x{0:X8}" -f $active)
Write-Host ''

if ($session -eq 0) {
    Write-Host 'BRIDGE_CALL_READY = NO' -ForegroundColor Yellow
    Write-Host 'Reason: session singleton DE4394 is NULL.'
    Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
    exit 0
}

$sessionVt = Read-U32 ([int64]$session)
$state28   = Read-U32 ([int64]$session + 0x28)
$listHead  = Read-U32 ([int64]$session + 0x10)
$current44 = Read-U32 ([int64]$session + 0x44)
$localIp   = Read-U32 ([int64]$session + 0x48)
$localPort = Read-U16 ([int64]$session + 0x4C)
$fallbackIp= Read-U32 ([int64]$session + 0x54)

Write-Host '================ SESSION CONTRACT ================'
Write-Host ("vtable               : 0x{0:X8} expected=0x{1:X8} match={2}" -f $sessionVt,$expectedSessionVt,($sessionVt -eq $expectedSessionVt))
Write-Host ("state +0x28          : {0} (join permits 0 or 2)" -f $state28)
Write-Host ("GameInfo list +0x10 : 0x{0:X8}" -f $listHead)
Write-Host ("current +0x44       : 0x{0:X8}" -f $current44)
Write-Host ("local endpoint      : {0}" -f (Format-Endpoint $localIp $localPort))
Write-Host ("fallback IP +0x54   : 0x{0:X8} ({1})" -f $fallbackIp,(Format-IPv4BE $fallbackIp))
Write-Host ''

$sessionOk = ($sessionVt -eq $expectedSessionVt)
$stateOk = ($state28 -eq 0 -or $state28 -eq 2)

Write-Host '================ SESSION GAMEINFO LIST ================'
$candidates = @()
$seen = @{}
$p = [uint32]$listHead
$index = 0

while ($p -ne 0 -and $index -lt 32) {
    $key = ('{0:X8}' -f $p)
    if ($seen.ContainsKey($key)) {
        Write-Host ("[{0}] 0x{1:X8} CYCLE DETECTED - stop" -f $index,$p) -ForegroundColor Yellow
        break
    }
    $seen[$key] = $true

    $ok = [ref]$false
    $vt = Safe-U32 ([int64]$p) $ok
    if (-not $ok.Value) {
        Write-Host ("[{0}] 0x{1:X8} unreadable - stop" -f $index,$p) -ForegroundColor Yellow
        break
    }

    $next       = Read-U32 ([int64]$p + 0xFBC)
    $activeFlag = Read-U8  ([int64]$p + 0xFC8)
    $row0       = Read-U32 ([int64]$p + 0x18)

    $row0Readable = $false
    $row0Type = [uint32]::MaxValue
    $row0Ip = [uint32]0
    $row0Port = [uint16]0

    if ($row0 -ne 0) {
        try {
            $row0Type = Read-U32 ([int64]$row0 + 4)
            $row0Ip = Read-U32 ([int64]$row0 + 0x38)
            $row0Port = Read-U16 ([int64]$row0 + 0x3C)
            $row0Readable = $true
        }
        catch {
            $row0Readable = $false
        }
    }

    $vtOk = ($vt -eq $expectedGameInfoVt)
    $rowOk = ($row0 -ne 0 -and $row0Readable)
    $endpointNonZero = ($row0Ip -ne 0 -or $row0Port -ne 0)
    $isRemoteEndpoint = $endpointNonZero -and -not ($row0Ip -eq $localIp -and $row0Port -eq $localPort)
    $arg1Safe = $vtOk -and $rowOk
    $remoteJoinCandidate = $arg1Safe -and $isRemoteEndpoint

    $marks = @()
    if ($p -eq $current44) { $marks += 'CURRENT' }
    if ($p -eq $network)   { $marks += 'NETWORK' }
    $mark = if ($marks.Count -gt 0) { ' ' + ($marks -join ',') } else { '' }

    Write-Host ("[{0}] GI=0x{1:X8}{2} vtOK={3} next=0x{4:X8} active={5} row0=0x{6:X8} type={7} endpoint={8} arg1Safe={9} remoteCandidate={10}" -f `
        $index,$p,$mark,$vtOk,$next,$activeFlag,$row0,$row0Type,(Format-Endpoint $row0Ip $row0Port),$arg1Safe,$remoteJoinCandidate)

    $candidates += [pscustomobject]@{
        Index=$index
        Ptr=$p
        VtableOk=$vtOk
        Row0=$row0
        Row0Type=$row0Type
        Ip=$row0Ip
        Port=$row0Port
        Arg1Safe=$arg1Safe
        RemoteCandidate=$remoteJoinCandidate
        Current=($p -eq $current44)
        Network=($p -eq $network)
    }

    $p = [uint32]$next
    $index++
}

if ($index -ge 32 -and $p -ne 0) {
    Write-Host 'List truncated at 32 nodes.' -ForegroundColor Yellow
}
if ($candidates.Count -eq 0) {
    Write-Host '<no GameInfo objects in session+0x10 list>'
}
Write-Host ''

$arg1SafeCandidates = @($candidates | Where-Object { $_.Arg1Safe })
$remoteCandidates = @($candidates | Where-Object { $_.RemoteCandidate })

Write-Host '================ JOIN +0x40 SAFETY RESULT ================'
Write-Host ("Session vtable valid : {0}" -f $sessionOk)
Write-Host ("Session state valid  : {0}" -f $stateOk)
Write-Host ("arg1-safe GameInfos  : {0}" -f $arg1SafeCandidates.Count)
Write-Host ("remote candidates    : {0}" -f $remoteCandidates.Count)
Write-Host 'arg2 convention      : pointer to {0,0} is the native no-explicit-endpoint sentinel handled by 0x84C257.'

$ready = $sessionOk -and $stateOk -and ($remoteCandidates.Count -gt 0)
if ($ready) {
    Write-Host 'BRIDGE_CALL_READY = YES' -ForegroundColor Green
    foreach ($c in $remoteCandidates) {
        Write-Host ("  candidate[{0}] arg1=0x{1:X8} row0Endpoint={2}" -f $c.Index,$c.Ptr,(Format-Endpoint $c.Ip $c.Port))
    }
    Write-Host 'Next step: controlled call-PoC may invoke session vtable +0x40 using one listed arg1 candidate.'
}
else {
    Write-Host 'BRIDGE_CALL_READY = NO' -ForegroundColor Yellow
    if (-not $sessionOk) {
        Write-Host 'Reason: session vtable mismatch.'
    }
    if (-not $stateOk) {
        Write-Host ("Reason: session+0x28={0}; native +0x40 only enters ID3 build path for state 0 or 2." -f $state28)
    }
    if ($arg1SafeCandidates.Count -eq 0) {
        Write-Host 'Reason: no session-listed Network GameInfo has a readable row0.'
    }
    elseif ($remoteCandidates.Count -eq 0) {
        Write-Host 'Reason: session-listed GameInfo objects exist, but none currently has a non-local row0 endpoint.'
    }
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
