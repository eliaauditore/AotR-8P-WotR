param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Classifies the object allocated at 0x82BE68 (size 0xE9C), constructed by
# 0x628B3A, then installed into DE8930/DE892C. Also maps the immediate
# post-construction helpers and direct callers of the constructor.

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

$tempPy = Join-Path $env:TEMP ('a8p_network_gi_ctor_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys,struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
CTOR=0x00628B3A
POST1=0x005F2D09
POST2=0x00801680
KNOWN_GI_VT=0x00C54B78
WRITER=0x0082BE92

with open(path,'rb') as f:data=f.read()
pe=struct.unpack_from('<I',data,0x3c)[0]
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
    return s,s['rp']+(va-(IMAGE_BASE+s['rva']))

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

def disasm_from(va,size=0x180):
    s,raw=raw_for_va(va)
    if not s:return []
    hi=min(s['rp']+s['rs'],raw+size)
    return list(md.disasm(data[raw:hi],va))

def direct_callers(target):
    out=[]
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        base=IMAGE_BASE+s['rva']
        # byte-resilient scan: try every E8 byte as a potential call start
        for i,b in enumerate(blob[:-4]):
            if b != 0xE8: continue
            rel=struct.unpack_from('<i',blob,i+1)[0]
            va=base+i
            dst=(va+5+rel)&0xffffffff
            if dst != target: continue
            ins=list(md.disasm(blob[i:i+8],va,count=1))
            if ins and ins[0].mnemonic=='call': out.append((s,ins[0]))
    return out

def refs_imm(insns,val):
    hits=[]
    for x in insns:
        for op in x.operands:
            if op.type==X86_OP_IMM and (op.imm & 0xffffffff)==val:
                hits.append(x); break
            if op.type==X86_OP_MEM and op.mem.base==0 and op.mem.index==0 and (op.mem.disp & 0xffffffff)==val:
                hits.append(x); break
    return hits

print('============================================================')
print(' AOTR WOTR NETWORK GI CONSTRUCTOR CLASS PROBE - DISK ONLY')
print('============================================================')
print('Image hash     : '+sys.argv[2])
print(f'Allocation size: 0xE9C')
print(f'Constructor    : 0x{CTOR:08X}')
print(f'Known GI vtable: 0x{KNOWN_GI_VT:08X}')
print('')

for label,va,size in [
    ('CTOR_628B3A',CTOR,0x260),
    ('POST_INIT_5F2D09',POST1,0x180),
    ('POST_INIT_801680',POST2,0x180),
]:
    print(f'================ {label} 0x{va:08X} ================')
    ins=disasm_from(va,size)
    for x in ins:
        print(fmt(x,'>>' if x.address==va else '  '))
        if x.mnemonic.startswith('ret'): break
    if va==CTOR:
        hits=refs_imm(ins,KNOWN_GI_VT)
        print('\n-- KNOWN GAMEINFO VTABLE REFERENCES IN CTOR WINDOW --')
        if hits:
            for x in hits: print(fmt(x,'>>'))
        else:
            print('  <none in decoded constructor window>')
    print('')

print('================ DIRECT CALLERS OF CTOR 0x628B3A ================')
cs=direct_callers(CTOR)
print('count='+str(len(cs)))
for n,(s,x) in enumerate(cs,1):
    print(f'  #{n:02d} {fmt(x,"").strip()} section={s["name"]}')
print('')

print('================ DIRECT CALLERS OF POST-INIT HELPERS ================')
for label,target in [('5F2D09',POST1),('801680',POST2)]:
    cs=direct_callers(target)
    print(label+' count='+str(len(cs)))
    for n,(s,x) in enumerate(cs[:80],1):
        print(f'  #{n:02d} {fmt(x,"").strip()} section={s["name"]}')
print('')

# Strong static sanity anchors from the already proven writer path.
writer_ins=disasm_from(0x0082BE68,0x70)
print('================ WRITER CREATION SEQUENCE ================')
for x in writer_ins:
    print(fmt(x,'>>' if x.address in (0x0082BE68,0x0082BE83,0x0082BE92,0x0082BE97,0x0082BE9C,0x0082BEA7,0x0082BEB4,0x0082BEC1) else '  '))
    if x.address>=0x0082BEC4: break

print('\nINTERPRETATION TARGETS')
print('  1) Does 0x628B3A install known GameInfo vtable 0x00C54B78?')
print('  2) What fields/subobjects does the constructor initialize?')
print('  3) What do 0x5F2D09 and 0x801680 do to the fresh object?')
print('  4) Is the 0x82BE92/97 path the native pre-start NetworkGameInfo creation path?')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw "constructor class probe failed. Python exit=$LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
