param(
    [int]$ProcessId = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY runtime observer for the frontend switch table used by 0x00784148.
# No WriteProcessMemory / VirtualAllocEx / CreateRemoteThread.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$UiTableRva   = [int64]0x009E7D40   # VA 0x00DE7D40, two 12-byte entries used by 0x00784148
$UiIndexRva   = [int64]0x009EA114   # VA 0x00DEA114
$UiManagerRva = [int64]0x009EA110   # VA 0x00DEA110
$SessionRva   = [int64]0x009E4394
$ActiveRva    = [int64]0x009E7D6C
$NetworkRva   = [int64]0x009E892C

if (-not ('A8PUiSwitchObserver' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class A8PUiSwitchObserver {
    [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr got);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
    public const UInt32 PROCESS_QUERY_INFORMATION=0x0400;
    public const UInt32 PROCESS_VM_READ=0x0010;
}
"@
}

function Resolve-GameProcess {
    if ($ProcessId -gt 0) { return Get-Process -Id $ProcessId -ErrorAction Stop }
    $games = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'game.dat' -and $_.ExecutablePath -match '\\rotwk\\game\.dat$' })
    if ($games.Count -ne 1) {
        $txt = $games | ForEach-Object { 'PID={0} Path={1}' -f $_.ProcessId,$_.ExecutablePath }
        throw "Expected exactly one rotwk\\game.dat. Found $($games.Count). Pass -ProcessId.`n$($txt -join "`n")"
    }
    return Get-Process -Id ([int]$games[0].ProcessId) -ErrorAction Stop
}

$proc = Resolve-GameProcess
$exe = $proc.MainModule.FileName
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "Unsupported game.dat build. Expected $ExpectedHash Actual $hash Path $exe" }
$base = $proc.MainModule.BaseAddress.ToInt64()

$access = [A8PUiSwitchObserver]::PROCESS_QUERY_INFORMATION -bor [A8PUiSwitchObserver]::PROCESS_VM_READ
$h = [A8PUiSwitchObserver]::OpenProcess([uint32]$access,$false,[uint32]$proc.Id)
if ($h -eq [IntPtr]::Zero) { throw "OpenProcess failed Win32=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }

function Read-Bytes([int64]$addr,[int]$count) {
    $b = New-Object byte[] $count
    $got=[IntPtr]::Zero
    if (-not [A8PUiSwitchObserver]::ReadProcessMemory($h,[IntPtr]$addr,$b,[IntPtr]$count,[ref]$got) -or $got.ToInt64() -ne $count) {
        throw ('ReadProcessMemory failed at 0x{0:X8}' -f $addr)
    }
    return $b
}
function Read-U32([int64]$addr) { [BitConverter]::ToUInt32((Read-Bytes $addr 4),0) }
function Try-Read-U32([int64]$addr) {
    try { return (Read-U32 $addr) } catch { return $null }
}
function Fmt-U32($v) { if ($null -eq $v) { return '<unreadable>' }; return ('0x{0:X8}' -f [uint32]$v) }

try {
    $session = Read-U32 ($base+$SessionRva)
    $active  = Read-U32 ($base+$ActiveRva)
    $network = Read-U32 ($base+$NetworkRva)
    $mgr     = Read-U32 ($base+$UiManagerRva)
    $idx     = Read-U32 ($base+$UiIndexRva)

    Write-Host '============================================================'
    Write-Host ' AOTR WOTR UI SWITCH TABLE OBSERVER - READ ONLY'
    Write-Host '============================================================'
    Write-Host ("PID              : {0}" -f $proc.Id)
    Write-Host ("Image            : {0}" -f $exe)
    Write-Host ("SHA256           : {0}" -f $hash)
    Write-Host ("UI index DEA114  : {0}" -f $idx)
    Write-Host ("UI manager DEA110: {0}" -f (Fmt-U32 $mgr))
    Write-Host ("Session          : {0}" -f (Fmt-U32 $session))
    if($session -ne 0){
        Write-Host ("Session +0x28    : {0}" -f (Read-U32 ([int64]$session+0x28)))
        Write-Host ("Session +0x44    : {0}" -f (Fmt-U32 (Read-U32 ([int64]$session+0x44))))
    }
    Write-Host ("DE892C NetworkGI : {0}" -f (Fmt-U32 $network))
    Write-Host ("TheGameInfo      : {0}" -f (Fmt-U32 $active))
    Write-Host ''
    Write-Host '0x00784148 uses: entry = 0x00DE7D40 + (index * 0x0C)'
    Write-Host 'and forwards entry[0] + entry[1] to 0x00784063.'
    Write-Host ''

    for($i=0;$i -lt 2;$i++){
        $entry = $base + $UiTableRva + ($i*0x0C)
        $v0 = Read-U32 $entry
        $v1 = Read-U32 ($entry+4)
        $v2 = Read-U32 ($entry+8)
        Write-Host ("SLOT {0} @ 0x{1:X8}{2}" -f $i,$entry,$(if($idx -eq $i){'  <== CURRENT INDEX'}else{''}))
        Write-Host ("  +0x00 = {0}" -f (Fmt-U32 $v0))
        Write-Host ("  +0x04 = {0}" -f (Fmt-U32 $v1))
        Write-Host ("  +0x08 = {0}" -f (Fmt-U32 $v2))
        foreach($pair in @(@('+0x00',$v0),@('+0x04',$v1),@('+0x08',$v2))){
            $val=[uint32]$pair[1]
            if($val -ne 0){
                $p0=Try-Read-U32 ([int64]$val)
                $p4=Try-Read-U32 ([int64]$val+4)
                Write-Host ("    deref {0}: [0]={1} [4]={2}" -f $pair[0],(Fmt-U32 $p0),(Fmt-U32 $p4))
            }
        }
        Write-Host ''
    }

    Write-Host 'INTERPRETATION:'
    Write-Host '  - If SLOT 1 +0/+4 are NULL, 0x784148(1) cannot perform a real Strategic-lobby switch in this state.'
    Write-Host '  - If SLOT 1 is populated, the missing transition is downstream in 0x784063 / its target objects.'
    Write-Host '  - This observer changes nothing.'
}
finally {
    [void][A8PUiSwitchObserver]::CloseHandle($h)
}
