# =================================================================================================
# WOTR CURSOR ZOOM + DRAG - FINAL STABLE
# Based on verified V7.
#
# FINAL BASELINE:
#   AnchorGain = 2.0
#   DragSpeed  = -16.0
#
# This file intentionally preserves the proven V7 runtime logic.
# Experimental V8-V13B world-space zoom attempts are NOT part of this build.
# =================================================================================================

[CmdletBinding()]
param(
    [string]$GameDat = "D:\Games\AotR\AgeoftheRing\rotwk\game.dat",
    [ValidateRange(-10.0, 10.0)]
    [single]$AnchorGain = 2.0,
    [ValidateRange(-20.0, 20.0)]
    [single]$DragSpeed = -16.0,
    [Parameter(Mandatory=$true)]
    [byte[]]$V7Shellcode
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Known931Size = 11347456
$Known931DiskSha256 = "66AB714EA565CC490F9C41E1350F9A30708AEF6FBC2942325F50470BCB980202"
$RequiredImageBase = 0x00400000

$RawWheelHookRva = 0x0004128C
$MapHandlerRva = 0x00575507
$ZoomUpdateRva = 0x0009AB21
$RawStubOffset = 0x000
$MapStubOffset = 0x100
$ZoomStubOffset = 0x500
$StateOffset = 0x800
$AllocationSize = 0x1000
$StateAnchorOffset = 0x24
$StateDragOffset = 0x28
$StateOneOffset = 0x2C
$StateQuarterOffset = 0x40
$StateMarkerOffset = 0x44
$StateCursorXOffset = 0x48
$StateCursorYOffset = 0x4C
$StateCursorValidOffset = 0x50

[byte[]]$OriginalRawWheelHook = @(
    0x8B, 0x45, 0xFC,
    0xC1, 0xE8, 0x10,
    0x0F, 0xBF, 0xC0,
    0x89, 0x46, 0x0C
)

[byte[]]$V3RawWheelHook = @(
    0xE9, 0xE1, 0x1E, 0x29, 0x00,
    0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90
)

[byte[]]$OriginalMapHandler = @(
    0x55, 0x8B, 0xEC, 0x51, 0x51, 0x8B, 0x45, 0x08
)

[byte[]]$V2MapHandler = @(
    0xE9, 0x66, 0xDC, 0xD5, 0xFF, 0x90, 0x90, 0x90
)

[byte[]]$OriginalZoomUpdate = @(
    0xF3, 0x0F, 0x58, 0x86, 0x34, 0x01, 0x00, 0x00,
    0xF3, 0x0F, 0x11, 0x86, 0x34, 0x01, 0x00, 0x00
)

# V7 also depends on these two stable targets. Validate them before any write so a new AotR build
# cannot accidentally run shellcode against relocated internals.
$CameraGlobalRefAddress = [IntPtr]0x0097548E
[byte[]]$ExpectedCameraGlobalRef = @(0x8B,0x0D,0x58,0x49,0xDE,0x00)
$CancelReleaseAddress = [IntPtr]0x009D9167
[byte[]]$ExpectedCancelRelease = @(
    0x8B,0x41,0x1C,0x8B,0x54,0x24,0x04,0x3B,
    0xD0,0x74,0x12,0x50,0x51,0x89,0x51,0x1C
)

[byte[]]$ShellcodeTemplate = [byte[]]$V7Shellcode
if ($null -eq $ShellcodeTemplate -or $ShellcodeTemplate.Length -eq 0) {
    throw "Interner V7-Shellcode-Resource fehlt."
}

if ($ShellcodeTemplate.Length -ne 1577) {
    throw "Interner V7-Shellcode-Laengenfehler: $($ShellcodeTemplate.Length) statt 1577 Bytes."
}

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-","").ToUpperInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Test-Bytes([byte[]]$Actual, [byte[]]$Expected) {
    if ($Actual.Length -ne $Expected.Length) {
        return $false
    }
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Actual[$i] -ne $Expected[$i]) {
            return $false
        }
    }
    return $true
}

function Test-BytesAt(
    [byte[]]$Actual,
    [int]$ActualOffset,
    [byte[]]$Expected,
    [int]$ExpectedOffset,
    [int]$Length
) {
    if (($ActualOffset -lt 0) -or ($ExpectedOffset -lt 0) -or
        (($ActualOffset + $Length) -gt $Actual.Length) -or
        (($ExpectedOffset + $Length) -gt $Expected.Length)) {
        return $false
    }
    for ($i = 0; $i -lt $Length; $i++) {
        if ($Actual[$ActualOffset + $i] -ne $Expected[$ExpectedOffset + $i]) {
            return $false
        }
    }
    return $true
}

function Copy-Bytes(
    [byte[]]$Destination,
    [int]$DestinationOffset,
    [byte[]]$Source
) {
    [Array]::Copy($Source, 0, $Destination, $DestinationOffset, $Source.Length)
}

