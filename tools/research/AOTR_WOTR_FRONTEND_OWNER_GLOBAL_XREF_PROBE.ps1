param(
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Classifies the three proven module slots that held the runtime frontend owner:
#   0x00DE6CD8, 0x00DE6D1C, 0x00DE8D90
# Finds executable-code xrefs, classifies READ/WRITE access, and prints local context.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash got $hash" }

$py = Get-Command py.exe -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python.exe -ErrorAction SilentlyContinue }
if (-not $py) { throw 'Python not found.' }
$pyPath = $py.Source
& $pyPath -c "import capstone" 2>$null
if ($LASTEXITCODE -ne 0) { throw ('Python capstone missing. Install with: "{0}" -m pip install --user capstone' -f $pyPath) }

$tempPy = Join-Path $env:TEMP ('a8p_owner_global_xref_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
TARGETS=[
  (0x00DE6CD8,'OWNER_SLOT_A_DE6CD8'),
  (0x00DE6D1C,'OWNER_SLOT_B_DE6D1C'),
  (0x00DE8D90,'OWNER_SLOT_C_DE8D90'),
]

with open(path,'rb') as f:data=f.read()
if data[:2]!=b'MZ': raise SystemExit('Not MZ')
pe=struct.unpack_from('<I',data,0x3c)[0]
if data[pe:pe+4]!=b'PE\0\0': raise SystemExit('Bad PE')
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

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True; md.skipdata=True

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<34} {x.mnemonic:<8} {x.op_str}'

def access_for(x,target):
    modes=[]
    for idx,op in enumerate(x.operands):
        if op.type==X86_OP_MEM and op.mem.base==0 and op.mem.index==0 and (op.mem.disp & 0xffffffff)==target:
            acc=getattr(op,'access',0)
            if acc & CS_AC_READ: modes.append('READ')
            if acc & CS_AC_WRITE: modes.append('WRITE')
            if acc==0:
                # Conservative fallback for older capstone access metadata.
                if idx==0 and x.mnemonic.lower() not in ('cmp','test','push'):
                    modes.append('WRITE?')
                else:
                    modes.append('READ?')
        elif op.type==X86_OP_IMM and (op.imm & 0xffffffff)==target:
            modes.append('IMM_ADDR')
    return modes

# Linear decode executable sections and retain neighboring instructions.
allins=[]
for s in secs:
    if not (s['ch'] & 0x20000000): continue
    blob=data[s['rp']:s['rp']+s['rs']]
    base=IMAGE_BASE+s['rva']
    ins=list(md.disasm(blob,base))
    allins.extend((s['name'],x) for x in ins)

print('============================================================')
print(' AOTR WOTR FRONTEND OWNER GLOBAL XREF PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print('')

summary=[]
for target,name in TARGETS:
    hits=[]
    for k,(sec,x) in enumerate(allins):
        modes=access_for(x,target)
        if modes: hits.append((k,sec,x,modes))
    reads=sum(1 for _,_,_,m in hits if any(v.startswith('READ') for v in m))
    writes=sum(1 for _,_,_,m in hits if any(v.startswith('WRITE') for v in m))
    imms=sum(1 for _,_,_,m in hits if 'IMM_ADDR' in m)
    summary.append((target,name,len(hits),reads,writes,imms))
    print(f'================ {name} 0x{target:08X} ================')
    print(f'XREF_COUNT={len(hits)} READ_REFS={reads} WRITE_REFS={writes} IMM_REFS={imms}')
    if not hits:
        print('  <no direct executable xrefs>\n')
        continue
    for n,(k,sec,x,modes) in enumerate(hits,1):
        print(f'XREF #{n}: section={sec} mode={"+".join(modes)}')
        lo=max(0,k-6); hi=min(len(allins),k+7)
        # Keep context within same section and near address to avoid section-boundary noise.
        for j in range(lo,hi):
            secj,y=allins[j]
            if secj!=sec or abs(int(y.address)-int(x.address))>0x60: continue
            print(fmt(y,'>>' if j==k else '  '))
        print('')

print('================ COMPACT SUMMARY ================')
for target,name,total,reads,writes,imms in summary:
    print(f'{name}=0x{target:08X} XREFS={total} READS={reads} WRITES={writes} IMMS={imms}')
print('')
print('INTERPRETATION TARGET')
print('  Prefer a slot that is explicitly written/cleared by frontend-owner construction/destruction')
print('  and read by the 0x849xxx frontend state-machine family.')
print('  Do not mutate any of these globals from this probe.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw "owner global xref probe failed. Python exit=$LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ_ONLY_COMPLETE=YES'
Write-Host 'No process memory was opened or modified.'