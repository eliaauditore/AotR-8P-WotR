param(
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY / PS5.1 COMPATIBLE.
# 1) Finds every executable-image C7 /0 write of immediate 9 to [base+0x6A4].
# 2) Revalidates direct rel32 xrefs to POST_JOIN_REFRESH 0x008472BF.
# 3) Dumps exact bytes around 0x008472BF and the two known caller regions.
# 4) Prints raw rel32 call/jump candidates and DE-global dword candidates inside
#    the post-join function window. Raw candidate scans are not a disassembler.
# No process APIs, debugger APIs, Python, Capstone, or file writes are used.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ImageBase    = [uint32]0x00400000
$PostJoin     = [uint32]0x008472BF
$WindowStart  = [uint32]0x00847280
$WindowEnd    = [uint32]0x00847540

if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }
$Data = [IO.File]::ReadAllBytes($GameDat)

function U16([int]$Offset) { [BitConverter]::ToUInt16($Data,$Offset) }
function U32([int]$Offset) { [BitConverter]::ToUInt32($Data,$Offset) }

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
    $b
}
function Hex([byte[]]$Bytes) { (($Bytes | ForEach-Object { $_.ToString('X2') }) -join ' ') }
function Dump-Hex([uint32]$Start,[uint32]$End) {
    for ($v=[uint64]$Start; $v -lt [uint64]$End; $v += 16) {
        $n=[int][Math]::Min(16,[uint64]$End-$v)
        Write-Host ('0x{0:X8}: {1}' -f [uint32]$v,(Hex (Read-BytesVa ([uint32]$v) $n)))
    }
}
function Rel32-Target([uint32]$Src,[int]$Raw) {
    $disp=[BitConverter]::ToInt32($Data,$Raw+1)
    $t = (([int64][uint64]$Src + 5 + [int64]$disp) -band [int64]0xFFFFFFFF)
    return [uint32]$t
}
function Context([uint32]$Va,[int]$Before=16,[int]$After=24) {
    $lo=[uint32]($Va-$Before)
    Write-Host ('  0x{0:X8}: {1}' -f $lo,(Hex (Read-BytesVa $lo ($Before+$After))))
}

$ExecSections=@($Sections | Where-Object { ($_.Characteristics -band [uint32]0x20000000) -ne 0 })

Write-Host '============================================================'
Write-Host ' AOTR POSTJOIN STATE9 + 0x8472BF - PURE PS / READ ONLY'
Write-Host '============================================================'
Write-Host ('Image  : {0}' -f $GameDat)
Write-Host ('SHA256 : {0}' -f $hash)
Write-Host 'Mode   : DISK ONLY / NO PYTHON / NO PROCESS ACCESS'
Write-Host ''

Write-Host '================ STATE9 +0x6A4 WRITE UNIQUENESS ================'
# x86 C7 /0 with mod=10, disp32=0x6A4, imm32=9. ModRM may use any base r/m 0..7.
$state9Hits=@()
foreach ($s in $ExecSections) {
    $start=[int]$s.Raw; $end=[int]($s.Raw+$s.RawSize)
    for ($r=$start; $r -le $end-10; $r++) {
        if ($Data[$r] -ne 0xC7) { continue }
        $m=$Data[$r+1]
        if ($m -lt 0x80 -or $m -gt 0x87) { continue }
        if ($Data[$r+2] -ne 0xA4 -or $Data[$r+3] -ne 0x06 -or $Data[$r+4] -ne 0 -or $Data[$r+5] -ne 0) { continue }
        if ($Data[$r+6] -ne 0x09 -or $Data[$r+7] -ne 0 -or $Data[$r+8] -ne 0 -or $Data[$r+9] -ne 0) { continue }
        $va=[uint32]([uint64]$ImageBase+[uint64]$s.Rva+[uint64]($r-[int]$s.Raw))
        $state9Hits += [pscustomobject]@{VA=$va;ModRM=$m;Section=$s.Name}
    }
}
Write-Host ('STATE9_WRITE_COUNT={0}' -f $state9Hits.Count)
foreach ($h in $state9Hits) {
    Write-Host ('  VA=0x{0:X8} ModRM=0x{1:X2} Section={2}' -f $h.VA,$h.ModRM,$h.Section)
    Context $h.VA 12 34
}
if ($state9Hits.Count -eq 1 -and $state9Hits[0].VA -eq [uint32]0x008496F5) {
    Write-Host 'STATE9_WRITE_UNIQUE_AT_8496F5=YES' -ForegroundColor Green
} else {
    Write-Host 'STATE9_WRITE_UNIQUE_AT_8496F5=NO' -ForegroundColor Yellow
}
Write-Host ''

