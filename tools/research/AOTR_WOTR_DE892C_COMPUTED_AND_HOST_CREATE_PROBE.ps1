param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Goals:
#  1) Find computed/base+offset writes that resolve to DE892C but do not encode
#     0x00DE892C directly in the memory operand.
#  2) Classify the C54B78 create path around 0x84E1F4 / 0x84E24E / 0x84A86A /
#     0x84E3E4 to determine whether the Host DE892C=C54 state may be host-create-specific.
# No process memory or game.dat bytes are modified.

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

$tempPy = Join-Path $env:TEMP ('a8p_de892c_computed_hostcreate_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
image_hash=sys.argv[2]
IMAGE_BASE=0x00400000
TARGET=0x00DE892C
C54CTOR=0x0084AEA1
HOST_CREATE=0x0084E1F4
C54_POST=0x0084A86A
LIST_ATTACH_CALLSITE=0x0084E3E4
LIST_ATTACH=0x0084DF84

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
    ch=struct.unpack_from('<I',data,o+36)[0]
    secs.append(dict(name=name,rva=rva,vs=vs,rs=rs,rp=rp,ch=ch))

def sec_for_va(va):
    rva=va-IMAGE_BASE
    for s in secs:
        if s['rva'] <= rva < s['rva']+max(s['vs'],s['rs']): return s
    return None

def raw_for_va(va):
    s=sec_for_va(va)
    if not s: return None,None
    rel=(va-IMAGE_BASE)-s['rva']
    if rel < 0 or rel >= s['rs']: return None,s
    return s['rp']+rel,s

def off_to_va(off):
    for s in secs:
        if s['rp'] <= off < s['rp']+s['rs']:
            return IMAGE_BASE+s['rva']+(off-s['rp']),s
    return None,None

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True
REGS=[X86_REG_EAX,X86_REG_EBX,X86_REG_ECX,X86_REG_EDX,X86_REG_ESI,X86_REG_EDI,X86_REG_EBP,X86_REG_ESP]
REGNAME={r:md.reg_name(r) for r in REGS}

def fmt(x,mark='  '):
    b=' '.join(f'{v:02X}' for v in x.bytes)
    return f'{mark} 0x{x.address:08X}: {b:<42} {x.mnemonic:<8} {x.op_str}'

def disasm_exact(start,end):
    off,s=raw_for_va(start)
    if off is None: return [],s
    return list(md.disasm(data[off:off+(end-start)],start)),s

def direct_rel_refs(target):
    out=[]
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        base=IMAGE_BASE+s['rva']
        for i in range(max(0,len(blob)-5)):
            if blob[i] not in (0xE8,0xE9): continue
            src=base+i
            rel=struct.unpack_from('<i',blob,i+1)[0]
            dst=(src+5+rel)&0xffffffff
            if dst==target: out.append((src,'CALL' if blob[i]==0xE8 else 'JMP',s['name']))
    return out

def literal_refs(target):
    pat=struct.pack('<I',target); out=[]
    p=0
    while True:
        p=data.find(pat,p)
        if p<0: break
        va,s=off_to_va(p)
        out.append((va,s['name'] if s else '<unmapped>', bool(s and (s['ch'] & 0x20000000))))
        p+=1
    return out

def is_write_to_mem(x):
    if not x.operands or x.operands[0].type != X86_OP_MEM: return False
    # Capstone access flags are preferable when present; mnemonic fallback covers old builds.
    try:
        if x.operands[0].access & CS_AC_WRITE: return True
    except Exception:
        pass
    return x.mnemonic in ('mov','and','or','xor','add','sub','inc','dec','xchg','cmpxchg')

def mem_ea(op,known):
    m=op.mem
    total=m.disp & 0xffffffff
    if m.base:
        if m.base not in known: return None
        total=(total+known[m.base])&0xffffffff
    if m.index:
        if m.index not in known: return None
        total=(total+(known[m.index]*m.scale))&0xffffffff
    return total

def set_known_from_instruction(x,known):
    # Conservative constant propagation for common x86 forms.
    if not x.operands: return
    dst=x.operands[0]
    if dst.type != X86_OP_REG: return
    r=dst.reg
    if r not in REGS: return
    val=None
    try:
        if x.mnemonic=='mov' and len(x.operands)>=2:
            src=x.operands[1]
            if src.type==X86_OP_IMM: val=src.imm & 0xffffffff
            elif src.type==X86_OP_REG and src.reg in known: val=known[src.reg]
        elif x.mnemonic=='lea' and len(x.operands)>=2 and x.operands[1].type==X86_OP_MEM:
            val=mem_ea(x.operands[1],known)
        elif x.mnemonic=='xor' and len(x.operands)>=2 and x.operands[1].type==X86_OP_REG and x.operands[1].reg==r:
            val=0
        elif x.mnemonic in ('add','sub') and len(x.operands)>=2 and x.operands[1].type==X86_OP_IMM and r in known:
            imm=x.operands[1].imm & 0xffffffff
            val=((known[r]+imm) if x.mnemonic=='add' else (known[r]-imm)) & 0xffffffff
        elif x.mnemonic=='inc' and r in known: val=(known[r]+1)&0xffffffff
        elif x.mnemonic=='dec' and r in known: val=(known[r]-1)&0xffffffff
    except Exception:
        val=None
    if val is None: known.pop(r,None)
    else: known[r]=val

print('============================================================')
print(' AOTR WOTR DE892C COMPUTED + HOST CREATE PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {image_hash}')
print(f'DE892C     : 0x{TARGET:08X}')
print('')

# ------------------------------------------------------------------
# A) Computed effective-address writes.
# ------------------------------------------------------------------
print('================ COMPUTED/BASE+OFFSET DE892C WRITES ================')
hits=[]
for s in secs:
    if not (s['ch'] & 0x20000000): continue
    blob=data[s['rp']:s['rp']+s['rs']]
    base=IMAGE_BASE+s['rva']
    known={}
    history=[]
    for x in md.disasm(blob,base):
        # Evaluate EA using state *before* the instruction mutates a register.
        if is_write_to_mem(x):
            ea=mem_ea(x.operands[0],known)
            if ea==TARGET:
                direct=(x.operands[0].mem.base==0 and x.operands[0].mem.index==0 and (x.operands[0].mem.disp & 0xffffffff)==TARGET)
                if not direct:
                    hits.append((s['name'],x,list(history[-10:]),dict(known),ea))
        history.append(x)
        if len(history)>16: history=history[-16:]

        set_known_from_instruction(x,known)

        # Calls clobber volatile registers but keep callee-saved constants.
        if x.mnemonic=='call':
            for r in (X86_REG_EAX,X86_REG_ECX,X86_REG_EDX): known.pop(r,None)
        # Control-flow joins make straight-line constants unreliable.
        if x.group(CS_GRP_JUMP) or x.mnemonic.startswith('ret') or x.mnemonic in ('int','iret'):
            known.clear(); history=[]

print('count='+str(len(hits)))
if not hits:
    print('  <no computed/base+offset write resolved to DE892C>')
for n,(sn,x,hist,known,ea) in enumerate(hits,1):
    print(f'\n-- HIT #{n} section={sn} EA=0x{ea:08X} --')
    for p in hist: print(fmt(p))
    print(fmt(x,'>>'))
    ks=', '.join(f'{REGNAME[r]}=0x{v:08X}' for r,v in known.items())
    print('  known regs before write: '+(ks if ks else '<none>'))
print('')

# Also find instructions that compute exactly &DE892C into a register, even if
# the following use is beyond our conservative block model.
print('================ COMPUTED ADDRESS-OF DE892C ================')
addr_hits=[]
for s in secs:
    if not (s['ch'] & 0x20000000): continue
    blob=data[s['rp']:s['rp']+s['rs']]
    base=IMAGE_BASE+s['rva']
    known={}
    hist=[]
    for x in md.disasm(blob,base):
        before=dict(known)
        set_known_from_instruction(x,known)
        for r,v in known.items():
            if v==TARGET and before.get(r)!=TARGET:
                # Ignore direct MOV reg,0xDE892C only if desired? Keep it visible.
                addr_hits.append((s['name'],x,r,list(hist[-8:])))
        hist.append(x)
        if len(hist)>12: hist=hist[-12:]
        if x.mnemonic=='call':
            for r in (X86_REG_EAX,X86_REG_ECX,X86_REG_EDX): known.pop(r,None)
        if x.group(CS_GRP_JUMP) or x.mnemonic.startswith('ret'):
            known.clear(); hist=[]
print('count='+str(len(addr_hits)))
for n,(sn,x,r,hist) in enumerate(addr_hits,1):
    print(f'\n-- ADDRESS HIT #{n} section={sn} reg={REGNAME[r]} --')
    for p in hist: print(fmt(p))
    print(fmt(x,'>>'))
print('')

# ------------------------------------------------------------------
# B) Host C54 create path.
# ------------------------------------------------------------------
print('================ HOST C54 CREATE PATH 0x84E1F4..0x84E426 ================')
ins,s=disasm_exact(HOST_CREATE,0x0084E427)
print('section='+(s['name'] if s else '?'))
for x in ins:
    mark='>>' if x.address in (0x0084E24E,0x0084E2E4,0x0084E38B,0x0084E3C4,LIST_ATTACH_CALLSITE) else '  '
    print(fmt(x,mark))
print('')

print('================ 0x84A86A POST/FINALIZE HELPER ================')
ins,s=disasm_exact(C54_POST,0x0084A970)
print('section='+(s['name'] if s else '?'))
for x in ins: print(fmt(x,'>>' if x.address==C54_POST else '  '))
print('Direct E8/E9 refs:')
for va,k,sn in direct_rel_refs(C54_POST): print(f'  0x{va:08X} {k} section={sn}')
print('Literal refs:')
for va,sn,ex in literal_refs(C54_POST): print(f'  VA={"0x%08X"%va if va is not None else "<unmapped>"} section={sn} exec={ex}')
print('')

print('================ HOST CREATE FUNCTION REFERENCES ================')
print('Direct E8/E9 refs to 0x84E1F4:')
refs=direct_rel_refs(HOST_CREATE)
print('  count='+str(len(refs)))
for va,k,sn in refs: print(f'  0x{va:08X} {k} section={sn}')
print('Literal DWORD refs to 0x84E1F4:')
lits=literal_refs(HOST_CREATE)
print('  count='+str(len(lits)))
for va,sn,ex in lits: print(f'  VA={"0x%08X"%va if va is not None else "<unmapped>"} section={sn} exec={ex}')
print('')

print('================ LIST ATTACH CALLSITE VALIDATION ================')
off,s=raw_for_va(LIST_ATTACH_CALLSITE)
if off is None:
    print('0x84E3E4 unmapped')
else:
    b=data[off:off+5]
    if b and b[0]==0xE8:
        rel=struct.unpack_from('<i',b,1)[0]
        dst=(LIST_ATTACH_CALLSITE+5+rel)&0xffffffff
        print(f'0x84E3E4 bytes={b.hex(" ").upper()} -> 0x{dst:08X} expected 0x{LIST_ATTACH:08X} match={dst==LIST_ATTACH}')
    else:
        print(f'0x84E3E4 bytes={b.hex(" ").upper()} not direct CALL')
print('')

print('STATIC DECISION TARGETS')
print('  1) If computed-write count > 0, classify each newly found DE892C writer source.')
print('  2) If computed-write count == 0, static direct/computed publication routes are close to exhausted.')
print('  3) Determine whether 0x84E1F4 is a host/create-game lifecycle by its callers/vtable refs and state gates.')
print('  4) Do not infer that a normal client must have DE892C populated solely from the Host control until the create path is classified.')
print('  5) If static routes are exhausted, next proof should be a dynamic write-watch during a clean Host lobby creation or a normal-client join control.')
print('  6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw "DE892C computed/host-create probe failed. Python exit=$LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
