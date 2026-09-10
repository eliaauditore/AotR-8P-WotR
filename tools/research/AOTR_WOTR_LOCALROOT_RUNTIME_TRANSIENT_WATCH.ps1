param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat',
    [string]$Label = 'HOST',
    [int]$WaitSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY runtime watcher.
# Purpose: capture the ACTUAL localRoot instance published at [DE3380]+0x24,
# then observe localRoot+0x04 (sink), sink vtable/+0x10, and localRoot+0x44
# during the transient initialization window. No process memory is modified.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$CurrentRootGlobalRva = [int64]0x009E3380   # VA 0x00DE3380; manager pointer, manager+0x24 = current localRoot

if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$diskHash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($diskHash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $diskHash" }

if (-not ('A8PLocalRootWatch' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class A8PLocalRootWatch {
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr n, out IntPtr got);
    const UInt32 PROCESS_VM_READ=0x0010, PROCESS_QUERY_INFORMATION=0x0400;
    public static IntPtr Open(UInt32 pid) {
        IntPtr h=OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION,false,pid);
        if(h==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        return h;
    }
    public static void Close(IntPtr h) { if(h!=IntPtr.Zero) CloseHandle(h); }
    public static bool U32(IntPtr h, Int64 addr, out UInt32 value) {
        value=0; byte[] b=new byte[4]; IntPtr got;
        if(!ReadProcessMemory(h,new IntPtr(addr),b,new IntPtr(4),out got) || got.ToInt64()!=4) return false;
        value=BitConverter.ToUInt32(b,0); return true;
    }
    public static bool U8(IntPtr h, Int64 addr, out Byte value) {
        value=0; byte[] b=new byte[1]; IntPtr got;
        if(!ReadProcessMemory(h,new IntPtr(addr),b,new IntPtr(1),out got) || got.ToInt64()!=1) return false;
        value=b[0]; return true;
    }
}
"@
}

function Get-MatchingGameProcesses {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -ieq 'game.dat' -and $_.ExecutablePath -and ([string]::Equals($_.ExecutablePath, $GameDat, [System.StringComparison]::OrdinalIgnoreCase))
    })
}

$existing = @(Get-MatchingGameProcesses)
if ($existing.Count -gt 0) {
    throw "A matching game.dat is already running (PID(s): $($existing.ProcessId -join ', ')). Close it first; this watcher must start before game initialization."
}

Write-Host '============================================================'
Write-Host ' AOTR WOTR LOCALROOT TRANSIENT WATCH - READ ONLY'
Write-Host '============================================================'
Write-Host ("Label                : {0}" -f $Label)
Write-Host ("Image                : {0}" -f $GameDat)
Write-Host ("SHA256               : {0}" -f $diskHash)
Write-Host ("Waiting for launch   : up to {0}s" -f $WaitSeconds)
Write-Host 'Start AotR normally now. The watcher only reads process memory.'
Write-Host ''

$deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
$wmi = $null
while ([DateTime]::UtcNow -lt $deadline) {
    $matches = @(Get-MatchingGameProcesses)
    if ($matches.Count -eq 1) { $wmi = $matches[0]; break }
    if ($matches.Count -gt 1) { throw "Multiple matching game.dat processes found: $($matches.ProcessId -join ', ')" }
    Start-Sleep -Milliseconds 75
}
if (-not $wmi) { throw 'Timed out waiting for game.dat launch.' }

$pidFound = [int]$wmi.ProcessId
$proc = Get-Process -Id $pidFound -ErrorAction Stop
$exe = $proc.MainModule.FileName
$liveHash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToUpperInvariant()
if ($liveHash -ne $ExpectedHash) { throw "LIVE HASH MISMATCH. Expected $ExpectedHash, got $liveHash" }
$base = $proc.MainModule.BaseAddress.ToInt64()
$h = [A8PLocalRootWatch]::Open([uint32]$pidFound)

function Try-U32([int64]$Addr, [ref]$Out) {
    $v = [uint32]0
    $ok = [A8PLocalRootWatch]::U32($h,$Addr,[ref]$v)
    if ($ok) { $Out.Value = $v }
    return $ok
}
function Try-U8([int64]$Addr, [ref]$Out) {
    $v = [byte]0
    $ok = [A8PLocalRootWatch]::U8($h,$Addr,[ref]$v)
    if ($ok) { $Out.Value = $v }
    return $ok
}

