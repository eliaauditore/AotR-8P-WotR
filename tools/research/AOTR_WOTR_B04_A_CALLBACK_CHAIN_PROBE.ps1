param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Follow-up after runtime proved B04 component B identical on HOST/VM and
# component A alone different. Resynchronizes the unique 0x638C52 caller from
# the true owner-function boundary, then traces the wrapper vtable 0xBFE4BC
# and the downstream 0x5B4A7C call. No file/process memory is modified.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

$py = Get-Command py.exe -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python.exe -ErrorAction SilentlyContinue }
if (-not $py) { throw 'Python not found.' }
$pyPath = $py.Source
& $pyPath -c "import capstone" 2>$null
if ($LASTEXITCODE -ne 0) { throw ('Python capstone missing. Install with: "{0}" -m pip install --user capstone' -f $pyPath) }

$tempPy = Join-Path $env:TEMP ('a8p_b04_a_chain_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86_const import X86_OP_IMM, X86_OP_MEM, X86_OP_REG, X86_REG_EBP

path=sys.argv[1]
IMAGE_BASE=0x00400000
OWNER=0x0063AD4F
OWNER_END=0x0063C830
CALLSITE=0x0063C7E8
PRODUCER=0x00638C52
DOWNSTREAM=0x005B4A7C
WRAP_VT=0x00BFE4BC

with open(path,'rb') as f: data=f.read()
pe=struct.unpack_from('<I',data,0x3c)[0]
if data[pe:pe+4] != b'PE\0\0': raise SystemExit('Bad PE')
num=struct.unpack_from('<H',data,pe+6)[0]
opt=struct.unpack_from('<H',data,pe+20)[0]
sec0=pe+24+opt
secs=[]
for i in range(num):
    o=sec0+i*40
    name=data[o:o+8].split(b'\0',1)[0].decode('ascii','replace')
    vs,rva,rs,rp=struct.unpack_from('<IIII',data,o+8)
    chars=struct.unpack_from('<I',data,o+36)[0]
    secs.append(dict(name=name,rva=rva,vs=vs,rs=rs,rp=rp,chars=chars))

def sec_for_va(va):
    rva=va-IMAGE_BASE
    for s in secs:
        if s['rva'] <= rva < s['rva']+max(s['vs'],s['rs']): return s
    return None

def rb(va,n):
    s=sec_for_va(va)
    if not s: raise ValueError(f'VA 0x{va:08X} not mapped')
    raw=s['rp']+((va-IMAGE_BASE)-s['rva'])
    return data[raw:raw+n],s,raw

def u32(va): return struct.unpack('<I',rb(va,4)[0])[0]

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def dis(start,end):
    b,s,raw=rb(start,end-start)
    return list(md.disasm(b,start)),s,raw

def fmt(x,mark='  ',note=''):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    q=f'{mark} 0x{x.address:08X}: {bs:<43} {x.mnemonic:<8} {x.op_str}'
    return q + ((' ; '+note) if note else '')

def target(x):
    if x.mnemonic not in ('call','jmp') or len(x.operands)!=1: return None
    op=x.operands[0]
    return (op.imm & 0xffffffff) if op.type==X86_OP_IMM else None

print('============================================================')
print(' AOTR WOTR B04 COMPONENT-A CALLBACK CHAIN PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print(f'Owner function   : 0x{OWNER:08X}')
print(f'Unique producer  : 0x{PRODUCER:08X}')
print(f'Owner callsite   : 0x{CALLSITE:08X}')
print(f'Downstream       : 0x{DOWNSTREAM:08X}')
print(f'Wrapper vtable   : 0x{WRAP_VT:08X}')
print('')

# Decode from the proven true owner boundary so callsite context cannot start mid-instruction.
owner_ins,s,raw=dis(OWNER,OWNER_END)
idx={x.address:i for i,x in enumerate(owner_ins)}
ci=idx.get(CALLSITE)
print('================ RESYNCHRONIZED OWNER CALLSITE ================')
if ci is None:
    print('ERROR: exact callsite did not decode from true owner boundary.')
else:
    lo=max(0,ci-55); hi=min(len(owner_ins),ci+12)
    for x in owner_ins[lo:hi]:
        n=''
        if x.address==CALLSITE: n='unique call to 0x638C52'
        if x.mnemonic=='push': n=(n+', ' if n else '')+'stack argument setup'
        print(fmt(x,'>>' if x.address==CALLSITE else '  ',n))
print('')

print('================ PRODUCER CONTRACT REFERENCE ================')
pins,_,_=dis(PRODUCER,0x00638CC7)
for x in pins:
    note=''
    if x.address==0x00638C61: note='ESI = arg1/output pointer'
    elif x.address==0x00638C5E: note='EDI = arg3'
    elif x.address==0x00638C6A: note='*arg1 = arg3'
    elif x.address==0x00638C76: note='wrapper+4 = output pointer'
    elif x.address==0x00638C79: note='wrapper vtable = 0xBFE4BC'
    elif x.address==0x00638CA8: note='downstream call 0x5B4A7C'
    print(fmt(x,'>>' if note else '  ',note))
print('')

print('================ WRAPPER VTABLE 0xBFE4BC ================')
vt_targets=[]
for off in range(0,0x40,4):
    try: t=u32(WRAP_VT+off)
    except Exception: break
    sec=sec_for_va(t)
    executable=bool(sec and (sec['chars'] & 0x20000000))
    print(f'+0x{off:02X} -> 0x{t:08X} section={sec["name"] if sec else "<none>"} exec={executable}')
    if executable and t not in [q for _,q in vt_targets]: vt_targets.append((off,t))
print('')

print('================ WRAPPER METHOD EXCERPTS ================')
for off,t in vt_targets:
    print(f'\n--- vtable +0x{off:02X} -> 0x{t:08X} ---')
    try:
        ii,_,_=dis(t,t+0x120)
        for x in ii[:70]:
            notes=[]
            # Highlight this+4 and writes through values derived from this+4.
            for op in x.operands:
                if op.type==X86_OP_MEM and op.mem.disp==4:
                    notes.append('MEM +4 (wrapper stores output pointer here)')
                if op.type==X86_OP_MEM and op.mem.disp==0x44:
                    notes.append('MEM +0x44 (Component-A target offset)')
            if x.mnemonic=='call':
                tt=target(x)
                notes.append('CALL '+(f'0x{tt:08X}' if tt is not None else x.op_str))
            print(fmt(x,'>>' if notes else '  ', ', '.join(notes)))
            if x.mnemonic.startswith('ret'): break
    except Exception as e:
        print(f'<decode failed: {e}>')
print('')

print('================ DOWNSTREAM 0x5B4A7C FOCUSED DISASSEMBLY ================')
# 0x600 bytes is intentionally bounded. We only need entry argument routing / wrapper use.
dins,ds,draw=dis(DOWNSTREAM,DOWNSTREAM+0x600)
print(f'section={ds["name"]} raw=0x{draw:X}')
for x in dins:
    notes=[]
    # Stack argument accesses.
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.base==X86_REG_EBP and 8 <= op.mem.disp <= 0x30:
            notes.append(f'STACK_ARG +0x{op.mem.disp:X}')
        if op.type==X86_OP_MEM and op.mem.disp==0x44:
            notes.append('MEM +0x44')
    if x.mnemonic=='call':
        tt=target(x)
        notes.append('CALL '+(f'0x{tt:08X}' if tt is not None else x.op_str))
    # Keep full entry and all annotated lines; avoid dumping hundreds of irrelevant instructions.
    if x.address < DOWNSTREAM+0x90 or notes:
        print(fmt(x,'>>' if notes else '  ', ', '.join(notes)))
    if x.mnemonic.startswith('ret') and x.address > DOWNSTREAM+0x20:
        break
print('')

print('================ DOWNSTREAM STACK-ARG ROUTING SUMMARY ================')
for x in dins:
    if x.address > DOWNSTREAM+0x600: break
    hit=[]
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.base==X86_REG_EBP and 8 <= op.mem.disp <= 0x30:
            hit.append(f'[ebp+0x{op.mem.disp:X}]')
    if hit:
        print(fmt(x,'>>','args='+','.join(hit)))
print('')

print('================ INTERPRETATION TARGETS ================')
print('1) Correct the prior mid-instruction owner-window artifact by decoding from 0x63AD4F.')
print('2) Resolve which exact caller argument points at localRoot [ebp-0x6C].')
print('3) Trace wrapper vtable 0xBFE4BC; wrapper+4 stores the output/local-root pointer.')
print('4) Identify whether a wrapper method or 0x5B4A7C writes localRoot+0x44 (Component A).')
print('5) Runtime already proved Component B identical and Component A alone causes HOST/VM B04 mismatch.')
print('6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'B04 Component-A callback-chain probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
