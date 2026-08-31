param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Focused follow-up after runtime proved B04 component B ([DE3D84]+0x200)
# is identical on HOST and VM, while component A differs.  The exact B04
# writer reads A from [ebp-0x28].  Immediately before that read, 0x638C52
# receives a pointer to the local object rooted at [ebp-0x6C]; -0x28 is
# exactly +0x44 from that root.  This probe resolves that producer path.

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

$tempPy = Join-Path $env:TEMP ('a8p_b04_a_producer_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys,struct
from capstone import Cs,CS_ARCH_X86,CS_MODE_32
from capstone.x86_const import X86_OP_MEM,X86_OP_REG,X86_OP_IMM,X86_REG_EBP

path=sys.argv[1]
IMAGE_BASE=0x00400000
OWNER_PRE=0x0063C760
OWNER_END=0x0063C830
PRODUCER=0x00638C52
CLEANUP=0x00A205AD
LOCAL_ROOT=-0x6C
TARGET_LOCAL=-0x28
TARGET_FIELD=0x44

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

def sec_for_va(va):
    rva=va-IMAGE_BASE
    for s in secs:
        if s['rva']<=rva<s['rva']+max(s['vs'],s['rs']): return s
    return None

def va_to_raw(va):
    s=sec_for_va(va)
    if not s: raise ValueError(f'VA 0x{va:08X} not mapped')
    return s['rp']+((va-IMAGE_BASE)-s['rva']),s

def rb(va,n):
    raw,s=va_to_raw(va)
    return data[raw:raw+n],s,raw

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def dis(va,n):
    b,s,r=rb(va,n)
    return list(md.disasm(b,va)),s,r

def fmt(x,mark='  '):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<43} {x.mnemonic:<8} {x.op_str}'

def direct_target(x):
    if x.mnemonic not in ('call','jmp') or not x.operands: return None
    op=x.operands[0]
    return (op.imm & 0xffffffff) if op.type==X86_OP_IMM else None

def find_function_end(start,maxlen=0x2000):
    ins,_,_=dis(start,maxlen)
    out=[]
    for x in ins:
        out.append(x)
        if x.mnemonic.startswith('ret'):
            break
    return out

