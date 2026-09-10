param(
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY / PS5.1 COMPATIBLE.
# Focuses only on the two helper functions reached from 0x8472BF for owner State != 1:
#   0x846C6D(arg)
#   0x846CDE(arg)
# No process APIs, debugger APIs, Python, Capstone, or file writes are used.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ImageBase = [uint32]0x00400000
$HelperA = [uint32]0x00846C6D
$HelperB = [uint32]0x00846CDE
$RegionStart = [uint32]0x00846C40
$RegionEnd   = [uint32]0x00846D40

if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash=(Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }
$Data=[IO.File]::ReadAllBytes($GameDat)

function U16([int]$Offset) { [BitConverter]::ToUInt16($Data,$Offset) }
function U32([int]$Offset) { [BitConverter]::ToUInt32($Data,$Offset) }

if ($Data.Length -lt 0x1000 -or $Data[0] -ne 0x4D -or $Data[1] -ne 0x5A) { throw 'Not an MZ image.' }
$pe=[int](U32 0x3C)
if ($Data[$pe] -ne 0x50 -or $Data[$pe+1] -ne 0x45 -or $Data[$pe+2] -ne 0 -or $Data[$pe+3] -ne 0) { throw 'Bad PE signature.' }
$numSections=[int](U16 ($pe+6))
$optSize=[int](U16 ($pe+20))
$sec0=$pe+24+$optSize
$Sections=@()
for($i=0;$i-lt$numSections;$i++){
    $o=$sec0+($i*40)
    $nameBytes=New-Object byte[] 8
    [Array]::Copy($Data,$o,$nameBytes,0,8)
    $name=([Text.Encoding]::ASCII.GetString($nameBytes)).Trim([char]0)
    $Sections += [pscustomobject]@{
        Name=$name
        VirtualSize=[uint32](U32 ($o+8))
        Rva=[uint32](U32 ($o+12))
        RawSize=[uint32](U32 ($o+16))
        Raw=[uint32](U32 ($o+20))
        Characteristics=[uint32](U32 ($o+36))
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
function Read-BytesVa([uint32]$Va,[int]$Count){
    $raw=Va-ToRaw $Va
    if($raw-lt0 -or ($raw+$Count)-gt$Data.Length){ throw ('Read outside file: 0x{0:X8}' -f $Va) }
    $b=New-Object byte[] $Count
    [Array]::Copy($Data,$raw,$b,0,$Count)
    return $b
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
    while($t-lt0){$t+=4294967296}
    while($t-ge4294967296){$t-=4294967296}
    return [uint32]$t
}
function Context([uint32]$Va,[int]$Before=16,[int]$After=32){
    $lo=[uint32]($Va-$Before)
    Write-Host ('  0x{0:X8}: {1}' -f $lo,(Hex (Read-BytesVa $lo ($Before+$After))))
}

$ExecSections=@($Sections|Where-Object{($_.Characteristics-band[uint32]0x20000000)-ne0})

Write-Host '============================================================'
Write-Host ' AOTR POSTJOIN HELPERS 0x846C6D / 0x846CDE - PURE PS'
Write-Host '============================================================'
Write-Host ('Image  : {0}' -f $GameDat)
Write-Host ('SHA256 : {0}' -f $hash)
Write-Host 'Mode   : DISK ONLY / READ ONLY / NO PYTHON / NO PROCESS ACCESS'
Write-Host ''
Write-Host 'Known predecessor for State8/9: 0x8472BF -> HelperB(2) -> HelperB(1)'
Write-Host ''

Write-Host '================ EXACT HELPER REGION 0x846C40..0x846D3F ================'
Dump-Hex $RegionStart $RegionEnd
Write-Host ''

foreach($target in @($HelperA,$HelperB)){
    Write-Host ('================ DIRECT REL32 XREFS TO 0x{0:X8} ================' -f $target)
    $hits=@()
    foreach($s in $ExecSections){
        $start=[int]$s.Raw; $end=[int]($s.Raw+$s.RawSize)
        for($r=$start;$r-le$end-5;$r++){
            if($Data[$r]-ne0xE8 -and $Data[$r]-ne0xE9){continue}
            $src=[uint32]([uint64]$ImageBase+[uint64]$s.Rva+[uint64]($r-[int]$s.Raw))
            if((Rel32-Target $src $r)-ne$target){continue}
            $hits += [pscustomobject]@{VA=$src;Kind=$(if($Data[$r]-eq0xE8){'CALL'}else{'JMP'});Section=$s.Name}
        }
    }
    Write-Host ('XREF_COUNT={0}' -f $hits.Count)
    foreach($h in $hits){
        Write-Host ('  0x{0:X8} {1} section={2}' -f $h.VA,$h.Kind,$h.Section)
        Context $h.VA 18 34
    }
    Write-Host ''
}

Write-Host '================ REL32 TARGETS INSIDE HELPER REGION ================'
$rr0=Va-ToRaw $RegionStart
$rr1=Va-ToRaw ([uint32]($RegionEnd-1))
$count=0
for($r=$rr0;$r-le$rr1-4;$r++){
    $op=$Data[$r]
    if($op-ne0xE8 -and $op-ne0xE9){continue}
    $src=[uint32]([uint64]$RegionStart+[uint64]($r-$rr0))
    $t=Rel32-Target $src $r
    if($t-lt[uint32]0x00400000 -or $t-ge[uint32]0x00ED4000){continue}
    $count++
    Write-Host ('  0x{0:X8} {1} -> 0x{2:X8} bytes={3}' -f $src,$(if($op-eq0xE8){'CALL'}else{'JMP'}),$t,(Hex (Read-BytesVa $src 5)))
}
Write-Host ('HELPER_REGION_REL32_IN_IMAGE_COUNT={0}' -f $count)
Write-Host ''

Write-Host '================ EMBEDDED DE00xx GLOBAL DWORDS IN HELPER REGION ================'
$seen=@{}; $gcount=0
for($r=$rr0;$r-le$rr1-3;$r++){
    $v=[BitConverter]::ToUInt32($Data,$r)
    if($v-lt[uint32]0x00DE0000 -or $v-gt[uint32]0x00DEFFFF){continue}
    $src=[uint32]([uint64]$RegionStart+[uint64]($r-$rr0))
    $key=('{0:X8}:{1:X8}' -f $src,$v)
    if($seen.ContainsKey($key)){continue}
    $seen[$key]=$true; $gcount++
    Write-Host ('  embedded dword at VA 0x{0:X8} -> 0x{1:X8}' -f $src,$v)
}
Write-Host ('HELPER_REGION_DE_GLOBAL_COUNT={0}' -f $gcount)
Write-Host ''

Write-Host '================ KNOWN 0x8472BF STATE!=1 CALLSITE BYTES ================'
foreach($a in @([uint32]0x00847351,[uint32]0x00847360,[uint32]0x0084736B)){
    Write-Host ('ANCHOR 0x{0:X8}' -f $a)
    Context $a 12 28
}
Write-Host ''
Write-Host 'READ_ONLY_COMPLETE=YES'
Write-Host 'No process was opened/debugged and no file bytes were modified.'
