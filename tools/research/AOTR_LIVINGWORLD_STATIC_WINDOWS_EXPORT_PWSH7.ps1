#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat',
    [string]$OutFile = "$env:USERPROFILE\AOTR_CODEX\OUTPUT\LIVINGWORLD_STATIC_WINDOWS.txt"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ImageBase = [uint32]0x00400000

function Read-U16([byte[]]$b,[int]$o) { [BitConverter]::ToUInt16($b,$o) }
function Read-U32([byte[]]$b,[int]$o) { [BitConverter]::ToUInt32($b,$o) }

if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) {
    throw "GAME_DAT_MISSING: $GameDat"
}

$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) {
    throw "GAME_DAT_HASH_MISMATCH expected=$ExpectedHash actual=$hash"
}

$bytes = [IO.File]::ReadAllBytes($GameDat)
if ($bytes.Length -lt 0x1000) { throw 'GAME_DAT_TOO_SMALL' }
if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { throw 'NOT_MZ' }

$pe = [int](Read-U32 $bytes 0x3C)
if ($pe -lt 0 -or ($pe + 0x100) -ge $bytes.Length) { throw 'BAD_PE_OFFSET' }
if ($bytes[$pe] -ne 0x50 -or $bytes[$pe+1] -ne 0x45 -or $bytes[$pe+2] -ne 0 -or $bytes[$pe+3] -ne 0) { throw 'NOT_PE' }

$coff = $pe + 4
$sectionCount = [int](Read-U16 $bytes ($coff + 2))
$optSize = [int](Read-U16 $bytes ($coff + 16))
$sectionTable = $coff + 20 + $optSize

$sections = @()
for ($i=0; $i -lt $sectionCount; $i++) {
    $o = $sectionTable + (40 * $i)
    $nameBytes = $bytes[$o..($o+7)]
    $name = ([Text.Encoding]::ASCII.GetString($nameBytes)).Trim([char]0)
    $virtualSize = [uint32](Read-U32 $bytes ($o + 8))
    $virtualAddress = [uint32](Read-U32 $bytes ($o + 12))
    $rawSize = [uint32](Read-U32 $bytes ($o + 16))
    $rawPtr = [uint32](Read-U32 $bytes ($o + 20))
    $sections += [pscustomobject]@{
        Name=$name; VirtualSize=$virtualSize; RVA=$virtualAddress; RawSize=$rawSize; RawPtr=$rawPtr
    }
}

function Va-To-Raw([uint32]$va) {
    if ($va -lt $ImageBase) { throw ('VA_BELOW_IMAGEBASE 0x{0:X8}' -f $va) }
    $rva = [uint32]($va - $ImageBase)
    foreach ($s in $sections) {
        $span = [Math]::Max([uint64]$s.VirtualSize,[uint64]$s.RawSize)
        if ([uint64]$rva -ge [uint64]$s.RVA -and [uint64]$rva -lt ([uint64]$s.RVA + $span)) {
            $delta = [uint64]$rva - [uint64]$s.RVA
            if ($delta -ge [uint64]$s.RawSize) {
                throw ('VA_NOT_BACKED_BY_RAW_DATA va=0x{0:X8} section={1}' -f $va,$s.Name)
            }
            return [pscustomobject]@{
                Raw=[uint64]$s.RawPtr + $delta
                Section=$s.Name
                RVA=$rva
            }
        }
    }
    throw ('VA_NOT_MAPPED 0x{0:X8}' -f $va)
}

$windows = @(
    [pscustomobject]@{ Name='LivingWorld setup / GameInfo selection'; Start=[uint32]0x00932E80; End=[uint32]0x00933140 },
    [pscustomobject]@{ Name='C54 local-slot override + helper'; Start=[uint32]0x0084A380; End=[uint32]0x0084A4C0 },
    [pscustomobject]@{ Name='LivingWorldPlayer factory wrapper'; Start=[uint32]0x006BB350; End=[uint32]0x006BB4D0 },
    [pscustomobject]@{ Name='LivingWorldPlayer constructor target'; Start=[uint32]0x006E3C40; End=[uint32]0x006E3F00 },
    [pscustomobject]@{ Name='Local LivingWorldPlayer setter'; Start=[uint32]0x006B42B0; End=[uint32]0x006B4380 }
)

$parent = Split-Path -Parent $OutFile
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

$sb = [Text.StringBuilder]::new()
[void]$sb.AppendLine('AOTR LIVINGWORLD STATIC WINDOWS EXPORT')
[void]$sb.AppendLine(('Generated={0}' -f (Get-Date -Format o)))
[void]$sb.AppendLine(('GameDat={0}' -f $GameDat))
[void]$sb.AppendLine(('SHA256={0}' -f $hash))
[void]$sb.AppendLine(('Length={0}' -f $bytes.Length))
[void]$sb.AppendLine(('ImageBase=0x{0:X8}' -f $ImageBase))
[void]$sb.AppendLine('MODE=READ_ONLY_BINARY_EXPORT')
[void]$sb.AppendLine('PYTHON_REQUIRED=NO')
[void]$sb.AppendLine('EXTERNAL_TOOLS_REQUIRED=NO')
[void]$sb.AppendLine('')

foreach ($w in $windows) {
    if ($w.End -le $w.Start) { throw "BAD_WINDOW $($w.Name)" }
    $map = Va-To-Raw $w.Start
    $length = [int]($w.End - $w.Start)
    if (($map.Raw + [uint64]$length) -gt [uint64]$bytes.Length) { throw "WINDOW_OUT_OF_FILE $($w.Name)" }

    [void]$sb.AppendLine(('===== {0} =====' -f $w.Name))
    [void]$sb.AppendLine(('VA_START=0x{0:X8}' -f $w.Start))
    [void]$sb.AppendLine(('VA_END_EXCLUSIVE=0x{0:X8}' -f $w.End))
    [void]$sb.AppendLine(('SECTION={0}' -f $map.Section))
    [void]$sb.AppendLine(('RAW_START=0x{0:X8}' -f $map.Raw))

    for ($off=0; $off -lt $length; $off += 16) {
        $count = [Math]::Min(16,$length-$off)
        $raw = [int]($map.Raw + [uint64]$off)
        $slice = $bytes[$raw..($raw+$count-1)]
        $hex = ($slice | ForEach-Object { $_.ToString('X2') }) -join ' '
        [void]$sb.AppendLine(('{0:X8}: {1}' -f ([uint32]($w.Start + $off)),$hex))
    }
    [void]$sb.AppendLine('')
}

[IO.File]::WriteAllText($OutFile,$sb.ToString(),[Text.UTF8Encoding]::new($false))
$outHash = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToUpperInvariant()
$outSize = (Get-Item -LiteralPath $OutFile).Length

Write-Host '============================================================'
Write-Host ' AOTR LIVINGWORLD STATIC WINDOWS EXPORT'
Write-Host '============================================================'
Write-Host "GAME_DAT_HASH_OK=YES"
Write-Host "GAME_DAT_SHA256=$hash"
Write-Host "OUTPUT=$OutFile"
Write-Host "OUTPUT_SIZE=$outSize"
Write-Host "OUTPUT_SHA256=$outHash"
Write-Host 'MODE=READ_ONLY_BINARY_EXPORT'
Write-Host 'PYTHON_REQUIRED=NO'
Write-Host 'EXTERNAL_TOOLS_REQUIRED=NO'
Write-Host 'RESULT=PASS_STATIC_WINDOWS_EXPORTED' -ForegroundColor Green
