param(
    [int]$ProcessId = 0,
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [int]$DurationSeconds = 30,
    [int]$IntervalMs = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY / Windows PowerShell 5.1 compatible.
# Purpose: capture transient frontend state during one clean normal UI join.
# No WriteProcessMemory, no game-function calls, no file mutation.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }
if ($DurationSeconds -lt 1) { throw 'DurationSeconds must be >= 1.' }
if ($IntervalMs -lt 2) { throw 'IntervalMs must be >= 2.' }

if (-not ('AotrFrontendTimelineNative' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AotrFrontendTimelineNative {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint access, bool inheritHandle, int processId);

    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr address, byte[] buffer, UIntPtr size, out UIntPtr bytesRead);

    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr handle);

    public static bool TryReadUInt32(IntPtr hProcess, long address, out uint value) {
        byte[] b = new byte[4];
        UIntPtr got;
        bool ok = ReadProcessMemory(hProcess, new IntPtr(address), b, new UIntPtr(4u), out got);
        if (!ok || got.ToUInt64() != 4UL) { value = 0u; return false; }
        value = BitConverter.ToUInt32(b,0);
        return true;
    }
}
'@
}

if ($ProcessId -eq 0) {
    $matches = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -ieq 'game.dat' -and $_.ExecutablePath -eq $GameDat
    })
    if ($matches.Count -ne 1) { throw "Expected exactly one game.dat at '$GameDat', found $($matches.Count)." }
    $ProcessId = [int]$matches[0].ProcessId
}

$proc = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId"
if (-not $proc) { throw "PID $ProcessId not found." }
if ($proc.ExecutablePath -ne $GameDat) { throw "PID path mismatch: '$($proc.ExecutablePath)'" }

