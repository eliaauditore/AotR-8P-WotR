param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Finds all direct CALL/JMP rel32 references to the constructor/helper reached at
# VA 0x009035AE from the known 0x0078844A path. The goal is to identify all
# construction paths for the live pre-start network GameInfo object.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ImageBase = [int64]0x00400000
$TargetVA  = [int64]0x009035AE

if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

$bytes = [IO.File]::ReadAllBytes($GameDat)

function Read-U16([int]$o) { [BitConverter]::ToUInt16($bytes,$o) }
function Read-U32([int]$o) { [BitConverter]::ToUInt32($bytes,$o) }
function Read-I32([int]$o) { [BitConverter]::ToInt32($bytes,$o) }

if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { throw 'Not MZ' }
$pe = [int](Read-U32 0x3C)
if ($bytes[$pe] -ne 0x50 -or $bytes[$pe+1] -ne 0x45) { throw 'Bad PE' }
$numSections = [int](Read-U16 ($pe+6))
$optSize = [int](Read-U16 ($pe+20))
$secBase = $pe + 24 + $optSize

$sections = @()
for ($i=0; $i -lt $numSections; $i++) {
    $o = $secBase + ($i*40)
    $name = ([Text.Encoding]::ASCII.GetString($bytes,$o,8)).Trim([char]0)
    $virtualSize = [uint32](Read-U32 ($o+8))
    $rva         = [uint32](Read-U32 ($o+12))
    $rawSize     = [uint32](Read-U32 ($o+16))
    $rawPtr      = [uint32](Read-U32 ($o+20))
    $sections += [pscustomobject]@{ Name=$name; RVA=$rva; VirtualSize=$virtualSize; RawSize=$rawSize; RawPtr=$rawPtr }
}

$text = $sections | Where-Object Name -eq '.text' | Select-Object -First 1
if (-not $text) { throw '.text not found' }

$hits = @()
$start = [int]$text.RawPtr
$end = [int]($text.RawPtr + $text.RawSize - 5)
for ($raw=$start; $raw -le $end; $raw++) {
    $op = $bytes[$raw]
    if ($op -ne 0xE8 -and $op -ne 0xE9) { continue }
    $siteRva = [int64]$text.RVA + ($raw - [int]$text.RawPtr)
    $siteVA = $ImageBase + $siteRva
    $disp = [int64](Read-I32 ($raw+1))
    $dest = $siteVA + 5 + $disp
    if ($dest -eq $TargetVA) {
        $hits += [pscustomobject]@{ Raw=$raw; VA=$siteVA; Kind=($(if($op -eq 0xE8){'CALL'}else{'JMP'})) }
    }
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR NETWORK GAMEINFO CTOR CALL XREF - DISK ONLY'
Write-Host '============================================================'
Write-Host ("Image    : {0}" -f $GameDat)
Write-Host ("SHA256   : {0}" -f $hash)
Write-Host ("TargetVA : 0x{0:X8}" -f $TargetVA)
Write-Host ("Direct E8/E9 refs: {0}" -f $hits.Count)
Write-Host ''

$n=0
foreach ($h in $hits) {
    $n++
    $ctxStart = [Math]::Max([int]$text.RawPtr, [int]$h.Raw - 96)
    $ctxEnd   = [Math]::Min([int]($text.RawPtr+$text.RawSize), [int]$h.Raw + 101)
    $ctx = $bytes[$ctxStart..($ctxEnd-1)]
    $ctxHex = ($ctx | ForEach-Object { $_.ToString('X2') }) -join ' '
    Write-Host ("HIT #{0}: {1} raw=0x{2:X8} VA=0x{3:X8} section=.text" -f $n,$h.Kind,$h.Raw,$h.VA)
    Write-Host ("  context: {0}" -f $ctxHex)
    Write-Host ''
}

Write-Host 'Interpretation:'
Write-Host '  - 0x009035AE is the constructor/helper called on [outer+0x674] in the known 0x0078844A path.'
Write-Host '  - Multiple callers would prove there are multiple construction/lifecycle paths for this GameInfo-like subobject.'
Write-Host '  - For each caller, trace ECX into the call and nearby writes to 0x00DE892C / 0x00DE8930 / 0x00DE7D6C.'
Write-Host '  - Do not assume the 0x0078844A/0x00DE7D68 lifecycle is the current native WotR lobby path.'
Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
