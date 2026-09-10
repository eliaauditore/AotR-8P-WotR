param(
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY / PS5.1 COMPATIBLE.
# Continuation-only follow-up after STATE9_WRITE_UNIQUE_AT_8496F5=YES was already proven.
# This probe intentionally does NOT repeat the State9 scan.
# It only:
#   1) finds direct rel32 CALL/JMP xrefs to 0x008472BF,
#   2) dumps exact bytes around 0x008472BF and known caller anchors,
#   3) lists rel32 targets inside the post-join window that stay inside game.dat,
#   4) lists embedded DE00xx global candidates inside that window.
# No process APIs, debugger APIs, Python, Capstone, or file writes are used.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ImageBase    = [uint32]0x00400000
$ImageEnd     = [uint32]0x00ED4000
$PostJoin     = [uint32]0x008472BF
$WindowStart  = [uint32]0x00847280
$WindowEnd    = [uint32]0x00847540
$Two32        = [int64]4294967296

if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }
$Data = [IO.File]::ReadAllBytes($GameDat)

function U16([int]$Offset) { return [BitConverter]::ToUInt16($Data,$Offset) }
function U32([int]$Offset) { return [BitConverter]::ToUInt32($Data,$Offset) }

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
    $Sections += [pscustomobject]@{
        Name=$name
        VirtualSize=[uint32](U32 ($o+8))
        Rva=[uint32](U32 ($o+12))
        RawSize=[uint32](U32 ($o+16))
        Raw=[uint32](U32 ($o+20))
        Characteristics=[uint32](U32 ($o+36))
    }
}

function Va-ToRaw([uint32]$Va) {
    if ($Va -lt $ImageBase) { throw ('VA below image base: 0x{0:X8}' -f $Va) }
    $rva = [uint32]($Va - $ImageBase)
    foreach ($s in $Sections) {
        $span = [Math]::Max([uint64]$s.VirtualSize,[uint64]$s.RawSize)
        if ([uint64]$rva -ge [uint64]$s.Rva -and [uint64]$rva -lt ([uint64]$s.Rva + $span)) {
            $rel = [uint64]$rva - [uint64]$s.Rva
            if ($rel -ge [uint64]$s.RawSize) { throw ('VA maps to virtual tail: 0x{0:X8}' -f $Va) }
            return [int]([uint64]$s.Raw + $rel)
        }
    }
    throw ('VA not mapped: 0x{0:X8}' -f $Va)
}

function Read-BytesVa([uint32]$Va,[int]$Count) {
    $raw = Va-ToRaw $Va
    if ($raw -lt 0 -or ($raw+$Count) -gt $Data.Length) { throw ('Read outside file: 0x{0:X8}' -f $Va) }
    $b = New-Object byte[] $Count
    [Array]::Copy($Data,$raw,$b,0,$Count)
    return $b
}

function Hex([byte[]]$Bytes) {
    return (($Bytes | ForEach-Object { $_.ToString('X2') }) -join ' ')
}

function Dump-Hex([uint32]$Start,[uint32]$End) {
    for ($v=[uint64]$Start; $v -lt [uint64]$End; $v += 16) {
        $n=[int][Math]::Min(16,[uint64]$End-$v)
        Write-Host ('0x{0:X8}: {1}' -f [uint32]$v,(Hex (Read-BytesVa ([uint32]$v) $n)))
    }
}

function Wrap-U32([int64]$Value) {
    $n = $Value % $Two32
    if ($n -lt 0) { $n += $Two32 }
    return [uint32]$n
}

function Rel32-Target([uint32]$Src,[int]$Raw) {
    $disp=[BitConverter]::ToInt32($Data,$Raw+1)
    $sum=[int64][uint64]$Src + [int64]5 + [int64]$disp
    return (Wrap-U32 $sum)
}

function Context([uint32]$Va,[int]$Before=16,[int]$After=24) {
    $lo=[uint32]($Va-$Before)
    Write-Host ('  0x{0:X8}: {1}' -f $lo,(Hex (Read-BytesVa $lo ($Before+$After))))
}

$ExecSections=@($Sections | Where-Object { ($_.Characteristics -band [uint32]0x20000000) -ne 0 })

Write-Host '============================================================'
Write-Host ' AOTR POSTJOIN 0x8472BF - PURE PS V2 / READ ONLY'
Write-Host '============================================================'
Write-Host ('Image  : {0}' -f $GameDat)
Write-Host ('SHA256 : {0}' -f $hash)
Write-Host 'Mode   : DISK ONLY / NO PYTHON / NO PROCESS ACCESS'
Write-Host 'Prior proof reused: STATE9_WRITE_UNIQUE_AT_8496F5=YES'
Write-Host ''

