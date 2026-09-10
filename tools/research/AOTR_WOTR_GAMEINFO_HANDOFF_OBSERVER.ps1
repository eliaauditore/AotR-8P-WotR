param(
    [int]$ProcessId = 0,
    [int]$TimeoutSeconds = 90,
    [int]$PollMs = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# Observes the native WotR transition from the pre-start network GameInfo global
# (RVA 0x009E892C) to active TheGameInfo (RVA 0x009E7D6C).
# No WriteProcessMemory is imported or used.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ImageBaseStatic = [int64]0x00400000
$NetworkGlobalRva = [int64]0x009E892C
$AlternateGlobalRva = [int64]0x009E8930
$ActiveGlobalRva = [int64]0x009E7D6C
$ParentVtableRva = [int64]0x00854B78
$RowVtableRva = [int64]0x00854B5C
$RowOffset = 0xDC
$Stride = 0x1DC

if (-not ('A8PGameInfoHandoffRead' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PGameInfoHandoffRead
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

    static bool ReadExact(IntPtr h, Int64 addr, byte[] b)
    {
        IntPtr got;
        bool ok = ReadProcessMemory(h, new IntPtr(addr), b, new IntPtr(b.Length), out got);
        return ok && got.ToInt64() == b.Length;
    }

    public static UInt32 ReadU32(UInt32 pid, Int64 addr)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            byte[] b = new byte[4];
            if (!ReadExact(h, addr, b)) throw new Exception("ReadU32 failed at 0x" + addr.ToString("X8"));
            return BitConverter.ToUInt32(b, 0);
        } finally { CloseHandle(h); }
    }

    public static UInt16 ReadU16(UInt32 pid, Int64 addr)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            byte[] b = new byte[2];
            if (!ReadExact(h, addr, b)) throw new Exception("ReadU16 failed at 0x" + addr.ToString("X8"));
            return BitConverter.ToUInt16(b, 0);
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
$networkGlobal = $base + $NetworkGlobalRva
$alternateGlobal = $base + $AlternateGlobalRva
$activeGlobal = $base + $ActiveGlobalRva
$expectedParentVtable = [uint32]($base + $ParentVtableRva)
$expectedRowVtable = [uint32]($base + $RowVtableRva)

function Read-U32([int64]$addr) {
    [A8PGameInfoHandoffRead]::ReadU32([uint32]$ProcessId, $addr)
}

function Read-U16([int64]$addr) {
    [A8PGameInfoHandoffRead]::ReadU16([uint32]$ProcessId, $addr)
}

function Get-GameInfoSnapshot([uint32]$ptr) {
    if ($ptr -eq 0) {
        return [pscustomobject]@{ Ptr=[uint32]0; Vtable=[uint32]0; ParentMatch=$false; Endpoint=[uint32]0; Port=[uint16]0; Types=@() }
    }

    $vt = Read-U32 ([int64]$ptr)
    $ep = Read-U32 ([int64]$ptr + 0x38)
    $port = Read-U16 ([int64]$ptr + 0x3C)
    $types = @()

    if ($vt -eq $expectedParentVtable) {
        for ($i=0; $i -lt 8; $i++) {
            $obj = [int64]$ptr + $RowOffset + ([int64]$i * $Stride)
            $rowVt = Read-U32 $obj
            $typ = Read-U32 ($obj + 4)
            $types += [pscustomobject]@{ Index=$i; Vtable=$rowVt; Type=$typ; VtableMatch=($rowVt -eq $expectedRowVtable) }
        }
    }

    return [pscustomobject]@{
        Ptr=$ptr
        Vtable=$vt
        ParentMatch=($vt -eq $expectedParentVtable)
        Endpoint=$ep
        Port=$port
        Types=$types
    }
}

function Format-Types($snap) {
    if (-not $snap.ParentMatch -or $snap.Types.Count -ne 8) { return '<not decoded>' }
    return (($snap.Types | ForEach-Object { $_.Type }) -join ',')
}

function Format-IPv4BE([uint32]$raw) {
    $b0 = ($raw -shr 24) -band 0xFF
    $b1 = ($raw -shr 16) -band 0xFF
    $b2 = ($raw -shr 8) -band 0xFF
    $b3 = $raw -band 0xFF
    return "$b0.$b1.$b2.$b3"
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR GAMEINFO HANDOFF OBSERVER - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID              : {0}" -f $ProcessId)
Write-Host ("Image            : {0}" -f $exe)
Write-Host ("SHA256           : {0}" -f $hash)
Write-Host ("Runtime base     : 0x{0:X8}" -f $base)
Write-Host ("Network global   : 0x{0:X8}" -f $networkGlobal)
Write-Host ("Alternate global : 0x{0:X8}" -f $alternateGlobal)
Write-Host ("TheGameInfo      : 0x{0:X8}" -f $activeGlobal)
Write-Host ''

$network0 = Read-U32 $networkGlobal
$alternate0 = Read-U32 $alternateGlobal
$active0 = Read-U32 $activeGlobal
$networkSnap0 = Get-GameInfoSnapshot $network0

Write-Host ("PRE network      = 0x{0:X8}" -f $network0)
Write-Host ("PRE alternate    = 0x{0:X8}" -f $alternate0)
Write-Host ("PRE TheGameInfo  = 0x{0:X8}" -f $active0)
Write-Host ("PRE network vtbl = 0x{0:X8} parentMatch={1}" -f $networkSnap0.Vtable,$networkSnap0.ParentMatch)
Write-Host ("PRE endpoint     = {0}:{1}" -f (Format-IPv4BE $networkSnap0.Endpoint),$networkSnap0.Port)
Write-Host ("PRE types        = {0}" -f (Format-Types $networkSnap0))
Write-Host ''

if ($network0 -eq 0) { throw 'Network GameInfo global is NULL. Enter the native WotR host lobby first.' }
if (-not $networkSnap0.ParentMatch) { throw 'Network GameInfo does not have expected network-GameInfo vtable.' }
if ($active0 -ne 0) { throw 'TheGameInfo is already non-NULL. This observer must be armed before Start Game.' }

Write-Host 'ARMED.' -ForegroundColor Green
Write-Host 'Now switch to AotR and click Start Game ONCE. Do not change any lobby fields.' -ForegroundColor Yellow
Write-Host ("Watching for up to {0}s at ~{1}ms intervals..." -f $TimeoutSeconds,$PollMs)
Write-Host ''

$sw = [Diagnostics.Stopwatch]::StartNew()
$lastNetwork = $network0
$lastAlternate = $alternate0
$lastActive = $active0
$seenActive = $false

while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
    try {
        $network = Read-U32 $networkGlobal
        $alternate = Read-U32 $alternateGlobal
        $active = Read-U32 $activeGlobal
    } catch {
        Write-Host ("READ STOP at {0} ms: {1}" -f $sw.ElapsedMilliseconds,$_.Exception.Message) -ForegroundColor Yellow
        break
    }

    if ($network -ne $lastNetwork -or $alternate -ne $lastAlternate -or $active -ne $lastActive) {
        Write-Host ("[{0,6} ms] network=0x{1:X8} alternate=0x{2:X8} active=0x{3:X8}" -f `
            $sw.ElapsedMilliseconds,$network,$alternate,$active)
        $lastNetwork = $network
        $lastAlternate = $alternate
        $lastActive = $active
    }

    if ($active -ne 0) {
        $seenActive = $true
        $activeSnap = Get-GameInfoSnapshot $active
        Write-Host ''
        Write-Host 'ACTIVE GAMEINFO OBSERVED' -ForegroundColor Green
        Write-Host ("Active ptr        : 0x{0:X8}" -f $active)
        Write-Host ("Active vtable     : 0x{0:X8} parentMatch={1}" -f $activeSnap.Vtable,$activeSnap.ParentMatch)
        Write-Host ("Active endpoint   : {0}:{1}" -f (Format-IPv4BE $activeSnap.Endpoint),$activeSnap.Port)
        Write-Host ("Active types      : {0}" -f (Format-Types $activeSnap))
        Write-Host ("Active == PRE net : {0}" -f ($active -eq $network0))
        Write-Host ("Active == NOW net : {0}" -f ($active -eq $network))
        Write-Host ("PRE net still ptr : 0x{0:X8}" -f $network)
        Write-Host ''

        if ($active -eq $network0) {
            Write-Host 'HANDOFF SAME INSTANCE: PASS' -ForegroundColor Green
            Write-Host 'The pre-start network GameInfo instance became TheGameInfo directly.' -ForegroundColor Green
        } elseif ($activeSnap.ParentMatch) {
            Write-Host 'HANDOFF DIFFERENT INSTANCE: OBSERVED' -ForegroundColor Yellow
            Write-Host 'TheGameInfo is another instance of the same network-GameInfo-derived type; compare vectors/copy path.' -ForegroundColor Yellow
        } else {
            Write-Host 'HANDOFF DIFFERENT TYPE/INSTANCE: OBSERVED' -ForegroundColor Yellow
        }
        break
    }

    Start-Sleep -Milliseconds $PollMs
}

if (-not $seenActive) {
    Write-Host ''
    Write-Host 'TIMEOUT: TheGameInfo never became non-NULL during the observation window.' -ForegroundColor Yellow
    Write-Host ("Final network=0x{0:X8} alternate=0x{1:X8} active=0x{2:X8}" -f $lastNetwork,$lastAlternate,$lastActive)
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
