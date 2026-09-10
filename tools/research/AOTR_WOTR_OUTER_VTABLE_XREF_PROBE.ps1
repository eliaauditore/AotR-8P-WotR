param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Correlates the runtime outer-object vtable with the base-constructor vtable
# seen in the GameInfo publish constructor. No process memory is opened/written.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ImageBase = [uint32]0x00400000
$Targets = @(
    [pscustomobject]@{ Name='RUNTIME_OUTER'; VA=[uint32]0x00BE9C80 },
    [pscustomobject]@{ Name='BASE_CTOR';     VA=[uint32]0x00C2FC58 }
)

if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

$bytes = [IO.File]::ReadAllBytes($GameDat)
if ($bytes.Length -lt 0x100) { throw 'File too small.' }
if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { throw 'Not MZ.' }
$pe = [BitConverter]::ToInt32($bytes,0x3C)
if ($bytes[$pe] -ne 0x50 -or $bytes[$pe+1] -ne 0x45) { throw 'Bad PE.' }
$numSections = [BitConverter]::ToUInt16($bytes,$pe+6)
$optSize = [BitConverter]::ToUInt16($bytes,$pe+20)
$secOff = $pe + 24 + $optSize
$sections = @()
for ($i=0; $i -lt $numSections; $i++) {
    $o = $secOff + 40*$i
    $nameBytes = $bytes[$o..($o+7)]
    $name = ([Text.Encoding]::ASCII.GetString($nameBytes)).Trim([char]0)
    $vs = [BitConverter]::ToUInt32($bytes,$o+8)
    $rva = [BitConverter]::ToUInt32($bytes,$o+12)
    $rawSize = [BitConverter]::ToUInt32($bytes,$o+16)
    $rawPtr = [BitConverter]::ToUInt32($bytes,$o+20)
    $sections += [pscustomobject]@{Name=$name;RVA=$rva;VS=$vs;RawSize=$rawSize;RawPtr=$rawPtr}
}

function Get-SectionByRaw([int]$raw) {
    foreach ($s in $sections) {
        if ($raw -ge $s.RawPtr -and $raw -lt ($s.RawPtr + $s.RawSize)) { return $s }
    }
    return $null
}

function Raw-To-VA([int]$raw) {
    $s = Get-SectionByRaw $raw
    if (-not $s) { return [uint32]0 }
    return [uint32]($ImageBase + $s.RVA + ($raw - $s.RawPtr))
}

function Hex-Context([int]$raw,[int]$before=24,[int]$after=40) {
    $a = [Math]::Max(0,$raw-$before)
    $b = [Math]::Min($bytes.Length-1,$raw+$after-1)
    return (($bytes[$a..$b] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR OUTER VTABLE XREF PROBE - DISK ONLY'
Write-Host '============================================================'
Write-Host ("Image  : {0}" -f $GameDat)
Write-Host ("SHA256 : {0}" -f $hash)
Write-Host ''

foreach ($t in $Targets) {
    $pat = [BitConverter]::GetBytes([uint32]$t.VA)
    $hits = @()
    for ($i=0; $i -le $bytes.Length-4; $i++) {
        if ($bytes[$i] -eq $pat[0] -and $bytes[$i+1] -eq $pat[1] -and $bytes[$i+2] -eq $pat[2] -and $bytes[$i+3] -eq $pat[3]) {
            $s = Get-SectionByRaw $i
            $hits += [pscustomobject]@{Raw=$i;VA=(Raw-To-VA $i);Section=if($s){$s.Name}else{'<none>'}}
        }
    }

    Write-Host '------------------------------------------------------------'
    Write-Host ("{0} vtable VA=0x{1:X8} RVA=0x{2:X8}" -f $t.Name,$t.VA,($t.VA-$ImageBase))
    Write-Host ("Literal refs: {0}" -f $hits.Count)
    $n=0
    foreach ($h in $hits) {
        $n++
        $tag = if ($h.Section -eq '.text') {'CODE-XREF-CANDIDATE'} else {'DATA-REF'}
        Write-Host ("HIT #{0}: raw=0x{1:X8} VA=0x{2:X8} section={3} {4}" -f $n,$h.Raw,$h.VA,$h.Section,$tag)
        Write-Host ("  context: {0}" -f (Hex-Context $h.Raw))
    }
    Write-Host ''
}

Write-Host 'Interpretation:'
Write-Host '  - A .text assignment to 0x00BE9C80 identifies the derived/live outer vtable installation site.'
Write-Host '  - If that function calls/contains the 0x0078844A base constructor on the same this pointer, the base->derived constructor chain is closed.'
Write-Host '  - Do not classify same-instance solely from a matching +0x674 offset; trace the same this pointer through the constructor chain.'
Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