# Self-test the exact PS5.1 arithmetic failure mode before scanning the image.
$testNeg = Wrap-U32 ([int64]-1287621655)
$testPos = Wrap-U32 ([int64]([uint64]0x00849374 + 5 + [int64]-839466))
if ($testNeg -ne [uint32]3007345641) { throw ('WRAP_SELFTEST_NEG_FAILED got=0x{0:X8}' -f $testNeg) }
Write-Host ('REL32_WRAP_SELFTEST_PASS neg=0x{0:X8} sample=0x{1:X8}' -f $testNeg,$testPos) -ForegroundColor Green
Write-Host ''

Write-Host '================ DIRECT REL32 XREFS TO 0x8472BF ================'
$xrefs=@()
foreach ($s in $ExecSections) {
    $start=[int]$s.Raw; $end=[int]($s.Raw+$s.RawSize)
    for ($r=$start; $r -le $end-5; $r++) {
        $op=$Data[$r]
        if ($op -ne 0xE8 -and $op -ne 0xE9) { continue }
        $src=[uint32]([uint64]$ImageBase+[uint64]$s.Rva+[uint64]($r-[int]$s.Raw))
        $target=Rel32-Target $src $r
        if ($target -ne $PostJoin) { continue }
        $xrefs += [pscustomobject]@{
            VA=$src
            Kind=$(if($op-eq 0xE8){'CALL'}else{'JMP'})
            Section=$s.Name
        }
    }
}
Write-Host ('POSTJOIN_8472BF_XREF_COUNT={0}' -f $xrefs.Count)
foreach ($x in $xrefs) {
    Write-Host ('  0x{0:X8} {1} section={2}' -f $x.VA,$x.Kind,$x.Section)
    Context $x.VA 32 64
}
Write-Host ''

Write-Host '================ EXACT POST-JOIN WINDOW 0x847280..0x84753F ================'
Dump-Hex $WindowStart $WindowEnd
Write-Host ''

Write-Host '================ REL32 TARGETS INSIDE POST-JOIN WINDOW ================'
$wr0=Va-ToRaw $WindowStart
$wr1=Va-ToRaw ([uint32]($WindowEnd-1))
$relHits=@()
for ($r=$wr0; $r -le $wr1-4; $r++) {
    $op=$Data[$r]
    if ($op -ne 0xE8 -and $op -ne 0xE9) { continue }
    $src=[uint32]([uint64]$WindowStart+[uint64]($r-$wr0))
    $t=Rel32-Target $src $r
    if ($t -lt $ImageBase -or $t -ge $ImageEnd) { continue }
    $relHits += [pscustomobject]@{VA=$src;Target=$t;Kind=$(if($op-eq 0xE8){'CALL'}else{'JMP'})}
}
Write-Host ('POSTJOIN_WINDOW_REL32_IN_IMAGE_COUNT={0}' -f $relHits.Count)
foreach ($h in $relHits) {
    Write-Host ('  0x{0:X8} {1} -> 0x{2:X8} bytes={3}' -f $h.VA,$h.Kind,$h.Target,(Hex (Read-BytesVa $h.VA 5)))
}
Write-Host ''

Write-Host '================ DE00xx GLOBAL DWORD CANDIDATES IN WINDOW ================'
$globals=@()
for ($r=$wr0; $r -le $wr1-3; $r++) {
    $v=[BitConverter]::ToUInt32($Data,$r)
    if ($v -lt [uint32]0x00DE0000 -or $v -gt [uint32]0x00DEFFFF) { continue }
    $src=[uint32]([uint64]$WindowStart+[uint64]($r-$wr0))
    $globals += [pscustomobject]@{VA=$src;Value=[uint32]$v}
}
Write-Host ('POSTJOIN_WINDOW_DE_GLOBAL_COUNT={0}' -f $globals.Count)
foreach ($g in $globals) {
    Write-Host ('  embedded dword at VA 0x{0:X8} -> 0x{1:X8}' -f $g.VA,$g.Value)
}
Write-Host ''

Write-Host '================ KNOWN CALLER ANCHORS ================'
foreach ($a in @([uint32]0x008487F2,[uint32]0x00849374,[uint32]0x00849379)) {
    Write-Host ('ANCHOR 0x{0:X8}' -f $a)
    Context $a 40 80
}
Write-Host ''

Write-Host 'READ_ONLY_COMPLETE=YES'
Write-Host 'No process was opened/debugged and no file bytes were modified.'
