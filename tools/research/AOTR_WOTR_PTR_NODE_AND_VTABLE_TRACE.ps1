param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Traces the two vtable-like literals found near runtime GameInfo pointer xrefs and
# the lookup/insert helpers used by 0x007871FC.

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

$tempPy = Join-Path $env:TEMP ('a8p_nodevt_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path=sys.argv[1]
IMAGE_BASE=0x00400000
with open(path,'rb') as f: data=f.read()
if data[:2] != b'MZ': raise SystemExit('Not MZ')
pe=struct.unpack_from('<I',data,0x3C)[0]
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

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=False

def dump(title,start,stop):
    print('\n============================================================')
    print(title)
    print('============================================================')
    r0=va_to_raw(start); r1=va_to_raw(stop-1)+1
    ins=list(md.disasm(data[r0:r1],start))
    for x in ins:
        b=' '.join(f'{v:02X}' for v in x.bytes)
        mark=''
        op=x.op_str.lower()
        if '0xc54ce0' in op or '0xc508a0' in op or x.address in (0x0073D1FA,0x005FD414):
            mark='  <<'
        print(f'0x{x.address:08X}: {b:<32} {x.mnemonic:<8} {x.op_str}{mark}')

# Exact contexts around all literal occurrences previously found.
dump('VTABLE-LIKE 0x00C54CE0 XREF #1',0x0084C750,0x0084C7D0)
dump('VTABLE-LIKE 0x00C54CE0 XREF #2',0x0084E610,0x0084E690)
dump('VTABLE-LIKE 0x00C508A0 XREF #1',0x0081C830,0x0081C8A0)
dump('VTABLE-LIKE 0x00C508A0 XREF #2',0x0081D360,0x0081D3C0)
dump('VTABLE-LIKE 0x00C508A0 XREF #3',0x008470F0,0x00847170)

# Helper used by 0x007871FC for lookup and insertion.
dump('LOOKUP HELPER 0x0073D1FA',0x0073D1FA,0x0073D2A0)
dump('INSERT HELPER 0x005FD414',0x005FD414,0x005FD520)

print('\nInterpretation:')
print('  - Treat a literal as a constructor/destructor vtable write only if the instruction actually writes the immediate into [this/...].')
print('  - 0x007871FC returns node+0x14; its lookup path compares the key with [node+0x10].')
print('  - Use 0x0073D1FA / 0x005FD414 to recover node link/header layout before classifying runtime refs as map nodes.')
print('  - Do not infer an object base merely because a vtable-like value appears near a runtime pointer ref.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat
    if ($LASTEXITCODE -ne 0) { throw 'node/vtable trace failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