try {
    Write-Host ("PID                  : {0}" -f $pidFound)
    Write-Host ("Runtime base         : 0x{0:X8}" -f $base)
    Write-Host ''

    $manager = [uint32]0
    $root = [uint32]0
    $rootSeen = $false
    $firstRoot = [uint32]0
    $rootVtable = [uint32]0
    $firstSink = [uint32]0
    $firstSinkVtable = [uint32]0
    $firstSinkMethod10 = [uint32]0
    $firstA = [uint32]0
    $lastA = [uint32]0
    $lastSink = [uint32]0
    $lastSinkVtable = [uint32]0
    $lastMode = [byte]0
    $lastFlag40 = [byte]0
    $haveState = $false
    $eventCount = 0
    $printed = 0
    $maxPrinted = 500
    $activeDeadline = [DateTime]::UtcNow.AddSeconds(90)

    while ([DateTime]::UtcNow -lt $activeDeadline) {
        if (-not (Try-U32 ($base + $CurrentRootGlobalRva) ([ref]$manager))) {
            if ($proc.HasExited) { break }
            continue
        }
        if ($manager -eq 0) {
            if ($proc.HasExited) { break }
            Start-Sleep -Milliseconds 1
            continue
        }
        if (-not (Try-U32 ([int64]$manager + 0x24) ([ref]$root))) {
            if ($proc.HasExited) { break }
            continue
        }

        if ($root -eq 0) {
            if ($rootSeen) { break }
            if ($proc.HasExited) { break }
            Start-Sleep -Milliseconds 1
            continue
        }

        if (-not $rootSeen) {
            $rootSeen = $true
            $firstRoot = $root
            [void](Try-U32 ([int64]$root + 0x00) ([ref]$rootVtable))
            Write-Host '================ CURRENT localRoot PUBLISHED ================'
            Write-Host ("manager              : 0x{0:X8}" -f $manager)
            Write-Host ("localRoot            : 0x{0:X8}" -f $root)
            Write-Host ("localRoot vtable     : 0x{0:X8}" -f $rootVtable)
            Write-Host ''
        }

        $sink = [uint32]0
        $sinkVt = [uint32]0
        $sinkM10 = [uint32]0
        $a = [uint32]0
        $mode = [byte]0
        $flag40 = [byte]0
        [void](Try-U32 ([int64]$root + 0x04) ([ref]$sink))
        [void](Try-U8  ([int64]$root + 0x08) ([ref]$mode))
        [void](Try-U8  ([int64]$root + 0x40) ([ref]$flag40))
        [void](Try-U32 ([int64]$root + 0x44) ([ref]$a))
        if ($sink -ne 0) {
            if (Try-U32 ([int64]$sink + 0x00) ([ref]$sinkVt)) {
                if ($sinkVt -ne 0) { [void](Try-U32 ([int64]$sinkVt + 0x10) ([ref]$sinkM10)) }
            }
        }

        if (-not $haveState) {
            $firstA = $a
            $lastA = $a
            $lastSink = $sink
            $lastSinkVtable = $sinkVt
            $lastMode = $mode
            $lastFlag40 = $flag40
            $haveState = $true
            $changed = $true
        } else {
            $changed = ($a -ne $lastA -or $sink -ne $lastSink -or $sinkVt -ne $lastSinkVtable -or $mode -ne $lastMode -or $flag40 -ne $lastFlag40)
        }

        if ($sink -ne 0 -and $firstSink -eq 0) {
            $firstSink = $sink
            $firstSinkVtable = $sinkVt
            $firstSinkMethod10 = $sinkM10
        }

        if ($changed) {
            $eventCount++
            if ($printed -lt $maxPrinted) {
                Write-Host ("EVENT {0:D4}: ROOT=0x{1:X8};SINK=0x{2:X8};SINKVT=0x{3:X8};M10=0x{4:X8};MODE={5};FLAG40={6};A=0x{7:X8}" -f $eventCount,$root,$sink,$sinkVt,$sinkM10,$mode,$flag40,$a)
                $printed++
            }
            $lastA = $a
            $lastSink = $sink
            $lastSinkVtable = $sinkVt
            $lastMode = $mode
            $lastFlag40 = $flag40
        }
    }

    Write-Host ''
    Write-Host '================ CAPTURE SUMMARY ================'
    Write-Host ("root seen             : {0}" -f $rootSeen)
    Write-Host ("first root            : 0x{0:X8}" -f $firstRoot)
    Write-Host ("root vtable           : 0x{0:X8}" -f $rootVtable)
    Write-Host ("first sink            : 0x{0:X8}" -f $firstSink)
    Write-Host ("first sink vtable     : 0x{0:X8}" -f $firstSinkVtable)
    Write-Host ("sink vtable +0x10     : 0x{0:X8}" -f $firstSinkMethod10)
    Write-Host ("first A               : 0x{0:X8}" -f $firstA)
    Write-Host ("final observed A      : 0x{0:X8}" -f $lastA)
    Write-Host ("state-change events   : {0}" -f $eventCount)
    if ($eventCount -gt $maxPrinted) { Write-Host ("printed events        : {0} (output capped)" -f $maxPrinted) }
    Write-Host ''
    Write-Host ("CAPTURE_KEY          : ROOTVT={0:X8};SINKVT={1:X8};M10={2:X8};A_FIRST={3:X8};A_FINAL={4:X8};EVENTS={5}" -f $rootVtable,$firstSinkVtable,$firstSinkMethod10,$firstA,$lastA,$eventCount)
    Write-Host ''

    if (-not $rootSeen) {
        Write-Host 'RESULT: current localRoot publication was not observed. Re-run before launch; do not start with an already-running game.'
    } elseif ($firstSink -eq 0) {
        Write-Host 'RESULT: localRoot was observed, but no non-NULL +0x04 sink was captured.'
    } else {
        Write-Host 'RESULT: actual runtime localRoot sink/vtable binding captured without mutation.'
    }
}
finally {
    [A8PLocalRootWatch]::Close($h)
}

Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
