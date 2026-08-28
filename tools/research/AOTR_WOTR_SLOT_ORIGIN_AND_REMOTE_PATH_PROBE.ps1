param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

$tempPy = Join-Path $env:TEMP ('a8p_slot_origin_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_OP_IMM, CS_OP_MEM, CS_OP_REG
from capstone.x86_const import X86_REG_EBP, X86_REG_EDI, X86_REG_EBX

path=sys.argv[1]
IMAGE_BASE=0x00400000
ERR_PROLOG_TARGET=0x00A3CEF0
TARGETS={
    0x008014F1:'PLAYERINFO_ASSIGN',
    0x0084B01B:'GAMEINFO_SLOT_SETTER',
    0x0084DF19:'PLAYERINFO_STACK_COPY',
    0x00649242:'PLAYERINFO_HELPER_A',
    0x00649279:'PLAYERINFO_HELPER_B',
    0x0084A419:'GAMEINFO_GET_ROW',
}
PATHS=[
    ('PATH_A',0x0098A40E,0x0098A482),
    ('PATH_B',0x0098A6BB,0x0098A6DD),
    ('PATH_C',0x0098ACB2,0x0098AD9D),
]

with open(path,'rb') as f: data=f.read()
pe=struct.unpack_from('<I',data,0x3c)[0]
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

def va_to_raw(va):
    rva=va-IMAGE_BASE
    for s in secs:
        span=max(s['vs'],s['rs'])
        if s['rva'] <= rva < s['rva']+span:
            return s['rp'] + (rva-s['rva']), s
    return None,None

def rel_target(va, raw):
    op=data[raw]
    if op not in (0xE8,0xE9): return None
    rel=struct.unpack_from('<i',data,raw+1)[0]
    return (va+5+rel) & 0xffffffff

def find_func_start(anchor,back=0x1200):
    raw_anchor,s=va_to_raw(anchor)
    if raw_anchor is None: return None
    lo=max(s['rp'], raw_anchor-back)
    best=None
    # Binary frequently uses: B8 imm32 ; E8 rel32 -> 0xA3CEF0 as function start.
    for raw in range(lo, raw_anchor-9):
        if data[raw] != 0xB8 or data[raw+5] != 0xE8: continue
        va=IMAGE_BASE+s['rva']+(raw-s['rp'])
        dst=rel_target(va+5,raw+5)
        if dst==ERR_PROLOG_TARGET:
            best=va
    return best

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=True

def disasm_func(start, anchor_after, maxlen=0x1200):
    raw,s=va_to_raw(start)
    blob=data[raw:min(raw+maxlen,s['rp']+s['rs'])]
    out=[]
    passed=False
    for x in md.disasm(blob,start):
        out.append(x)
        if x.address >= anchor_after: passed=True
        if passed and x.mnemonic.startswith('ret'):
            break
    return out

def fmt(x,mark='  '):
    b=' '.join(f'{v:02X}' for v in x.bytes)
    ann=''
    if x.mnemonic in ('call','jmp') and x.operands and x.operands[0].type==CS_OP_IMM:
        d=x.operands[0].imm & 0xffffffff
        if d in TARGETS: ann=' ; '+TARGETS[d]
    return f'{mark} 0x{x.address:08X}: {b:<34} {x.mnemonic:<8} {x.op_str}{ann}'

def mem_is_ebp_disp(op,disp):
    return op.type==CS_OP_MEM and op.mem.base==X86_REG_EBP and op.mem.index==0 and op.mem.disp==disp

print('============================================================')
print(' AOTR WOTR SLOT ORIGIN / REMOTE PATH PROBE - DISK ONLY')
print('============================================================')
print('Image hash:',sys.argv[2])

for name,typecall,setter in PATHS:
    start=find_func_start(typecall)
    print(f'\n================ {name} ================')
    print(f'Type call   : 0x{typecall:08X}')
    print(f'Setter call : 0x{setter:08X}')
    print('Function start:', f'0x{start:08X}' if start else '<not found>')
    if start is None: continue
    ins=disasm_func(start,setter)
    idx={x.address:i for i,x in enumerate(ins)}
    # Print only from function start through modestly after setter, preserving args/origins.
    for x in ins:
        mark='>>' if x.address in (typecall,setter) else '  '
        print(fmt(x,mark))

    print(f'\n----- {name} ARG/ORIGIN SUMMARY -----')
    # What is pushed immediately before Type assignment?
    ti=idx.get(typecall)
    if ti is not None:
        print('Last 8 instructions before PLAYERINFO_ASSIGN:')
        for x in ins[max(0,ti-8):ti]: print(fmt(x))

    si=idx.get(setter)
    if si is not None:
        print('Last 12 instructions before GAMEINFO_SLOT_SETTER:')
        for x in ins[max(0,si-12):si]: print(fmt(x))

    if name=='PATH_A':
        print('Writes/loads involving [ebp-0x14] (slot carrier candidate):')
        for x in ins[:si+1 if si is not None else len(ins)]:
            if any(mem_is_ebp_disp(op,-0x14) for op in x.operands): print(fmt(x))
    elif name=='PATH_B':
        print('Uses of [ebp+0x10] (setter slot argument is direct function arg candidate):')
        for x in ins[:si+1 if si is not None else len(ins)]:
            if any(mem_is_ebp_disp(op,0x10) for op in x.operands): print(fmt(x))
        print('EDI definitions before PLAYERINFO_ASSIGN (Type source candidate):')
        for x in ins[:ti+1 if ti is not None else len(ins)]:
            if x.operands and x.operands[0].type==CS_OP_REG and x.operands[0].reg==X86_REG_EDI:
                print(fmt(x))
    elif name=='PATH_C':
        print('EBX / [ebp-0x10] origins before setter (slot carrier candidates):')
        for x in ins[:si+1 if si is not None else len(ins)]:
            hit=False
            for op in x.operands:
                if op.type==CS_OP_REG and op.reg==X86_REG_EBX: hit=True
                if mem_is_ebp_disp(op,-0x10): hit=True
            if hit: print(fmt(x))

print('\nInterpretation targets:')
print('  1) Resolve exact function starts for PATH_A/B/C using the binary\'s standard error-prologue signature.')
print('  2) PATH_A: prove where [ebp-0x14] slot index originates.')
print('  3) PATH_B: prove [ebp+0x10] is a function argument and resolve EDI/type origin.')
print('  4) PATH_C: resolve EBX/[ebp-0x10] slot origin and classify deserialize/import vs live join.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'slot origin probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
