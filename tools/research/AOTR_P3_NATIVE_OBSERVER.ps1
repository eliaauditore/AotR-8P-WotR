param(
    [int]$ProcessId = 0,
    [int]$IntervalMs = 250,
    [string]$CsvPath = "",
    [switch]$Once
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# AotR 8P WotR native P3 observer
# READ-ONLY: this script never calls WriteProcessMemory.
#
# Supported engine baseline:
#   game.dat size   11,347,456 bytes
#   SHA256          CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC
#
# Static-analysis anchors in this build:
#   GameInfo* global             VA 0x00DE7D6C / RVA 0x009E7D6C
#   TheLivingWorldLogic* global  VA 0x00DE4950 / RVA 0x009E4950
#   PlayerInfo slot array        GameInfo + 0x18, 8 pointers
#   PlayerType                   PlayerInfo + 0x04
#   Network identity DWORD       PlayerInfo/GameInfo + 0x38
#   Network identity WORD        PlayerInfo/GameInfo + 0x3C
#   LivingWorld player vector    TheLivingWorldLogic + 0x8C/+0x90
#   Current local LW player      TheLivingWorldLogic + 0x98
#   LivingWorldPlayer unique ID  LivingWorldPlayer + 0x14
#
# Known runtime 8P bytes:
#   RVA 0x00440A91 : 06 -> 08 (InitGadgets/player slots)
#   RVA 0x0044692B : 06 -> 08 (Strategic player rows/loop)

$ExpectedHash = "CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC"

$RvaGameInfoGlobal       = [int64]0x009E7D6C
$RvaLivingWorldGlobal    = [int64]0x009E4950
$RvaPatchInitGadgets     = [int64]0x00440A91
$RvaPatchStrategicRows   = [int64]0x0044692B

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class AotrReadOnlyMemory
{
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(
        UInt32 dwDesiredAccess,
        bool bInheritHandle,
        UInt32 dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ReadProcessMemory(
        IntPtr hProcess,
        IntPtr lpBaseAddress,
        byte[] lpBuffer,
        UIntPtr nSize,
        out UIntPtr lpNumberOfBytesRead);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@

function Resolve-GameProcess {
    param([int]$RequestedId)

    if ($RequestedId -gt 0) {
        return Get-Process -Id $RequestedId -ErrorAction Stop
    }

    $candidates = @(
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessName -like "game*" }
    )

    if ($candidates.Count -eq 0) {
        throw "No running game process found. Start AotR first, or pass -ProcessId <PID>."
    }

    if ($candidates.Count -eq 1) {
        return $candidates[0]
    }

    $described = $candidates | ForEach-Object {
        $path = $null
        try { $path = $_.MainModule.FileName } catch {}
        "PID=$($_.Id) Name=$($_.ProcessName) Path=$path"
    }

    throw "Multiple game-like processes found. Re-run with -ProcessId <PID>. Candidates:`n$($described -join "`n")"
}

function Read-Bytes {
    param(
        [IntPtr]$Handle,
        [int64]$Address,
        [int]$Count
    )

    $buffer = New-Object byte[] $Count
    $read = [UIntPtr]::Zero
    $ok = [AotrReadOnlyMemory]::ReadProcessMemory(
        $Handle,
        [IntPtr]$Address,
        $buffer,
        [UIntPtr]$Count,
        [ref]$read
    )

    if (-not $ok -or $read.ToUInt64() -ne [uint64]$Count) {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ("ReadProcessMemory failed at 0x{0:X8} count={1} Win32={2}" -f $Address, $Count, $err)
    }

    return $buffer
}

function Read-U8 {
    param([IntPtr]$Handle, [int64]$Address)
    return [byte](Read-Bytes $Handle $Address 1)[0]
}

function Read-U16 {
    param([IntPtr]$Handle, [int64]$Address)
    $b = Read-Bytes $Handle $Address 2
    return [BitConverter]::ToUInt16($b, 0)
}

function Read-U32 {
    param([IntPtr]$Handle, [int64]$Address)
    $b = Read-Bytes $Handle $Address 4
    return [BitConverter]::ToUInt32($b, 0)
}

function Format-Ptr {
    param([uint32]$Value)
    return ("0x{0:X8}" -f $Value)
}

function Format-IPv4 {
    param([uint32]$Value)
    # The engine compares loopback against numeric 0x7F000001, so render MSB first.
    return "{0}.{1}.{2}.{3}" -f `
        (($Value -shr 24) -band 0xFF), `
        (($Value -shr 16) -band 0xFF), `
        (($Value -shr 8)  -band 0xFF), `
        ($Value -band 0xFF)
}

function Safe-U8 {
    param([IntPtr]$Handle, [int64]$Address, [byte]$Default = 0)
    try { return Read-U8 $Handle $Address } catch { return $Default }
}

function Safe-U16 {
    param([IntPtr]$Handle, [int64]$Address, [uint16]$Default = 0)
    try { return Read-U16 $Handle $Address } catch { return $Default }
}

function Safe-U32 {
    param([IntPtr]$Handle, [int64]$Address, [uint32]$Default = 0)
    try { return Read-U32 $Handle $Address } catch { return $Default }
}

$proc = Resolve-GameProcess -RequestedId $ProcessId

try {
    $exePath = $proc.MainModule.FileName
    $base = $proc.MainModule.BaseAddress.ToInt64()
}
catch {
    throw "Could not inspect the game module. Run PowerShell at the same/elevated integrity level as the game. $($_.Exception.Message)"
}

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Process image path does not exist: $exePath"
}

$hash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) {
    throw @"
Unsupported game.dat build.
Expected: $ExpectedHash
Actual:   $hash
Path:     $exePath

Observer aborted intentionally so addresses from another binary are never used blindly.
"@
}

if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $CsvPath = Join-Path (Get-Location) "AOTR_P3_NATIVE_OBSERVER_$stamp.csv"
}

$PROCESS_VM_READ = [uint32]0x0010
$PROCESS_QUERY_INFORMATION = [uint32]0x0400
$access = $PROCESS_VM_READ -bor $PROCESS_QUERY_INFORMATION

$handle = [AotrReadOnlyMemory]::OpenProcess($access, $false, [uint32]$proc.Id)
if ($handle -eq [IntPtr]::Zero) {
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "OpenProcess failed for PID $($proc.Id), Win32=$err"
}

Write-Host ""
Write-Host "============================================================"
Write-Host " AOTR P3 NATIVE NETWORK -> LIVINGWORLD OBSERVER"
Write-Host " READ ONLY - no memory writes"
Write-Host "============================================================"
Write-Host ("PID              : {0}" -f $proc.Id)
Write-Host ("Image            : {0}" -f $exePath)
Write-Host ("SHA256           : {0}" -f $hash)
Write-Host ("Module base      : 0x{0:X8}" -f $base)
Write-Host ("CSV              : {0}" -f $CsvPath)

try {
    $patchA = Read-U8 $handle ($base + $RvaPatchInitGadgets)
    $patchB = Read-U8 $handle ($base + $RvaPatchStrategicRows)

    Write-Host ("Runtime byte A   : RVA 0x00440A91 = 0x{0:X2} (8P expected: 08)" -f $patchA)
    Write-Host ("Runtime byte B   : RVA 0x0044692B = 0x{0:X2} (8P expected: 08)" -f $patchB)

    if ($patchA -ne 0x08 -or $patchB -ne 0x08) {
        Write-Warning "The known 8P runtime bytes are not both 08. The observer will continue read-only, but this is not the expected active 8P runtime."
    }

    Write-Host ""
    Write-Host "Expected P3 proof on PC3:"
    Write-Host "  LocalSlot = 2"
    Write-Host "  Slot2 Type = 6"
    Write-Host "  Slot2 endpoint = LocalEndpoint"
    Write-Host "  LWCurrent != 0 after LivingWorld creation"
    Write-Host ""
    Write-Host "Press Ctrl+C to stop."
    Write-Host ""

    $lastSignature = $null
    $csvInitialized = Test-Path -LiteralPath $CsvPath

    while ($true) {
        $now = Get-Date
        $gameInfo = Safe-U32 $handle ($base + $RvaGameInfoGlobal)
        $lwLogic  = Safe-U32 $handle ($base + $RvaLivingWorldGlobal)

        $gameInfoActive = 0
        $gameInfoStarted = 0
        $gameInfoMode = 0
        $localIp = [uint32]0
        $localPort = [uint16]0
        $localSlot = -1
        $slotText = @()

        if ($gameInfo -ne 0) {
            $gameInfoActive  = Safe-U8  $handle ([int64]$gameInfo + 0x10)
            $gameInfoStarted = Safe-U8  $handle ([int64]$gameInfo + 0x11)
            $gameInfoMode    = Safe-U32 $handle ([int64]$gameInfo + 0x5C)
            $localIp         = Safe-U32 $handle ([int64]$gameInfo + 0x38)
            $localPort       = Safe-U16 $handle ([int64]$gameInfo + 0x3C)

            for ($i = 0; $i -lt 8; $i++) {
                $playerPtr = Safe-U32 $handle ([int64]$gameInfo + 0x18 + (4 * $i))
                if ($playerPtr -eq 0) {
                    $slotText += "${i}:EMPTY"
                    continue
                }

                $type = Safe-U32 $handle ([int64]$playerPtr + 0x04)
                $ip   = Safe-U32 $handle ([int64]$playerPtr + 0x38)
                $port = Safe-U16 $handle ([int64]$playerPtr + 0x3C)

                $isLocal = (
                    $type -eq 6 -and
                    $ip -eq $localIp -and
                    $port -eq $localPort
                )

                if ($isLocal) {
                    $localSlot = $i
                }

                $mark = if ($isLocal) { "*" } else { "" }
                if ($type -eq 6) {
                    $slotText += ("{0}:T6:{1}:{2}{3}" -f $i, (Format-IPv4 $ip), $port, $mark)
                }
                else {
                    $slotText += ("{0}:T{1}{2}" -f $i, $type, $mark)
                }
            }
        }

        $lwBegin = [uint32]0
        $lwEnd = [uint32]0
        $lwCurrent = [uint32]0
        $lwCount = 0
        $lwCurrentVectorIndex = -1
        $lwCurrentId = [uint32]0
        $lwVectorText = @()

        if ($lwLogic -ne 0) {
            $lwBegin   = Safe-U32 $handle ([int64]$lwLogic + 0x8C)
            $lwEnd     = Safe-U32 $handle ([int64]$lwLogic + 0x90)
            $lwCurrent = Safe-U32 $handle ([int64]$lwLogic + 0x98)

            if ($lwBegin -ne 0 -and $lwEnd -ge $lwBegin) {
                $delta = [uint64]$lwEnd - [uint64]$lwBegin
                if (($delta % 4) -eq 0 -and $delta -le 0x100) {
                    $lwCount = [int]($delta / 4)
                    for ($i = 0; $i -lt $lwCount; $i++) {
                        $p = Safe-U32 $handle ([int64]$lwBegin + (4 * $i))
                        $id = if ($p -ne 0) { Safe-U32 $handle ([int64]$p + 0x14) } else { [uint32]0 }
                        if ($p -eq $lwCurrent -and $p -ne 0) {
                            $lwCurrentVectorIndex = $i
                        }
                        $lwVectorText += ("{0}:{1}/ID{2}" -f $i, (Format-Ptr $p), $id)
                    }
                }
            }

            if ($lwCurrent -ne 0) {
                $lwCurrentId = Safe-U32 $handle ([int64]$lwCurrent + 0x14)
            }
        }

        $localEndpoint = if ($gameInfo -ne 0) {
            "{0}:{1}" -f (Format-IPv4 $localIp), $localPort
        } else {
            ""
        }

        $phase = if ($lwCurrent -ne 0) {
            "LIVINGWORLD_LOCAL_SET"
        }
        elseif ($lwLogic -ne 0) {
            "LIVINGWORLD_NO_LOCAL_YET"
        }
        elseif ($gameInfo -ne 0) {
            "GAMEINFO"
        }
        else {
            "NO_GAMEINFO"
        }

        $row = [pscustomobject]@{
            Timestamp              = $now.ToString("o")
            Phase                  = $phase
            RuntimeByte440A91      = ("0x{0:X2}" -f $patchA)
            RuntimeByte44692B      = ("0x{0:X2}" -f $patchB)
            GameInfo               = (Format-Ptr $gameInfo)
            GameInfoActive         = $gameInfoActive
            GameInfoByte11         = $gameInfoStarted
            GameInfoField5C        = $gameInfoMode
            LocalEndpoint          = $localEndpoint
            LocalSlot              = $localSlot
            Slots                  = ($slotText -join " | ")
            LivingWorldLogic       = (Format-Ptr $lwLogic)
            LWVectorBegin          = (Format-Ptr $lwBegin)
            LWVectorEnd            = (Format-Ptr $lwEnd)
            LWCount                = $lwCount
            LWCurrent              = (Format-Ptr $lwCurrent)
            LWCurrentVectorIndex   = $lwCurrentVectorIndex
            LWCurrentId            = $lwCurrentId
            LWVector               = ($lwVectorText -join " | ")
        }

        $signature = @(
            $row.Phase,
            $row.GameInfo,
            $row.GameInfoActive,
            $row.GameInfoByte11,
            $row.GameInfoField5C,
            $row.LocalEndpoint,
            $row.LocalSlot,
            $row.Slots,
            $row.LivingWorldLogic,
            $row.LWCount,
            $row.LWCurrent,
            $row.LWCurrentVectorIndex,
            $row.LWCurrentId,
            $row.LWVector
        ) -join "||"

        if ($signature -ne $lastSignature) {
            $lastSignature = $signature

            Write-Host ("[{0}] Phase={1} LocalSlot={2} GameInfo={3} LW={4} Current={5} CurrentID={6}" -f `
                $now.ToString("HH:mm:ss.fff"),
                $phase,
                $localSlot,
                (Format-Ptr $gameInfo),
                (Format-Ptr $lwLogic),
                (Format-Ptr $lwCurrent),
                $lwCurrentId)

            if ($gameInfo -ne 0) {
                Write-Host ("  LocalEndpoint: {0}" -f $localEndpoint)
                Write-Host ("  Slots: {0}" -f ($slotText -join " | "))
            }

            if ($lwLogic -ne 0) {
                Write-Host ("  LWVector[{0}]: {1}" -f $lwCount, ($lwVectorText -join " | "))
            }

            if (-not $csvInitialized) {
                $row | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
                $csvInitialized = $true
            }
            else {
                $row | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8 -Append
            }
        }

        if ($Once) {
            break
        }

        Start-Sleep -Milliseconds ([Math]::Max(50, $IntervalMs))
    }
}
finally {
    if ($handle -ne [IntPtr]::Zero) {
        [void][AotrReadOnlyMemory]::CloseHandle($handle)
    }
}