function Get-RunningTarget([string]$FullGamePath) {
    $targets = @(
        Get-CimInstance Win32_Process -Filter "Name = 'game.dat'" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ExecutablePath -and
                [string]::Equals(
                    [IO.Path]::GetFullPath($_.ExecutablePath),
                    $FullGamePath,
                    [StringComparison]::OrdinalIgnoreCase
                )
            } |
            Sort-Object CreationDate -Descending
    )
    if ($targets.Count -eq 0) {
        return $null
    }
    return $targets[0]
}

if (-not ("WotrNativeMemoryV7" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class WotrNativeMemoryV7
{
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(
        UInt32 dwDesiredAccess,
        bool bInheritHandle,
        UInt32 dwProcessId
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ReadProcessMemory(
        IntPtr hProcess,
        IntPtr lpBaseAddress,
        [Out] byte[] lpBuffer,
        UIntPtr nSize,
        out UIntPtr lpNumberOfBytesRead
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool WriteProcessMemory(
        IntPtr hProcess,
        IntPtr lpBaseAddress,
        byte[] lpBuffer,
        UIntPtr nSize,
        out UIntPtr lpNumberOfBytesWritten
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool VirtualProtectEx(
        IntPtr hProcess,
        IntPtr lpAddress,
        UIntPtr dwSize,
        UInt32 flNewProtect,
        out UInt32 lpflOldProtect
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr VirtualAllocEx(
        IntPtr hProcess,
        IntPtr lpAddress,
        UIntPtr dwSize,
        UInt32 flAllocationType,
        UInt32 flProtect
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool FlushInstructionCache(
        IntPtr hProcess,
        IntPtr lpBaseAddress,
        UIntPtr dwSize
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@
}

function Get-Win32ErrorText([string]$Operation) {
    $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    return "$Operation fehlgeschlagen (Win32-Fehler $code). PowerShell als Administrator starten."
}

function Read-RemoteBytes(
    [IntPtr]$ProcessHandle,
    [IntPtr]$Address,
    [int]$Length
) {
    [byte[]]$buffer = [byte[]]::new($Length)
    [UIntPtr]$read = [UIntPtr]::Zero
    $ok = [WotrNativeMemoryV7]::ReadProcessMemory(
        $ProcessHandle,
        $Address,
        $buffer,
        [UIntPtr]::new([UInt32]$Length),
        [ref]$read
    )
    if ((-not $ok) -or ($read.ToUInt64() -ne [UInt64]$Length)) {
        throw (Get-Win32ErrorText "ReadProcessMemory")
    }
    return $buffer
}

function Write-RemoteBytes(
    [IntPtr]$ProcessHandle,
    [IntPtr]$Address,
    [byte[]]$Bytes
) {
    $PAGE_EXECUTE_READWRITE = 0x40
    [UInt32]$oldProtection = 0
    $protectOk = [WotrNativeMemoryV7]::VirtualProtectEx(
        $ProcessHandle,
        $Address,
        [UIntPtr]::new([UInt32]$Bytes.Length),
        $PAGE_EXECUTE_READWRITE,
        [ref]$oldProtection
    )
    if (-not $protectOk) {
        throw (Get-Win32ErrorText "VirtualProtectEx")
    }

    try {
        [UIntPtr]$written = [UIntPtr]::Zero
        $writeOk = [WotrNativeMemoryV7]::WriteProcessMemory(
            $ProcessHandle,
            $Address,
            $Bytes,
            [UIntPtr]::new([UInt32]$Bytes.Length),
            [ref]$written
        )
        if ((-not $writeOk) -or ($written.ToUInt64() -ne [UInt64]$Bytes.Length)) {
            throw (Get-Win32ErrorText "WriteProcessMemory")
        }
    }
    finally {
        [UInt32]$ignoredProtection = 0
        [void][WotrNativeMemoryV7]::VirtualProtectEx(
            $ProcessHandle,
            $Address,
            [UIntPtr]::new([UInt32]$Bytes.Length),
            $oldProtection,
            [ref]$ignoredProtection
        )
    }
}

function Flush-RemoteCode(
    [IntPtr]$ProcessHandle,
    [IntPtr]$Address,
    [int]$Length
) {
    $ok = [WotrNativeMemoryV7]::FlushInstructionCache(
        $ProcessHandle,
        $Address,
        [UIntPtr]::new([UInt32]$Length)
    )
    if (-not $ok) {
        throw (Get-Win32ErrorText "FlushInstructionCache")
    }
}

function New-DetourBytes(
    [IntPtr]$Source,
    [IntPtr]$Target,
    [int]$Length
) {
    if ($Length -lt 5) {
        throw "Detour-Laenge muss mindestens 5 sein."
    }
    [Int64]$relative64 = $Target.ToInt64() - ($Source.ToInt64() + 5)
    if (($relative64 -lt [Int32]::MinValue) -or ($relative64 -gt [Int32]::MaxValue)) {
        throw "Detour-Ziel liegt ausserhalb der 32-Bit-Reichweite."
    }
    [byte[]]$result = [byte[]]::new($Length)
    for ($i = 0; $i -lt $Length; $i++) {
        $result[$i] = 0x90
    }
    $result[0] = 0xE9
    Copy-Bytes $result 1 ([BitConverter]::GetBytes([Int32]$relative64))
    return $result
}

function Get-DetourTarget(
    [IntPtr]$Source,
    [byte[]]$Bytes
) {
    if (($Bytes.Length -lt 5) -or ($Bytes[0] -ne 0xE9)) {
        return [Int64]0
    }
    [Int32]$relative = [BitConverter]::ToInt32($Bytes, 1)
    return [Int64]($Source.ToInt64() + 5 + $relative)
}

function Get-ExistingV7Info(
    [IntPtr]$ProcessHandle,
    [IntPtr]$RawHookAddress,
    [byte[]]$RawBytes,
    [IntPtr]$MapHookAddress,
    [byte[]]$MapBytes,
    [IntPtr]$ZoomHookAddress,
    [byte[]]$ZoomBytes
) {
    $candidates = @()

    [Int64]$rawTarget = Get-DetourTarget $RawHookAddress $RawBytes
    if ($rawTarget -gt 0) {
        $candidates += $rawTarget
    }

    [Int64]$mapTarget = Get-DetourTarget $MapHookAddress $MapBytes
    if ($mapTarget -gt $MapStubOffset) {
        $candidates += ($mapTarget - $MapStubOffset)
    }

    [Int64]$zoomTarget = Get-DetourTarget $ZoomHookAddress $ZoomBytes
    if ($zoomTarget -gt $ZoomStubOffset) {
        $candidates += ($zoomTarget - $ZoomStubOffset)
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        try {
            [byte[]]$probe = Read-RemoteBytes $ProcessHandle ([IntPtr]$candidate) 0x629
            if (-not (Test-BytesAt $probe 0 $ShellcodeTemplate 0 15)) {
                continue
            }
            if (-not (Test-BytesAt $probe $MapStubOffset $ShellcodeTemplate $MapStubOffset 3)) {
                continue
            }
            if (-not (Test-BytesAt $probe $ZoomStubOffset $ShellcodeTemplate $ZoomStubOffset 9)) {
                continue
            }

            [UInt32]$state1 = [BitConverter]::ToUInt32($probe, 0x0F)
            [UInt32]$state2 = [BitConverter]::ToUInt32($probe, 0x103)
            [UInt32]$state3 = [BitConverter]::ToUInt32($probe, 0x510)
            [UInt32]$state4 = [BitConverter]::ToUInt32($probe, 0x540)
            if (($state1 -eq 0) -or ($state1 -ne $state2) -or
                ($state1 -ne $state3) -or ($state1 -ne $state4)) {
                continue
            }

            [byte[]]$marker = Read-RemoteBytes $ProcessHandle ([IntPtr]([Int64]$state1 + $StateMarkerOffset)) 4
            if ([Text.Encoding]::ASCII.GetString($marker) -ne "WZV7") {
                continue
            }

            return [PSCustomObject]@{
                BlockAddress = [IntPtr]$candidate
                StateAddress = [IntPtr]([Int64]$state1)
            }
        }
        catch {
            continue
        }
    }
    return $null
}

function Test-ExistingV6Installation(
    [IntPtr]$ProcessHandle,
    [IntPtr]$RawHookAddress,
    [byte[]]$RawBytes,
    [IntPtr]$MapHookAddress,
    [byte[]]$MapBytes,
    [IntPtr]$ZoomHookAddress,
    [byte[]]$ZoomBytes
) {
    [Int64]$rawTarget = Get-DetourTarget $RawHookAddress $RawBytes
    [Int64]$mapTarget = Get-DetourTarget $MapHookAddress $MapBytes
    [Int64]$zoomTarget = Get-DetourTarget $ZoomHookAddress $ZoomBytes
    if (($rawTarget -le 0) -or
        ($mapTarget -ne ($rawTarget + 0x100)) -or
        ($zoomTarget -ne ($rawTarget + 0x300))) {
        return $false
    }

    try {
        [byte[]]$probe = Read-RemoteBytes $ProcessHandle ([IntPtr]$rawTarget) 0x415
        [byte[]]$rawPrefix = @(
            0x8B,0x45,0xFC,0xC1,0xE8,0x10,0x0F,0xBF,
            0xC0,0x89,0x46,0x0C,0x9C,0x60,0xBF
        )
        [byte[]]$mapPrefix = @(0x9C,0x60,0xBF)
        [byte[]]$zoomPrefix = @(
            0x57,0x83,0xEC,0x04,0xF3,0x0F,0x11,0x0C,0x24
        )

        if (-not (Test-BytesAt $probe 0 $rawPrefix 0 $rawPrefix.Length)) {
            return $false
        }
        if (-not (Test-BytesAt $probe 0x100 $mapPrefix 0 $mapPrefix.Length)) {
            return $false
        }
        if (-not (Test-BytesAt $probe 0x300 $zoomPrefix 0 $zoomPrefix.Length)) {
            return $false
        }

        [UInt32]$state1 = [BitConverter]::ToUInt32($probe, 0x0F)
        [UInt32]$state2 = [BitConverter]::ToUInt32($probe, 0x103)
        [UInt32]$state3 = [BitConverter]::ToUInt32($probe, 0x30A)
        [UInt32]$state4 = [BitConverter]::ToUInt32($probe, 0x343)
        if (($state1 -eq 0) -or ($state1 -ne $state2) -or
            ($state1 -ne $state3) -or ($state1 -ne $state4)) {
            return $false
        }

        [byte[]]$marker = Read-RemoteBytes $ProcessHandle ([IntPtr]([Int64]$state1 + 0x44)) 4
        return ([Text.Encoding]::ASCII.GetString($marker) -eq "WZV6")
    }
    catch {
        return $false
    }
}

function Test-ExistingV5Installation(
    [IntPtr]$ProcessHandle,
    [IntPtr]$RawHookAddress,
    [byte[]]$RawBytes,
    [IntPtr]$MapHookAddress,
    [byte[]]$MapBytes,
    [IntPtr]$ZoomHookAddress,
    [byte[]]$ZoomBytes
) {
    [Int64]$rawTarget = Get-DetourTarget $RawHookAddress $RawBytes
    [Int64]$mapTarget = Get-DetourTarget $MapHookAddress $MapBytes
    [Int64]$zoomTarget = Get-DetourTarget $ZoomHookAddress $ZoomBytes
    if (($rawTarget -le 0) -or
        ($mapTarget -ne ($rawTarget + 0x0F0)) -or
        ($zoomTarget -ne ($rawTarget + 0x240))) {
        return $false
    }

    try {
        [byte[]]$probe = Read-RemoteBytes $ProcessHandle ([IntPtr]$rawTarget) 0x288
        [byte[]]$v5RawPrefix = @(
            0x8B,0x45,0xFC,0xC1,0xE8,0x10,0x0F,0xBF,
            0xC0,0x89,0x46,0x0C,0x9C,0x60,0xBF
        )
        [byte[]]$v5MapPrefix = @(0x9C,0x60,0xBF)
        [byte[]]$v5ZoomPrefix = @(0x57,0x83,0xEC,0x04,0xF3,0x0F,0x11,0x0C,0x24)

        if (-not (Test-BytesAt $probe 0 $v5RawPrefix 0 $v5RawPrefix.Length)) {
            return $false
        }
        if (-not (Test-BytesAt $probe 0x0F0 $v5MapPrefix 0 $v5MapPrefix.Length)) {
            return $false
        }
        if (-not (Test-BytesAt $probe 0x240 $v5ZoomPrefix 0 $v5ZoomPrefix.Length)) {
            return $false
        }

        [UInt32]$state1 = [BitConverter]::ToUInt32($probe, 0x0F)
        [UInt32]$state2 = [BitConverter]::ToUInt32($probe, 0x0F3)
        [UInt32]$state3 = [BitConverter]::ToUInt32($probe, 0x24A)
        [UInt32]$state4 = [BitConverter]::ToUInt32($probe, 0x283)
        if (($state1 -eq 0) -or ($state1 -ne $state2) -or
            ($state1 -ne $state3) -or ($state1 -ne $state4)) {
            return $false
        }

        [byte[]]$marker = Read-RemoteBytes $ProcessHandle ([IntPtr]([Int64]$state1 + 0x44)) 4
        return ([Text.Encoding]::ASCII.GetString($marker) -eq "WZV5")
    }
    catch {
        return $false
    }
}

function Test-ExistingV4Installation(
    [IntPtr]$ProcessHandle,
    [IntPtr]$RawHookAddress,
    [byte[]]$RawBytes,
    [IntPtr]$MapHookAddress,
    [byte[]]$MapBytes
) {
    [Int64]$rawTarget = Get-DetourTarget $RawHookAddress $RawBytes
    [Int64]$mapTarget = Get-DetourTarget $MapHookAddress $MapBytes
    if (($rawTarget -le 0) -or ($mapTarget -ne ($rawTarget + 0x130))) {
        return $false
    }

    try {
        [byte[]]$probe = Read-RemoteBytes $ProcessHandle ([IntPtr]$rawTarget) 0x138
        [byte[]]$v4RawPrefix = @(
            0x8B,0x45,0xFC,0xC1,0xE8,0x10,0x0F,0xBF,
            0xC0,0x89,0x46,0x0C,0x9C,0x60,0xBF
        )
        [byte[]]$v4MapPrefix = @(0x9C,0x60,0xBF)
        if (-not (Test-BytesAt $probe 0 $v4RawPrefix 0 $v4RawPrefix.Length)) {
            return $false
        }
        if (-not (Test-BytesAt $probe 0x130 $v4MapPrefix 0 $v4MapPrefix.Length)) {
            return $false
        }

        [UInt32]$state1 = [BitConverter]::ToUInt32($probe, 0x0F)
        [UInt32]$state2 = [BitConverter]::ToUInt32($probe, 0x133)
        if (($state1 -eq 0) -or ($state1 -ne $state2)) {
            return $false
        }
        [byte[]]$marker = Read-RemoteBytes $ProcessHandle ([IntPtr]([Int64]$state1 + 0x30)) 4
        return ([Text.Encoding]::ASCII.GetString($marker) -eq "WZV4")
    }
    catch {
        return $false
    }
}

Write-Host "WOTR - CURSOR ZOOM + DRAG - FINAL STABLE (V7)"
Write-Host ("=" * 100)
Write-Host ""

if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) {
    throw "game.dat nicht gefunden: $GameDat"
}

$GameDat = [IO.Path]::GetFullPath($GameDat)
$diskInfo = Get-Item -LiteralPath $GameDat
$diskHash = Get-Sha256 $GameDat

Write-Host "GAME.DAT DISK : $GameDat"
Write-Host "DISK SIZE     : $($diskInfo.Length)"
Write-Host "DISK SHA256   : $diskHash"
Write-Host ""

if (($diskInfo.Length -eq $Known931Size) -and ($diskHash -eq $Known931DiskSha256)) {
    Write-Host "[OK] Bekannter AotR 9.3.1 Referenz-Build erkannt."
}
else {
    Write-Host "[INFO] Neuer/anderer AotR-Build erkannt."
    Write-Host "[INFO] Whole-file SHA wird nicht blind freigeschaltet; Runtime-Signaturen werden vor jedem Write geprueft."
}
Write-Host ""

$target = Get-RunningTarget $GameDat
if ($null -eq $target) {
    throw @"
Die passende game.dat laeuft noch nicht. V7 wurde absichtlich nicht installiert.

Richtige Reihenfolge:
  1. Normalen AotR-8P-WotR-Launcher starten.
  2. Auf LAUNCH klicken und bis ins Spiel-Hauptmenue warten.
  3. Erst danach dieses V7-Skript als Administrator ausfuehren.

Damit kann der Launcher den Runtime-Hook nicht wieder ueberschreiben.
"@
}

Write-Host "[OK] Bereits laufende passende game.dat gefunden."

$pidValue = [UInt32]$target.ProcessId
Write-Host "[OK] Passende game.dat erkannt. PID: $pidValue"
if ($target.CommandLine) {
    Write-Host "CMDLINE  : $($target.CommandLine)"
}

$process = Get-Process -Id $pidValue -ErrorAction Stop
$process.Refresh()

$processAge = ([DateTime]::Now - $process.StartTime).TotalSeconds
if ($processAge -lt 12.0) {
    $remaining = [Math]::Ceiling(12.0 - $processAge)
    Write-Host "[WAIT] Launcher-/Spielinitialisierung noch etwa $remaining Sekunden ..."
    Start-Sleep -Milliseconds ([int]([Math]::Max(0.0, (12.0 - $processAge) * 1000.0)))
    $process.Refresh()
}

$imageBase = $process.MainModule.BaseAddress
if ($imageBase.ToInt64() -ne $RequiredImageBase) {
    throw ("Unerwartete game.dat ImageBase: 0x{0:X8}; erwartet 0x{1:X8}. Nichts gepatcht." -f $imageBase.ToInt64(), $RequiredImageBase)
}

$rawHookAddress = [IntPtr]($imageBase.ToInt64() + $RawWheelHookRva)
$mapHookAddress = [IntPtr]($imageBase.ToInt64() + $MapHandlerRva)
$zoomHookAddress = [IntPtr]($imageBase.ToInt64() + $ZoomUpdateRva)

$PROCESS_VM_OPERATION = 0x0008
$PROCESS_VM_READ = 0x0010
$PROCESS_VM_WRITE = 0x0020
$PROCESS_QUERY_INFO = 0x0400
$access = $PROCESS_VM_OPERATION -bor $PROCESS_VM_READ -bor $PROCESS_VM_WRITE -bor $PROCESS_QUERY_INFO

$handle = [WotrNativeMemoryV7]::OpenProcess([UInt32]$access, $false, $pidValue)
if ($handle -eq [IntPtr]::Zero) {
    throw (Get-Win32ErrorText "OpenProcess")
}

$repairedCount = 0
$reusedAllocation = $false

try {
    [byte[]]$rawBefore = Read-RemoteBytes $handle $rawHookAddress $OriginalRawWheelHook.Length
    [byte[]]$mapBefore = Read-RemoteBytes $handle $mapHookAddress $OriginalMapHandler.Length
    [byte[]]$zoomBefore = Read-RemoteBytes $handle $zoomHookAddress $OriginalZoomUpdate.Length
    [byte[]]$cameraGlobalRefBefore = Read-RemoteBytes $handle $CameraGlobalRefAddress $ExpectedCameraGlobalRef.Length
    [byte[]]$cancelReleaseBefore = Read-RemoteBytes $handle $CancelReleaseAddress $ExpectedCancelRelease.Length

    if (-not (Test-Bytes $cameraGlobalRefBefore $ExpectedCameraGlobalRef)) {
        throw "AotR build changed the LivingWorld camera-global reference. V7 compatibility check failed before any write."
    }
    if (-not (Test-Bytes $cancelReleaseBefore $ExpectedCancelRelease)) {
        throw "AotR build changed the strategic cancel/release callback. V7 compatibility check failed before any write."
    }

    $existing = Get-ExistingV7Info $handle $rawHookAddress $rawBefore $mapHookAddress $mapBefore $zoomHookAddress $zoomBefore
    if ($null -ne $existing) {
        $blockAddress = $existing.BlockAddress
        $stateAddress = $existing.StateAddress
        $reusedAllocation = $true
    }
    else {
        $v6Installed = Test-ExistingV6Installation $handle $rawHookAddress $rawBefore $mapHookAddress $mapBefore $zoomHookAddress $zoomBefore
        $v5Installed = Test-ExistingV5Installation $handle $rawHookAddress $rawBefore $mapHookAddress $mapBefore $zoomHookAddress $zoomBefore
        $v4Installed = Test-ExistingV4Installation $handle $rawHookAddress $rawBefore $mapHookAddress $mapBefore
        $rawKnown = (
            (Test-Bytes $rawBefore $OriginalRawWheelHook) -or
            (Test-Bytes $rawBefore $V3RawWheelHook) -or
            $v6Installed -or
            $v5Installed -or
            $v4Installed
        )
        $mapKnown = (
            (Test-Bytes $mapBefore $OriginalMapHandler) -or
            (Test-Bytes $mapBefore $V2MapHandler) -or
            $v6Installed -or
            $v5Installed -or
            $v4Installed
        )
        $zoomKnown = (Test-Bytes $zoomBefore $OriginalZoomUpdate) -or $v6Installed -or $v5Installed
        if (-not $rawKnown) {
            throw ("Unbekannter Raw-Wheel-Hook bei VA 0x{0:X8}. Nichts geschrieben." -f $rawHookAddress.ToInt64())
        }
        if (-not $mapKnown) {
            throw ("Unbekannter Map-Handler bei VA 0x{0:X8}. Nichts geschrieben." -f $mapHookAddress.ToInt64())
        }
        if (-not $zoomKnown) {
            throw ("Unbekannter Zoom-Update-Hook bei VA 0x{0:X8}. Nichts geschrieben." -f $zoomHookAddress.ToInt64())
        }

        $MEM_COMMIT = 0x1000
        $MEM_RESERVE = 0x2000
        $PAGE_EXECUTE_READWRITE = 0x40
        $blockAddress = [WotrNativeMemoryV7]::VirtualAllocEx(
            $handle,
            [IntPtr]::Zero,
            [UIntPtr]::new([UInt32]$AllocationSize),
            [UInt32]($MEM_COMMIT -bor $MEM_RESERVE),
            [UInt32]$PAGE_EXECUTE_READWRITE
        )
        if ($blockAddress -eq [IntPtr]::Zero) {
            throw (Get-Win32ErrorText "VirtualAllocEx")
        }
        if (($blockAddress.ToInt64() -lt 0) -or ($blockAddress.ToInt64() -gt [UInt32]::MaxValue)) {
            throw "Unerwartete Remote-Adresse ausserhalb des 32-Bit-Adressraums."
        }

        $stateAddress = [IntPtr]($blockAddress.ToInt64() + $StateOffset)
        [byte[]]$payload = [byte[]]::new($AllocationSize)
        [byte[]]$runtimeShellcode = $ShellcodeTemplate.Clone()
        [UInt32]$stateAddress32 = [UInt32]($stateAddress.ToInt64())
        [byte[]]$statePointer = [BitConverter]::GetBytes($stateAddress32)
        Copy-Bytes $runtimeShellcode 0x0F $statePointer
        Copy-Bytes $runtimeShellcode 0x103 $statePointer
        Copy-Bytes $runtimeShellcode 0x510 $statePointer
        Copy-Bytes $runtimeShellcode 0x540 $statePointer
        Copy-Bytes $payload 0 $runtimeShellcode
        Copy-Bytes $payload ($StateOffset + $StateOneOffset) ([BitConverter]::GetBytes([single]1.0))
        Copy-Bytes $payload ($StateOffset + $StateQuarterOffset) ([BitConverter]::GetBytes([single]0.25))
        Copy-Bytes $payload ($StateOffset + $StateMarkerOffset) ([Text.Encoding]::ASCII.GetBytes("WZV7"))
        Copy-Bytes $payload ($StateOffset + $StateCursorValidOffset) ([BitConverter]::GetBytes([Int32]0))
        Write-RemoteBytes $handle $blockAddress $payload
        Flush-RemoteCode $handle $blockAddress $ShellcodeTemplate.Length
    }

    # Tuneable values can be changed by rerunning V7 in the same process.
    Write-RemoteBytes $handle ([IntPtr]($stateAddress.ToInt64() + $StateOneOffset)) ([BitConverter]::GetBytes([single]1.0))
    Write-RemoteBytes $handle ([IntPtr]($stateAddress.ToInt64() + $StateQuarterOffset)) ([BitConverter]::GetBytes([single]0.25))
    Write-RemoteBytes $handle ([IntPtr]($stateAddress.ToInt64() + $StateAnchorOffset)) ([BitConverter]::GetBytes([single]$AnchorGain))
    Write-RemoteBytes $handle ([IntPtr]($stateAddress.ToInt64() + $StateDragOffset)) ([BitConverter]::GetBytes([single]$DragSpeed))
    Write-RemoteBytes $handle ([IntPtr]($stateAddress.ToInt64() + 0x38)) ([BitConverter]::GetBytes([Int32]0))

    $rawStubAddress = [IntPtr]($blockAddress.ToInt64() + $RawStubOffset)
    $mapStubAddress = [IntPtr]($blockAddress.ToInt64() + $MapStubOffset)
    $zoomStubAddress = [IntPtr]($blockAddress.ToInt64() + $ZoomStubOffset)
    [byte[]]$expectedRawDetour = New-DetourBytes $rawHookAddress $rawStubAddress $OriginalRawWheelHook.Length
    [byte[]]$expectedMapDetour = New-DetourBytes $mapHookAddress $mapStubAddress $OriginalMapHandler.Length
    [byte[]]$expectedZoomDetour = New-DetourBytes $zoomHookAddress $zoomStubAddress $OriginalZoomUpdate.Length

    Write-RemoteBytes $handle $zoomHookAddress $expectedZoomDetour
    Flush-RemoteCode $handle $zoomHookAddress $expectedZoomDetour.Length
    Write-RemoteBytes $handle $mapHookAddress $expectedMapDetour
    Flush-RemoteCode $handle $mapHookAddress $expectedMapDetour.Length
    Write-RemoteBytes $handle $rawHookAddress $expectedRawDetour
    Flush-RemoteCode $handle $rawHookAddress $expectedRawDetour.Length

    [byte[]]$rawAfter = Read-RemoteBytes $handle $rawHookAddress $expectedRawDetour.Length
    [byte[]]$mapAfter = Read-RemoteBytes $handle $mapHookAddress $expectedMapDetour.Length
    [byte[]]$zoomAfter = Read-RemoteBytes $handle $zoomHookAddress $expectedZoomDetour.Length
    if ((-not (Test-Bytes $rawAfter $expectedRawDetour)) -or
        (-not (Test-Bytes $mapAfter $expectedMapDetour)) -or
        (-not (Test-Bytes $zoomAfter $expectedZoomDetour))) {
        throw "Runtime-Nachpruefung direkt nach der Installation fehlgeschlagen."
    }

    Write-Host ""
    Write-Host "[WAIT] Kurze 5-Sekunden-Nachpruefung der drei Runtime-Hooks ..."
    $stabilizeUntil = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $stabilizeUntil) {
        Start-Sleep -Milliseconds 500
        if ($null -eq (Get-Process -Id $pidValue -ErrorAction SilentlyContinue)) {
            throw "game.dat wurde waehrend der Stabilisierung beendet."
        }

        [byte[]]$currentRaw = Read-RemoteBytes $handle $rawHookAddress $expectedRawDetour.Length
        [byte[]]$currentMap = Read-RemoteBytes $handle $mapHookAddress $expectedMapDetour.Length
        [byte[]]$currentZoom = Read-RemoteBytes $handle $zoomHookAddress $expectedZoomDetour.Length
        $rawOk = Test-Bytes $currentRaw $expectedRawDetour
        $mapOk = Test-Bytes $currentMap $expectedMapDetour
        $zoomOk = Test-Bytes $currentZoom $expectedZoomDetour

        if ((-not $rawOk) -or (-not $mapOk) -or (-not $zoomOk)) {
            $rawRecoverable = $rawOk -or (Test-Bytes $currentRaw $OriginalRawWheelHook) -or (Test-Bytes $currentRaw $V3RawWheelHook)
            $mapRecoverable = $mapOk -or (Test-Bytes $currentMap $OriginalMapHandler) -or (Test-Bytes $currentMap $V2MapHandler)
            $zoomRecoverable = $zoomOk -or (Test-Bytes $currentZoom $OriginalZoomUpdate)
            if ((-not $rawRecoverable) -or (-not $mapRecoverable) -or (-not $zoomRecoverable)) {
                throw "Der Launcher hat einen Hook mit unbekannten Bytes ersetzt. Automatische Reparatur gestoppt."
            }

            Write-RemoteBytes $handle $zoomHookAddress $expectedZoomDetour
            Flush-RemoteCode $handle $zoomHookAddress $expectedZoomDetour.Length
            Write-RemoteBytes $handle $mapHookAddress $expectedMapDetour
            Flush-RemoteCode $handle $mapHookAddress $expectedMapDetour.Length
            Write-RemoteBytes $handle $rawHookAddress $expectedRawDetour
            Flush-RemoteCode $handle $rawHookAddress $expectedRawDetour.Length
            $repairedCount++
        }
    }

    [byte[]]$finalRaw = Read-RemoteBytes $handle $rawHookAddress $expectedRawDetour.Length
    [byte[]]$finalMap = Read-RemoteBytes $handle $mapHookAddress $expectedMapDetour.Length
    [byte[]]$finalZoom = Read-RemoteBytes $handle $zoomHookAddress $expectedZoomDetour.Length
    if ((-not (Test-Bytes $finalRaw $expectedRawDetour)) -or
        (-not (Test-Bytes $finalMap $expectedMapDetour)) -or
        (-not (Test-Bytes $finalZoom $expectedZoomDetour))) {
        throw "Abschliessende Runtime-Pruefung fehlgeschlagen."
    }
}
finally {
    [void][WotrNativeMemoryV7]::CloseHandle($handle)
}

Write-Host ""
Write-Host "[OK] AotR build passed all V7 runtime compatibility signatures."
Write-Host "[OK] SSE-sicherer Mauszeiger-Zoom-Lock und Linksklick-Ziehen V7 sind aktiv."
if ($reusedAllocation) {
    Write-Host "[OK] Vorhandene V7-Runtime-Installation erkannt und aktualisiert."
}
if ($repairedCount -gt 0) {
    Write-Host "[OK] Vom Launcher ersetzte Hooks automatisch repariert: $repairedCount"
}
else {
    Write-Host "[OK] Runtime-Hooks blieben waehrend der Launcher-Stabilisierung unveraendert."
}
Write-Host "  Prozess-ID          : $pidValue"
Write-Host "  ImageBase           : 0x$('{0:X8}' -f $imageBase.ToInt64())"
Write-Host "  Runtime-Block       : 0x$('{0:X8}' -f $blockAddress.ToInt64())"
Write-Host "  Raw-Wheel-Hook      : 0x$('{0:X8}' -f $rawHookAddress.ToInt64())"
Write-Host "  Map-Handler-Hook    : 0x$('{0:X8}' -f $mapHookAddress.ToInt64())"
Write-Host "  Zoom-Update-Hook    : 0x$('{0:X8}' -f $zoomHookAddress.ToInt64())"
Write-Host "  SSE-Rueckgabe        : XMM0=newZoom; XMM1/XMM2 unveraendert wie im Original"
Write-Host "  Hover               : echter Karten-Viewport / aufloesungsunabhaengig"
Write-Host "  Zoomanker           : aktuelle Mausposition pro Zoom-Frame, Gain $AnchorGain / SSE-Register originalgetreu"
Write-Host "  Ziehen               : Linksklick, Schwelle 5 px, Tempo $DragSpeed"
Write-Host "  Gebietsklick        : unter 5 px unveraendert"
Write-Host "  game.dat auf Disk   : UNVERAENDERT / ORIGINAL"
Write-Host "  Disk-SHA256         : $(Get-Sha256 $GameDat)"
Write-Host ""
Write-Host "JETZT TESTEN:"
Write-Host "  1. Mausrad ausserhalb der Karte: Es darf nichts passieren."
Write-Host "  2. Maus auf ein gut erkennbares Land am Kartenrand setzen und hineinzoomen."
Write-Host "     Das Land soll waehrend der gesamten Zoomanimation unter dem Zeiger bleiben - ohne Klick/Drag zum Nachfokussieren."
Write-Host "  3. Linksklick kurz: Gebiet muss weiterhin ausgewaehlt werden."
Write-Host "  4. Linksklick halten und rechts/unten ziehen: Karte soll links/oben wandern."
Write-Host "Der Runtime-Patch verschwindet automatisch beim Beenden des Spiels."
