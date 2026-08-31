param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Finds literal references to the secondary GameInfo-related global observed at runtime:
#   0x00DE892C == live pre-start network-GameInfo-derived object
# while TheGameInfo 0x00DE7D6C is still NULL.
# This script only reports literal references and surrounding bytes.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$TargetVA = [uint32]0x00DE892C

if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

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
    $name = ([Text.Encoding]::ASCII.GetString($b[$s..($s+7)])).Trim([char]0)
    $sections += [pscustomobject]@{
        Name=$name; RVA=[uint32](U32 ($s+12)); RawSize=[uint32](U32 ($s+16)); RawPtr=[uint32](U32 ($s+20))
    }
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
function Hex-Context([int]$center,[int]$before=40,[int]$after=40) {
    $lo = [Math]::Max(0,$center-$before)
    $hi = [Math]::Min($b.Length-1,$center+$after)
    (($b[$lo..$hi] | ForEach-Object { $_.ToString('X2') }) -join ' ')
}

$needle = [BitConverter]::GetBytes($TargetVA)
$hits = New-Object System.Collections.Generic.List[int]
for ($i=0; $i -le $b.Length-4; $i++) {
    if ($b[$i] -eq $needle[0] -and $b[$i+1] -eq $needle[1] -and $b[$i+2] -eq $needle[2] -and $b[$i+3] -eq $needle[3]) { $hits.Add($i) }
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR SECONDARY GAMEINFO GLOBAL XREF PROBE - DISK ONLY'
Write-Host '============================================================'
Write-Host ("Image      : {0}" -f $GameDat)
Write-Host ("SHA256     : {0}" -f $hash)
Write-Host ("ImageBase  : 0x{0:X8}" -f $imageBase)
Write-Host ("Target     : VA 0x{0:X8} RVA 0x{1:X8}" -f $TargetVA, ($TargetVA-$imageBase))
Write-Host ("Literal refs: {0}" -f $hits.Count)
Write-Host ''

$n=0
foreach ($raw in $hits) {
    $n++
    $va = Raw-To-VA $raw
    $sec = Raw-To-Section $raw
    $tag = if ($sec -eq '.text') { 'CODE-XREF-CANDIDATE' } else { 'DATA-XREF' }
    Write-Host ("HIT #{0}: raw=0x{1:X8} VA=0x{2:X8} section={3} {4}" -f $n,$raw,$va,$sec,$tag)
    Write-Host ("  context: {0}" -f (Hex-Context $raw 40 40))
}

Write-Host ''
Write-Host 'Interpretation:'
Write-Host '  - Compare writes/clears against TheGameInfo 0x00DE7D6C.'
Write-Host '  - A site that writes 0x00DE892C without writing TheGameInfo is especially valuable.'
Write-Host '  - Do not classify this global as pending/owner until the lifecycle is traced.'
Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
