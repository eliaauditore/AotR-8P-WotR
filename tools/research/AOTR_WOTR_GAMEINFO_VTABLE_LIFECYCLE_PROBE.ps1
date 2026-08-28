param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Maps the lifecycle/origin of the known session GameInfo vtable 0x00C54B78.
# Focuses on the embedded 0x9035AE object path and its immediate initializer 0x903179.

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

$tempPy = Join-Path $env:TEMP ('a8p_gameinfo_vtable_lifecycle_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
KNOWN_GI_VT=0x00C54B78
EMBEDDED_VT=0x00C2FB98
EMBEDDED_CTOR=0x009035AE
IMMEDIATE_INIT=0x00903179
ROW_CTOR=0x009034EC
ROW_DTOR=0x007848CD
DE892C_WRITE=0x00788542
THEGAMEINFO_WRITE=0x0078853D

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

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

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

def decoded_absolute_refs(target):
    needle=struct.pack('<I',target)
    results=[]
    seen=set()
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        pos=0
        while True:
            j=blob.find(needle,pos)
            if j<0: break
            rawhit=s['rp']+j
            vahit=IMAGE_BASE+s['rva']+j
            # Try instruction starts up to 10 bytes before the immediate bytes.
            validated=None
            for back in range(0,11):
                va=vahit-back
                raw=rawhit-back
                if raw < s['rp']: continue
                ins=list(md.disasm(data[raw:min(raw+15,s['rp']+s['rs'])],va,count=1))
                if not ins: continue
                x=ins[0]
                if not (x.address <= vahit < x.address+x.size): continue
                ok=False
                for op in x.operands:
                    if op.type==X86_OP_IMM and (op.imm & 0xffffffff)==target: ok=True
                    if op.type==X86_OP_MEM and op.mem.base==0 and op.mem.index==0 and (op.mem.disp & 0xffffffff)==target: ok=True
                if ok:
                    validated=x; break
            if validated and validated.address not in seen:
                seen.add(validated.address)
                results.append((validated,s['name']))
            pos=j+1
    return sorted(results,key=lambda z:z[0].address)

def context(addr,before=0x20,after=0x50):
    start=max(IMAGE_BASE,addr-before)
    ins=window(start,before+after)
    # Since starting mid-instruction can decode garbage, choose only lines near target and additionally decode target itself.
    near=[x for x in ins if addr-0x18 <= x.address <= addr+0x38]
    exact=window(addr,0x40)
    out=[]; seen=set()
    for x in near+exact:
        if x.address in seen: continue
        seen.add(x.address); out.append(x)
    return sorted(out,key=lambda x:x.address)

print('============================================================')
print(' AOTR WOTR GAMEINFO VTABLE LIFECYCLE PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print(f'Known GI vtable  : 0x{KNOWN_GI_VT:08X}')
print(f'Embedded vtable  : 0x{EMBEDDED_VT:08X}')
print('')

for target,label,size in (
    (IMMEDIATE_INIT,'IMMEDIATE INIT 0x903179',0x300),
    (EMBEDDED_CTOR,'EMBEDDED CTOR 0x9035AE',0x120),
    (ROW_CTOR,'EMBEDDED ROW CTOR 0x9034EC',0x180),
    (ROW_DTOR,'EMBEDDED ROW DTOR 0x7848CD',0x100),
):
    print('================ '+label+' ================')
    for x in window(target,size):
        print(fmt(x,'>>' if x.address==target else '  '))
    print('')

print('================ ALL VALIDATED EXECUTABLE REFERENCES TO C54B78 ================')
refs=decoded_absolute_refs(KNOWN_GI_VT)
print('count='+str(len(refs)))
for idx,(x,sec) in enumerate(refs,1):
    print(f'\n-- REF #{idx:02d} section={sec} --')
    for y in context(x.address):
        print(fmt(y,'>>' if y.address==x.address else '  '))
print('')

print('================ VALIDATED EXECUTABLE REFERENCES TO C2FB98 ================')
refs2=decoded_absolute_refs(EMBEDDED_VT)
print('count='+str(len(refs2)))
for idx,(x,sec) in enumerate(refs2,1):
    print(f'\n-- REF #{idx:02d} section={sec} --')
    for y in context(x.address):
        print(fmt(y,'>>' if y.address==x.address else '  '))
print('')

for target,label in ((IMMEDIATE_INIT,'DIRECT CALLERS OF 0x903179'),(EMBEDDED_CTOR,'DIRECT CALLERS OF 0x9035AE')):
    print('================ '+label+' ================')
    cs=direct_callers(target)
    print('count='+str(len(cs)))
    for va,sec in cs: print(f'  0x{va:08X} section={sec}')
    print('')

print('================ KNOWN PUBLICATION POINT ================')
print(f'  0x{THEGAMEINFO_WRITE:08X}: TheGameInfo = embedded object')
print(f'  0x{DE892C_WRITE:08X}: DE892C = same embedded object')
print('')
print('INTERPRETATION TARGETS')
print('  1) Find every instruction that installs/references C54B78.')
print('  2) Determine whether 0x903179 changes C2FB98 object state/vtable or only resets fields.')
print('  3) Identify any constructor that directly installs C54B78.')
print('  4) Reconcile host runtime DE892C/session+0x44 C54B78 identity with 0x788542 publication path.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw "GameInfo vtable lifecycle probe failed. Python exit=$LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
