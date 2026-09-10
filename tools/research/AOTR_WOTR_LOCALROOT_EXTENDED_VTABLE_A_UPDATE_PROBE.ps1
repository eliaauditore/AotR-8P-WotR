param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Runtime proof established concrete localRoot vtable 0x00BFD2A0 and showed
# localRoot+0x44 changes 19592 times while localRoot+0x04 remains NULL.
# The prior vtable probe stopped at +0x7C, but derived feed method 0xA1FD80
# explicitly performs call [vtable+0x98]. This probe extends the concrete
# vtable and focuses on +0x90..+0xA8, especially +0x98, for the real A updater.

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

$tempPy = Join-Path $env:TEMP ('a8p_localroot_extended_vt_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_AC_READ, CS_AC_WRITE
from capstone.x86_const import X86_OP_IMM, X86_OP_MEM, X86_OP_REG

path=sys.argv[1]
IMAGE_BASE=0x00400000
VTABLE=0x00BFD2A0
COMP_OFF=0x44
FEED_METHOD=0x00A1FD80

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
def is_exec(va):
    s=sec_for_va(va)
    return bool(s and (s['chars'] & 0x20000000))

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def dis(start,n=0x240):
    b,s,raw=rb(start,n)
    return list(md.disasm(b,start))

def direct_target(x):
    if x.mnemonic not in ('call','jmp') or len(x.operands)!=1: return None
    op=x.operands[0]
    if op.type==X86_OP_IMM: return op.imm & 0xffffffff
    return None

def method_body(start,limit=0x300):
    out=[]
    for x in dis(start,limit):
        out.append(x)
        if x.mnemonic.startswith('ret'): break
        if len(out)>1 and x.mnemonic=='jmp' and direct_target(x) is not None: break
    return out

def resolve_thunk(start):
    cur=start; chain=[]
    for _ in range(4):
        body=method_body(cur,0x20)
        if not body: break
        x=body[0]
        if x.mnemonic=='jmp':
            t=direct_target(x)
            if t is not None and is_exec(t): chain.append((cur,t)); cur=t; continue
        break
    return cur,chain

def regname(r): return md.reg_name(r) if r else ''

def access_kind(op):
    a=getattr(op,'access',0)
    if (a & CS_AC_READ) and (a & CS_AC_WRITE): return 'READ+WRITE'
    if a & CS_AC_WRITE: return 'WRITE'
    if a & CS_AC_READ: return 'READ'
    return 'MEM'

def fmt(x,mark='  ',note=''):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    z=f'{mark} 0x{x.address:08X}: {bs:<43} {x.mnemonic:<8} {x.op_str}'
    return z + ((' ; '+note) if note else '')

def analyze_this44(body):
    aliases={'ecx'}; hits=[]
    for x in body:
        for op in x.operands:
            if op.type==X86_OP_MEM and regname(op.mem.base) in aliases and op.mem.disp==COMP_OFF:
                hits.append((x,'THIS+0x44 '+access_kind(op)))
        if x.mnemonic=='lea' and len(x.operands)>=2 and x.operands[0].type==X86_OP_REG and x.operands[1].type==X86_OP_MEM:
            src=x.operands[1]
            if regname(src.mem.base) in aliases and src.mem.disp==COMP_OFF:
                hits.append((x,'ADDRESS-TAKE this+0x44'))
        if x.mnemonic=='mov' and len(x.operands)>=2 and x.operands[0].type==X86_OP_REG:
            dst=regname(x.operands[0].reg); src=x.operands[1]
            if src.type==X86_OP_REG and regname(src.reg) in aliases:
                aliases.add(dst)
            elif dst in aliases and dst!='ecx':
                aliases.discard(dst)
        if x.mnemonic=='lea' and len(x.operands)>=2 and x.operands[0].type==X86_OP_REG and x.operands[1].type==X86_OP_MEM:
            dst=regname(x.operands[0].reg); src=x.operands[1]
            if regname(src.mem.base) in aliases and src.mem.index==0 and src.mem.disp==0:
                aliases.add(dst)
    return hits

print('============================================================')
print(' AOTR WOTR LOCALROOT EXTENDED VTABLE / COMPONENT-A PROBE')
print('============================================================')
print(f'Image hash        : {sys.argv[2]}')
print(f'Concrete vtable   : 0x{VTABLE:08X}')
print(f'Component A       : this+0x{COMP_OFF:X}')
print('Trigger evidence  : 0xA1FD80 calls [localRoot.vtable+0x98]')
print('')

print('================ FEED +0x64 -> VIRTUAL +0x98 BINDING ================')
feed=method_body(FEED_METHOD,0x180)
found98=False
for x in feed:
    note=''
    if x.mnemonic=='call' and len(x.operands)==1 and x.operands[0].type==X86_OP_MEM:
        op=x.operands[0]
        if op.mem.disp==0x98:
            note='INDIRECT call via vtable+0x98'; found98=True
    if 0x00A1FDB0 <= x.address <= 0x00A1FDF0:
        print(fmt(x,'>>' if note else '  ',note))
print(f'vtable+0x98 call seen: {found98}')
print('')

entries=[]
print('================ EXTENDED CONCRETE VTABLE +0x80..+0xB8 ================')
for off in range(0x80,0xBC,4):
    try: p=u32(VTABLE+off)
    except Exception: break
    entries.append((off,p))
    s=sec_for_va(p)
    print(f'+0x{off:02X} -> 0x{p:08X} exec={is_exec(p)} section={s["name"] if s else "?"}')
print('')

focus={0x88,0x8C,0x90,0x94,0x98,0x9C,0xA0,0xA4,0xA8}
strong=[]; helper_candidates=[]
print('================ FOCUSED EXTENDED METHODS ================')
for off,p in entries:
    if off not in focus or not is_exec(p): continue
    resolved,chain=resolve_thunk(p)
    body=method_body(resolved,0x380)
    hits=analyze_this44(body)
    print(f'\n--- vtable +0x{off:02X} entry=0x{p:08X} resolved=0x{resolved:08X} ---')
    for a,b in chain: print(f'  thunk 0x{a:08X} -> 0x{b:08X}')
    for x in body:
        note=''
        for hx,hn in hits:
            if hx.address==x.address: note=hn; strong.append((off,resolved,x.address,hn))
        if x.mnemonic=='call':
            t=direct_target(x)
            if t is not None and is_exec(t):
                helper_candidates.append((off,x.address,t))
                note=(note+', ' if note else '')+f'CALL 0x{t:08X}'
            elif len(x.operands)==1 and x.operands[0].type==X86_OP_MEM:
                d=x.operands[0].mem.disp
                note=(note+', ' if note else '')+f'INDIRECT CALL disp=0x{d & 0xffffffff:X}'
        print(fmt(x,'>>' if note else '  ',note))
print('')

print('================ ONE DIRECT HELPER LEVEL FROM EXTENDED METHODS ================')
seen=set(); helper_hits=[]
for off,callsite,t in helper_candidates:
    if t in seen: continue
    seen.add(t)
    body=method_body(t,0x280)
    hs=[]
    for x in body:
        for op in x.operands:
            if op.type==X86_OP_MEM and op.mem.disp==COMP_OFF:
                hs.append((x,access_kind(op),regname(op.mem.base)))
    if hs:
        print(f'\n--- helper 0x{t:08X} (reachable from slot +0x{off:02X}) ---')
        for x,k,b in hs:
            print(fmt(x,'>>',f'disp +0x44 {k}; base={b or "?"}'))
            helper_hits.append((t,x.address,k,b))
if not helper_hits:
    print('No raw +0x44 displacement found in one direct helper level.')
print('')

print('================ CLASSIFICATION ================')
if found98:
    print('BEWIESEN STATIC: derived feed method +0x64 dispatches through the same concrete object vtable slot +0x98.')
else:
    print('WARNING: expected vtable+0x98 dispatch was not rediscovered; inspect decode before using extended-slot conclusions.')
slot98=dict(entries).get(0x98)
if slot98 is not None:
    print(f'Concrete +0x98 target: 0x{slot98:08X} exec={is_exec(slot98)}')
if strong:
    print('BEWIESEN STATIC CANDIDATE(S): extended concrete-vtable method directly accesses this+0x44:')
    for off,res,addr,n in strong:
        print(f'  slot +0x{off:02X} method 0x{res:08X} @ 0x{addr:08X}: {n}')
else:
    print('No conservative direct this+0x44 access found in focused extended slots.')
print('Do not patch B04/+0x44. First close the updater algorithm and then compare the input stream between HOST and VM.')
print('No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'localRoot extended-vtable component-A probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
