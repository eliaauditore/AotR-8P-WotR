param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat',
    [uint32]$AnchorVA = 0x00787C44,
    [uint32]$StopVA   = 0x00787CFD,
    [int]$BackScan    = 0x1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Alignment-safe trace for the 0x00787CA3 Network-GameInfo constructor caller.
# The previous generic range trace can start in the middle of an x86 instruction.
# This probe finds the nearest preceding CC padding run, starts after it, and
# disassembles forward across the known aligned anchor at 0x00787C44.

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

$tempPy = Join-Path $env:TEMP ('a8p_resync_' + [guid]::NewGuid().ToString('N') + '.py')
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
# Find nearest preceding padding run of at least two CC bytes.
last=None
i=scan_raw
while i < anchor_raw-1:
    if data[i] == 0xCC:
        j=i
        while j < anchor_raw and data[j] == 0xCC:
            j+=1
        if j-i >= 2:
            last=(i,j)
        i=j
    else:
        i+=1

if not last:
    raise SystemExit(f'No >=2-byte CC padding run found in 0x{back:X} bytes before anchor')

pad0,pad1=last
start_raw=pad1
start_va=raw_to_va(start_raw)
stop_raw=va_to_raw(stop-1)+1
code=data[start_raw:stop_raw]

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=False
ins=list(md.disasm(code,start_va))
if not ins:
    raise SystemExit('No instructions decoded from resynchronized start')

# Require the known aligned anchor to be an instruction boundary or to fall after
# a complete instruction stream that reaches it exactly.
boundaries={x.address for x in ins}
if anchor not in boundaries:
    # 0x787C44 is expected to be LEA EAX,[EBP+0xD4]. If padding choice was wrong,
    # fail rather than silently present a misaligned stream.
    raise SystemExit(f'Resync validation failed: anchor 0x{anchor:08X} is not an instruction boundary. Found start 0x{start_va:08X}.')

print('============================================================')
print(' AOTR WOTR CALLER1 FUNCTION TRACE - ALIGNMENT SAFE')
print('============================================================')
print(f'Function start : 0x{start_va:08X}')
print(f'CC padding     : 0x{raw_to_va(pad0):08X} - 0x{raw_to_va(pad1-1):08X}')
print(f'Anchor         : 0x{anchor:08X}')
print(f'Stop           : 0x{stop:08X}')
print('')

lines=[]
for x in ins:
    b=' '.join(f'{v:02X}' for v in x.bytes)
    line=f'0x{x.address:08X}: {b:<32} {x.mnemonic:<8} {x.op_str}'
    lines.append(line)
    print(line)

print('\n================ KEY FLOW =================')
for line in lines:
    l=line.lower()
    if ('esi' in l or 'edi' in l or '0x42f6e0' in l or '0x9035ae' in l or
        '0x7871fc' in l or '[eax], edi' in l or '[eax],edi' in l):
        print(line)
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat ('0x{0:X}' -f $AnchorVA) ('0x{0:X}' -f $StopVA) $BackScan
    if ($LASTEXITCODE -ne 0) { throw 'Alignment-safe disassembly failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
