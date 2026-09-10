param(
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY / PS5.1 COMPATIBLE.
# Revalidates exact machine bytes around the disputed 0x8496xx frontend region.
# No process API, debugger API, Python, Capstone, or file write is used.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ImageBase = [uint32]0x00400000

if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }
$Data = [IO.File]::ReadAllBytes($GameDat)

function U16([int]$Offset) { return [BitConverter]::ToUInt16($Data,$Offset) }
function U32([int]$Offset) { return [BitConverter]::ToUInt32($Data,$Offset) }
function I32([int]$Offset) { return [BitConverter]::ToInt32($Data,$Offset) }

if ($Data.Length -lt 0x1000 -or $Data[0] -ne 0x4D -or $Data[1] -ne 0x5A) { throw 'Not an MZ image.' }
$pe = [int](U32 0x3C)
if ($Data[$pe] -ne 0x50 -or $Data[$pe+1] -ne 0x45 -or $Data[$pe+2] -ne 0 -or $Data[$pe+3] -ne 0) { throw 'Bad PE signature.' }
$numSections = [int](U16 ($pe+6))
$optSize = [int](U16 ($pe+20))
$sec0 = $pe + 24 + $optSize
$Sections = @()
for ($i=0; $i -lt $numSections; $i++) {
    $o = $sec0 + ($i*40)
    $nameBytes = New-Object byte[] 8
    [Array]::Copy($Data,$o,$nameBytes,0,8)
    $name = ([Text.Encoding]::ASCII.GetString($nameBytes)).Trim([char]0)
    $vs   = [uint32](U32 ($o+8))
    $rva  = [uint32](U32 ($o+12))
    $rs   = [uint32](U32 ($o+16))
    $raw  = [uint32](U32 ($o+20))
    $ch   = [uint32](U32 ($o+36))
    $Sections += [pscustomobject]@{Name=$name;Rva=$rva;VirtualSize=$vs;RawSize=$rs;Raw=$raw;Characteristics=$ch}
}

function Va-ToRaw([uint32]$Va) {
    if ($Va -lt $ImageBase) { throw ('VA below image base: 0x{0:X8}' -f $Va) }
    $rva = [uint32]($Va - $ImageBase)
    foreach ($s in $Sections) {
        $span = [Math]::Max([uint64]$s.VirtualSize,[uint64]$s.RawSize)
        if ([uint64]$rva -ge [uint64]$s.Rva -and [uint64]$rva -lt ([uint64]$s.Rva + $span)) {
            $rel = [uint64]$rva - [uint64]$s.Rva
            if ($rel -ge [uint64]$s.RawSize) { throw ('VA maps to virtual tail, not raw data: 0x{0:X8}' -f $Va) }
            return [int]([uint64]$s.Raw + $rel)
        }
    }
    throw ('VA not mapped by PE sections: 0x{0:X8}' -f $Va)
}

function Read-BytesVa([uint32]$Va,[int]$Count) {
    $raw = Va-ToRaw $Va
    if ($raw -lt 0 -or $raw + $Count -gt $Data.Length) { throw ('Read outside file at VA 0x{0:X8}' -f $Va) }
    $b = New-Object byte[] $Count
    [Array]::Copy($Data,$raw,$b,0,$Count)
    return $b
}
function Hex([byte[]]$Bytes) { return (($Bytes | ForEach-Object { $_.ToString('X2') }) -join ' ') }
function Dump-Hex([uint32]$Start,[uint32]$End) {
    for ($va=[uint64]$Start; $va -lt [uint64]$End; $va += 16) {
        $count = [int][Math]::Min(16,[uint64]$End-$va)
        $b = Read-BytesVa ([uint32]$va) $count
        Write-Host ('0x{0:X8}: {1}' -f [uint32]$va,(Hex $b))
    }
}
function Show-Anchor([uint32]$Va) {
    $before = [uint32]($Va-8)
    $b = Read-BytesVa $before 32
    Write-Host ('ANCHOR 0x{0:X8} raw=0x{1:X8}' -f $Va,(Va-ToRaw $Va))
    Write-Host ('  0x{0:X8}: {1}' -f $before,(Hex $b))
    $op = (Read-BytesVa $Va 1)[0]
    if ($op -eq 0xE8 -or $op -eq 0xE9) {
        $raw = Va-ToRaw $Va
        $disp = [BitConverter]::ToInt32($Data,$raw+1)
        $target64 = [int64][uint64]$Va + 5 + [int64]$disp
        $kind = if ($op -eq 0xE8) { 'CALL rel32' } else { 'JMP rel32' }
        Write-Host ('  EXACT_REL32_AT_ANCHOR = {0} -> 0x{1:X8}' -f $kind,[uint32]$target64)
    } else {
        Write-Host ('  FIRST_BYTE_AT_ANCHOR = 0x{0:X2}' -f $op)
    }
}
function Find-PatternInRegion([byte[]]$Pattern,[uint32]$Start,[uint32]$End,[string]$Label) {
    $startRaw = Va-ToRaw $Start
    $endRaw = Va-ToRaw ([uint32]($End-1))
    $hits = @()
    for ($r=$startRaw; $r -le ($endRaw-$Pattern.Length+1); $r++) {
        $ok=$true
        for ($j=0; $j -lt $Pattern.Length; $j++) {
            if ($Data[$r+$j] -ne $Pattern[$j]) { $ok=$false; break }
        }
        if ($ok) {
            $delta = $r-$startRaw
            $va = [uint32]($Start+$delta)
            $hits += $va
        }
    }
    Write-Host ('{0}_COUNT={1}' -f $Label,$hits.Count)
    foreach ($va in $hits) {
        $lo = if ($va -ge 12) { [uint32]($va-12) } else { $va }
        Write-Host ('  {0} at 0x{1:X8}' -f $Label,$va)
        Write-Host ('    0x{0:X8}: {1}' -f $lo,(Hex (Read-BytesVa $lo 36)))
    }
    return ,$hits
}

