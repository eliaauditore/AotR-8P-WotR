param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Follow-up after proving:
# - localRoot ctor 0x6251F5 / vtable 0xBFD2A0
# - base ctor 0xA20EDC / base vtable 0xC93AE0
# - localRoot+0x04 initially NULL
# - cleanup 0xA205AD dispatches END to [localRoot+0x04], not localRoot itself
# - component A is localRoot+0x44
# This probe resolves the class API and searches for the real +0x04/+0x44 setter/update path.

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

$tempPy = Join-Path $env:TEMP ('a8p_localroot_api_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86_const import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
DERIVED_VT=0x00BFD2A0
BASE_VT=0x00C93AE0
DERIVED_CTOR=0x006251F5
BASE_CTOR=0x00A20EDC
CLEANUP=0x00A205AD
DE3380=0x00DE3380

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

def direct_target(x):
    if x.mnemonic not in ('call','jmp') or len(x.operands)!=1: return None
    op=x.operands[0]
    return (op.imm & 0xffffffff) if op.type==X86_OP_IMM else None

def is_exec(va):
    s=sec_for_va(va)
    return bool(s and (s['chars'] & 0x20000000))

def decode_method(va,maxlen=0x280):
    try:
        ii,_,_=dis(va,va+maxlen)
    except Exception:
        return []
    out=[]
    for x in ii:
        out.append(x)
        if x.mnemonic.startswith('ret') and x.address>va:
            break
        if x.mnemonic=='jmp' and direct_target(x) is not None and x.address==va:
            break
    return out

def regname(r):
    try: return md.reg_name(r)
    except: return f'reg{r}'

def analyze_this_fields(ii):
    # Lightweight alias tracking: ECX is this at method entry; copy aliases through MOV reg,reg.
    aliases={X86_REG_ECX}
    hits=[]
    for x in ii:
        # Track simple register copies before evaluating fields.
        if x.mnemonic=='mov' and len(x.operands)==2 and x.operands[0].type==X86_OP_REG and x.operands[1].type==X86_OP_REG:
            dst=x.operands[0].reg; src=x.operands[1].reg
            if src in aliases: aliases.add(dst)
            elif dst in aliases and src not in aliases and dst!=X86_REG_ECX: aliases.discard(dst)
        notes=[]
        for oi,op in enumerate(x.operands):
            if op.type!=X86_OP_MEM: continue
            b=op.mem.base; d=op.mem.disp
            if b in aliases and d in (4,0x44,0x40,8):
                rw='MEM'
                if oi==0 and x.mnemonic not in ('cmp','test','push'):
                    rw='WRITE/DEST'
                notes.append(f'{rw} this+0x{d:X} via {regname(b)}')
            if b in aliases and d==4 and x.mnemonic=='lea':
                notes.append(f'ADDRESS this+0x04 via {regname(b)}')
            if b in aliases and d==0x44 and x.mnemonic=='lea':
                notes.append(f'ADDRESS this+0x44 via {regname(b)}')
        if notes: hits.append((x,notes.copy()))
    return hits

print('============================================================')
print(' AOTR WOTR LOCALROOT API / +0x04 +0x44 SETTER PROBE')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print(f'Derived ctor     : 0x{DERIVED_CTOR:08X}')
print(f'Derived vtable   : 0x{DERIVED_VT:08X}')
print(f'Base ctor        : 0x{BASE_CTOR:08X}')
print(f'Base vtable      : 0x{BASE_VT:08X}')
print('Correction held : END receiver is [localRoot+0x04], not localRoot.')
print('')

print('================ LOCALROOT SMALL API NEIGHBORHOOD ================')
ii,_,_=dis(0x006251F5,0x00625290)
for x in ii:
    notes=[]
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.disp in (4,8,0x40,0x44):
            notes.append(f'field disp=0x{op.mem.disp:X}')
    if x.address in (0x00625214,0x00625219,0x0062521E,0x00625223): notes.append('known derived-vtable target')
    if x.mnemonic=='call':
        t=direct_target(x); notes.append('CALL '+(f'0x{t:08X}' if t is not None else x.op_str))
    print(fmt(x,'>>' if notes else '  ', ', '.join(notes)))
print('')

# Dump both vtables and unique method targets.
all_methods=[]
for label,vt in [('DERIVED',DERIVED_VT),('BASE',BASE_VT)]:
    print(f'================ {label} VTABLE 0x{vt:08X} ================')
    seen=set()
    for off in range(0,0x80,4):
        try: t=u32(vt+off)
        except: break
        sec=sec_for_va(t); ex=is_exec(t)
        print(f'+0x{off:02X} -> 0x{t:08X} section={sec["name"] if sec else "<none>"} exec={ex}')
        if ex and t not in seen:
            seen.add(t); all_methods.append((label,off,t))
    print('')

print('================ VTABLE METHODS TOUCHING this+04 / +44 ================')
printed=set()
for label,off,t in all_methods:
    if t in printed: continue
    printed.add(t)
    ii=decode_method(t)
    hits=analyze_this_fields(ii)
    if not hits: continue
    print(f'--- {label} vtable representative +0x{off:02X} -> 0x{t:08X} ---')
    # Print complete small method if <=40 insns, otherwise windows around hits.
    if len(ii)<=40:
        hitadd={x.address:notes for x,notes in hits}
        for x in ii:
            notes=hitadd.get(x.address,[])
            if x.mnemonic=='call':
                tt=direct_target(x); notes=notes+['CALL '+(f'0x{tt:08X}' if tt is not None else x.op_str)]
            print(fmt(x,'>>' if notes else '  ', ', '.join(notes)))
    else:
        idx={x.address:i for i,x in enumerate(ii)}
        shown=set()
        for hx,notes in hits:
            j=idx[hx.address]
            for k in range(max(0,j-5),min(len(ii),j+7)):
                x=ii[k]
                if x.address in shown: continue
                shown.add(x.address)
                nn=[]
                for q,n in hits:
                    if q.address==x.address: nn+=n
                if x.mnemonic=='call':
                    tt=direct_target(x); nn+=['CALL '+(f'0x{tt:08X}' if tt is not None else x.op_str)]
                print(fmt(x,'>>' if nn else '  ', ', '.join(nn)))
    print('')

print('================ BASE CLEANUP / SETTER FAMILY ================')
for start,end,label in [
    (0x00A205AD,0x00A20680,'A205AD/A205DA family'),
    (0x00A20D79,0x00A20E79,'A20D79/A20DD0 family'),
    (0x00A1F566,0x00A1F900,'A1F5xx/A1F8xx vtable family')]:
    print(f'--- {label} ---')
    try: ii,_,_=dis(start,end)
    except Exception as e:
        print(f'<decode failed: {e}>'); continue
    for x in ii:
        notes=[]
        for op in x.operands:
            if op.type==X86_OP_MEM and op.mem.disp in (4,8,0x44):
                notes.append(f'mem disp=0x{op.mem.disp:X}')
        if x.mnemonic=='call':
            t=direct_target(x); notes.append('CALL '+(f'0x{t:08X}' if t is not None else x.op_str))
        if notes or x.address in (0x00A205AD,0x00A205DA,0x00A20D79,0x00A20DD0):
            print(fmt(x,'>>',', '.join(notes)))
    print('')

# Find code that obtains current localRoot via [DE3380] then [manager+0x24].
text=next((s for s in secs if s['name']=='.text'),None)
print('================ DE3380 +0x24 CURRENT-localRoot DISPATCH SITES ================')
if not text:
    print('<no .text>')
else:
    tb=data[text['rp']:text['rp']+text['rs']]
    tins=list(md.disasm(tb,IMAGE_BASE+text['rva']))
    found=0
    for i,x in enumerate(tins):
        # mov reg, dword ptr [0xDE3380]
        if x.mnemonic!='mov' or len(x.operands)!=2 or x.operands[0].type!=X86_OP_REG or x.operands[1].type!=X86_OP_MEM: continue
        m=x.operands[1].mem
        if m.base!=0 or m.index!=0 or (m.disp & 0xffffffff)!=DE3380: continue
        r=x.operands[0].reg
        for j in range(i+1,min(len(tins),i+18)):
            y=tins[j]
            hit=False
            for op in y.operands:
                if op.type==X86_OP_MEM and op.mem.base==r and op.mem.disp==0x24:
                    hit=True
            if hit:
                found+=1
                print(f'--- site #{found} around 0x{x.address:08X} -> manager+0x24 at 0x{y.address:08X} ---')
                for z in tins[max(0,i-3):min(len(tins),j+8)]:
                    notes=[]
                    for op in z.operands:
                        if op.type==X86_OP_MEM and op.mem.base==r and op.mem.disp==0x24: notes.append('DE3380-object +0x24 localRoot field')
                    if z.mnemonic=='call':
                        tt=direct_target(z); notes.append('CALL '+(f'0x{tt:08X}' if tt is not None else z.op_str))
                    print(fmt(z,'>>' if notes else '  ', ', '.join(notes)))
                print('')
                break
    print(f'count={found}')
print('')

print('================ CLASSIFICATION TARGETS ================')
print('1) Identify the exact method that assigns localRoot+0x04 after base ctor NULL initialization.')
print('2) Identify any exact writer/update of localRoot+0x44 (Component A).')
print('3) If +0x04 assignment is indirect, use DE3380+0x24 dispatch sites to locate the binding call.')
print('4) Only after the concrete sink vtable is bound should sink+0x10 (END receiver) be disassembled semantically.')
print('5) Do not patch or rename Component A as CRC/checksum until its update algorithm is visible.')
print('6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'localRoot API/setter probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
