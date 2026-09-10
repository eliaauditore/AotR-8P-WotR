param(
    [int]$ProcessId = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY / DISK ONLY.
# Confirms PE mappings, dumps the two adjacent vtable candidates discovered at runtime,
# and scans the exact game.dat image for literal references to their VAs.
# No process memory is written and the executable is never modified.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$Targets = @(
    [pscustomobject]@{ Name = 'VTABLE_A'; VA = [uint32]0x00C54B5C; Entries = 7 },
    [pscustomobject]@{ Name = 'VTABLE_B'; VA = [uint32]0x00C54B78; Entries = 12 }
)

if ($ProcessId -le 0) {
    $games = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.MainModule.FileName -match '\\game\.dat$' } catch { $false }
    })
    if ($games.Count -ne 1) {
        throw "Expected exactly one running game.dat. Found $($games.Count). Pass -ProcessId explicitly."
    }
    $ProcessId = [int]$games[0].Id
}

$proc = Get-Process -Id $ProcessId -ErrorAction Stop
$exePath = $proc.MainModule.FileName
$hash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw 'HASH MISMATCH - aborted before analysis.' }

[byte[]]$Data = [System.IO.File]::ReadAllBytes($exePath)

function U16([int]$o) { [BitConverter]::ToUInt16($Data, $o) }
function U32([int]$o) { [BitConverter]::ToUInt32($Data, $o) }
function HexBytes([int]$start, [int]$count) {
    $s = [Math]::Max(0, $start)
    $e = [Math]::Min($Data.Length, $s + $count)
    if ($e -le $s) { return '' }
    (($Data[$s..($e-1)] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')
}

$pe = [int](U32 0x3C)
if ($Data[$pe] -ne 0x50 -or $Data[$pe+1] -ne 0x45 -or $Data[$pe+2] -ne 0 -or $Data[$pe+3] -ne 0) {
    throw 'Invalid PE signature.'
}

$coff = $pe + 4
$numSections = [int](U16 ($coff + 2))
$optSize = [int](U16 ($coff + 16))
$opt = $coff + 20
$magic = U16 $opt
if ($magic -ne 0x10B) { throw ("Expected PE32 optional header 0x10B, found 0x{0:X}" -f $magic) }
$imageBase = [uint32](U32 ($opt + 0x1C))
$secTable = $opt + $optSize

$sections = @()
for ($i = 0; $i -lt $numSections; $i++) {
    $o = $secTable + ($i * 40)
    $nameBytes = $Data[$o..($o+7)]
    $name = ([Text.Encoding]::ASCII.GetString($nameBytes)).Trim([char]0)
    $vs = [uint32](U32 ($o + 8))
    $va = [uint32](U32 ($o + 12))
    $rawSize = [uint32](U32 ($o + 16))
    $rawPtr = [uint32](U32 ($o + 20))
    $chars = [uint32](U32 ($o + 36))
    $sections += [pscustomobject]@{
        Name=$name; VirtualSize=$vs; RVA=$va; RawSize=$rawSize; RawPtr=$rawPtr; Characteristics=$chars
    }
}

function Find-SectionByRva([uint32]$rva) {
    foreach ($s in $sections) {
        $span = [Math]::Max([uint64]$s.VirtualSize, [uint64]$s.RawSize)
        if ([uint64]$rva -ge [uint64]$s.RVA -and [uint64]$rva -lt ([uint64]$s.RVA + $span)) { return $s }
    }
    return $null
}

function Va-To-Raw([uint32]$va) {
    if ($va -lt $imageBase) { return $null }
    $rva = [uint32]($va - $imageBase)
    $s = Find-SectionByRva $rva
    if ($null -eq $s) { return $null }
    $delta = [uint32]($rva - $s.RVA)
    if ($delta -ge $s.RawSize) { return $null }
    [uint32]($s.RawPtr + $delta)
}

function Raw-To-Va([uint32]$raw) {
    foreach ($s in $sections) {
        if ([uint64]$raw -ge [uint64]$s.RawPtr -and [uint64]$raw -lt ([uint64]$s.RawPtr + [uint64]$s.RawSize)) {
            return [uint32]($imageBase + $s.RVA + ($raw - $s.RawPtr))
        }
    }
    return $null
}

function Section-For-Va([uint32]$va) {
    if ($va -lt $imageBase) { return $null }
    Find-SectionByRva ([uint32]($va - $imageBase))
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR VTABLE XREF PROBE - READ ONLY / DISK ONLY'
Write-Host '============================================================'
Write-Host ("PID       : {0}" -f $ProcessId)
Write-Host ("Image     : {0}" -f $exePath)
Write-Host ("SHA256    : {0}" -f $hash)
Write-Host ("ImageBase : 0x{0:X8}" -f $imageBase)
Write-Host ("Sections  : {0}" -f $numSections)
Write-Host ''

Write-Host 'PE sections:'
foreach ($s in $sections) {
    Write-Host ("  {0,-8} RVA=0x{1:X8} VS=0x{2:X8} RAW=0x{3:X8}+0x{4:X8}" -f $s.Name,$s.RVA,$s.VirtualSize,$s.RawPtr,$s.RawSize)
}

foreach ($t in $Targets) {
    Write-Host ''
    Write-Host ("------------------------------------------------------------")
    Write-Host ("{0} @ VA 0x{1:X8} (RVA 0x{2:X8})" -f $t.Name,$t.VA,([uint32]($t.VA-$imageBase)))
    $raw = Va-To-Raw $t.VA
    if ($null -eq $raw) {
        Write-Host 'Could not map vtable VA to raw file offset.' -ForegroundColor Yellow
        continue
    }
    $sec = Section-For-Va $t.VA
    Write-Host ("Section={0} Raw=0x{1:X8}" -f $sec.Name,$raw)
    Write-Host 'Entries:'
    for ($i=0; $i -lt $t.Entries; $i++) {
        $p = [uint32](U32 ([int]($raw + ($i*4))))
        $pSec = Section-For-Va $p
        $pSecName = if ($null -ne $pSec) { $pSec.Name } else { '<none>' }
        Write-Host ("  [{0:D2}] VA=0x{1:X8} RVA=0x{2:X8} section={3}" -f $i,$p,([uint32]($p-$imageBase)),$pSecName)
    }

    $needle = [BitConverter]::GetBytes([uint32]$t.VA)
    $hits = New-Object System.Collections.Generic.List[uint32]
    foreach ($s in $sections) {
        if ($s.RawSize -lt 4) { continue }
        $start = [int]$s.RawPtr
        $end = [int]([Math]::Min([uint64]$Data.Length, [uint64]$s.RawPtr + [uint64]$s.RawSize))
        for ($o=$start; $o -le $end-4; $o++) {
            if ($Data[$o] -eq $needle[0] -and $Data[$o+1] -eq $needle[1] -and $Data[$o+2] -eq $needle[2] -and $Data[$o+3] -eq $needle[3]) {
                $hits.Add([uint32]$o)
            }
        }
    }

    Write-Host ("Literal VA references in file: {0}" -f $hits.Count)
    $n=0
    foreach ($h in $hits) {
        $n++
        $hVa = Raw-To-Va $h
        $hSec = if ($null -ne $hVa) { Section-For-Va $hVa } else { $null }
        $hSecName = if ($null -ne $hSec) { $hSec.Name } else { '<none>' }
        $kind = if ($hSecName -eq '.text') { 'CODE-XREF-CANDIDATE' } else { 'DATA-REF' }
        Write-Host ("  HIT #{0}: raw=0x{1:X8} VA=0x{2:X8} section={3} {4}" -f $n,$h,$hVa,$hSecName,$kind)
        Write-Host ("    context: {0}" -f (HexBytes ([int]$h-12) 32))
    }
}

Write-Host ''
Write-Host 'Interpretation rule:'
Write-Host '  - A .text literal reference is a constructor/assignment xref candidate.'
Write-Host '  - Separate .text references to VTABLE_A and VTABLE_B strongly support two adjacent vtables.'
Write-Host '  - Do not infer RTTI from VTABLE[-1] without validating the pointed structure.'
Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