$RegionStart = [uint32]0x00849620
$RegionEnd   = [uint32]0x00849750
$Anchors = @(
    [uint32]0x00849641,
    [uint32]0x00849654,
    [uint32]0x00849655,
    [uint32]0x0084965F,
    [uint32]0x00849677,
    [uint32]0x00849683,
    [uint32]0x008496C2,
    [uint32]0x008496CE,
    [uint32]0x0084970B,
    [uint32]0x00849726
)

Write-Host '============================================================'
Write-Host ' AOTR WOTR FRONTEND 0x8496xx EXACT BYTES - PURE PS'
Write-Host '============================================================'
Write-Host ("Image  : {0}" -f $GameDat)
Write-Host ("SHA256 : {0}" -f $hash)
Write-Host 'Mode   : DISK ONLY / READ ONLY / NO PYTHON / NO PROCESS ACCESS'
Write-Host ''

Write-Host '================ EXACT ANCHORS ================'
foreach ($a in $Anchors) { Show-Anchor $a }
Write-Host ''

Write-Host '================ RAW REGION 0x849620..0x84974F ================'
Dump-Hex $RegionStart $RegionEnd
Write-Host ''

Write-Host '================ +0x6A4 DISPLACEMENT OCCURRENCES ================'
$disp6A4 = [byte[]](0xA4,0x06,0x00,0x00)
[void](Find-PatternInRegion $disp6A4 $RegionStart $RegionEnd 'DISP_6A4')
Write-Host ''

Write-Host '================ KNOWN STATE8 CMP/WRITE PATTERNS ================'
# cmp dword ptr [ESI+6A4],8 : 83 BE A4 06 00 00 08
[void](Find-PatternInRegion ([byte[]](0x83,0xBE,0xA4,0x06,0x00,0x00,0x08)) $RegionStart $RegionEnd 'CMP_ESI_6A4_IMM8_8')
# cmp dword ptr [ECX+6A4],8 : 83 B9 A4 06 00 00 08
[void](Find-PatternInRegion ([byte[]](0x83,0xB9,0xA4,0x06,0x00,0x00,0x08)) $RegionStart $RegionEnd 'CMP_ECX_6A4_IMM8_8')
# cmp dword ptr [EDI+6A4],8 : 83 BF A4 06 00 00 08
[void](Find-PatternInRegion ([byte[]](0x83,0xBF,0xA4,0x06,0x00,0x00,0x08)) $RegionStart $RegionEnd 'CMP_EDI_6A4_IMM8_8')
# mov [base+6A4],8/9/1, common C7 /0 disp32 imm32 forms.
foreach ($spec in @(
    @('MOV_ESI_6A4_8',[byte[]](0xC7,0x86,0xA4,0x06,0x00,0x00,0x08,0x00,0x00,0x00)),
    @('MOV_ESI_6A4_9',[byte[]](0xC7,0x86,0xA4,0x06,0x00,0x00,0x09,0x00,0x00,0x00)),
    @('MOV_ECX_6A4_8',[byte[]](0xC7,0x81,0xA4,0x06,0x00,0x00,0x08,0x00,0x00,0x00)),
    @('MOV_ECX_6A4_9',[byte[]](0xC7,0x81,0xA4,0x06,0x00,0x00,0x09,0x00,0x00,0x00)),
    @('MOV_EDI_6A4_8',[byte[]](0xC7,0x87,0xA4,0x06,0x00,0x00,0x08,0x00,0x00,0x00)),
    @('MOV_EDI_6A4_9',[byte[]](0xC7,0x87,0xA4,0x06,0x00,0x00,0x09,0x00,0x00,0x00))
)) {
    [void](Find-PatternInRegion $spec[1] $RegionStart $RegionEnd $spec[0])
}
Write-Host ''

Write-Host '================ RAW E8/E9 REL32 CANDIDATES IN REGION ================'
# This is intentionally a raw-byte candidate scan, not a disassembler. It prints every
# E8/E9 byte and target so exact anchor/call claims can be checked against surrounding bytes.
$sr = Va-ToRaw $RegionStart
$er = Va-ToRaw ([uint32]($RegionEnd-1))
for ($r=$sr; $r -le $er-4; $r++) {
    $op=$Data[$r]
    if ($op -ne 0xE8 -and $op -ne 0xE9) { continue }
    $va=[uint32]($RegionStart+($r-$sr))
    $disp=[BitConverter]::ToInt32($Data,$r+1)
    $target=[uint32]([int64][uint64]$va+5+[int64]$disp)
    $kind=if($op-eq 0xE8){'E8/CALL'}else{'E9/JMP'}
    Write-Host ('0x{0:X8} {1} -> 0x{2:X8}  bytes={3}' -f $va,$kind,$target,(Hex (Read-BytesVa $va 5)))
}

Write-Host ''
Write-Host 'READ_ONLY_COMPLETE=YES'
Write-Host 'No process was opened and no file bytes were modified.'
