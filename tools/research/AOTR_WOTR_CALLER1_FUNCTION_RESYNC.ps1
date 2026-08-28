param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat',
    [uint32]$AnchorVA = 0x00787C54,
    [uint32]$StopVA   = 0x00787CFD,
    [int]$BackScan    = 0x2000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Robust function-start recovery for the 0x00787CA3 Network-GameInfo ctor caller.
# Does NOT assume CC padding. It scans backward for plausible MSVC x86 prologues,
# disassembles each candidate forward, and accepts only candidates whose instruction
# boundaries match several already-proven addresses in this function.

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

$tempPy = Join-Path $env:TEMP ('a8p_resync2_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path=sys.argv[1]
anchor=int(sys.argv[2],16)
stop=int(sys.argv[3],16)
back=int(sys.argv[4],0)
IMAGE_BASE=0x00400000

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

def va_to_raw(va):
    rva=va-IMAGE_BASE
    for name,srva,vs,rp,rs in secs:
        if srva <= rva < srva+max(vs,rs):
            return rp+(rva-srva)
    raise ValueError(f'VA 0x{va:08X} not mapped')

def raw_to_va(raw):
    for name,srva,vs,rp,rs in secs:
        if rp <= raw < rp+rs:
            return IMAGE_BASE+srva+(raw-rp)
    raise ValueError(f'raw 0x{raw:X} not mapped')

anchor_raw=va_to_raw(anchor)
scan_raw=max(0,anchor_raw-back)
stop_raw=va_to_raw(stop-1)+1

# Already-proven instruction boundaries from the previous correctly aligned trace.
required = {
    0x00787C54: 'lea',
    0x00787C90: 'call',
    0x00787CA3: 'call',
    0x00787CD9: 'mov',
    0x00787CFA: 'ret',
}

# Candidate starts. Strong MSVC patterns first, then standard frame/SEH starts.
candidates=set()
for r in range(scan_raw, anchor_raw):
    # Common MSVC stack-probe prologue used by nearby functions:
    #   B8 imm32 ; E8 rel32 ; 81 EC imm32
    if r+16 <= len(data) and data[r] == 0xB8 and data[r+5] == 0xE8 and data[r+10:r+12] == b'\x81\xEC':
        candidates.add(r)
    # Standard frame prologue.
    if r+3 <= len(data) and data[r:r+3] == b'\x55\x8B\xEC':
        candidates.add(r)
    # MSVC SEH-style start.
    if r+6 <= len(data) and data[r:r+6] == b'\x64\xA1\x00\x00\x00\x00':
        candidates.add(r)

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=False

valid=[]
for r in sorted(candidates):
    sva=raw_to_va(r)
    code=data[r:stop_raw]
    ins=list(md.disasm(code,sva))
    if not ins:
        continue
    byaddr={x.address:x for x in ins}
    ok=True
    for va,mnem in required.items():
        x=byaddr.get(va)
        if x is None or x.mnemonic != mnem:
            ok=False
            break
    if not ok:
        continue

    # Additional semantic checks at known sites.
    if byaddr[0x00787CA3].op_str.lower() not in ('0x9035ae','0x009035ae'):
        continue
    if byaddr[0x00787C90].op_str.lower() not in ('0x42f6e0','0x0042f6e0'):
        continue

    score=0
    first=ins[:8]
    if first and first[0].mnemonic == 'mov' and first[0].op_str.lower().startswith('eax, 0x'):
        score += 4
    if any(x.mnemonic == 'call' for x in first[:3]):
        score += 2
    if any(x.mnemonic == 'sub' and x.op_str.lower().startswith('esp,') for x in first[:6]):
        score += 3
    if first and first[0].mnemonic == 'push' and first[0].op_str.lower() == 'ebp':
        score += 3
    if any(x.mnemonic == 'mov' and x.op_str.lower() in ('esi, ecx','edi, ecx') for x in ins[:20]):
        score += 2

    valid.append((score,sva,ins))

if not valid:
    print(f'No validated function-start candidate found in 0x{back:X} bytes before anchor 0x{anchor:08X}.')
    print(f'Prologue-like raw candidates tested: {len(candidates)}')
    raise SystemExit(2)

# Prefer highest score; for ties choose the closest plausible prologue before anchor.
valid.sort(key=lambda t:(t[0],t[1]), reverse=True)
score,start_va,ins=valid[0]

print('============================================================')
print(' AOTR WOTR CALLER1 FUNCTION TRACE - VALIDATED RESYNC V2')
print('============================================================')
print(f'Function start : 0x{start_va:08X}')
print(f'Anchor         : 0x{anchor:08X}')
print(f'Stop           : 0x{stop:08X}')
print(f'Validated starts: {len(valid)} / {len(candidates)} candidates')
print(f'Selected score : {score}')
print('')

# Only print selected function from start through known RET.
lines=[]
for x in ins:
    if x.address > 0x00787CFA:
        break
    b=' '.join(f'{v:02X}' for v in x.bytes)
    line=f'0x{x.address:08X}: {b:<32} {x.mnemonic:<8} {x.op_str}'
    lines.append(line)
    print(line)

print('\n================ KEY FLOW =================')
for line in lines:
    l=line.lower()
    if ('esi' in l or 'edi' in l or '0x42f6e0' in l or '0x9035ae' in l or
        '0x7871fc' in l or '[eax], edi' in l or '[eax],edi' in l or
        'sub      esp' in l or 'sub     esp' in l):
        print(line)

print('\n================ VALIDATED STARTS =================')
for sc,sva,_ in valid[:10]:
    print(f'0x{sva:08X} score={sc}')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat ('0x{0:X}' -f $AnchorVA) ('0x{0:X}' -f $StopVA) $BackScan
    if ($LASTEXITCODE -ne 0) { throw 'Validated resync disassembly failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
