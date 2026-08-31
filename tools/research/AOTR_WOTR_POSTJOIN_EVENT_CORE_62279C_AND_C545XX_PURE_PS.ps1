param(
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY / PS5.1 COMPATIBLE.
# Classifies the common 0x0062279C target used by frontend HelperA/HelperB and
# inspects the four C545xx arguments paired with owner+0x6BC bits 0/1.
# No process APIs, debugger APIs, Python, Capstone, or file writes are used.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ImageBase = [uint32]0x00400000
$Core = [uint32]0x0062279C
$CoreStart = [uint32]0x00622760
$CoreEnd   = [uint32]0x00622920
$ConstStart = [uint32]0x00C545A0
$ConstEnd   = [uint32]0x00C54620
$Constants = @([uint32]0x00C545C0,[uint32]0x00C545D0,[uint32]0x00C545E4,[uint32]0x00C545F4)

if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }
$Data = [IO.File]::ReadAllBytes($GameDat)

function U16([int]$Offset) { [BitConverter]::ToUInt16($Data,$Offset) }
function U32([int]$Offset) { [BitConverter]::ToUInt32($Data,$Offset) }
if ($Data.Length -lt 0x1000 -or $Data[0] -ne 0x4D -or $Data[1] -ne 0x5A) { throw 'Not an MZ image.' }
$pe=[int](U32 0x3C)
if ($Data[$pe] -ne 0x50 -or $Data[$pe+1] -ne 0x45 -or $Data[$pe+2] -ne 0 -or $Data[$pe+3] -ne 0) { throw 'Bad PE signature.' }
$num=[int](U16 ($pe+6)); $opt=[int](U16 ($pe+20)); $sec0=$pe+24+$opt
$Sections=@()
for($i=0;$i-lt$num;$i++){
    $o=$sec0+($i*40); $nb=New-Object byte[] 8; [Array]::Copy($Data,$o,$nb,0,8)
    $Sections += [pscustomobject]@{
        Name=([Text.Encoding]::ASCII.GetString($nb)).Trim([char]0)
        VirtualSize=[uint32](U32 ($o+8)); Rva=[uint32](U32 ($o+12)); RawSize=[uint32](U32 ($o+16)); Raw=[uint32](U32 ($o+20)); Characteristics=[uint32](U32 ($o+36))
    }
}
function Va-ToRaw([uint32]$Va){
    $rva=[uint32]($Va-$ImageBase)
    foreach($s in $Sections){
        $span=[Math]::Max([uint64]$s.VirtualSize,[uint64]$s.RawSize)
        if([uint64]$rva-ge[uint64]$s.Rva -and [uint64]$rva-lt([uint64]$s.Rva+$span)){
            $rel=[uint64]$rva-[uint64]$s.Rva
            if($rel-ge[uint64]$s.RawSize){ throw ('VA maps to virtual tail: 0x{0:X8}' -f $Va) }
            return [int]([uint64]$s.Raw+$rel)
        }
    }
    throw ('VA not mapped: 0x{0:X8}' -f $Va)
}
function Raw-ToVa([int]$Raw,$s){ [uint32]([uint64]$ImageBase+[uint64]$s.Rva+[uint64]($Raw-[int]$s.Raw)) }
function Read-BytesVa([uint32]$Va,[int]$Count){
    $r=Va-ToRaw $Va; if($r+$Count-gt$Data.Length){throw 'read past EOF'}
    $b=New-Object byte[] $Count; [Array]::Copy($Data,$r,$b,0,$Count); $b
}
function Hex([byte[]]$Bytes){ (($Bytes|ForEach-Object{$_.ToString('X2')}) -join ' ') }
function Dump-Hex([uint32]$Start,[uint32]$End){
    for($v=[uint64]$Start;$v-lt[uint64]$End;$v+=16){
        $n=[int][Math]::Min(16,[uint64]$End-$v)
        Write-Host ('0x{0:X8}: {1}' -f [uint32]$v,(Hex (Read-BytesVa ([uint32]$v) $n)))
    }
}
function Rel32-Target([uint32]$Src,[int]$Raw){
    $disp=[BitConverter]::ToInt32($Data,$Raw+1)
    $t=[int64][uint64]$Src + 5 + [int64]$disp
    $mod=[int64]4294967296
    $t=$t % $mod; if($t-lt0){$t+=$mod}
    [uint32]$t
}
function Find-ImmediateDword([uint32]$Value){
    $pat=[BitConverter]::GetBytes($Value); $hits=@()
    foreach($s in @($Sections|Where-Object{($_.Characteristics-band[uint32]0x20000000)-ne0})){
        $start=[int]$s.Raw; $end=[int]($s.Raw+$s.RawSize)
        for($r=$start;$r-le$end-4;$r++){
            if($Data[$r]-eq$pat[0]-and$Data[$r+1]-eq$pat[1]-and$Data[$r+2]-eq$pat[2]-and$Data[$r+3]-eq$pat[3]){
                $hits += [pscustomobject]@{VA=(Raw-ToVa $r $s);Section=$s.Name}
            }
        }
    }
    $hits
}