print('============================================================')
print(' AOTR WOTR B04 COMPONENT-A PRODUCER PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print(f'Producer         : 0x{PRODUCER:08X}')
print(f'Local root       : [ebp-0x6C]')
print(f'Component A      : [ebp-0x28] = localRoot+0x{TARGET_FIELD:X}')
print('')

print('================ EXACT OWNER CALL / LOCAL-OBJECT WINDOW ================')
ins,s,r=dis(OWNER_PRE,OWNER_END-OWNER_PRE)
for x in ins:
    mark='>>' if x.address in (0x0063C7CA,0x0063C7E8,0x0063C7F0,0x0063C7F3,0x0063C806,0x0063C809) else '  '
    print(fmt(x,mark))
print('')
print('Key geometry: [ebp-0x28] - [ebp-0x6C] = +0x44.')
print('The local-root pointer is visibly passed in the argument setup immediately before 0x638C52.')
print('')

print('================ PRODUCER 0x638C52 DISASSEMBLY ================')
pins=find_function_end(PRODUCER,0x1800)
for x in pins:
    print(fmt(x,'>>' if x.address==PRODUCER else '  '))
print('')

print('================ PRODUCER STACK-ARG LOADS ================')
for x in pins:
    hits=[]
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.base==X86_REG_EBP and op.mem.disp>=8 and op.mem.disp<=0x40:
            hits.append(op.mem.disp)
    if hits:
        print(fmt(x,'>>') + ' ; args=' + ','.join(f'[ebp+0x{d:X}]' for d in hits))
print('')

# Lightweight linear taint: registers that receive a pointer directly from a
# stack arg are tagged ARG+offset.  Track simple mov reg,reg propagation and
# report memory writes through a tagged base, especially +0x44.
print('================ PRODUCER ARG-POINTER DERIVED WRITES ================')
regtag={}
found=[]
for x in pins:
    # kill/propagate destination register for simple MOV/LEA forms
    if x.mnemonic=='mov' and len(x.operands)>=2:
        d,sop=x.operands[0],x.operands[1]
        if d.type==X86_OP_REG:
            dr=d.reg
            if sop.type==X86_OP_MEM and sop.mem.base==X86_REG_EBP and 8<=sop.mem.disp<=0x40:
                regtag[dr]=f'ARG_[ebp+0x{sop.mem.disp:X}]'
            elif sop.type==X86_OP_REG and sop.reg in regtag:
                regtag[dr]=regtag[sop.reg]
            else:
                regtag.pop(dr,None)
    elif x.mnemonic=='lea' and len(x.operands)>=2 and x.operands[0].type==X86_OP_REG:
        regtag.pop(x.operands[0].reg,None)

    # report writes through a tagged register base
    if x.operands:
        d=x.operands[0]
        if d.type==X86_OP_MEM and d.mem.base in regtag:
            tag=regtag[d.mem.base]
            disp=d.mem.disp
            mark=' << TARGET +0x44' if disp==TARGET_FIELD else ''
            line=fmt(x,'>>')+f' ; base={tag} disp={disp:+#x}{mark}'
            found.append(line)
            print(line)
if not found:
    print('<no simple direct arg-derived memory writes detected>')
print('')

print('================ PRODUCER CALLS WITH ARG-DERIVED POINTERS ================')
# Re-run simple taint and report calls preceded by pushes of tagged regs within
# the last few instructions.  This catches out-parameter helper patterns.
regtag={}; recent=[]
for x in pins:
    if x.mnemonic=='mov' and len(x.operands)>=2:
        d,sop=x.operands[0],x.operands[1]
        if d.type==X86_OP_REG:
            if sop.type==X86_OP_MEM and sop.mem.base==X86_REG_EBP and 8<=sop.mem.disp<=0x40:
                regtag[d.reg]=f'ARG_[ebp+0x{sop.mem.disp:X}]'
            elif sop.type==X86_OP_REG and sop.reg in regtag:
                regtag[d.reg]=regtag[sop.reg]
            else: regtag.pop(d.reg,None)
    if x.mnemonic=='push' and x.operands and x.operands[0].type==X86_OP_REG and x.operands[0].reg in regtag:
        recent.append((x.address,regtag[x.operands[0].reg]))
        recent=recent[-6:]
    elif x.mnemonic=='call':
        dst=direct_target(x)
        if recent:
            print(f'  call 0x{x.address:08X} -> ' + (f'0x{dst:08X}' if dst else '<indirect>') + ' ; recent arg-derived pushes: ' + ', '.join(f'0x{a:08X}:{t}' for a,t in recent))
        recent=[]
print('')

print('================ PRODUCER DIRECT CALL MAP ================')
for x in pins:
    if x.mnemonic=='call':
        dst=direct_target(x)
        print(f'  0x{x.address:08X} -> ' + (f'0x{dst:08X}' if dst else '<indirect>'))
print('')

print('================ CLEANUP 0xA205AD EXCERPT ================')
try:
    cins,_,_=dis(CLEANUP,0x120)
    for x in cins[:48]:
        print(fmt(x,'>>' if x.address==CLEANUP else '  '))
        if x.mnemonic.startswith('ret'): break
except Exception as e:
    print(f'<decode failed: {e}>')
print('')

print('================ DIRECT CALLERS OF 0x638C52 ================')
refs=[]
for sec in secs:
    if not (sec['chars'] & 0x20000000): continue
    raw0=sec['rp']; raw1=min(len(data),raw0+sec['rs']); blob=data[raw0:raw1]; sva=IMAGE_BASE+sec['rva']
    for i in range(max(0,len(blob)-5)):
        if blob[i]!=0xE8: continue
        rel=struct.unpack_from('<i',blob,i+1)[0]
        src=sva+i; dst=(src+5+rel)&0xffffffff
        if dst==PRODUCER: refs.append(src)
print(f'count={len(refs)}')
for src in refs: print(f'  0x{src:08X}')
print('')

print('================ INTERPRETATION TARGETS ================')
print('1) Runtime already proved component B identical; component A alone differs HOST vs VM.')
print('2) Determine which 0x638C52 argument is the [ebp-0x6C] local object and how +0x44 gets populated.')
print('3) If +0x44 is written by a helper, follow only that helper and its input source.')
print('4) Do not patch B04 yet; first classify whether A is content/config, host/session identity, random/time, or other local state.')
print('5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'B04 component-A producer probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
