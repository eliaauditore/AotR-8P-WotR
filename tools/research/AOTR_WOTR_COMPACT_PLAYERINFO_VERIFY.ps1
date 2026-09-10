param(
    [int]$ProcessId = 0,
    [uint32]$P1TypeField = 0x09592D40,
    [uint32]$Stride = 0x1DC
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# Verifies the live compact WotR lobby row representation as PlayerInfo-like objects.
# Hypothesis under test:
#   object base = TypeField - 4
#   +0x00 = vtable-like pointer
#   +0x04 = PlayerType
#   +0x38 = endpoint IPv4-like field
#   +0x3C = endpoint port-like field
# Eight rows are spaced by 0x1DC in the current runtime representation.
# No WriteProcessMemory is imported or called.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'

Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PCompactPlayerInfoRead
{
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool ReadProcessMemory(
        IntPtr hProcess,
        IntPtr lpBaseAddress,
        byte[] lpBuffer,
        IntPtr nSize,
        out IntPtr lpNumberOfBytesRead);

    const UInt32 PROCESS_VM_READ = 0x0010;
    const UInt32 PROCESS_QUERY_INFORMATION = 0x0400;

    static byte[] Read(UInt32 pid, Int64 address, Int32 count)
    {
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess failed");
        try
        {
            byte[] b = new byte[count];
            IntPtr got;
            bool ok = ReadProcessMemory(h, new IntPtr(address), b, new IntPtr(count), out got);
            if (!ok || got.ToInt64() != count)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "ReadProcessMemory failed");
            return b;
        }
        finally { CloseHandle(h); }
    }

    public static UInt32 U32(UInt32 pid, Int64 address) { return BitConverter.ToUInt32(Read(pid,address,4),0); }
    public static UInt16 U16(UInt32 pid, Int64 address) { return BitConverter.ToUInt16(Read(pid,address,2),0); }
    public static byte[] Bytes(UInt32 pid, Int64 address, Int32 count) { return Read(pid,address,count); }
}
"@

if ($ProcessId -le 0) {
    $games = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.MainModule.FileName -match '\\game\.dat$' } catch { $false }
    })
    if ($games.Count -ne 1) { throw "Expected exactly one running game.dat. Found $($games.Count). Pass -ProcessId explicitly." }
    $ProcessId = [int]$games[0].Id
}

$proc = Get-Process -Id $ProcessId -ErrorAction Stop
$exePath = $proc.MainModule.FileName
$hash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToUpperInvariant()
$moduleBase = $proc.MainModule.BaseAddress.ToInt64()
$moduleEnd = $moduleBase + $proc.MainModule.ModuleMemorySize

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR COMPACT PLAYERINFO VERIFY - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID        : {0}" -f $ProcessId)
Write-Host ("Image      : {0}" -f $exePath)
Write-Host ("SHA256     : {0}" -f $hash)
Write-Host ("Type field : 0x{0:X8} (P1)" -f $P1TypeField)
Write-Host ("Stride     : 0x{0:X} ({0})" -f $Stride)
Write-Host ''

if ($hash -ne $ExpectedHash) { throw 'HASH MISMATCH - aborted before memory reads.' }

function Type-Name([uint32]$t) {
    switch ($t) {
        0 { 'Open' }
        1 { 'Closed' }
        2 { 'Peasant/Easy' }
        3 { 'Soldier/Medium' }
        4 { 'Captain/Hard' }
        5 { 'DeathMarch/Brutal' }
        6 { 'Network Human' }
        default { 'Unknown' }
    }
}

function IPv4-Both([uint32]$v) {
    $b0 =  $v        -band 255
    $b1 = ($v -shr 8)  -band 255
    $b2 = ($v -shr 16) -band 255
    $b3 = ($v -shr 24) -band 255
    return ("LE={0}.{1}.{2}.{3} BE={3}.{2}.{1}.{0}" -f $b0,$b1,$b2,$b3)
}

$vtables = @()
for ($i=0; $i -lt 8; $i++) {
    $typeAddr = [int64]$P1TypeField + ([int64]$Stride * $i)
    $obj = $typeAddr - 4
    $vt = [A8PCompactPlayerInfoRead]::U32([uint32]$ProcessId,$obj)
    $type = [A8PCompactPlayerInfoRead]::U32([uint32]$ProcessId,$obj + 4)
    $ep = [A8PCompactPlayerInfoRead]::U32([uint32]$ProcessId,$obj + 0x38)
    $port = [A8PCompactPlayerInfoRead]::U16([uint32]$ProcessId,$obj + 0x3C)
    $vtInModule = ([int64]$vt -ge $moduleBase -and [int64]$vt -lt $moduleEnd)
    $vtables += $vt

    Write-Host ("P{0}: obj=0x{1:X8} vtbl=0x{2:X8} inModule={3} Type={4} {5}" -f ($i+1),$obj,$vt,$vtInModule,$type,(Type-Name $type))
    Write-Host ("    +38 raw=0x{0:X8} {1}  +3C={2}" -f $ep,(IPv4-Both $ep),$port)
}

$uniqueVtables = @($vtables | Sort-Object -Unique)
Write-Host ''
Write-Host ("Unique vtable-like values: {0}" -f $uniqueVtables.Count)
foreach ($v in $uniqueVtables) { Write-Host ("  0x{0:X8}" -f $v) }

Write-Host ''
if ($uniqueVtables.Count -eq 1) {
    Write-Host 'VTABLE UNIFORMITY: PASS' -ForegroundColor Green
    Write-Host 'All 8 compact rows begin with the same vtable-like pointer and carry PlayerType at +0x04.'
} else {
    Write-Host 'VTABLE UNIFORMITY: NOT CONFIRMED' -ForegroundColor Yellow
}
Write-Host 'READ-ONLY COMPLETE. No process memory was modified.'
