param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Finds literal references to the known TheGameInfo global in the exact AotR game.dat.
# The static image VA is 0x00DE7D6C (ImageBase 0x00400000, RVA 0x009E7D6C).
# No process memory is opened or modified.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$TargetVA = [uint32]0x00DE7D6C

if (-not (Test-Path -LiteralPath $GameDat)) {
    throw "game.dat not found: $GameDat"
}

$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) {
    throw "HASH MISMATCH. Expected $ExpectedHash, got $hash"
}

[byte[]]$b = [System.IO.File]::ReadAllBytes($GameDat)

function U16([int]$o) { [BitConverter]::ToUInt16($b,$o) }
function U32([int]$o) { [BitConverter]::ToUInt32($b,$o) }

if ((U16 0) -ne 0x5A4D) { throw 'Not an MZ image.' }
$pe = [int](U32 0x3C)
if ((U32 $pe) -ne 0x00004550) { throw 'Invalid PE signature.' }

$numSections = [int](U16 ($pe + 6))
$optSize = [int](U16 ($pe + 20))
$opt = $pe + 24
$imageBase = [uint32](U32 ($opt + 28))
$secTable = $opt + $optSize

$sections = @()
for ($i=0; $i -lt $numSections; $i++) {
    $s = $secTable + ($i * 40)
    $nameBytes = $b[$s..($s+7)]
    $name = ([Text.Encoding]::ASCII.GetString($nameBytes)).Trim([char]0)
    $vs = [uint32](U32 ($s+8))
    $rva = [uint32](U32 ($s+12))
    $rawSize = [uint32](U32 ($s+16))
    $rawPtr = [uint32](U32 ($s+20))
    $sections += [pscustomobject]@{ Name=$name; RVA=$rva; VS=$vs; RawSize=$rawSize; RawPtr=$rawPtr }
}

function Raw-To-VA([int64]$raw) {
    foreach ($s in $sections) {
        if ($raw -ge $s.RawPtr -and $raw -lt ([int64]$s.RawPtr + $s.RawSize)) {
            return [uint32]($imageBase + $s.RVA + ($raw - $s.RawPtr))
        }
    }
    return [uint32]0
}

function Raw-To-Section([int64]$raw) {
    foreach ($s in $sections) {
        if ($raw -ge $s.RawPtr -and $raw -lt ([int64]$s.RawPtr + $s.RawSize)) { return $s.Name }
    }
    return '<none>'
}

function Hex-Context([int]$center,[int]$before=32,[int]$after=32) {
    $lo = [Math]::Max(0,$center-$before)
    $hi = [Math]::Min($b.Length-1,$center+$after)
    (($b[$lo..$hi] | ForEach-Object { $_.ToString('X2') }) -join ' ')
}

$needle = [BitConverter]::GetBytes($TargetVA)
$hits = New-Object System.Collections.Generic.List[int]
for ($i=0; $i -le $b.Length-4; $i++) {
    if ($b[$i] -eq $needle[0] -and $b[$i+1] -eq $needle[1] -and $b[$i+2] -eq $needle[2] -and $b[$i+3] -eq $needle[3]) {
        $hits.Add($i)
    }
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR THEGAMEINFO GLOBAL XREF PROBE - DISK ONLY'
Write-Host '============================================================'
Write-Host ("Image      : {0}" -f $GameDat)
Write-Host ("SHA256     : {0}" -f $hash)
Write-Host ("ImageBase  : 0x{0:X8}" -f $imageBase)
Write-Host ("TheGameInfo: VA 0x{0:X8} RVA 0x{1:X8}" -f $TargetVA, ($TargetVA-$imageBase))
Write-Host ("Literal refs: {0}" -f $hits.Count)
Write-Host ''

$n=0
foreach ($raw in $hits) {
    $n++
    $va = Raw-To-VA $raw
    $sec = Raw-To-Section $raw
    $tag = if ($sec -eq '.text') { 'CODE-XREF-CANDIDATE' } else { 'DATA-XREF' }
    Write-Host ("HIT #{0}: raw=0x{1:X8} VA=0x{2:X8} section={3} {4}" -f $n,$raw,$va,$sec,$tag)
    Write-Host ("  context: {0}" -f (Hex-Context $raw 32 32))
}

Write-Host ''
Write-Host 'Interpretation:'
Write-Host '  - .text hits are direct code references to TheGameInfo global.'
Write-Host '  - Nearby opcodes determine whether the site reads, writes, clears, or publishes the pointer.'
Write-Host '  - This probe does not patch or execute the target binary.'
Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
