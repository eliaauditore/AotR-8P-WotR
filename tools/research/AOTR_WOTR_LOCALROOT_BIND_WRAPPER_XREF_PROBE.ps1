param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Corrects the previous missed-xref result. 0x931EE2 is a proven wrapper that
# directly calls 0xA20DD0 at 0x931F00. This probe resolves callers/vtable xrefs
# of 0x931EE2 and the argument setup feeding the concrete sink object.

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

$tempPy = Join-Path $env:TEMP ('a8p_localroot_bind_wrapper_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86_const import X86_OP_IMM, X86_OP_MEM

path=sys.argv[1]
IMAGE_BASE=0x00400000
WRAPPER=0x00931EE2
SETTER=0x00A20DD0
KNOWN_SETTER_CALL=0x00931F00

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
    return list(md.disasm(b,start))

def fmt(x,mark='  ',note=''):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    z=f'{mark} 0x{x.address:08X}: {bs:<43} {x.mnemonic:<8} {x.op_str}'
    return z + ((' ; '+note) if note else '')

def direct_target(x):
    if x.mnemonic!='call' or len(x.operands)!=1: return None
    op=x.operands[0]
    if op.type==X86_OP_IMM: return op.imm & 0xffffffff
    return None

print('============================================================')
print(' AOTR WOTR LOCALROOT BIND-WRAPPER XREF PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print(f'Binding wrapper  : 0x{WRAPPER:08X}')
print(f'Exact setter     : 0x{SETTER:08X}')
print(f'Known setter call: 0x{KNOWN_SETTER_CALL:08X}')
print('')

print('================ EXACT 0x931EE2 WRAPPER ================')
win=dis(WRAPPER,0x00931F30)
for x in win:
    note=''
    if x.address==KNOWN_SETTER_CALL: note='DIRECT call to 0xA20DD0'
    if x.address==0x00931EEE: note='this->vfunc(+0x10) before bind'
    if x.address in (0x00931EF9,0x00931EFA,0x00931EFC): note='A20DD0 argument setup'
    print(fmt(x,'>>' if note else '  ',note))
    if x.mnemonic.startswith('ret'): break
print('')
print('Proven wrapper call shape:')
print('  ECX = wrapper this/localRoot-like object')
print('  A20DD0 arg1 = original wrapper arg1 (candidate sink object)')
print('  A20DD0 arg2 = 1')
print('  A20DD0 arg3 = boolean derived from this->vfunc(+0x10)')
print('')

# Disassemble executable sections once and collect direct calls robustly.
all_exec=[]
for s in secs:
    if not (s['chars'] & 0x20000000) or s['rs']==0: continue
    raw=s['rp']; blob=data[raw:raw+s['rs']]; va=IMAGE_BASE+s['rva']
    all_exec.extend(md.disasm(blob,va))

wrapper_calls=[x for x in all_exec if direct_target(x)==WRAPPER]
setter_calls=[x for x in all_exec if direct_target(x)==SETTER]
print('================ DIRECT CALLERS FOUND BY FULL .TEXT DISASSEMBLY ================')
print(f'callers of 0x{WRAPPER:08X}: {len(wrapper_calls)}')
for x in wrapper_calls: print(f'  0x{x.address:08X}')
print(f'calls to 0x{SETTER:08X}: {len(setter_calls)}')
for x in setter_calls: print(f'  0x{x.address:08X}')
print('')

# Print resynchronized windows before each wrapper direct caller.
print('================ WRAPPER DIRECT-CALL ARGUMENT WINDOWS ================')
for c in wrapper_calls:
    ins=dis(max(IMAGE_BASE,c.address-0x90),c.address+0x20)
    print(f'\n--- direct call @ 0x{c.address:08X} ---')
    for x in ins:
        if c.address-0x50 <= x.address <= c.address+8:
            n=''
            if x.address==c.address: n='CALL wrapper 0x931EE2'
            elif x.mnemonic=='push': n='possible argument setup'
            print(fmt(x,'>>' if n else '  ',n))
print('')

# Raw dword xrefs in non-executable sections are appropriate for vtables/function-pointer tables.
pat=struct.pack('<I',WRAPPER)
ptr_refs=[]
for s in secs:
    if (s['chars'] & 0x20000000) or s['rs']<4: continue
    blob=data[s['rp']:s['rp']+s['rs']]
    pos=0
    while True:
        k=blob.find(pat,pos)
        if k<0: break
        ptr_refs.append(IMAGE_BASE+s['rva']+k)
        pos=k+1

print('================ NON-EXEC POINTER XREFS TO 0x931EE2 ================')
print(f'count={len(ptr_refs)}')
for p in ptr_refs:
    s=sec_for_va(p)
    print(f'\nref @ 0x{p:08X} section={s["name"] if s else "?"}')
    for q in range(p-0x20,p+0x24,4):
        try:
            v=u32(q); ts=sec_for_va(v); ex=bool(ts and (ts['chars']&0x20000000))
            mark='>>' if q==p else '  '
            print(f'{mark} 0x{q:08X}: 0x{v:08X} exec={ex} section={ts["name"] if ts else "<none>"}')
        except Exception: pass
print('')

# For each pointer ref, find immediate constants to nearby plausible table bases.
print('================ CODE REFERENCES NEAR WRAPPER POINTER TABLES ================')
for p in ptr_refs:
    lo=p-0x80; hi=p+4
    hits=[]
    for x in all_exec:
        for op in x.operands:
            if op.type==X86_OP_IMM and lo <= (op.imm & 0xffffffff) <= hi:
                hits.append((x,op.imm & 0xffffffff))
            elif op.type==X86_OP_MEM and op.mem.base==0 and op.mem.index==0 and lo <= (op.mem.disp & 0xffffffff) <= hi:
                hits.append((x,op.mem.disp & 0xffffffff))
    if hits:
        print(f'\n--- refs around pointer slot 0x{p:08X} ---')
        for x,v in hits[:80]: print(fmt(x,'>>',f'references 0x{v:08X}'))
print('')

# Also explicitly prove the previous scanner miss: known call must decode to SETTER.
known=[x for x in all_exec if x.address==KNOWN_SETTER_CALL]
print('================ SCANNER CORRECTION CHECK ================')
if known:
    t=direct_target(known[0])
    print(fmt(known[0],'>>',f'decoded direct target=0x{t:08X}' if t is not None else 'no direct target'))
    print('Previous count=0 for 0xA20DD0 direct callers is FALSIFIED if target is 0xA20DD0.')
else:
    print('ERROR: known instruction 0x931F00 not decoded in full executable scan.')
print('')

print('================ NEXT DECISION ================')
print('1) If 0x931EE2 has direct callers, use their argument window to identify the concrete sink producer.')
print('2) If it has only a non-exec pointer xref, bind that slot to its function-pointer/vtable table and constructor.')
print('3) Then disassemble the concrete sink vtable +0x10 handler receiving ALAE/2STR/.../END protocol tokens.')
print('4) Component A remains localRoot+0x44; no patch is applied.')
print('5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'localRoot bind-wrapper xref probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