Write-Host '============================================================'
Write-Host ' AOTR POSTJOIN EVENT CORE 0x62279C + C545xx - PURE PS'
Write-Host '============================================================'
Write-Host ('Image  : {0}' -f $GameDat)
Write-Host ('SHA256 : {0}' -f $hash)
Write-Host 'Mode   : DISK ONLY / READ ONLY / NO PYTHON / NO PROCESS ACCESS'
Write-Host ''

Write-Host '================ CORE 0x62279C RAW WINDOW ================'
Dump-Hex $CoreStart $CoreEnd
Write-Host ''

Write-Host '================ REL32 TARGETS IN CORE WINDOW ================'
$cr0=Va-ToRaw $CoreStart; $cr1=Va-ToRaw ([uint32]($CoreEnd-1)); $count=0
for($r=$cr0;$r-le$cr1-4;$r++){
    $op=$Data[$r]; if($op-ne0xE8-and$op-ne0xE9){continue}
    $src=[uint32]([uint64]$CoreStart+[uint64]($r-$cr0)); $t=Rel32-Target $src $r
    if($t-ge[uint32]0x00400000-and$t-lt[uint32]0x00ED4000){
        $count++; Write-Host ('  0x{0:X8} {1} -> 0x{2:X8} bytes={3}' -f $src,$(if($op-eq0xE8){'CALL'}else{'JMP'}),$t,(Hex (Read-BytesVa $src 5)))
    }
}
Write-Host ('CORE_REL32_IN_IMAGE_COUNT={0}' -f $count)
Write-Host ''

Write-Host '================ DIRECT REL32 CALL/JMP XREFS TO 0x62279C ================'
$xrefs=@()
foreach($s in @($Sections|Where-Object{($_.Characteristics-band[uint32]0x20000000)-ne0})){
    $start=[int]$s.Raw; $end=[int]($s.Raw+$s.RawSize)
    for($r=$start;$r-le$end-5;$r++){
        $op=$Data[$r]; if($op-ne0xE8-and$op-ne0xE9){continue}
        $src=Raw-ToVa $r $s
        if((Rel32-Target $src $r)-eq$Core){$xrefs += [pscustomobject]@{VA=$src;Kind=$(if($op-eq0xE8){'CALL'}else{'JMP'});Section=$s.Name}}
    }
}
Write-Host ('CORE_62279C_XREF_COUNT={0}' -f $xrefs.Count)
foreach($x in $xrefs){ Write-Host ('  0x{0:X8} {1} section={2}' -f $x.VA,$x.Kind,$x.Section) }
Write-Host ''

Write-Host '================ C545xx RAW DATA ================'
Dump-Hex $ConstStart $ConstEnd
Write-Host ''
foreach($c in $Constants){
    $raw=Va-ToRaw $c
    $bytes=Read-BytesVa $c 32
    $d0=[BitConverter]::ToUInt32($Data,$raw)
    $d1=[BitConverter]::ToUInt32($Data,$raw+4)
    $d2=[BitConverter]::ToUInt32($Data,$raw+8)
    $d3=[BitConverter]::ToUInt32($Data,$raw+12)
    Write-Host ('CONST 0x{0:X8}: dwords=[0x{1:X8},0x{2:X8},0x{3:X8},0x{4:X8}] bytes={5}' -f $c,$d0,$d1,$d2,$d3,(Hex $bytes))
    $hits=@(Find-ImmediateDword $c)
    Write-Host ('  EXEC_IMAGE_IMMEDIATE_XREF_COUNT={0}' -f $hits.Count)
    foreach($h in $hits){ Write-Host ('    embedded at 0x{0:X8} section={1}' -f $h.VA,$h.Section) }
}
Write-Host ''

Write-Host '================ KNOWN HELPER CALL ARGUMENT WINDOWS ================'
foreach($a in @([uint32]0x00846C80,[uint32]0x00846CB3,[uint32]0x00846CF1,[uint32]0x00846D24)){
    Write-Host ('ANCHOR 0x{0:X8}: {1}' -f $a,(Hex (Read-BytesVa $a 48)))
}
Write-Host ''
Write-Host 'READ_ONLY_COMPLETE=YES'
Write-Host 'No process was opened/debugged and no file bytes were modified.'
