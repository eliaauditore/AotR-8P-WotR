param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Finds direct CALL/JMP rel32 xrefs to the factory at VA 0x00788955.
# The factory allocates 0x1730 bytes and invokes ctor 0x0078844A.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ImageBase = [uint32]0x00400000
$TargetVA = [uint32]0x00788955

if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

[byte[]]$data = [IO.File]::ReadAllBytes($GameDat)
if ($data.Length -lt 0x1000 -or $data[0] -ne 0x4D -or $data[1] -ne 0x5A) { throw 'Not a valid MZ image.' }
$pe = [BitConverter]::ToInt32($data, 0x3C)
if ($data[$pe] -ne 0x50 -or $data[$pe+1] -ne 0x45) { throw 'Invalid PE signature.' }
$numSections = [BitConverter]::ToUInt16($data, $pe + 6)
$optSize = [BitConverter]::ToUInt16($data, $pe + 20)
$secOff = $pe + 24 + $optSize

$sections = @()
for ($i=0; $i -lt $numSections; $i++) {
    $o = $secOff + ($i * 40)
    $nameBytes = $data[$o..($o+7)]
    $name = ([Text.Encoding]::ASCII.GetString($nameBytes)).Trim([char]0)
    $virtualSize = [BitConverter]::ToUInt32($data, $o + 8)
    $virtualAddress = [BitConverter]::ToUInt32($data, $o + 12)
    $rawSize = [BitConverter]::ToUInt32($data, $o + 16)
    $rawPtr = [BitConverter]::ToUInt32($data, $o + 20)
    $characteristics = [BitConverter]::ToUInt32($data, $o + 36)
    $sections += [pscustomobject]@{
        Name=$name; RVA=$virtualAddress; VirtualSize=$virtualSize; RawSize=$rawSize; RawPtr=$rawPtr; Characteristics=$characteristics
    }
}

$text = $sections | Where-Object { $_.Name -eq '.text' } | Select-Object -First 1
if (-not $text) { throw '.text section not found.' }

function Raw-ToVA([int]$raw) {
    foreach ($s in $sections) {
        $start = [int64]$s.RawPtr
        $end = $start + [int64]$s.RawSize
        if ($raw -ge $start -and $raw -lt $end) {
            return [uint32]($ImageBase + $s.RVA + ($raw - $s.RawPtr))
        }
    }
    return [uint32]0
}

function Get-SectionName([int]$raw) {
    foreach ($s in $sections) {
        if ($raw -ge $s.RawPtr -and $raw -lt ([int64]$s.RawPtr + $s.RawSize)) { return $s.Name }
    }
    return '<none>'
}

function Hex-Context([int]$raw, [int]$before=48, [int]$after=64) {
    $a = [Math]::Max(0, $raw - $before)
    $b = [Math]::Min($data.Length - 1, $raw + 4 + $after)
    return (($data[$a..$b] | ForEach-Object { $_.ToString('X2') }) -join ' ')
}

$hits = @()
$startRaw = [int]$text.RawPtr
$stopRaw = [int]([int64]$text.RawPtr + $text.RawSize - 5)
for ($raw=$startRaw; $raw -le $stopRaw; $raw++) {
    $op = $data[$raw]
    if ($op -ne 0xE8 -and $op -ne 0xE9) { continue }
    $srcVA = Raw-ToVA $raw
    if ($srcVA -eq 0) { continue }
    $rel = [BitConverter]::ToInt32($data, $raw + 1)
    $dest = [int64]$srcVA + 5 + $rel
    if ($dest -eq $TargetVA) {
        $hits += [pscustomobject]@{
            Kind = $(if ($op -eq 0xE8) { 'CALL' } else { 'JMP' })
            Raw = $raw
            VA = $srcVA
            Section = Get-SectionName $raw
            Context = Hex-Context $raw
        }
    }
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR FACTORY CALL XREF PROBE - DISK ONLY'
Write-Host '============================================================'
Write-Host ("Image    : {0}" -f $GameDat)
Write-Host ("SHA256   : {0}" -f $hash)
Write-Host ("TargetVA : 0x{0:X8}" -f $TargetVA)
Write-Host ("Direct E8/E9 refs: {0}" -f $hits.Count)
Write-Host ''

$n=0
foreach ($h in $hits) {
    $n++
    Write-Host ("HIT #{0}: {1} raw=0x{2:X8} VA=0x{3:X8} section={4}" -f $n,$h.Kind,$h.Raw,$h.VA,$h.Section)
    Write-Host ("  context: {0}" -f $h.Context)
}

Write-Host ''
Write-Host 'Interpretation:'
Write-Host '  - 0x00788955 allocates 0x1730 bytes and constructs the object through 0x0078844A.'
Write-Host '  - Trace the caller around each hit and follow the returned EAX pointer.'
Write-Host '  - The important question is where that returned 0x1730-object pointer is stored/owned before the WotR lobby.'
Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
