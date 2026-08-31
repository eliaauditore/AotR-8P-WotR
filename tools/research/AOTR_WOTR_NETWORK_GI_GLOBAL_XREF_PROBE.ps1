param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Traces all executable references to the pre-start NetworkGI globals and
# compares them with the proven native session current pointer path.

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

$tempPy = Join-Path $env:TEMP ('a8p_network_gi_xref_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
TARGETS={
  0x00DE892C:'NETWORK_GI_DE892C',
  0x00DE8930:'NETWORK_GI_ALT_DE8930',
  0x00DE7D6C:'THE_GAMEINFO_DE7D6C',
  0x00DE4394:'SESSION_GLOBAL_DE4394',
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
    ch=struct.unpack_from('<I',data,o+36)[0]
    secs.append(dict(name=name,rva=rva,vs=vs,rs=rs,rp=rp,ch=ch))

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

def is_exec(s): return bool(s['ch'] & 0x20000000)

def section_insns(s):
    blob=data[s['rp']:s['rp']+s['rs']]
    va=IMAGE_BASE+s['rva']
    return list(md.disasm(blob,va))

def refs_target(x,target):
    hit=False
    for op in x.operands:
        if op.type==X86_OP_MEM:
            if op.mem.base==0 and op.mem.index==0 and (op.mem.disp & 0xffffffff)==target:
                hit=True
        elif op.type==X86_OP_IMM and (op.imm & 0xffffffff)==target:
            hit=True
    return hit

def classify_access(x,target):
    # Best-effort x86 operand-direction classification.
    tags=[]
    for i,op in enumerate(x.operands):
        if op.type==X86_OP_MEM and op.mem.base==0 and op.mem.index==0 and (op.mem.disp & 0xffffffff)==target:
            if x.mnemonic in ('mov','movzx','movsx','lea','cmp','test'):
                tags.append('WRITE' if i==0 and x.mnemonic=='mov' else 'READ')
            elif x.mnemonic in ('inc','dec','and','or','xor','add','sub'):
                tags.append('READWRITE' if i==0 else 'READ')
            else:
                tags.append('REF')
        elif op.type==X86_OP_IMM and (op.imm & 0xffffffff)==target:
            tags.append('IMM_ADDR')
    return '/'.join(sorted(set(tags))) if tags else 'REF'

allins=[]
for s in secs:
    if is_exec(s):
        for x in section_insns(s): allins.append((x,s['name']))
byaddr={x.address:i for i,(x,_) in enumerate(allins)}

print('============================================================')
print(' AOTR WOTR NETWORK GI GLOBAL XREF PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print('')

for target,label in TARGETS.items():
    hits=[(i,x,sn,classify_access(x,target)) for i,(x,sn) in enumerate(allins) if refs_target(x,target)]
    print(f'================ {label} 0x{target:08X} ================')
    print(f'count={len(hits)}')
    for n,(idx,x,sn,kind) in enumerate(hits,1):
        print(f'\nREF #{n}: {kind} section={sn}')
        lo=max(0,idx-18); hi=min(len(allins),idx+20)
        for j in range(lo,hi):
            y,_=allins[j]
            # prevent context running across distant disassembly gaps/sections
            if abs(y.address-x.address)>0x120: continue
            print(fmt(y,'>>' if j==idx else '  '))
    print('')

# Dedicated compact summary of direct MOV writers to DE892C/DE8930.
print('================ COMPACT NETWORK_GI WRITERS ================')
for target in (0x00DE892C,0x00DE8930):
    label=TARGETS[target]
    print(f'{label}:')
    anyw=False
    for x,sn in allins:
        if not refs_target(x,target): continue
        kind=classify_access(x,target)
        if 'WRITE' in kind:
            anyw=True
            print('  '+fmt(x,'').strip()+f' section={sn} kind={kind}')
    if not anyw: print('  <no direct absolute writer decoded>')

print('\nINTERPRETATION TARGETS')
print('  1) Identify every direct writer to DE892C and DE8930.')
print('  2) Find the normal path that installs a pre-start NetworkGI pointer.')
print('  3) Determine whether that writer can source session+0x44/current GameInfo.')
print('  4) Compare that path with the direct native join PoC, which currently leaves DE892C NULL on the VM.')
print('  5) Do not patch DE892C directly until the producer/caller semantics are proven.')
print('  6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'network GI global xref probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
