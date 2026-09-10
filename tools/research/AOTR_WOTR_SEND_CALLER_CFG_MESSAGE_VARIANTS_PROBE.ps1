param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Corrects the earlier "nearest message[0] write" simplification by resolving, for
# each direct call to 0x84C257, the exact stack buffer passed as arg1 and then
# collecting ALL immediate writes to that buffer's message[0] within the containing
# function. This exposes multi-variant send callsites (notably 0x98AF02) and searches
# for the real 0x08 remove/clear sender.

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

$tempPy = Join-Path $env:TEMP ('a8p_send_cfg_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86 import X86_OP_REG, X86_OP_MEM, X86_OP_IMM, X86_REG_EBP

path=sys.argv[1]
IMAGE_BASE=0x00400000
SEND=0x0084C257
KNOWN_LABELS={
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
        if s['rva'] <= rva < s['rva']+max(s['vs'],s['rs']): return s
    return None

def va_to_raw(va):
    s=sec_for_va(va)
    if not s: raise ValueError(f'VA 0x{va:08X} outside image sections')
    return s['rp'] + ((va-IMAGE_BASE)-s['rva']),s

def bytes_at(va,n):
    raw,s=va_to_raw(va)
    return data[raw:raw+n],s,raw

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def disasm(va,n):
    b,s,raw=bytes_at(va,n)
    return list(md.disasm(b,va)),s,raw

def fmt(x,mark='  '):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

# Direct E8 refs, byte-based so we do not depend on full-section disassembly.
callers=[]
for s in secs:
    if not (s['chars'] & 0x20000000): continue
    blob=data[s['rp']:s['rp']+s['rs']]
    base=IMAGE_BASE+s['rva']
    for i in range(0,max(0,len(blob)-5)):
        if blob[i] != 0xE8: continue
        disp=struct.unpack_from('<i',blob,i+1)[0]
        src=base+i; dst=(src+5+disp)&0xffffffff
        if dst==SEND: callers.append(src)
callers=sorted(set(callers))

# Find nearest conventional EBP function prologue. This is used only to bound the
# same-function scan; every actual message write is still validated by Capstone.
def find_func_start(callva,back=0x1200):
    s=sec_for_va(callva)
    lo=max(IMAGE_BASE+s['rva'],callva-back)
    raw_lo,_=va_to_raw(lo); raw_call,_=va_to_raw(callva)
    blob=data[raw_lo:raw_call]
    pats=[b'\x55\x8b\xec', b'\x55\x89\xe5']
    best=None
    for p in pats:
        pos=blob.rfind(p)
        if pos>=0:
            va=lo+pos
            if best is None or va>best: best=va
    return best

# Infer arg1 message buffer from the last LEA reg,[ebp+disp] -> PUSH reg chain.
def infer_msg_disp(callva):
    start=max(callva-0x80, IMAGE_BASE)
    ins,_,_=disasm(start,callva-start+5)
    ins=[x for x in ins if x.address < callva]
    reg_to_disp={}
    push_candidates=[]
    for x in ins:
        if x.mnemonic=='lea' and len(x.operands)==2 and x.operands[0].type==X86_OP_REG and x.operands[1].type==X86_OP_MEM:
            m=x.operands[1].mem
            if m.base==X86_REG_EBP and m.index==0:
                reg_to_disp[x.operands[0].reg]=(m.disp,x.address)
        elif x.mnemonic=='push' and len(x.operands)==1:
            op=x.operands[0]
            if op.type==X86_OP_REG and op.reg in reg_to_disp:
                disp,leava=reg_to_disp[op.reg]
                push_candidates.append((x.address,disp,leava))
    # arg1 is normally the second push from the end because endpoint arg2 is pushed
    # first, then message arg1. However many callers pass endpoint=0 immediately.
    # Choose the stack-buffer push nearest to call whose displacement magnitude looks
    # like the ~0x1D8 packet local.
    plausible=[p for p in push_candidates if p[1] < -0x100]
    return plausible[-1] if plausible else (push_candidates[-1] if push_candidates else None)

# Decode all MOV [ebp+msgDisp], imm writes in a function window.
def collect_id_writes(fstart,callva,msgdisp):
    if fstart is None: return []
    size=callva+5-fstart
    ins,_,_=disasm(fstart,size)
    out=[]
    for x in ins:
        if x.mnemonic!='mov' or len(x.operands)!=2: continue
        a,b=x.operands
        if a.type!=X86_OP_MEM or b.type!=X86_OP_IMM: continue
        m=a.mem
        if m.base==X86_REG_EBP and m.index==0 and m.disp==msgdisp:
            imm=b.imm & 0xffffffff
            if imm <= 0x13:
                out.append((x.address,imm,x))
    return out

print('============================================================')
print(' AOTR WOTR SEND CALLER CFG / MESSAGE VARIANTS - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print(f'Send helper: 0x{SEND:08X}')
print(f'Direct callers: {len(callers)}')
print('')

rows=[]
for idx,c in enumerate(callers,1):
    inf=infer_msg_disp(c)
    fstart=find_func_start(c)
    if not inf:
        print(f'CALLER #{idx:02d} 0x{c:08X} msg=<unresolved> func={"0x%08X"%fstart if fstart else "<unknown>"}')
        rows.append((c,None,fstart,[])); continue
    pushva,msgdisp,leava=inf
    writes=collect_id_writes(fstart,c,msgdisp)
    ids=sorted(set(v for _,v,_ in writes))
    idtxt=','.join(f'0x{x:02X}' + (f'({KNOWN_LABELS[x]})' if x in KNOWN_LABELS else '') for x in ids) if ids else '<none>'
    print(f'CALLER #{idx:02d} 0x{c:08X} func=0x{fstart:08X} msgDisp={msgdisp:+d} possibleIDs={idtxt}')
    for va,v,x in writes:
        lab=(' '+KNOWN_LABELS[v]) if v in KNOWN_LABELS else ''
        print(f'    write 0x{va:08X}: ID=0x{v:02X}{lab}')
    rows.append((c,msgdisp,fstart,writes))

print('\n================ JOIN / REMOVE VARIANT SENDERS ================')
for wanted in (0x03,0x04,0x08):
    label=KNOWN_LABELS[wanted]
    hits=[]
    for c,msgdisp,fstart,writes in rows:
        if any(v==wanted for _,v,_ in writes): hits.append((c,msgdisp,fstart,writes))
    print(f'\n{label} ID=0x{wanted:02X} candidate send callsites: ' + (', '.join(f'0x{x[0]:08X}' for x in hits) if hits else '<NONE>'))
    for c,msgdisp,fstart,writes in hits:
        print(f'  call=0x{c:08X} func=0x{fstart:08X} msgDisp={msgdisp:+d}')
        for va,v,x in writes:
            if v==wanted:
                print('   '+fmt(x,'>>').strip())

# Focus on the known PATH_C common send callsite. Show all writes to the exact packet
# base and key branch/send neighborhoods so 0x04 vs 0x05 is explicit.
print('\n================ PATH_C 0x98AF02 MULTI-VARIANT PROOF ================')
pathc=next((r for r in rows if r[0]==0x0098AF02),None)
if pathc:
    c,msgdisp,fstart,writes=pathc
    print(f'func=0x{fstart:08X} msgDisp={msgdisp:+d}')
    print('All message[0] writes to exact buffer before common send:')
    for va,v,x in writes:
        print(fmt(x,'>>' if v in (4,5,8) else '  '))
    for a,b,title in [
        (0x0098ABDC,0x0098AC10,'0x04 WRITE / SUCCESS RESPONSE'),
        (0x0098ADD0,0x0098AE10,'BRANCH INTO 0x05 PATH'),
        (0x0098AE84,0x0098AF0A,'0x05 WRITE + COMMON SEND'),
    ]:
        print(f'\n--- {title} ---')
        ins,_,_=disasm(a,b-a)
        for x in ins: print(fmt(x,'>>' if x.address in (0x0098ABF6,0x0098ADE8,0x0098AE96,0x0098AF02) else '  '))
else:
    print('0x98AF02 was not resolved.')

# Focus exact 0x03 producer.
print('\n================ EXACT 0x03 PRODUCER ================')
r3=next((r for r in rows if r[0]==0x0084CC4D),None)
if r3:
    c,msgdisp,fstart,writes=r3
    print(f'func=0x{fstart:08X} msgDisp={msgdisp:+d}')
    ins,_,_=disasm(0x0084CB70,0xE8)
    for x in ins:
        print(fmt(x,'>>' if x.address in (0x0084CB80,0x0084CC4D) else '  '))

print('\n================ MESSAGE VARIANT SUMMARY ================')
for wanted in (0x03,0x04,0x08):
    hits=[c for c,_,_,w in rows if any(v==wanted for _,v,_ in w)]
    print(f'0x{wanted:02X} {KNOWN_LABELS[wanted]:<24} calls=' + (','.join(f'0x{x:08X}' for x in hits) if hits else '<NONE>'))

print('\nInterpretation targets:')
print('  1) 0x98AF02 must be treated as a shared/multi-variant send callsite, not labeled by only the nearest write.')
print('  2) Confirm 0x04 is a reachable message[0] value on the PATH_C success-response path.')
print('  3) Locate every caller whose exact passed stack buffer can carry message ID 0x08.')
print('  4) Preserve 0x84CC4D as the exact proven 0x03 producer/send callsite.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'send caller cfg/message variants probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'