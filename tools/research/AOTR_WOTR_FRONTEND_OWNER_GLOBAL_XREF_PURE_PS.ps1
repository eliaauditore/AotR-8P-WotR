param(
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY / PYTHON FREE.
# Scans executable PE sections for direct 32-bit references to the three
# runtime-proven frontend-owner module slots. It classifies only common,
# unambiguous x86 encodings and leaves anything else UNKNOWN.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ImageBase = [uint32]0x00400000
$Targets = @(
    [pscustomobject]@{ Address=[uint32]0x00DE6CD8; Name='OWNER_SLOT_A_DE6CD8' },
    [pscustomobject]@{ Address=[uint32]0x00DE6D1C; Name='OWNER_SLOT_B_DE6D1C' },
    [pscustomobject]@{ Address=[uint32]0x00DE8D90; Name='OWNER_SLOT_C_DE8D90' }
)

if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash=(Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if($hash -ne $ExpectedHash){throw "HASH MISMATCH. Expected $ExpectedHash got $hash"}

$data=[System.IO.File]::ReadAllBytes($GameDat)
if($data.Length -lt 0x1000){throw 'game.dat too small.'}
if($data[0] -ne 0x4D -or $data[1] -ne 0x5A){throw 'Not an MZ image.'}
$peOff=[BitConverter]::ToUInt32($data,0x3C)
if($peOff + 0x18 -ge $data.Length){throw 'Invalid PE header offset.'}
if($data[$peOff] -ne 0x50 -or $data[$peOff+1] -ne 0x45 -or $data[$peOff+2] -ne 0 -or $data[$peOff+3] -ne 0){throw 'Bad PE signature.'}
$numSections=[BitConverter]::ToUInt16($data,$peOff+6)
$optSize=[BitConverter]::ToUInt16($data,$peOff+20)
$secTable=$peOff+24+$optSize
if($numSections -le 0 -or $numSections -gt 96){throw "Suspicious section count: $numSections"}

$sections=New-Object System.Collections.Generic.List[object]
for($i=0;$i -lt $numSections;$i++){
    $o=$secTable+($i*40)
    if($o+40 -gt $data.Length){throw 'Section table exceeds file.'}
    $nameBytes=$data[$o..($o+7)]
    $zero=[Array]::IndexOf($nameBytes,[byte]0)
    if($zero -ge 0){$nameBytes=$nameBytes[0..([Math]::Max(0,$zero-1))]}
    $name=[Text.Encoding]::ASCII.GetString([byte[]]$nameBytes).Trim([char]0)
    $virtualSize=[BitConverter]::ToUInt32($data,$o+8)
    $rva=[BitConverter]::ToUInt32($data,$o+12)
    $rawSize=[BitConverter]::ToUInt32($data,$o+16)
    $rawPtr=[BitConverter]::ToUInt32($data,$o+20)
    $chars=[BitConverter]::ToUInt32($data,$o+36)
    if(([uint64]$rawPtr+[uint64]$rawSize) -gt [uint64]$data.Length){throw "Section $name exceeds file."}
    $sections.Add([pscustomobject]@{Name=$name;VirtualSize=$virtualSize;Rva=$rva;RawSize=$rawSize;RawPtr=$rawPtr;Characteristics=$chars;Executable=(($chars -band 0x20000000)-ne 0)})
}

function Hex-Bytes {
    param([byte[]]$Bytes)
    return (($Bytes|ForEach-Object{$_.ToString('X2')}) -join ' ')
}

function Get-ContextHex {
    param([int]$OperandRaw,[int]$Before=12,[int]$After=12)
    $lo=[Math]::Max(0,$OperandRaw-$Before)
    $hi=[Math]::Min($data.Length-1,$OperandRaw+3+$After)
    return Hex-Bytes ([byte[]]$data[$lo..$hi])
}

function Classify-DirectRef {
    param([int]$Pos)
    # Pos is the first byte of the 4-byte absolute address operand.
    $mode='UNKNOWN';$kind='UNKNOWN';$insStart=$null;$detail=''
    if($Pos -ge 1){
        $p1=$data[$Pos-1]
        switch($p1){
            0xA1 {$mode='READ';$kind='MOV_EAX_MOFFS32';$insStart=$Pos-1}
            0xA3 {$mode='WRITE';$kind='MOV_MOFFS32_EAX';$insStart=$Pos-1}
            0x68 {$mode='IMM_ADDR';$kind='PUSH_IMM32';$insStart=$Pos-1}
        }
        if($p1 -ge 0xB8 -and $p1 -le 0xBF){$mode='IMM_ADDR';$kind='MOV_REG_IMM32';$insStart=$Pos-1}
    }
    if($Pos -ge 2){
        $op=$data[$Pos-2];$mr=$data[$Pos-1]
        $absMem=(($mr -band 0xC7) -eq 0x05)
        if($absMem){
            switch($op){
                0x8B {$mode='READ';$kind='MOV_REG_MEM32';$insStart=$Pos-2}
                0x89 {$mode='WRITE';$kind='MOV_MEM32_REG';$insStart=$Pos-2}
                0x8A {$mode='READ';$kind='MOV_REG8_MEM8';$insStart=$Pos-2}
                0x88 {$mode='WRITE';$kind='MOV_MEM8_REG8';$insStart=$Pos-2}
                0x3B {$mode='READ';$kind='CMP_REG_MEM32';$insStart=$Pos-2}
                0x39 {$mode='READ';$kind='CMP_MEM32_REG';$insStart=$Pos-2}
                0x85 {$mode='READ';$kind='TEST_MEM32_REG';$insStart=$Pos-2}
                0x8D {$mode='IMM_ADDR';$kind='LEA_REG_ABS';$insStart=$Pos-2}
                0xC7 {$mode='WRITE';$kind='MOV_MEM32_IMM32';$insStart=$Pos-2}
                0xC6 {$mode='WRITE';$kind='MOV_MEM8_IMM8';$insStart=$Pos-2}
                0x81 {
                    $grp=($mr -shr 3)-band 7;$insStart=$Pos-2
                    if($grp -eq 7){$mode='READ';$kind='CMP_MEM32_IMM32'}else{$mode='READWRITE';$kind=('GRP81_MEM32_OP'+$grp)}
                }
                0x83 {
                    $grp=($mr -shr 3)-band 7;$insStart=$Pos-2
                    if($grp -eq 7){$mode='READ';$kind='CMP_MEM32_IMM8'}else{$mode='READWRITE';$kind=('GRP83_MEM32_OP'+$grp)}
                }
                0xFF {
                    $grp=($mr -shr 3)-band 7;$insStart=$Pos-2
                    switch($grp){
                        0 {$mode='READWRITE';$kind='INC_MEM32'}
                        1 {$mode='READWRITE';$kind='DEC_MEM32'}
                        2 {$mode='READ';$kind='CALL_MEM32'}
                        4 {$mode='READ';$kind='JMP_MEM32'}
                        6 {$mode='READ';$kind='PUSH_MEM32'}
                        default {$mode='READ';$kind=('FF_GROUP_'+$grp)}
                    }
                }
            }
        }
    }
    if($null -eq $insStart){$insStart=$Pos}
    $detail=('operandRaw=0x{0:X8}' -f $Pos)
    return [pscustomobject]@{Mode=$mode;Kind=$kind;InstructionRaw=[int]$insStart;Detail=$detail}
}

Write-Host '============================================================'
Write-Host ' AOTR WOTR FRONTEND OWNER GLOBAL XREF - PURE POWERSHELL'
Write-Host '============================================================'
Write-Host ("Image          : {0}" -f $GameDat)
Write-Host ("SHA256         : {0}" -f $hash)
Write-Host ("Sections       : {0}" -f $sections.Count)
Write-Host 'Python/Capstone : NOT USED'
Write-Host ''

$summary=New-Object System.Collections.Generic.List[object]
foreach($t in $Targets){
    $needle=[BitConverter]::GetBytes([uint32]$t.Address)
    $hits=New-Object System.Collections.Generic.List[object]
    foreach($s in $sections){
        if(-not $s.Executable -or $s.RawSize -lt 4){continue}
        $start=[int]$s.RawPtr;$end=[int]($s.RawPtr+$s.RawSize-4)
        for($p=$start;$p -le $end;$p++){
            if($data[$p] -ne $needle[0]){continue}
            if($data[$p+1] -ne $needle[1] -or $data[$p+2] -ne $needle[2] -or $data[$p+3] -ne $needle[3]){continue}
            $c=Classify-DirectRef -Pos $p
            $operandVa=[uint32]([uint64]$ImageBase+[uint64]$s.Rva+[uint64]($p-$s.RawPtr))
            $insVa=[uint32]([uint64]$ImageBase+[uint64]$s.Rva+[uint64]($c.InstructionRaw-$s.RawPtr))
            $hits.Add([pscustomobject]@{Section=$s.Name;OperandRaw=$p;OperandVA=$operandVa;InstructionRaw=$c.InstructionRaw;InstructionVA=$insVa;Mode=$c.Mode;Kind=$c.Kind;Context=(Get-ContextHex -OperandRaw $p)})
        }
    }
    $reads=@($hits|Where-Object{$_.Mode -eq 'READ'}).Count
    $writes=@($hits|Where-Object{$_.Mode -eq 'WRITE'}).Count
    $rw=@($hits|Where-Object{$_.Mode -eq 'READWRITE'}).Count
    $imms=@($hits|Where-Object{$_.Mode -eq 'IMM_ADDR'}).Count
    $unk=@($hits|Where-Object{$_.Mode -eq 'UNKNOWN'}).Count
    $summary.Add([pscustomobject]@{Name=$t.Name;Address=$t.Address;Total=$hits.Count;Reads=$reads;Writes=$writes;ReadWrite=$rw;Immediate=$imms;Unknown=$unk})

    Write-Host ("================ {0} 0x{1:X8} ================" -f $t.Name,$t.Address)
    Write-Host ("XREF_COUNT={0} READ_REFS={1} WRITE_REFS={2} READWRITE_REFS={3} IMM_REFS={4} UNKNOWN_REFS={5}" -f $hits.Count,$reads,$writes,$rw,$imms,$unk)
    $n=0
    foreach($h in $hits){
        $n++
        Write-Host ("XREF #{0}: VA=0x{1:X8} operandVA=0x{2:X8} section={3} mode={4} kind={5}" -f $n,$h.InstructionVA,$h.OperandVA,$h.Section,$h.Mode,$h.Kind)
        Write-Host ("  BYTES: {0}" -f $h.Context)
    }
    if($hits.Count -eq 0){Write-Host '  <no direct address references found in executable sections>'}
    Write-Host ''
}

Write-Host '================ COMPACT SUMMARY ================'
foreach($s in $summary){
    Write-Host ("{0}=0x{1:X8} XREFS={2} READS={3} WRITES={4} READWRITES={5} IMMS={6} UNKNOWN={7}" -f $s.Name,$s.Address,$s.Total,$s.Reads,$s.Writes,$s.ReadWrite,$s.Immediate,$s.Unknown)
}
Write-Host ''
Write-Host 'READ_ONLY_COMPLETE=YES'
Write-Host 'No Python, no process memory access, no WriteProcessMemory.'
