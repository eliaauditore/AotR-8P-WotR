param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat',
    [uint32]$TargetVA = 0x0078844A
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Finds direct near CALL/JMP xrefs (E8/E9 rel32) to the constructor whose
# +0x674 member is published to TheGameInfo/0x00DE892C.
# Does not open the game process and does not modify any file.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ImageBase = [uint32]0x00400000

if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

[byte[]]$data = [IO.File]::ReadAllBytes($GameDat)
if ($data.Length -lt 0x100 -or $data[0] -ne 0x4D -or $data[1] -ne 0x5A) { throw 'Not a valid MZ image.' }
$pe = [BitConverter]::ToInt32($data, 0x3C)
if ([Text.Encoding]::ASCII.GetString($data, $pe, 4) -ne "PE`0`0") { throw 'Invalid PE signature.' }
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
        Name=$name; RVA=$virtualAddress; VirtualSize=$virtualSize; RawSize=$rawSize; RawPtr=$rawPtr;
        Executable=(($characteristics -band 0x20000000) -ne 0)
    }
}

$hits = New-Object System.Collections.Generic.List[object]
foreach ($s in $sections | Where-Object Executable) {
    $limit = [Math]::Min([int64]$s.RawPtr + [int64]$s.RawSize, [int64]$data.Length)
    for ([int64]$raw = $s.RawPtr; $raw -le ($limit - 5); $raw++) {
        $op = $data[$raw]
        if ($op -ne 0xE8 -and $op -ne 0xE9) { continue }
        $rel = [BitConverter]::ToInt32($data, [int]($raw + 1))
        $siteVA = [int64]$ImageBase + [int64]$s.RVA + ($raw - [int64]$s.RawPtr)
        $destVA = $siteVA + 5 + [int64]$rel
        if ($destVA -eq [int64]$TargetVA) {
            $hits.Add([pscustomobject]@{
                Op=if($op -eq 0xE8){'CALL'}else{'JMP'}
                Raw=[uint32]$raw
                VA=[uint32]$siteVA
                Section=$s.Name
            })
        }
    }
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR BASE CTOR CALL XREF PROBE - DISK ONLY'
Write-Host '============================================================'
Write-Host ("Image    : {0}" -f $GameDat)
Write-Host ("SHA256   : {0}" -f $hash)
Write-Host ("TargetVA : 0x{0:X8}" -f $TargetVA)
Write-Host ("Direct E8/E9 refs: {0}" -f $hits.Count)
Write-Host ''

$n = 0
foreach ($h in $hits) {
    $n++
    $ctxStart = [Math]::Max(0, [int64]$h.Raw - 48)
    $ctxEnd = [Math]::Min([int64]$data.Length - 1, [int64]$h.Raw + 52)
    $ctx = $data[[int]$ctxStart..[int]$ctxEnd]
    $hex = ($ctx | ForEach-Object { $_.ToString('X2') }) -join ' '
    Write-Host ("HIT #{0}: {1} raw=0x{2:X8} VA=0x{3:X8} section={4}" -f $n,$h.Op,$h.Raw,$h.VA,$h.Section)
    Write-Host ("  context: {0}" -f $hex)
}

Write-Host ''
Write-Host 'Interpretation:'
Write-Host '  - A CALL hit is a direct constructor caller candidate.'
Write-Host '  - Disassemble ~0x100 bytes before/after each call site with the FAST range trace.'
Write-Host '  - Track ECX into the call: that is the constructor this pointer.'
Write-Host '  - Compare that this/object provenance against the live pre-start GameInfo containment evidence.'
Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
