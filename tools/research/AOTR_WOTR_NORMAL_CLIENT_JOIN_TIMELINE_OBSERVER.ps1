param(
    [int]$ProcessId = 0,
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [int]$DurationSeconds = 45,
    [int]$IntervalMs = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# Purpose: observe a clean, normal frontend client join and record only state changes
# in the session/current/NetworkGI globals. This does not patch game memory and does
# not call any game function. Intended control experiment after the PlayerTemplate
# mismatch was fixed.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }
if ($DurationSeconds -lt 1) { throw 'DurationSeconds must be >= 1.' }
if ($IntervalMs -lt 5) { throw 'IntervalMs must be >= 5.' }

if (-not ('AotrReadOnlyNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AotrReadOnlyNative {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint access, bool inheritHandle, int processId);

    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr address, byte[] buffer, UIntPtr size, out UIntPtr bytesRead);

    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr handle);
}
'@
}

if ($ProcessId -eq 0) {
    $matches = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -ieq 'game.dat' -and $_.ExecutablePath -eq $GameDat
    })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one game.dat at '$GameDat', found $($matches.Count). Pass -ProcessId explicitly if needed."
    }
    $ProcessId = [int]$matches[0].ProcessId
}

$proc = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId"
if (-not $proc) { throw "PID $ProcessId not found." }
if ($proc.ExecutablePath -ne $GameDat) {
    throw "PID path mismatch. PID $ProcessId image='$($proc.ExecutablePath)' expected='$GameDat'"
}

$PROCESS_VM_READ = 0x0010
$PROCESS_QUERY_INFORMATION = 0x0400
$h = [AotrReadOnlyNative]::OpenProcess(($PROCESS_VM_READ -bor $PROCESS_QUERY_INFORMATION), $false, $ProcessId)
if ($h -eq [IntPtr]::Zero) { throw "OpenProcess failed. Win32=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }

function Read-U32([uint32]$Address) {
    $buf = New-Object byte[] 4
    $got = [UIntPtr]::Zero
    $ok = [AotrReadOnlyNative]::ReadProcessMemory($h, [IntPtr]([int64]$Address), $buf, [UIntPtr]4, [ref]$got)
    if (-not $ok -or $got.ToUInt64() -ne 4) { return [uint32]0 }
    return [BitConverter]::ToUInt32($buf, 0)
}

function Read-VTable([uint32]$Ptr) {
    if ($Ptr -eq 0) { return [uint32]0 }
    return Read-U32 $Ptr
}

function HX([uint32]$v) { return ('0x{0:X8}' -f $v) }

$SessionGlobal = [uint32]0x00DE4394
$NetworkGI     = [uint32]0x00DE892C
$Staging       = [uint32]0x00DE8930
$TheGameInfo   = [uint32]0x00DE7D6C
$C54B78        = [uint32]0x00C54B78
$BFD668        = [uint32]0x00BFD668
$C2FB98        = [uint32]0x00C2FB98

function Get-Snapshot {
    $session = Read-U32 $SessionGlobal
    $state = [uint32]0
    $head = [uint32]0
    $current = [uint32]0
    if ($session -ne 0) {
        $state   = Read-U32 ([uint32]($session + 0x28))
        $head    = Read-U32 ([uint32]($session + 0x10))
        $current = Read-U32 ([uint32]($session + 0x44))
    }
    $ngi = Read-U32 $NetworkGI
    $stg = Read-U32 $Staging
    $tgi = Read-U32 $TheGameInfo

    [pscustomobject]@{
        Session = $session
        State = $state
        Head = $head
        Current = $current
        NetworkGI = $ngi
        Staging = $stg
        TheGameInfo = $tgi
        CurrentVT = Read-VTable $current
        NetworkVT = Read-VTable $ngi
        StagingVT = Read-VTable $stg
        TheGameInfoVT = Read-VTable $tgi
    }
}

function Snapshot-Key($s) {
    return ('{0:X8}|{1:X8}|{2:X8}|{3:X8}|{4:X8}|{5:X8}|{6:X8}|{7:X8}|{8:X8}|{9:X8}|{10:X8}' -f `
        $s.Session,$s.State,$s.Head,$s.Current,$s.NetworkGI,$s.Staging,$s.TheGameInfo,`
        $s.CurrentVT,$s.NetworkVT,$s.StagingVT,$s.TheGameInfoVT)
}

function Classify-VT([uint32]$vt) {
    if ($vt -eq $C54B78) { return 'C54B78' }
    if ($vt -eq $BFD668) { return 'BFD668' }
    if ($vt -eq $C2FB98) { return 'C2FB98' }
    if ($vt -eq 0) { return 'NULL' }
    return (HX $vt)
}

function Print-Snapshot($s, [string]$Reason, [double]$ElapsedMs) {
    $same = ($s.Current -ne 0 -and $s.Current -eq $s.NetworkGI)
    Write-Output ('[{0,9:N1} ms] {1}' -f $ElapsedMs,$Reason)
    Write-Output ('  Session={0} State={1} Head={2}' -f (HX $s.Session),$s.State,(HX $s.Head))
    Write-Output ('  Current={0} vt={1}' -f (HX $s.Current),(Classify-VT $s.CurrentVT))
    Write-Output ('  DE892C ={0} vt={1}' -f (HX $s.NetworkGI),(Classify-VT $s.NetworkVT))
    Write-Output ('  DE8930 ={0} vt={1}' -f (HX $s.Staging),(Classify-VT $s.StagingVT))
    Write-Output ('  DE7D6C ={0} vt={1}' -f (HX $s.TheGameInfo),(Classify-VT $s.TheGameInfoVT))
    Write-Output ('  Current==DE892C={0}' -f $same)
}

try {
    Write-Output '============================================================'
    Write-Output ' AOTR WOTR NORMAL CLIENT JOIN TIMELINE - READ ONLY'
    Write-Output '============================================================'
    Write-Output ("PID              : {0}" -f $ProcessId)
    Write-Output ("Image            : {0}" -f $GameDat)
    Write-Output ("SHA256           : {0}" -f $hash)
    Write-Output ("Duration         : {0}s" -f $DurationSeconds)
    Write-Output ("Poll interval    : {0}ms" -f $IntervalMs)
    Write-Output ''
    Write-Output 'CONTROL PROCEDURE: start this while the client is in the normal game browser, then click the normal Join button once.'
    Write-Output 'Only changed snapshots are printed. No memory is modified.'
    Write-Output ''

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $first = Get-Snapshot
    $lastKey = Snapshot-Key $first
    Print-Snapshot $first 'INITIAL' 0

    while ($sw.Elapsed.TotalSeconds -lt $DurationSeconds) {
        Start-Sleep -Milliseconds $IntervalMs
        $s = Get-Snapshot
        $key = Snapshot-Key $s
        if ($key -ne $lastKey) {
            Print-Snapshot $s 'CHANGE' $sw.Elapsed.TotalMilliseconds
            $lastKey = $key
        }
    }

    $final = Get-Snapshot
    Print-Snapshot $final 'FINAL' $sw.Elapsed.TotalMilliseconds
    Write-Output ''
    Write-Output 'READ-ONLY COMPLETE. No file or process memory was modified.'
}
finally {
    if ($h -ne [IntPtr]::Zero) { [void][AotrReadOnlyNative]::CloseHandle($h) }
}
