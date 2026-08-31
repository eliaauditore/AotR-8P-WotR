param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Maps every direct caller of native session send helper 0x84C257 to the
# exact stack message buffer passed as arg1, then finds the nearest immediate
# write to message[0]. This avoids noisy global scans for constants 3/4/8.

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

$tempPy = Join-Path $env:TEMP ('a8p_send_id_map_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86 import X86_OP_REG, X86_OP_MEM, X86_REG_EBP

path=sys.argv[1]
IMAGE_BASE=0x00400000
SEND=0x0084C257
ID_NAMES={
    0x03:'REMOTE_TYPE6_CREATE',
    0x04:'LOCAL_SLOT_BIND',
    0x08:'SLOT_REMOVE_CLEAR',
}

with open(path,'rb') as f: data=f.read()
if data[:2] != b'MZ': raise SystemExit('Not MZ')
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
        span=max(s['vs'],s['rs'])
        if s['rva'] <= rva < s['rva']+span:
            return s
    return None

def va_to_raw(va):
    s=sec_for_va(va)
    if not s: raise ValueError(f'VA 0x{va:08X} not in PE section')
    return s['rp']+((va-IMAGE_BASE)-s['rva']),s

def raw_to_va(raw,s):
    return IMAGE_BASE+s['rva']+(raw-s['rp'])

def read_bytes(va,n):
    raw,s=va_to_raw(va)
    return data[raw:raw+n],s,raw

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

# Raw E8 refs to SEND across executable sections.
refs=[]
for s in secs:
    if not (s['chars'] & 0x20000000):
        continue
    start=s['rp']; end=min(len(data), s['rp']+s['rs'])
    for raw in range(start,end-5):
        if data[raw] != 0xE8: continue
        disp=struct.unpack_from('<i',data,raw+1)[0]
        va=raw_to_va(raw,s)
        dst=(va+5+disp)&0xffffffff
        if dst==SEND:
            refs.append((va,s))
refs.sort()

# Find a synchronized instruction sequence that lands exactly on callsite.
def sync_before(callsite,maxback=48):
    best=None
    for back in range(1,maxback+1):
        start=callsite-back
        try: b,s,raw=read_bytes(start,back+5)
        except: continue
        ins=list(md.disasm(b,start))
        # require an instruction exactly at callsite
        idx=None
        for i,x in enumerate(ins):
            if x.address==callsite and x.mnemonic=='call': idx=i; break
        if idx is None: continue
        seq=ins[:idx+1]
        # require no gap: first ins begins at start and call ends at callsite+5
        if not seq or seq[0].address!=start or seq[-1].address+seq[-1].size!=callsite+5: continue
        score=(len(seq),back)
        if best is None or score>best[0]: best=(score,seq)
    return best[1] if best else []

# Parse LEA reg,[ebp+disp].
def lea_ebp_disp(x):
    if x.mnemonic!='lea' or len(x.operands)!=2: return None
    a,b=x.operands
    if a.type!=X86_OP_REG or b.type!=X86_OP_MEM: return None
    if b.mem.base!=X86_REG_EBP or b.mem.index!=0: return None
    return (a.reg,b.mem.disp)

def push_reg(x,reg):
    return x.mnemonic=='push' and len(x.operands)==1 and x.operands[0].type==X86_OP_REG and x.operands[0].reg==reg

# Nearest arg1 message buffer: closest LEA EBP-local followed shortly by push same reg before call.
def message_disp_from_seq(seq):
    if not seq: return None,None
    pre=seq[:-1]
    candidates=[]
    for i,x in enumerate(pre):
        z=lea_ebp_disp(x)
        if not z: continue
        reg,disp=z
        for j in range(i+1,min(len(pre),i+4)):
            if push_reg(pre[j],reg):
                candidates.append((j,i,disp,x.address,pre[j].address))
                break
    if not candidates: return None,None
    # The message is arg1, usually the last stack-local LEA/PUSH before MOV ECX / CALL.
    candidates.sort(reverse=True)
    j,i,disp,lva,pva=candidates[0]
    return disp,(lva,pva)

# Find immediate writes to [ebp+disp] in a bounded raw window before call.
def imm_writes_to_disp(callsite,disp,back=0x700):
    out=[]
    start=max(IMAGE_BASE,callsite-back)
    try:
        raw0,s0=va_to_raw(start)
        raw1,s1=va_to_raw(callsite)
    except:
        return out
    if s0 is not s1 and s0['name']!=s1['name']:
        # clamp to caller section
        s=s1; raw0=s['rp']; raw1=va_to_raw(callsite)[0]
    else:
        s=s1
    r=raw0
    while r<raw1:
        # C7 85 disp32 imm32
        if r+10<=raw1 and data[r]==0xC7 and data[r+1]==0x85:
            d=struct.unpack_from('<i',data,r+2)[0]
            imm=struct.unpack_from('<I',data,r+6)[0]
            if d==disp:
                out.append((raw_to_va(r,s),imm,10))
        # C7 45 disp8 imm32
        if r+7<=raw1 and data[r]==0xC7 and data[r+1]==0x45:
            d=struct.unpack_from('<b',data,r+2)[0]
            imm=struct.unpack_from('<I',data,r+3)[0]
            if d==disp:
                out.append((raw_to_va(r,s),imm,7))
        r+=1
    return out

def local_ins(va,before=24,after=40):
    # synchronize by trying several starts; favor a decode containing va.
    for back in range(before,0,-1):
        start=va-back
        try: b,s,raw=read_bytes(start,back+after)
        except: continue
        ins=list(md.disasm(b,start))
        if any(x.address==va for x in ins):
            return ins
    try:
        b,s,raw=read_bytes(va,after)
        return list(md.disasm(b,va))
    except: return []

print('============================================================')
print(' AOTR WOTR SEND CALLER -> MESSAGE ID MAP - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print(f'Send helper: 0x{SEND:08X}')
print(f'Direct refs: {len(refs)}')
print('')

mapped=[]
for n,(callsite,s) in enumerate(refs,1):
    seq=sync_before(callsite)
    disp,pair=message_disp_from_seq(seq)
    writes=imm_writes_to_disp(callsite,disp) if disp is not None else []
    idwrites=[w for w in writes if w[1] <= 0x13]
    chosen=idwrites[-1] if idwrites else None
    mid=chosen[1] if chosen else None
    mapped.append((callsite,disp,mid,chosen,seq,writes,s))
    label=ID_NAMES.get(mid,'') if mid is not None else ''
    print(f'CALLER #{n:02d} 0x{callsite:08X} section={s["name"]}  msgDisp={"%+d"%disp if disp is not None else "<unresolved>"}  ID={"0x%02X"%mid if mid is not None else "<unresolved>"} {label}')
    if chosen:
        print(f'  nearest message[0] write: 0x{chosen[0]:08X} imm=0x{chosen[1]:X}')
print('')

print('================ JOIN/REMOVE SENDERS ================')
interesting=[m for m in mapped if m[2] in ID_NAMES]
if not interesting:
    print('<NONE RESOLVED>')
for callsite,disp,mid,chosen,seq,writes,s in interesting:
    print(f'\n---------------- ID 0x{mid:02X} {ID_NAMES[mid]} sender call=0x{callsite:08X} msgDisp={disp:+d} ----------------')
    if chosen:
        print(f'Message ID write: 0x{chosen[0]:08X}')
        for x in local_ins(chosen[0],32,80):
            if chosen[0]-24 <= x.address <= chosen[0]+56:
                print(fmt(x,'>>' if x.address==chosen[0] else '  '))
    print('--- send call argument neighborhood ---')
    for x in seq[-12:]:
        print(fmt(x,'>>' if x.address==callsite else '  '))

print('\n================ MESSAGE ID SUMMARY ================')
for mid,name in ID_NAMES.items():
    xs=[m for m in mapped if m[2]==mid]
    print(f'0x{mid:02X} {name:<22} count={len(xs)} callers=' + (','.join(f'0x{m[0]:08X}' for m in xs) if xs else '<NONE>'))

print('\nInterpretation targets:')
print('  1) Identify the exact native producer/caller that sends message 0x03 REMOTE_TYPE6_CREATE.')
print('  2) Confirm 0x04 LOCAL_SLOT_BIND sender includes proven PATH_C callsite 0x0098AF02.')
print('  3) Identify native 0x08 SLOT_REMOVE_CLEAR sender(s).')
print('  4) Treat only caller-bound message[0] writes as evidence; ignore unrelated immediate constants.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'send caller message-id map probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'