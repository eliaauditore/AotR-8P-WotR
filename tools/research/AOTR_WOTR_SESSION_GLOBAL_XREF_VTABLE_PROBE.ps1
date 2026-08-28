param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Traces all static references to the proven native pre-start session singleton
# global 0x00DE4394 and dumps the C54CE0 vtable. Intended to identify lifecycle
# methods that populate/use session+0x10/+0x44 (Network GameInfo) and endpoint
# fields without writing process or file memory.

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

$tempPy = Join-Path $env:TEMP ('a8p_session_xref_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path=sys.argv[1]
IMAGE_BASE=0x00400000
SESSION_GLOBAL=0x00DE4394
SESSION_VTABLE=0x00C54CE0

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
    ch=struct.unpack_from('<I',data,o+36)[0]
    secs.append(dict(name=name,rva=rva,vs=vs,rp=rp,rs=rs,ch=ch))

def va_to_off(va):
    rva=va-IMAGE_BASE
    for s in secs:
        span=max(s['vs'],s['rs'])
        if s['rva'] <= rva < s['rva']+span:
            return s['rp'] + (rva-s['rva']), s
    return None,None

text=next(s for s in secs if s['name']=='.text')
text_blob=data[text['rp']:text['rp']+text['rs']]
text_va=IMAGE_BASE+text['rva']
text_end=text_va+text['rs']
pat=struct.pack('<I',SESSION_GLOBAL)
raw_hits=[]
pos=0
while True:
    i=text_blob.find(pat,pos)
    if i<0: break
    raw_hits.append(i)
    pos=i+1

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=False

print('============================================================')
print(' AOTR WOTR SESSION GLOBAL XREF + VTABLE PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print(f'Session global   : 0x{SESSION_GLOBAL:08X}')
print(f'Session vtable   : 0x{SESSION_VTABLE:08X}')
print(f'Raw .text refs   : {len(raw_hits)}')
print('')

for n,h in enumerate(raw_hits,1):
    hit_va=text_va+h
    start=max(0,h-72)
    end=min(len(text_blob),h+100)
    ins=list(md.disasm(text_blob[start:end],text_va+start))
    owner=None
    for x in ins:
        if x.address <= hit_va < x.address+x.size:
            owner=x; break
    print(f'================ GLOBAL XREF #{n}: literal VA=0x{hit_va:08X} ================')
    if owner:
        print(f'Containing instruction: 0x{owner.address:08X}  {owner.mnemonic} {owner.op_str}')
    else:
        print('Containing instruction: <not resolved in local disassembly>')
    for x in ins:
        mark='>>' if owner and x.address==owner.address else '  '
        b=' '.join(f'{v:02X}' for v in x.bytes)
        print(f'{mark} 0x{x.address:08X}: {b:<30} {x.mnemonic:<8} {x.op_str}')
    print('')

print('================ C54CE0 VTABLE ================')
off,sec=va_to_off(SESSION_VTABLE)
if off is None:
    print('vtable VA not mapped')
else:
    print(f'vtable section: {sec["name"]}')
    for i in range(0,0x120,4):
        if off+i+4>len(data): break
        fn=struct.unpack_from('<I',data,off+i)[0]
        cls='TEXT' if text_va <= fn < text_end else ''
        print(f'+0x{i:03X} -> 0x{fn:08X} {cls}')

print('')
print('Interpretation:')
print('  - Constructor paths already prove 0x00DE4394 owns the C54CE0 singleton.')
print('  - Focus on functions that load [0x00DE4394], then access +0x10/+0x44/+0x48/+0x4C or call a C54CE0 vtable slot.')
print('  - Those are candidates for native pre-start GameInfo/session lifecycle and future OWN_MP bridge entry points.')
print('  - No bytes are modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'session global xref/vtable probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
