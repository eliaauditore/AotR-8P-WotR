param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Robust byte-pattern xref probe for globals whose earlier linear Capstone scan
# could stop at decode gaps and falsely report zero references.

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

$tempPy = Join-Path $env:TEMP ('a8p_network_gi_byte_xref_' + [guid]::NewGuid().ToString('N') + '.py')
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

def is_exec(s): return bool(s['ch'] & 0x20000000)
def raw_to_va(raw,s): return IMAGE_BASE+s['rva']+(raw-s['rp'])

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def operand_refs(x,target):
    for op in x.operands:
        if op.type==X86_OP_MEM:
            if op.mem.base==0 and op.mem.index==0 and (op.mem.disp & 0xffffffff)==target:
                return True
        elif op.type==X86_OP_IMM and (op.imm & 0xffffffff)==target:
            return True
    return False

def classify(x,target):
    tags=[]
    for i,op in enumerate(x.operands):
        if op.type==X86_OP_MEM and op.mem.base==0 and op.mem.index==0 and (op.mem.disp & 0xffffffff)==target:
            if x.mnemonic=='mov' and i==0: tags.append('WRITE')
            elif x.mnemonic in ('inc','dec','and','or','xor','add','sub') and i==0: tags.append('READWRITE')
            else: tags.append('READ')
        elif op.type==X86_OP_IMM and (op.imm & 0xffffffff)==target:
            tags.append('IMM_ADDR')
    return '/'.join(sorted(set(tags))) if tags else 'RAW_ONLY'

def raw_hits(target):
    needle=struct.pack('<I',target)
    out=[]
    for s in secs:
        if not is_exec(s): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        p=0
        while True:
            i=blob.find(needle,p)
            if i<0: break
            out.append((s,s['rp']+i))
            p=i+1
    return out

def decode_instruction_for_hit(s,raw_hit,target):
    # Try every possible x86 instruction start up to 15 bytes before the 4-byte address.
    best=[]
    for back in range(0,16):
        start=raw_hit-back
        if start < s['rp']: continue
        va=raw_to_va(start,s)
        blob=data[start:min(s['rp']+s['rs'],start+24)]
        ins=list(md.disasm(blob,va,count=1))
        if not ins: continue
        x=ins[0]
        end=start+x.size
        if not (start <= raw_hit and raw_hit+4 <= end): continue
        if operand_refs(x,target):
            best.append((back,x))
    if not best: return None
    # Prefer the closest plausible instruction start.
    best.sort(key=lambda z:z[0])
    return best[0][1]

def context_for_instruction(s,x,before=0x50,after=0x60):
    raw_x=s['rp'] + (x.address-(IMAGE_BASE+s['rva']))
    lo=max(s['rp'],raw_x-before)
    hi=min(s['rp']+s['rs'],raw_x+after)
    # Find a synchronized decode stream that includes x.address.
    choices=[]
    for shift in range(0,min(32,raw_x-lo)+1):
        st=lo+shift
        va=raw_to_va(st,s)
        ins=list(md.disasm(data[st:hi],va))
        idx=next((i for i,y in enumerate(ins) if y.address==x.address),None)
        if idx is not None: choices.append((idx,ins))
    if not choices: return []
    idx,ins=max(choices,key=lambda z:z[0])
    return ins[max(0,idx-12):min(len(ins),idx+14)]

print('============================================================')
print(' AOTR WOTR NETWORK GI BYTE XREF PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print('Method     : raw little-endian address scan + aligned instruction validation')
print('')

all_decoded={}
for target,label in TARGETS.items():
    rh=raw_hits(target)
    decoded=[]; raw_only=[]
    seen=set()
    for s,raw in rh:
        x=decode_instruction_for_hit(s,raw,target)
        if x:
            key=x.address
            if key in seen: continue
            seen.add(key)
            decoded.append((s,x,classify(x,target),raw))
        else:
            raw_only.append((s,raw))
    all_decoded[target]=decoded
    print(f'================ {label} 0x{target:08X} ================')
    print(f'raw_hits={len(rh)} decoded_refs={len(decoded)} raw_only={len(raw_only)}')
    for n,(s,x,kind,raw) in enumerate(decoded,1):
        print(f'\nREF #{n}: {kind} section={s["name"]} raw=0x{raw:08X}')
        ctx=context_for_instruction(s,x)
        if ctx:
            for y in ctx: print(fmt(y,'>>' if y.address==x.address else '  '))
        else:
            print(fmt(x,'>>'))
    if raw_only:
        print('\nRAW-ONLY occurrences (not yet instruction-validated):')
        for s,raw in raw_only[:20]: print(f'  VA~0x{raw_to_va(raw,s):08X} raw=0x{raw:08X} section={s["name"]}')
    print('')

print('================ COMPACT WRITERS ================')
for target in (0x00DE892C,0x00DE8930,0x00DE7D6C):
    print(TARGETS[target]+':')
    ws=[(s,x,k) for s,x,k,_ in all_decoded[target] if 'WRITE' in k]
    if not ws:
        print('  <no validated direct absolute writer>')
    else:
        for s,x,k in ws:
            print('  '+fmt(x,'').strip()+f' section={s["name"]} kind={k}')

# Hard sanity gate: known session global must have at least one decoded reference.
if not all_decoded[0x00DE4394]:
    print('\nSANITY FAILURE: DE4394 still has zero decoded refs. Do not trust this probe.')
    raise SystemExit(3)
else:
    print(f'\nSANITY PASS: DE4394 decoded refs={len(all_decoded[0x00DE4394])}')

print('\nINTERPRETATION TARGETS')
print('  1) Find validated writers to DE892C/DE8930.')
print('  2) Trace the surrounding producer path and its source pointer.')
print('  3) Compare with session+0x44/current GameInfo.')
print('  4) Do not patch DE892C directly before producer semantics are proven.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw "network GI byte xref probe failed. Python exit=$LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
