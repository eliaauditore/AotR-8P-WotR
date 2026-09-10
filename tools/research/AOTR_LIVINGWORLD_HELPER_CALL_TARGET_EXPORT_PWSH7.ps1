#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat',
    [string]$OutFile = "$env:USERPROFILE\AOTR_CODEX\OUTPUT\LIVINGWORLD_HELPER_CALL_TARGET.txt"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ImageBase = [uint32]0x00400000
$DispStart = [uint32]0x005FF9E3
$DispEndExclusive = [uint32]0x005FF9E7
$NextInstruction = [uint32]0x005FF9E7

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
    $name = ([Text.Encoding]::ASCII.GetString($bytes[$o..($o+7)])).Trim([char]0)
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

$map = Va-To-Raw $DispStart
$length = [int]($DispEndExclusive - $DispStart)
if ($length -ne 4) { throw 'INTERNAL_RANGE_LENGTH_ERROR' }
if (($map.Raw + [uint64]$length) -gt [uint64]$bytes.Length) { throw 'RANGE_OUT_OF_FILE' }

$raw = [int]$map.Raw
$dispBytes = [byte[]]$bytes[$raw..($raw+3)]
$rel32 = [BitConverter]::ToInt32($dispBytes,0)
$target64 = [int64]$NextInstruction + [int64]$rel32
if ($target64 -lt 0 -or $target64 -gt [uint32]::MaxValue) {
    throw "CALL_TARGET_OUT_OF_32BIT_RANGE: $target64"
}
$target = [uint32]$target64
$hex = ($dispBytes | ForEach-Object { $_.ToString('X2') }) -join ' '

$parent = Split-Path -Parent $OutFile
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

$content = @"
AOTR LIVINGWORLD HELPER CALL TARGET EXPORT
Generated=$(Get-Date -Format o)
GameDat=$GameDat
SHA256=$hash
MODE=READ_ONLY_BINARY_EXPORT
PYTHON_REQUIRED=NO
EXTERNAL_TOOLS_REQUIRED=NO

CALL_OPCODE_VA=0x005FF9E2
DISPLACEMENT_RANGE=0x005FF9E3-0x005FF9E7
SECTION=$($map.Section)
DISPLACEMENT_BYTES=$hex
REL32_SIGNED=$rel32
NEXT_INSTRUCTION_VA=0x005FF9E7
CALL_TARGET_VA=$('0x{0:X8}' -f $target)
"@

[IO.File]::WriteAllText($OutFile,$content,[Text.UTF8Encoding]::new($false))
$outHash = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToUpperInvariant()
$outSize = (Get-Item -LiteralPath $OutFile).Length

Write-Host '============================================================'
Write-Host ' AOTR LIVINGWORLD HELPER CALL TARGET EXPORT'
Write-Host '============================================================'
Write-Host 'GAME_DAT_HASH_OK=YES'
Write-Host "GAME_DAT_SHA256=$hash"
Write-Host "DISPLACEMENT_BYTES=$hex"
Write-Host "REL32_SIGNED=$rel32"
Write-Host ('CALL_TARGET_VA=0x{0:X8}' -f $target)
Write-Host "OUTPUT=$OutFile"
Write-Host "OUTPUT_SIZE=$outSize"
Write-Host "OUTPUT_SHA256=$outHash"
Write-Host 'MODE=READ_ONLY_BINARY_EXPORT'
Write-Host 'PYTHON_REQUIRED=NO'
Write-Host 'EXTERNAL_TOOLS_REQUIRED=NO'
Write-Host 'RESULT=PASS_HELPER_CALL_TARGET_EXPORTED' -ForegroundColor Green