$h = [AotrFrontendTimelineNative]::OpenProcess((0x0010 -bor 0x0400), $false, $ProcessId)
if ($h -eq [IntPtr]::Zero) { throw "OpenProcess failed Win32=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }

function Read-U32([uint32]$Address) {
    [uint32]$value = 0
    if (-not [AotrFrontendTimelineNative]::TryReadUInt32($h,[int64][uint64]$Address,[ref]$value)) { return [uint32]0 }
    return $value
}
function HX([uint32]$v) { '0x{0:X8}' -f $v }
function VT([uint32]$p) { if($p -eq 0){ return [uint32]0 }; Read-U32 $p }

$SessionGlobal = [uint32]0x00DE4394
$NetworkGI     = [uint32]0x00DE892C
$Staging       = [uint32]0x00DE8930
$TheGameInfo   = [uint32]0x00DE7D6C
$UiTable0      = [uint32]0x00DE7D40
$UiTable1      = [uint32]0x00DE7D4C
$UiManager     = [uint32]0x00DEA110
$UiIndex       = [uint32]0x00DEA114
$Frontend412C  = [uint32]0x00DE412C
$Frontend4B04  = [uint32]0x00DE4B04
$C54B78        = [uint32]0x00C54B78
$BFD668        = [uint32]0x00BFD668
$C2FB98        = [uint32]0x00C2FB98

function VTN([uint32]$v) {
    if($v -eq 0){return 'NULL'}
    if($v -eq $C54B78){return 'C54B78'}
    if($v -eq $BFD668){return 'BFD668'}
    if($v -eq $C2FB98){return 'C2FB98'}
    return (HX $v)
}

function Snap {
    $ses=Read-U32 $SessionGlobal
    $state=[uint32]0; $head=[uint32]0; $cur=[uint32]0
    if($ses -ne 0){
        $state=Read-U32 ([uint32]($ses+0x28))
        $head=Read-U32 ([uint32]($ses+0x10))
        $cur=Read-U32 ([uint32]($ses+0x44))
    }
    $ngi=Read-U32 $NetworkGI
    $stg=Read-U32 $Staging
    $tgi=Read-U32 $TheGameInfo
    [pscustomobject]@{
        Session=$ses; State=$state; Head=$head; Current=$cur; CurrentVT=(VT $cur)
        Network=$ngi; NetworkVT=(VT $ngi); Staging=$stg; TheGameInfo=$tgi
        UiManager=(Read-U32 $UiManager); UiIndex=(Read-U32 $UiIndex)
        T00=(Read-U32 $UiTable0); T04=(Read-U32 ([uint32]($UiTable0+4))); T08=(Read-U32 ([uint32]($UiTable0+8)))
        T10=(Read-U32 $UiTable1); T14=(Read-U32 ([uint32]($UiTable1+4))); T18=(Read-U32 ([uint32]($UiTable1+8)))
        F412C=(Read-U32 $Frontend412C); F4B04=(Read-U32 $Frontend4B04)
    }
}
function Key($s) {
    @($s.Session,$s.State,$s.Head,$s.Current,$s.CurrentVT,$s.Network,$s.NetworkVT,$s.Staging,$s.TheGameInfo,
      $s.UiManager,$s.UiIndex,$s.T00,$s.T04,$s.T08,$s.T10,$s.T14,$s.T18,$s.F412C,$s.F4B04) -join '|'
}
function Print-Snap($s,[string]$why,[double]$ms){
    Write-Output ('[{0,9:N1} ms] {1}' -f $ms,$why)
    Write-Output ('  Session={0} State={1} Head={2}' -f (HX $s.Session),$s.State,(HX $s.Head))
    Write-Output ('  Current={0} vt={1}' -f (HX $s.Current),(VTN $s.CurrentVT))
    Write-Output ('  DE892C ={0} vt={1}  DE8930={2}  DE7D6C={3}' -f (HX $s.Network),(VTN $s.NetworkVT),(HX $s.Staging),(HX $s.TheGameInfo))
    Write-Output ('  DEA110 ={0}  DEA114={1}' -f (HX $s.UiManager),$s.UiIndex)
    Write-Output ('  UI0=[{0},{1},{2}]' -f (HX $s.T00),(HX $s.T04),(HX $s.T08))
    Write-Output ('  UI1=[{0},{1},{2}]' -f (HX $s.T10),(HX $s.T14),(HX $s.T18))
    Write-Output ('  DE412C={0}  DE4B04={1}' -f (HX $s.F412C),(HX $s.F4B04))
}

try {
    Write-Output '============================================================'
    Write-Output ' AOTR WOTR NORMAL CLIENT FRONTEND TIMELINE - READ ONLY'
    Write-Output '============================================================'
    Write-Output ("PID           : {0}" -f $ProcessId)
    Write-Output ("Image         : {0}" -f $GameDat)
    Write-Output ("SHA256        : {0}" -f $hash)
    Write-Output ("Duration      : {0}s" -f $DurationSeconds)
    Write-Output ("Poll interval : {0}ms" -f $IntervalMs)
    Write-Output ''
    Write-Output 'Start in normal browser, then click normal Join exactly once.'
    Write-Output 'Only changed snapshots are printed. No process memory is modified.'
    Write-Output ''

    $sw=[Diagnostics.Stopwatch]::StartNew()
    $s=Snap; $k=Key $s; Print-Snap $s 'INITIAL' 0
    while($sw.Elapsed.TotalSeconds -lt $DurationSeconds){
        Start-Sleep -Milliseconds $IntervalMs
        $n=Snap; $nk=Key $n
        if($nk -ne $k){ Print-Snap $n 'CHANGE' $sw.Elapsed.TotalMilliseconds; $k=$nk }
    }
    $f=Snap; Print-Snap $f 'FINAL' $sw.Elapsed.TotalMilliseconds
    Write-Output ''
    Write-Output 'READ-ONLY COMPLETE.'
}
finally {
    if($h -ne [IntPtr]::Zero){ [void][AotrFrontendTimelineNative]::CloseHandle($h) }
}
