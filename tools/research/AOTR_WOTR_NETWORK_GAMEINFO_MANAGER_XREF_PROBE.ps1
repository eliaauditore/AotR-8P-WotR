param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Finds direct rel32 callers/jumpers and literal pointer refs to the now-correct
# function start 0x00787C09 (the 0x1080 standalone Network-GameInfo allocation path).
# This is used to identify the manager/vtable that owns the [ESI+0x24] container.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$TargetVA = [uint32]0x00787C09

if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

$py = Get-Command py.exe -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python.exe -ErrorAction SilentlyContinue }
if (-not $py) { throw 'Python not found.' }
$pyPath = $py.Source

$tempPy = Join-Path $env:TEMP ('a8p_mgrxref_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
path=sys.argv[1]
target=int(sys.argv[2],16)
IMAGE_BASE=0x00400000
with open(path,'rb') as f: data=f.read()
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
    chars=struct.unpack_from('<I',data,o+36)[0]
    secs.append((name,rva,vs,rp,rs,chars))

def raw_to_va(raw):
    for name,rva,vs,rp,rs,ch in secs:
        if rp <= raw < rp+rs:
            return IMAGE_BASE+rva+(raw-rp),name
    return None,None

print('============================================================')
print(' AOTR WOTR NETWORK GAMEINFO MANAGER XREF - DISK ONLY')
print('============================================================')
print(f'Target function : 0x{target:08X}')
print('Role            : standalone 0x1080 Network-GameInfo creation path')
print('')

# Direct E8/E9 rel32 refs from executable sections.
refs=[]
for name,rva,vs,rp,rs,ch in secs:
    if not (ch & 0x20000000):
        continue
    end=min(len(data),rp+rs)
    for raw in range(rp,end-4):
        op=data[raw]
        if op not in (0xE8,0xE9): continue
        rel=struct.unpack_from('<i',data,raw+1)[0]
        va=IMAGE_BASE+rva+(raw-rp)
        dest=(va+5+rel)&0xFFFFFFFF
        if dest==target:
            refs.append((raw,va,op,name))
print(f'Direct E8/E9 refs: {len(refs)}')
for n,(raw,va,op,name) in enumerate(refs,1):
    kind='CALL' if op==0xE8 else 'JMP'
    a=max(0,raw-64); b=min(len(data),raw+96)
    ctx=' '.join(f'{x:02X}' for x in data[a:b])
    print(f'\nDIRECT #{n}: {kind} VA=0x{va:08X} section={name}')
    print('  context: '+ctx)

# Literal dword refs; especially useful for vtables in .rdata.
needle=struct.pack('<I',target)
lits=[]
pos=0
while True:
    pos=data.find(needle,pos)
    if pos<0: break
    va,name=raw_to_va(pos)
    if va is not None:
        lits.append((pos,va,name))
    pos+=1
print(f'\nLiteral dword refs: {len(lits)}')
for n,(raw,va,name) in enumerate(lits,1):
    a=max(0,raw-48); b=min(len(data),raw+52)
    ctx=' '.join(f'{x:02X}' for x in data[a:b])
    print(f'\nLITERAL #{n}: VA=0x{va:08X} section={name}')
    print('  context: '+ctx)

print('\nInterpretation:')
print('  - A .rdata literal is a strong vtable/function-table candidate.')
print('  - A direct CALL shows a concrete manager/controller caller.')
print('  - Next trace ECX into 0x00787C09; inside it ESI=ECX and [ESI+0x24] owns the new GameInfo pointer.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat ('0x{0:X}' -f $TargetVA)
    if ($LASTEXITCODE -ne 0) { throw 'Manager xref probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
