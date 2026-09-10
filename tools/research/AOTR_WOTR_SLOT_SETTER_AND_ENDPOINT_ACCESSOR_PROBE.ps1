param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Traces the native 8-slot GameInfo setter/copy chain and the proven
# C54CE0 session vtable +0x100 endpoint accessor used when constructing
# Network GameInfo / Type6 PlayerInfo state.

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

$tempPy = Join-Path $env:TEMP ('a8p_slotsetter_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path=sys.argv[1]
IMAGE_BASE=0x00400000
TARGETS={
    'GAMEINFO_SLOT_SETTER_0x84B01B': (0x0084B01B, 0x90),
    'PLAYERINFO_COPY_ASSIGN_0x84A825': (0x0084A825, 0x180),
    'PLAYERINFO_CTOR_0x84AE1D': (0x0084AE1D, 0x140),
    'GAMEINFO_ROW_INIT_0x800BDE': (0x00800BDE, 0x120),
    'SESSION_ENDPOINT_ACCESSOR_0x8A0318': (0x008A0318, 0x100),
    'PLAYERINFO_ASSIGN_TYPE6_0x8014F1': (0x008014F1, 0x190),
}
REF_TARGETS={
    'GAMEINFO_SLOT_SETTER_0x84B01B':0x0084B01B,
    'PLAYERINFO_COPY_ASSIGN_0x84A825':0x0084A825,
    'SESSION_ENDPOINT_ACCESSOR_0x8A0318':0x008A0318,
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
    secs.append(dict(name=name,rva=rva,vs=vs,rp=rp,rs=rs))

def va_to_off(va):
    rva=va-IMAGE_BASE
    for s in secs:
        span=max(s['vs'],s['rs'])
        if s['rva'] <= rva < s['rva']+span:
            return s['rp']+(rva-s['rva']),s
    return None,None

text=next(s for s in secs if s['name']=='.text')
text_blob=data[text['rp']:text['rp']+text['rs']]
text_va=IMAGE_BASE+text['rva']
md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=False

def dump(label,va,size):
    off,sec=va_to_off(va)
    print(f'================ {label} ================')
    if off is None:
        print('VA not mapped\n'); return
    blob=data[off:off+size]
    for x in md.disasm(blob,va):
        b=' '.join(f'{v:02X}' for v in x.bytes)
        print(f'0x{x.address:08X}: {b:<34} {x.mnemonic:<8} {x.op_str}')
        if x.mnemonic=='ret' and x.address>va+4:
            break
    print('')

def direct_refs(target):
    out=[]
    ins=list(md.disasm(text_blob,text_va))
    for x in ins:
        if x.mnemonic not in ('call','jmp'): continue
        try:
            dst=int(x.op_str,16)
        except Exception:
            continue
        if dst==target:
            out.append(x.address)
    return out

def context(va,before=48,after=96):
    off=va-text_va
    start=max(0,off-before); end=min(len(text_blob),off+after)
    for x in md.disasm(text_blob[start:end],text_va+start):
        mark='>>' if x.address==va else '  '
        b=' '.join(f'{v:02X}' for v in x.bytes)
        print(f'{mark} 0x{x.address:08X}: {b:<30} {x.mnemonic:<8} {x.op_str}')

print('============================================================')
print(' AOTR WOTR SLOT SETTER + ENDPOINT ACCESSOR PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print('')

for label,(va,size) in TARGETS.items():
    dump(label,va,size)

print('================ DIRECT CALL/JMP REFS ================')
for label,target in REF_TARGETS.items():
    refs=direct_refs(target)
    print(f'{label}: {len(refs)} refs')
    for r in refs:
        print(f'  0x{r:08X}')
    print('')

# The slot setter call sites are especially useful because the preceding pushes
# reveal the slot index and whether a full 0x1DC PlayerInfo is passed by value.
slot_refs=direct_refs(0x0084B01B)
for i,r in enumerate(slot_refs,1):
    print(f'================ SLOT SETTER CALLER #{i} @ 0x{r:08X} ================')
    context(r,96,112)
    print('')

print('Interpretation targets:')
print('  1) Confirm 0x84B01B is a generic slot 0..7 setter using +0xDC + slot*0x1DC.')
print('  2) Confirm 0x84A825 copies the complete PlayerInfo semantics needed for Type6 rows.')
print('  3) Confirm 0x8A0318 returns the session endpoint pair used by GameInfo/PlayerInfo constructors.')
print('  4) Use caller contexts to distinguish host slot-0 creation from remote/join slot updates.')
print('  5) No bytes are modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'slot setter / endpoint accessor probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
