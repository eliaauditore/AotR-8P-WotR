param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Classifies the strongest runtime xref candidates discovered for the current
# pre-start Network-GameInfo pointer:
#   candidate object A vtable-like value: 0x00C54CE0
#   candidate object B vtable-like value: 0x00C508A0
# It also disassembles helper 0x007871FC, used by 0x00787C09 before [eax]=GameInfo*.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

$py = Get-Command py.exe -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python.exe -ErrorAction SilentlyContinue }
if (-not $py) { throw 'Python not found.' }
$pyPath = $py.Source
& $pyPath -c "import capstone" 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Python capstone missing.' }

$tempPy = Join-Path $env:TEMP ('a8p_ptr_classifier_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys,struct
from capstone import Cs,CS_ARCH_X86,CS_MODE_32

path=sys.argv[1]
IMAGE_BASE=0x00400000
TARGETS=[0x00C54CE0,0x00C508A0]
HELPER=0x007871FC
HELPER_STOP=0x007872C0

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
    secs.append((name,rva,vs,rp,rs))

def va_to_raw(va):
    rva=va-IMAGE_BASE
    for name,srva,vs,rp,rs in secs:
        if srva <= rva < srva+max(vs,rs):
            return rp+(rva-srva)
    raise ValueError(hex(va))

def raw_to_va(raw):
    for name,srva,vs,rp,rs in secs:
        if rp <= raw < rp+rs:
            return IMAGE_BASE+srva+(raw-rp),name
    return None,None

text=next(s for s in secs if s[0]=='.text')
_,trva,tvs,trp,trs=text
text_bytes=data[trp:trp+trs]
text_va=IMAGE_BASE+trva
md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=False
ins=list(md.disasm(text_bytes,text_va))
byaddr={x.address:i for i,x in enumerate(ins)}

print('============================================================')
print(' AOTR WOTR POINTER-HIT CLASSIFIER - DISK ONLY')
print('============================================================')
print('Targets: 0x00C54CE0, 0x00C508A0')
print('Helper : 0x007871FC')
print('')

for target in TARGETS:
    pat=struct.pack('<I',target)
    literal=[]
    pos=0
    while True:
        p=data.find(pat,pos)
        if p<0: break
        va,sec=raw_to_va(p)
        if va is not None:
            literal.append((p,va,sec))
        pos=p+1
    print(f'================ TARGET 0x{target:08X} ================')
    print(f'Literal occurrences in mapped sections: {len(literal)}')
    for n,(raw,va,sec) in enumerate(literal,1):
        print(f'LITERAL #{n}: VA=0x{va:08X} section={sec}')
        # If in text, show containing instruction/context by nearest prior boundary.
        if sec=='.text':
            idx=None
            for j,x in enumerate(ins):
                if x.address <= va < x.address+x.size:
                    idx=j; break
            if idx is not None:
                lo=max(0,idx-8); hi=min(len(ins),idx+9)
                for j in range(lo,hi):
                    x=ins[j]; mark='>>' if j==idx else '  '
                    b=' '.join(f'{v:02X}' for v in x.bytes)
                    print(f'{mark} 0x{x.address:08X}: {b:<32} {x.mnemonic:<8} {x.op_str}')
        else:
            c0=max(0,raw-32); c1=min(len(data),raw+36)
            print('  bytes:', ' '.join(f'{b:02X}' for b in data[c0:c1]))
    print('')

print('================ HELPER 0x007871FC TRACE ================')
start_raw=va_to_raw(HELPER)
stop_raw=va_to_raw(HELPER_STOP-1)+1
helper=list(md.disasm(data[start_raw:stop_raw],HELPER))
for x in helper:
    b=' '.join(f'{v:02X}' for v in x.bytes)
    print(f'0x{x.address:08X}: {b:<32} {x.mnemonic:<8} {x.op_str}')
    if x.mnemonic.startswith('ret'):
        break

print('')
print('Interpretation targets:')
print('  - A .text write of an immediate vtable value identifies a constructor/destructor path.')
print('  - 0x00C54CE0 is especially important because runtime object 0x095875B8 held')
print('    GameInfo* at +0x10 and +0x44 and host endpoint at +0x48/+0x4C.')
print('  - Helper 0x007871FC semantics tell us whether EAX is a map/tree value-slot address,')
print('    which can link runtime pointer-xref nodes back to the manager container at this+0x24.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat
    if ($LASTEXITCODE -ne 0) { throw 'pointer-hit classifier failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
