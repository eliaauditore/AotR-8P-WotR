param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Maps the vtable installed by 0x628B3A and the helpers that build its 8x PlayerInfo layout.

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

$tempPy = Join-Path $env:TEMP ('a8p_staging_vtable_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys,struct
from capstone import *

path=sys.argv[1]
BASE=0x00400000
VT=0x00BFD668
FOCUS={
  'BIND_ROW_800BDE':0x00800BDE,
  'PLAYERINFO_CTOR_801415':0x00801415,
  'PLAYERINFO_ASSIGN_8014F1':0x008014F1,
  'POSTCOPY_801680':0x00801680,
  'STAGING_CTOR_628B3A':0x00628B3A,
}
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
    secs.append((name,rva,vs,rs,rp,ch))

def va2raw(va):
    rva=va-BASE
    for name,srva,vs,rs,rp,ch in secs:
        span=max(vs,rs)
        if srva<=rva<srva+span:
            return rp+(rva-srva),name,ch
    return None,None,None

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def dump(va,n=120):
    raw,name,ch=va2raw(va)
    print(f'-- 0x{va:08X} section={name} --')
    if raw is None:
        print('  <VA not mapped>');return
    blob=data[raw:raw+n]
    for x in md.disasm(blob,va):
        bs=' '.join(f'{b:02X}' for b in x.bytes)
        print(f'  0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}')
        if x.mnemonic.startswith('ret') and x.address>va+4: break

print('============================================================')
print(' AOTR WOTR STAGING VTABLE PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print(f'Vtable     : 0x{VT:08X}')
print('')

raw,name,ch=va2raw(VT)
if raw is None: raise SystemExit('vtable not mapped')
print('================ VTABLE ENTRIES ================')
entries=[]
for i in range(16):
    fn=struct.unpack_from('<I',data,raw+i*4)[0]
    entries.append(fn)
    print(f'+0x{i*4:02X} -> 0x{fn:08X}')

for off in (0x00,0x04,0x08,0x0C,0x10,0x14,0x18,0x1C,0x20,0x24,0x28,0x2C,0x30,0x34,0x38,0x3C):
    fn=entries[off//4]
    print(f'\n================ VFUNC +0x{off:02X} ================')
    dump(fn,180)

for label,va in FOCUS.items():
    print(f'\n================ {label} ================')
    dump(va,220)

print('\nINTERPRETATION TARGETS')
print('  1) Classify vtable +0x28, invoked twice during 0x82BE68..BEC1 creation.')
print('  2) Classify vtable +0x34, later called from LivingWorld setup through DE8930.')
print('  3) Prove what 0x800BDE writes for each of the eight inline PlayerInfo rows.')
print('  4) Compare this BFD668 class with the separate session GameInfo class C54B78.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'staging vtable probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
