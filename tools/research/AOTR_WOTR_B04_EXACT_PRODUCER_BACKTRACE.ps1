param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Focused follow-up after Reason-4 was proven to reject ID3 because
# client MSG+0x32 is sourced from local DE4364+0xB04 and compared against
# host DE4364+0xB04. This probe traces only the proven singleton writers:
#   0x63C809  [DE4364]+B04 = [ebp-0x28]
#   0x63C820  [DE4364]+B04 += return(0x61F300)
# It also checks publication of DE4364 and whether the other layout-only
# +B04 writers can be tied to the singleton.

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

$tempPy = Join-Path $env:TEMP ('a8p_b04_exact_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_AC_READ, CS_AC_WRITE
from capstone.x86_const import X86_OP_MEM, X86_OP_IMM, X86_REG_EBP

path=sys.argv[1]
IMAGE_BASE=0x00400000
DE4364=0x00DE4364
OWNER_START=0x0063AD4F
OWNER_END=0x0063CE40
BASE_WRITE=0x0063C809
ADD_WRITE=0x0063C820
ADD_HELPER=0x0061F300
CTOR_WRITE=0x006430E1
LAYOUT_WRITE=0x007BA4FB

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

def rb(va,n):
    s=sec_for_va(va)
    if not s: raise ValueError(f'VA 0x{va:08X} not mapped')
    raw=s['rp']+((va-IMAGE_BASE)-s['rva'])
    return data[raw:raw+n],s,raw

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def dis(start,end):
    b,s,raw=rb(start,end-start)
    return s,raw,list(md.disasm(b,start))

def fmt(x,mark='  ',note=''):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    out=f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'
    return out + ((' ; '+note) if note else '')

def direct_target(x):
    if x.mnemonic not in ('call','jmp') or len(x.operands)!=1: return None
    op=x.operands[0]
    return (op.imm & 0xffffffff) if op.type==X86_OP_IMM else None

def print_window(title,center,before=0x60,after=0x80):
    print('\n================ '+title+' ================')
    start=max(IMAGE_BASE,center-before); end=center+after
    s,raw,ins=dis(start,end)
    for x in ins:
        print(fmt(x,'>>' if x.address==center else '  '))

print('============================================================')
print(' AOTR WOTR B04 EXACT PRODUCER BACKTRACE - DISK ONLY')
print('============================================================')
print(f'Image hash          : {sys.argv[2]}')
print(f'Proven singleton    : [0x{DE4364:08X}]')
print(f'Base write          : 0x{BASE_WRITE:08X}')
print(f'Add write           : 0x{ADD_WRITE:08X}')
print(f'Add helper          : 0x{ADD_HELPER:08X}')

# 1) Exact proven writer block.
print_window('PROVEN SINGLETON B04 WRITER BLOCK',BASE_WRITE,0x70,0x70)

# 2) Back-slice local [ebp-0x28] inside the owning function.
print('\n================ [EBP-0x28] DEFINITIONS BEFORE BASE WRITE ================')
s,raw,owner=dis(OWNER_START,OWNER_END)
hits=[]
for x in owner:
    if x.address>=BASE_WRITE: break
    for op in x.operands:
        if op.type!=X86_OP_MEM: continue
        m=op.mem
        if m.base==X86_REG_EBP and m.disp==-0x28:
            acc=op.access
            if acc & CS_AC_WRITE:
                hits.append(x.address)
                print(fmt(x,'>>','WRITE to local [ebp-0x28]'))
                break
print(f'count={len(hits)}')
for va in hits:
    print_window(f'LOCAL SOURCE WINDOW @ 0x{va:08X}',va,0x70,0x70)

# Also show address-taking/read uses of the same local near the final writer.
print('\n================ ALL [EBP-0x28] USES IN OWNER FUNCTION ================')
for x in owner:
    if x.address>BASE_WRITE+0x20: break
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.base==X86_REG_EBP and op.mem.disp==-0x28:
            tags=[]
            if op.access & CS_AC_READ: tags.append('R')
            if op.access & CS_AC_WRITE: tags.append('W')
            if x.mnemonic=='lea': tags.append('ADDR')
            print(fmt(x,'>>','/'.join(tags) if tags else 'MEM'))
            break

# 3) Exact helper returning the additive component.
print('\n================ ADDITIVE HELPER 0x61F300 ================')
s,raw,hins=dis(ADD_HELPER,ADD_HELPER+0x500)
for x in hins:
    mark='>>' if x.address==ADD_HELPER else '  '
    note=''
    if x.mnemonic=='call':
        t=direct_target(x)
        if t is not None: note=f'CALL 0x{t:08X}'
    print(fmt(x,mark,note))
    if x.mnemonic.startswith('ret'):
        break

print('\n================ DIRECT CALLERS OF 0x61F300 ================')
refs=[]
for sec in secs:
    if not (sec['chars'] & 0x20000000): continue
    blob=data[sec['rp']:min(len(data),sec['rp']+sec['rs'])]
    sva=IMAGE_BASE+sec['rva']
    for i in range(max(0,len(blob)-5)):
        if blob[i]!=0xE8: continue
        src=sva+i
        dst=(src+5+struct.unpack_from('<i',blob,i+1)[0]) & 0xffffffff
        if dst==ADD_HELPER: refs.append(src)
print(f'count={len(refs)}')
for src in refs: print(f'  0x{src:08X}')

# 4) Find exact publication/writes of the global pointer DE4364.
print('\n================ ABSOLUTE WRITES TO GLOBAL 0xDE4364 ================')
ghits=[]
for sec in secs:
    if not (sec['chars'] & 0x20000000): continue
    start=IMAGE_BASE+sec['rva']; end=start+sec['rs']
    try: _,_,ins=dis(start,end)
    except Exception: continue
    for x in ins:
        for op in x.operands:
            if op.type!=X86_OP_MEM: continue
            m=op.mem
            if m.base==0 and m.index==0 and (m.disp & 0xffffffff)==DE4364 and (op.access & CS_AC_WRITE):
                ghits.append(x.address)
                print(fmt(x,'>>','WRITE/PUBLISH DE4364'))
                break
print(f'count={len(ghits)}')
for va in ghits:
    print_window(f'DE4364 PUBLICATION WINDOW @ 0x{va:08X}',va,0x60,0x70)

# 5) Do not assume same +B04 offset means same object. Show the two non-direct writers.
print_window('CTOR-LAYOUT B04 ZERO WRITE',CTOR_WRITE,0x60,0x70)
print_window('OTHER LAYOUT B04 WRITE',LAYOUT_WRITE,0x70,0x70)

print('\n================ CLASSIFICATION TARGETS ================')
print('1) BEWIESEN already: exact singleton final B04 = [ebp-0x28] then += return(0x61F300).')
print('2) Resolve every definition feeding [ebp-0x28].')
print('3) Resolve what 0x61F300 returns and whether it is machine/session dependent.')
print('4) Tie 0x6430E1 to DE4364 only if global publication/caller evidence supports it.')
print('5) Treat 0x7BA4FB as unrelated layout writer unless object provenance proves otherwise.')
print('6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'B04 exact producer backtrace failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
