#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$StartVa,
    [Parameter(Mandatory=$true)] [string]$EndVa,
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat',
    [string]$OutFile = "$env:USERPROFILE\AOTR_CODEX\OUTPUT\CANONICAL_VA_WINDOW.txt"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ImageBase = [uint32]0x00400000
$MaxWindow = 0x10000

function Parse-HexU32([string]$s) {
    $t = $s.Trim()
    if ($t.StartsWith('0x',[StringComparison]::OrdinalIgnoreCase)) { $t = $t.Substring(2) }
    if ($t -notmatch '^[0-9A-Fa-f]{1,8}$') { throw "BAD_HEX_U32: $s" }
    return [Convert]::ToUInt32($t,16)
}
function Read-U16([byte[]]$b,[int]$o) { [BitConverter]::ToUInt16($b,$o) }
function Read-U32([byte[]]$b,[int]$o) { [BitConverter]::ToUInt32($b,$o) }

$start = Parse-HexU32 $StartVa
$end   = Parse-HexU32 $EndVa
if ($end -le $start) { throw 'END_MUST_BE_GREATER_THAN_START' }
$length64 = [uint64]$end - [uint64]$start
if ($length64 -gt $MaxWindow) { throw "WINDOW_TOO_LARGE max=$MaxWindow requested=$length64" }
$length = [int]$length64

if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "GAME_DAT_MISSING: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "GAME_DAT_HASH_MISMATCH expected=$ExpectedHash actual=$hash" }

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
    $sections += [pscustomobject]@{ Name=$name; VirtualSize=$virtualSize; RVA=$virtualAddress; RawSize=$rawSize; RawPtr=$rawPtr }
}

function Va-To-Raw([uint32]$va) {
    if ($va -lt $ImageBase) { throw ('VA_BELOW_IMAGEBASE 0x{0:X8}' -f $va) }
    $rva = [uint32]($va - $ImageBase)
    foreach ($s in $sections) {
        $span = [Math]::Max([uint64]$s.VirtualSize,[uint64]$s.RawSize)
        if ([uint64]$rva -ge [uint64]$s.RVA -and [uint64]$rva -lt ([uint64]$s.RVA + $span)) {
            $delta = [uint64]$rva - [uint64]$s.RVA
            if ($delta -ge [uint64]$s.RawSize) { throw ('VA_NOT_BACKED_BY_RAW_DATA va=0x{0:X8} section={1}' -f $va,$s.Name) }
            return [pscustomobject]@{ Raw=[uint64]$s.RawPtr + $delta; Section=$s.Name; RVA=$rva }
        }
    }
    throw ('VA_NOT_MAPPED 0x{0:X8}' -f $va)
}

$mapStart = Va-To-Raw $start
$mapEndLast = Va-To-Raw ([uint32]($end - 1))
if ($mapStart.Section -ne $mapEndLast.Section) { throw 'WINDOW_CROSSES_SECTION_BOUNDARY' }
if (($mapStart.Raw + [uint64]$length) -gt [uint64]$bytes.Length) { throw 'WINDOW_OUT_OF_FILE' }

$parent = Split-Path -Parent $OutFile
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

$sb = [Text.StringBuilder]::new()
[void]$sb.AppendLine('AOTR CANONICAL VA WINDOW EXPORT')
[void]$sb.AppendLine(('Generated={0}' -f (Get-Date -Format o)))
[void]$sb.AppendLine(('GameDat={0}' -f $GameDat))
[void]$sb.AppendLine(('SHA256={0}' -f $hash))
[void]$sb.AppendLine(('VA_START=0x{0:X8}' -f $start))
[void]$sb.AppendLine(('VA_END_EXCLUSIVE=0x{0:X8}' -f $end))
[void]$sb.AppendLine(('LENGTH={0}' -f $length))
[void]$sb.AppendLine(('SECTION={0}' -f $mapStart.Section))
[void]$sb.AppendLine(('RAW_START=0x{0:X8}' -f $mapStart.Raw))
[void]$sb.AppendLine('MODE=READ_ONLY_BINARY_EXPORT')
[void]$sb.AppendLine('PYTHON_REQUIRED=NO')
[void]$sb.AppendLine('EXTERNAL_TOOLS_REQUIRED=NO')
[void]$sb.AppendLine('')

for ($off=0; $off -lt $length; $off += 16) {
    $count = [Math]::Min(16,$length-$off)
    $raw = [int]($mapStart.Raw + [uint64]$off)
    $slice = $bytes[$raw..($raw+$count-1)]
    $hex = ($slice | ForEach-Object { $_.ToString('X2') }) -join ' '
    [void]$sb.AppendLine(('{0:X8}: {1}' -f ([uint32]($start + $off)),$hex))
}

[IO.File]::WriteAllText($OutFile,$sb.ToString(),[Text.UTF8Encoding]::new($false))
$outHash = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToUpperInvariant()
$outSize = (Get-Item -LiteralPath $OutFile).Length

Write-Host '============================================================'
Write-Host ' AOTR CANONICAL VA WINDOW EXPORT'
Write-Host '============================================================'
Write-Host 'GAME_DAT_HASH_OK=YES'
Write-Host ('VA_START=0x{0:X8}' -f $start)
Write-Host ('VA_END_EXCLUSIVE=0x{0:X8}' -f $end)
Write-Host "LENGTH=$length"
Write-Host "OUTPUT=$OutFile"
Write-Host "OUTPUT_SIZE=$outSize"
Write-Host "OUTPUT_SHA256=$outHash"
Write-Host 'MODE=READ_ONLY_BINARY_EXPORT'
Write-Host 'PYTHON_REQUIRED=NO'
Write-Host 'EXTERNAL_TOOLS_REQUIRED=NO'
Write-Host 'RESULT=PASS_CANONICAL_VA_WINDOW_EXPORTED' -ForegroundColor Green