Write-Host '================ DIRECT REL32 XREF CANDIDATES TO 0x8472BF ================'
$xrefs=@()
foreach ($s in $ExecSections) {
    $start=[int]$s.Raw; $end=[int]($s.Raw+$s.RawSize)
    for ($r=$start; $r -le $end-5; $r++) {
        if ($Data[$r] -ne 0xE8 -and $Data[$r] -ne 0xE9) { continue }
        $src=[uint32]([uint64]$ImageBase+[uint64]$s.Rva+[uint64]($r-[int]$s.Raw))
        if ((Rel32-Target $src $r) -ne $PostJoin) { continue }
        $xrefs += [pscustomobject]@{VA=$src;Kind=$(if($Data[$r]-eq 0xE8){'CALL'}else{'JMP'});Section=$s.Name}
    }
}
Write-Host ('POSTJOIN_8472BF_XREF_COUNT={0}' -f $xrefs.Count)
foreach ($x in $xrefs) {
    Write-Host ('  0x{0:X8} {1} section={2}' -f $x.VA,$x.Kind,$x.Section)
    Context $x.VA 24 40
}
Write-Host ''

Write-Host '================ EXACT POST-JOIN WINDOW 0x847280..0x84753F ================'
Dump-Hex $WindowStart $WindowEnd
Write-Host ''

Write-Host '================ RAW REL32 CANDIDATES INSIDE POST-JOIN WINDOW ================'
$wr0=Va-ToRaw $WindowStart
$wr1=Va-ToRaw ([uint32]($WindowEnd-1))
for ($r=$wr0; $r -le $wr1-4; $r++) {
    $op=$Data[$r]
    if ($op -ne 0xE8 -and $op -ne 0xE9) { continue }
    $src=[uint32]([uint64]$WindowStart+[uint64]($r-$wr0))
    $t=Rel32-Target $src $r
    if ($t -lt [uint32]0x00400000 -or $t -ge [uint32]0x00ED4000) { continue }
    Write-Host ('  0x{0:X8} {1} -> 0x{2:X8} bytes={3}' -f $src,$(if($op-eq 0xE8){'CALL'}else{'JMP'}),$t,(Hex (Read-BytesVa $src 5)))
}
Write-Host ''

Write-Host '================ RAW DE00xx GLOBAL DWORD CANDIDATES IN WINDOW ================'
$seen=@{}
for ($r=$wr0; $r -le $wr1-3; $r++) {
    $v=[BitConverter]::ToUInt32($Data,$r)
    if ($v -lt [uint32]0x00DE0000 -or $v -gt [uint32]0x00DEFFFF) { continue }
    $src=[uint32]([uint64]$WindowStart+[uint64]($r-$wr0))
    $key=('{0:X8}:{1:X8}' -f $src,$v)
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key]=$true
    Write-Host ('  embedded dword at VA 0x{0:X8} -> 0x{1:X8}' -f $src,$v)
}
Write-Host ''

Write-Host '================ KNOWN CALLER ANCHORS ================'
foreach ($a in @([uint32]0x008487F2,[uint32]0x00849374,[uint32]0x00849379)) {
    Write-Host ('ANCHOR 0x{0:X8}' -f $a)
    Context $a 32 64
}
Write-Host ''
Write-Host 'READ_ONLY_COMPLETE=YES'
Write-Host 'No process was opened/debugged and no file bytes were modified.'
