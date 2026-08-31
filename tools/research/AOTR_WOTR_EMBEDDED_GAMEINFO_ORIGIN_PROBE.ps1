param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Traces the only plausible C54B78-producing DE892C writer path:
#   0x78844A outer constructor -> embedded object at ESI+0x674
#   -> 0x9035AE embedded constructor -> 0x788542 DE892C write.

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

$tempPy = Join-Path $env:TEMP ('a8p_embedded_gameinfo_origin_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
OUTER_CTOR=0x0078844A
EMBEDDED_CTOR=0x009035AE
DE892C_WRITE=0x00788542
THEGAMEINFO_WRITE=0x0078853D
KNOWN_GI_VT=0x00C54B78
OUTER_VT=0x00C2FC58
EMBED_OFFSET=0x674

with open(path,'rb') as f: data=f.read()
if data[:2] != b'MZ': raise SystemExit('Not MZ')
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
        span=max(s['vs'],s['rs'])
        if s['rva'] <= rva < s['rva']+span: return s
    return None

def va_to_raw(va):
    s=sec_for_va(va)
    if not s: return None
    return s['rp']+(va-IMAGE_BASE-s['rva'])

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def window(start,size):
    raw=va_to_raw(start); s=sec_for_va(start)
    if raw is None: return []
    hi=min(s['rp']+s['rs'],raw+size)
    return list(md.disasm(data[raw:hi],start))

def direct_callers(target):
    out=[]
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        for i in range(0,len(blob)-5):
            if blob[i] != 0xE8: continue
            va=IMAGE_BASE+s['rva']+i
            rel=struct.unpack_from('<i',blob,i+1)[0]
            if (va+5+rel)&0xffffffff == target:
                out.append((va,s['name']))
    return out

def refs_imm(ins,target):
    hits=[]
    for x in ins:
        for op in x.operands:
            if op.type==X86_OP_IMM and (op.imm & 0xffffffff)==target:
                hits.append(x); break
            if op.type==X86_OP_MEM and op.mem.base==0 and op.mem.index==0 and (op.mem.disp & 0xffffffff)==target:
                hits.append(x); break
    return hits

print('============================================================')
print(' AOTR WOTR EMBEDDED GAMEINFO ORIGIN PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print(f'Outer ctor       : 0x{OUTER_CTOR:08X}')
print(f'Embedded ctor    : 0x{EMBEDDED_CTOR:08X}')
print(f'Embedded offset  : +0x{EMBED_OFFSET:X}')
print(f'Known GI vtable  : 0x{KNOWN_GI_VT:08X}')
print('')

print('================ OUTER CONSTRUCTOR 0x78844A ================')
out=window(OUTER_CTOR,0x180)
for x in out: print(fmt(x,'>>' if x.address in (OUTER_CTOR,THEGAMEINFO_WRITE,DE892C_WRITE) else '  '))
print('')

print('================ EMBEDDED CONSTRUCTOR 0x9035AE ================')
emb=window(EMBEDDED_CTOR,0x500)
for x in emb: print(fmt(x,'>>' if x.address==EMBEDDED_CTOR else '  '))
print('')

print('================ KNOWN C54B78 REFERENCES IN EMBEDDED CTOR WINDOW ================')
hits=refs_imm(emb,KNOWN_GI_VT)
if hits:
    for x in hits: print(fmt(x,'>>'))
else:
    print('  <none>')
print('')

print('================ OUTER C2FC58 REFERENCES IN OUTER CTOR WINDOW ================')
hits2=refs_imm(out,OUTER_VT)
if hits2:
    for x in hits2: print(fmt(x,'>>'))
else:
    print('  <none>')
print('')

for target,label in ((OUTER_CTOR,'DIRECT CALLERS OF OUTER CTOR 0x78844A'),(EMBEDDED_CTOR,'DIRECT CALLERS OF EMBEDDED CTOR 0x9035AE')):
    print('================ '+label+' ================')
    cs=direct_callers(target)
    print('count='+str(len(cs)))
    for va,sec in cs:
        print(f'  0x{va:08X} section={sec}')
    print('')

print('================ TARGET CHAIN ================')
print('  0x7884E0: EDI = ESI + 0x674')
print('  0x7884EC: call 0x9035AE with ECX=EDI')
print('  0x788538: EAX = EDI')
print('  0x78853D: TheGameInfo = EAX')
print('  0x788542: DE892C = EAX')
print('')
print('INTERPRETATION TARGETS')
print('  1) Does 0x9035AE install/derive known C54B78 GameInfo semantics?')
print('  2) Is the host NetworkGI created as embedded outer+0x674 object?')
print('  3) Identify callers that create this outer object in the normal host/frontend path.')
print('  4) Do not infer copy direction merely from DE892C == session+0x44.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw "embedded GameInfo origin probe failed. Python exit=$LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
