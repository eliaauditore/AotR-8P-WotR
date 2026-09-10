param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Focused follow-up for the proven native Join reason-4 blocker.
# Traces the two components written into the exact DE4364+0xB04 singleton:
#   0x63C809: B04 = [ebp-0x28]
#   0x63C820: B04 += return(0x61F300)
# Also corrects the previously under-classified exact singleton reset writer
# at 0x7BA4FB, which is reached with ECX=[DE4364].

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

$tempPy = Join-Path $env:TEMP ('a8p_b04_components_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_AC_READ, CS_AC_WRITE
from capstone.x86_const import X86_OP_MEM, X86_OP_IMM, X86_REG_EBP, X86_REG_ECX

path=sys.argv[1]
reported_hash=sys.argv[2]
IMAGE_BASE=0x00400000
OWNER_START=0x0063AD4F
OWNER_END=0x0063CE30
BASE_WRITE=0x0063C809
ADD_CALL=0x0063C815
ADD_WRITE=0x0063C820
LAZY_GET=0x0061F300
LAZY_INIT=0x0061F199
GLOBAL_DE3D84=0x00DE3D84
GLOBAL_DE4364=0x00DE4364
RESET_START=0x007BA4CB
RESET_END=0x007BA505
RESET_WRITE=0x007BA4FB

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

def read_bytes(va,n):
    s=sec_for_va(va)
    if not s: raise ValueError(f'VA 0x{va:08X} not mapped')
    raw=s['rp']+((va-IMAGE_BASE)-s['rva'])
    return data[raw:raw+n],s,raw

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def dis(start,end):
    b,s,raw=read_bytes(start,end-start)
    return s,raw,list(md.disasm(b,start))

def fmt(x,mark='  ',note=''):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    line=f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'
    return line + ((' ; '+note) if note else '')

def direct_target(x):
    if x.mnemonic not in ('call','jmp') or len(x.operands)!=1 or x.operands[0].type!=X86_OP_IMM: return None
    return x.operands[0].imm & 0xffffffff

def mem_access(op):
    a=[]
    try:
        if op.access & CS_AC_READ: a.append('R')
        if op.access & CS_AC_WRITE: a.append('W')
    except Exception: pass
    return ''.join(a) or '?'

def all_exec_ins():
    for s in secs:
        if not (s['chars'] & 0x20000000): continue
        raw0=s['rp']; raw1=min(len(data),raw0+s['rs'])
        blob=data[raw0:raw1]
        va=IMAGE_BASE+s['rva']
        for x in md.disasm(blob,va):
            yield x,s

def print_window(ins,idx,before=12,after=12,markva=None):
    lo=max(0,idx-before); hi=min(len(ins),idx+after+1)
    for x in ins[lo:hi]: print(fmt(x,'>>' if x.address==markva else '  '))

print('============================================================')
print(' AOTR WOTR B04 COMPONENT SOURCE PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash          : {reported_hash}')
print(f'Exact B04 base write: 0x{BASE_WRITE:08X}')
print(f'Exact B04 add write : 0x{ADD_WRITE:08X}')
print('')

# Owner function: find every direct or address-taking reference to [ebp-0x28].
s,raw,owner=dis(OWNER_START,OWNER_END)
print('================ OWNER [EBP-0x28] REFERENCES ================')
refs=[]
for i,x in enumerate(owner):
    hit=False; roles=[]
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.base==X86_REG_EBP and op.mem.disp==-0x28:
            hit=True
            roles.append(('ADDR' if x.mnemonic=='lea' else mem_access(op)))
    if hit:
        refs.append((i,x,','.join(roles)))
        print(fmt(x,'>>',f'[ebp-0x28] {roles[-1]}'))
print(f'count={len(refs)}')
print('')

print('================ [EBP-0x28] FOCUSED WINDOWS ================')
for i,x,role in refs:
    print(f'\n--- ref 0x{x.address:08X} role={role} ---')
    print_window(owner,i,10,12,x.address)
    # If the address is taken, identify the first direct call immediately after it.
    if x.mnemonic=='lea':
        for y in owner[i+1:min(len(owner),i+10)]:
            if y.mnemonic=='call':
                t=direct_target(y)
                print('  nearest following call: ' + (f'0x{y.address:08X} -> 0x{t:08X}' if t is not None else f'0x{y.address:08X} -> {y.op_str}'))
                break
print('')

print('================ EXACT WRITER BLOCK 0x63C7E8..0x63C830 ================')
_,_,w=dis(0x0063C7E8,0x0063C830)
for x in w:
    notes=[]
    if x.address==BASE_WRITE: notes.append('B04 = [ebp-0x28]')
    if x.address==0x0063C80F: notes.append('ECX = [DE3D84]')
    if x.address==ADD_CALL: notes.append('returns object+0x200 DWORD')
    if x.address==ADD_WRITE: notes.append('B04 += EAX')
    print(fmt(x,'>>' if notes else '  ',','.join(notes)))
print('')

print('================ 0x61F300 LAZY GETTER ================')
_,_,g=dis(LAZY_GET,0x0061F315)
for x in g: print(fmt(x,'>>' if x.address in (LAZY_GET,0x0061F301,0x0061F311) else '  '))
print('Proven local contract: return *(DWORD*)(ECX+0x200); if zero, call 0x61F199 first.')
print('At the exact B04 writer, ECX is loaded from [0xDE3D84] immediately before this call.')
print('')

print('================ 0x61F199 LAZY INITIALIZER ================')
_,_,init=dis(LAZY_INIT,LAZY_GET)
for x in init: print(fmt(x,'>>' if x.address==LAZY_INIT else '  '))
print('')

print('================ DE3D84 ABSOLUTE REFERENCES ================')
# Print compact windows around every executable instruction that embeds absolute 0xDE3D84.
hits=[]
for x,s in all_exec_ins():
    found=False
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.base==0 and op.mem.index==0 and (op.mem.disp & 0xffffffff)==GLOBAL_DE3D84:
            found=True; break
    if found: hits.append((x,s))
print(f'count={len(hits)}')
for x,s in hits:
    print(f'  0x{x.address:08X} {x.mnemonic} {x.op_str} section={s["name"]}')
print('')

print('================ EXACT DE4364 RESET WRITER CORRECTION ================')
_,_,r=dis(RESET_START,RESET_END)
for x in r:
    note=''
    if x.address==0x007BA4CB: note='loads exact DE4364 singleton'
    if x.address==0x007BA4EA: note='EAX = 0xBAADEC4C'
    if x.address==0x007BA4EF: note='DE4364+B38 = same constant'
    if x.address==RESET_WRITE: note='DE4364+B04 = same constant'
    print(fmt(x,'>>' if note else '  ',note))
print('')

# direct E8 callers of exact reset function entry
refs_reset=[]
for x,s in all_exec_ins():
    if x.mnemonic=='call' and direct_target(x)==RESET_START:
        refs_reset.append((x.address,s['name']))
print('================ DIRECT CALLERS OF RESET 0x7BA4CB ================')
print(f'count={len(refs_reset)}')
for a,sn in refs_reset: print(f'  0x{a:08X} section={sn}')
print('')

print('================ CLASSIFICATION TARGETS ================')
print('1) Find whether [ebp-0x28] is written indirectly through an out-parameter (LEA) rather than by a direct MOV.')
print('2) Resolve the input source of that out-parameter helper.')
print('3) Resolve how [DE3D84]+0x200 is initialized by 0x61F199 and whether it is deterministic across machines.')
print('4) Keep 0x7BA4FB classified as an exact DE4364 singleton reset writer; current live B04/B38 values prove it was not the final writer in the observed join state.')
print('5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'B04 component source probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
