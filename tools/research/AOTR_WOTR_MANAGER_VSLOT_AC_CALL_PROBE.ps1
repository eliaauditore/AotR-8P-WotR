param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Finds indirect virtual CALL sites using vtable slot +0xAC.
# Known class relation:
#   vtable 0x00C2FC58
#   [vtable+0xAC] = 0x00787C09
# The target method allocates a standalone 0x1080 Network-GameInfo and stores it
# in the manager/container rooted at this+0x24.

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

$tempPy = Join-Path $env:TEMP ('a8p_vslot_ac_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path=sys.argv[1]
IMAGE_BASE=0x00400000
SLOT=0xAC

with open(path,'rb') as f:
    data=f.read()
if data[:2] != b'MZ': raise SystemExit('Not MZ')
pe=struct.unpack_from('<I',data,0x3C)[0]
if data[pe:pe+4] != b'PE\0\0': raise SystemExit('Bad PE')
num=struct.unpack_from('<H',data,pe+6)[0]
opt=struct.unpack_from('<H',data,pe+20)[0]
sec0=pe+24+opt
secs=[]
for i in range(num):
    o=sec0+i*40
    name=data[o:o+8].split(b'\0',1)[0].decode('ascii','replace')
    vs,rva,rs,rp=struct.unpack_from('<IIII',data,o+8)
    secs.append((name,rva,vs,rp,rs))

text=next((s for s in secs if s[0]=='.text'),None)
if not text: raise SystemExit('.text not found')
name,rva,vs,rp,rs=text
code=data[rp:rp+rs]
text_va=IMAGE_BASE+rva

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=False
ins=list(md.disasm(code,text_va))

hits=[]
for idx,x in enumerate(ins):
    if x.mnemonic != 'call':
        continue
    op=x.op_str.lower().replace(' ', '')
    # Capstone examples: dword ptr [eax + 0xac]
    if '[eax+0xac]' in op or '[ecx+0xac]' in op or '[edx+0xac]' in op or '[ebx+0xac]' in op or '[esi+0xac]' in op or '[edi+0xac]' in op or '[ebp+0xac]' in op or '[esp+0xac]' in op:
        hits.append((idx,x))

print('============================================================')
print(' AOTR WOTR MANAGER VSLOT +0xAC CALL PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash          : {sys.argv[2]}')
print('Manager vtable      : 0x00C2FC58')
print('Method slot         : +0xAC')
print('Slot function       : 0x00787C09')
print(f'Indirect slot calls : {len(hits)}')
print('')

for n,(idx,x) in enumerate(hits,1):
    print(f'HIT #{n}: VA=0x{x.address:08X}  {x.mnemonic} {x.op_str}')
    lo=max(0,idx-12); hi=min(len(ins),idx+7)
    for y in ins[lo:hi]:
        mark='>>' if y.address==x.address else '  '
        b=' '.join(f'{v:02X}' for v in y.bytes)
        print(f'{mark} 0x{y.address:08X}: {b:<32} {y.mnemonic:<8} {y.op_str}')
    print('')

print('Interpretation:')
print('  - Track the register used as the vtable base at each CALL.')
print('  - Walk backward to the object pointer whose [this] vtable was loaded.')
print('  - That object is the concrete receiver passed into 0x00787C09, where ESI=ECX.')
print('  - Compare its provenance against live lobby/session globals; do not infer ownership from offset coincidence alone.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'vslot +0xAC call probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
