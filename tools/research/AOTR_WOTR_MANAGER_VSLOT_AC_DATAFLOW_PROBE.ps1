param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Broader follow-up to the direct CALL [reg+0xAC] probe.
# Finds every .text memory operand with displacement +0xAC and checks whether
# a function pointer loaded from that slot is called/jumped through shortly after.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'

if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

$py = Get-Command py.exe -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python.exe -ErrorAction SilentlyContinue }
if (-not $py) { throw 'Python not found.' }
$pyPath = $py.Source

& $pyPath -c "import capstone" 2>$null
if ($LASTEXITCODE -ne 0) { throw ('Python capstone missing. Install with: "{0}" -m pip install --user capstone' -f $pyPath) }

$tempPy = Join-Path $env:TEMP ('a8p_vslot_ac_df_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86_const import X86_OP_MEM, X86_OP_REG

path=sys.argv[1]
IMAGE_BASE=0x00400000
SLOT=0xAC

with open(path,'rb') as f:
    data=f.read()
if data[:2] != b'MZ': raise SystemExit('Not MZ')
pe=struct.unpack_from('<I',data,0x3C)[0]
if data[pe:pe+4] != b'PE\0\0': raise SystemExit('Bad PE')
num=struct.unpack_from('<H',data,pe+6)[0]
opt=struct.unpack_from('<H',data,pe+20)[0]
sec0=pe+24+opt
secs=[]
for i in range(num):
    o=sec0+i*40
    name=data[o:o+8].split(b'\0',1)[0].decode('ascii','replace')
    vs,rva,rs,rp=struct.unpack_from('<IIII',data,o+8)
    secs.append((name,rva,vs,rp,rs))

text=next((s for s in secs if s[0]=='.text'),None)
if not text: raise SystemExit('.text not found')
name,rva,vs,rp,rs=text
code=data[rp:rp+rs]
text_va=IMAGE_BASE+rva

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=True
ins=list(md.disasm(code,text_va))

hits=[]
for idx,x in enumerate(ins):
    memops=[]
    try:
        for oi,op in enumerate(x.operands):
            if op.type == X86_OP_MEM and op.mem.disp == SLOT:
                memops.append((oi,op))
    except Exception:
        pass
    if memops:
        loaded_reg=None
        if x.mnemonic == 'mov' and len(x.operands) >= 2:
            if x.operands[0].type == X86_OP_REG and x.operands[1].type == X86_OP_MEM and x.operands[1].mem.disp == SLOT:
                loaded_reg=x.reg_name(x.operands[0].reg)
        flow=[]
        if loaded_reg:
            for y in ins[idx+1:idx+9]:
                opclean=y.op_str.lower().strip()
                if y.mnemonic in ('call','jmp') and opclean == loaded_reg:
                    flow.append((y.address,y.mnemonic,y.op_str))
                    break
                # Stop if destination register is overwritten before use.
                try:
                    if y.operands and y.operands[0].type == X86_OP_REG:
                        d=y.reg_name(y.operands[0].reg)
                        if d == loaded_reg and y.mnemonic not in ('cmp','test'):
                            break
                except Exception:
                    pass
        hits.append((idx,x,loaded_reg,flow))

print('============================================================')
print(' AOTR WOTR MANAGER VSLOT +0xAC DATAFLOW PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash                    : {sys.argv[2]}')
print('Manager vtable                : 0x00C2FC58')
print('Known slot address            : 0x00C2FD04')
print('Known slot function           : 0x00787C09')
print(f'.text refs with mem disp +0xAC: {len(hits)}')
print('')

for n,(idx,x,loaded_reg,flow) in enumerate(hits,1):
    print(f'HIT #{n}: VA=0x{x.address:08X}  {x.mnemonic} {x.op_str}')
    if loaded_reg:
        print(f'  loaded function register: {loaded_reg}')
    if flow:
        for va,mn,op in flow:
            print(f'  FOLLOW-UP CONTROL FLOW: 0x{va:08X} {mn} {op}')
    lo=max(0,idx-10); hi=min(len(ins),idx+10)
    for y in ins[lo:hi]:
        mark='>>' if y.address==x.address else '  '
        b=' '.join(f'{v:02X}' for v in y.bytes)
        print(f'{mark} 0x{y.address:08X}: {b:<32} {y.mnemonic:<8} {y.op_str}')
    print('')

print('Interpretation:')
print('  - Direct CALL [reg+0xAC] may be absent even when slot +0xAC is used.')
print('  - MOV reg,[vtable+0xAC] followed by CALL/JMP reg is an equivalent virtual-dispatch shape.')
print('  - Non-control-flow +0xAC hits may be unrelated object fields; classify by surrounding vtable/object provenance.')
print('  - Zero hits here would suggest dynamic-index dispatch or no static invocation in this image, not that the vtable entry is invalid.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'vslot +0xAC dataflow probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
