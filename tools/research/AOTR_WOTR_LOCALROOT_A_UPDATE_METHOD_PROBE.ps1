param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Runtime proof established that the concrete localRoot has vtable 0x00BFD2A0,
# localRoot+0x04 stays NULL for the observed fingerprint build, while +0x44
# changes thousands of times and finishes at the exact Component-A value.
# This probe therefore ignores the +0x04 sink path and inspects only the
# concrete vtable methods and one direct helper level for +0x44 access/update.

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

$tempPy = Join-Path $env:TEMP ('a8p_localroot_a_update_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_AC_READ, CS_AC_WRITE
from capstone.x86_const import X86_OP_IMM, X86_OP_MEM, X86_OP_REG

path=sys.argv[1]
IMAGE_BASE=0x00400000
VTABLE=0x00BFD2A0
COMP_OFF=0x44

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

def dis(start,n=0x180):
    b,s,raw=rb(start,n)
    return list(md.disasm(b,start))

def fmt(x,mark='  ',note=''):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    z=f'{mark} 0x{x.address:08X}: {bs:<43} {x.mnemonic:<8} {x.op_str}'
    return z + ((' ; '+note) if note else '')

def direct_target(x):
    if x.mnemonic not in ('call','jmp') or len(x.operands)!=1: return None
    op=x.operands[0]
    if op.type==X86_OP_IMM: return op.imm & 0xffffffff
    return None

def method_body(start,limit=0x180):
    ins=dis(start,limit)
    out=[]
    for x in ins:
        out.append(x)
        # Stop at a real return. For a first-instruction direct JMP thunk, caller
        # resolves it separately rather than mixing two functions here.
        if x.mnemonic.startswith('ret'): break
        if len(out)>1 and x.mnemonic=='jmp' and direct_target(x) is not None: break
    return out

def resolve_thunk(start):
    cur=start
    chain=[]
    for _ in range(3):
        ins=method_body(cur,0x20)
        if not ins: break
        first=ins[0]
        if first.mnemonic=='jmp':
            t=direct_target(first)
            if t is not None and is_exec(t):
                chain.append((cur,t)); cur=t; continue
        break
    return cur,chain

def regname(r): return md.reg_name(r) if r else ''

def classify_access(x,op):
    a=getattr(op,'access',0)
    if a & CS_AC_WRITE and a & CS_AC_READ: return 'READ+WRITE'
    if a & CS_AC_WRITE: return 'WRITE'
    if a & CS_AC_READ: return 'READ'
    return 'MEM'

def analyze_this_aliases(ins):
    # Conservative straight-line alias tracker. Seed ECX=this. We only use it
    # to label strong direct accesses; unknown/branchy cases remain candidates.
    aliases={'ecx'}
    hits=[]
    for x in ins:
        # inspect memory operands before updating aliases
        for oi,op in enumerate(x.operands):
            if op.type != X86_OP_MEM: continue
            base=regname(op.mem.base)
            disp=op.mem.disp
            if base in aliases and disp==COMP_OFF:
                hits.append((x,'THIS+0x44 '+classify_access(x,op)))
        # explicit LEA of this+44, useful when helper receives pointer to accumulator
        if x.mnemonic=='lea' and len(x.operands)>=2 and x.operands[0].type==X86_OP_REG and x.operands[1].type==X86_OP_MEM:
            src=x.operands[1]; base=regname(src.mem.base)
            if base in aliases and src.mem.disp==COMP_OFF:
                hits.append((x,'ADDRESS-TAKE this+0x44'))
        # simple MOV alias propagation
        if x.mnemonic=='mov' and len(x.operands)>=2 and x.operands[0].type==X86_OP_REG:
            dst=regname(x.operands[0].reg); src=x.operands[1]
            if src.type==X86_OP_REG and regname(src.reg) in aliases:
                aliases.add(dst)
            elif dst in aliases and not (src.type==X86_OP_REG and regname(src.reg) in aliases):
                if dst!='ecx': aliases.discard(dst)
        # LEA reg,[alias+0] also aliases this
        if x.mnemonic=='lea' and len(x.operands)>=2 and x.operands[0].type==X86_OP_REG and x.operands[1].type==X86_OP_MEM:
            dst=regname(x.operands[0].reg); src=x.operands[1]
            if regname(src.mem.base) in aliases and src.mem.index==0 and src.mem.disp==0:
                aliases.add(dst)
    return hits

def generic_disp44(ins):
    hits=[]
    for x in ins:
        for op in x.operands:
            if op.type==X86_OP_MEM and op.mem.disp==COMP_OFF:
                hits.append((x, classify_access(x,op), regname(op.mem.base)))
    return hits

print('============================================================')
print(' AOTR WOTR LOCALROOT COMPONENT-A UPDATE METHOD PROBE')
print('============================================================')
print(f'Image hash          : {sys.argv[2]}')
print(f'Runtime-proven VT   : 0x{VTABLE:08X}')
print(f'Component A field   : this+0x{COMP_OFF:X}')
print('Runtime invariant   : +0x04 sink stayed NULL while +0x44 changed 19592 times.')
print('')

entries=[]
print('================ CONCRETE VTABLE ================')
for off in range(0,0x80,4):
    p=u32(VTABLE+off)
    entries.append((off,p))
    print(f'+0x{off:02X} -> 0x{p:08X} exec={is_exec(p)} section={sec_for_va(p)["name"] if sec_for_va(p) else "?"}')
print('')

strong=[]
helpers=set()
print('================ VTABLE METHODS: DIRECT this+0x44 EVIDENCE ================')
for off,p in entries:
    if not is_exec(p): continue
    resolved,chain=resolve_thunk(p)
    body=method_body(resolved)
    hits=analyze_this_aliases(body)
    calls=[]
    for x in body:
        if x.mnemonic=='call':
            t=direct_target(x)
            if t is not None and is_exec(t): calls.append((x,t)); helpers.add(t)
    if hits:
        print(f'\n--- slot +0x{off:02X} entry=0x{p:08X} resolved=0x{resolved:08X} ---')
        for a,b in chain: print(f'  thunk 0x{a:08X} -> 0x{b:08X}')
        for x,n in hits:
            print(fmt(x,'>>',n))
            strong.append((off,resolved,x.address,n))
        if calls:
            print('  direct helpers from this method:')
            for x,t in calls: print(f'    0x{x.address:08X} -> 0x{t:08X}')

if not strong:
    print('No conservative direct this+0x44 hit found in vtable methods.')
print('')

print('================ ONE-LEVEL DIRECT HELPERS: DISP +0x44 CANDIDATES ================')
helper_hits=[]
for t in sorted(helpers):
    body=method_body(t)
    hs=generic_disp44(body)
    if not hs: continue
    print(f'\n--- helper 0x{t:08X} ---')
    for x,kind,base in hs:
        print(fmt(x,'>>',f'disp +0x44 {kind}; base={base or "?"} (helper arg/this binding not yet proven)'))
        helper_hits.append((t,x.address,kind,base))
if not helper_hits:
    print('No +0x44 displacement found in one direct helper level.')
print('')

# The specialized derived methods around +0x64/+0x68/+0x6C are likely high-value
# data-feed methods. Print their complete bodies regardless of hit so the exact
# update algorithm is visible if it uses a non-obvious helper or register flow.
print('================ HIGH-VALUE DERIVED FEED METHODS ================')
for wanted in (0x64,0x68,0x6C):
    p=dict(entries).get(wanted)
    if not p or not is_exec(p): continue
    resolved,chain=resolve_thunk(p)
    print(f'\n--- vtable +0x{wanted:02X} entry=0x{p:08X} resolved=0x{resolved:08X} ---')
    for a,b in chain: print(f'  thunk 0x{a:08X} -> 0x{b:08X}')
    body=method_body(resolved,0x280)
    for x in body:
        note=''
        for op in x.operands:
            if op.type==X86_OP_MEM and op.mem.disp==COMP_OFF:
                note='disp +0x44'
        if x.mnemonic=='call':
            t=direct_target(x)
            if t is not None: note=(note+', ' if note else '')+f'CALL 0x{t:08X}'
        print(fmt(x,'>>' if note else '  ',note))
print('')

print('================ CLASSIFICATION ================')
if strong:
    print('BEWIESEN STATIC CANDIDATES: concrete localRoot vtable method(s) directly access this+0x44.')
    for off,res,addr,n in strong:
        print(f'  slot +0x{off:02X} method 0x{res:08X} @ 0x{addr:08X}: {n}')
else:
    print('No direct updater was proven in the conservative vtable scan; use printed feed methods/helper candidates next.')
print('Do not patch B04 or +0x44 yet. First identify the exact update algorithm and its input stream.')
print('No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'localRoot component-A update method probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
