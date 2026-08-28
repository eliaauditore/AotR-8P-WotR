param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Robust V2: scans ALL executable PE sections, validates direct E8/E9 rel32
# targets byte-for-byte, and disassembles the three known 0x98Axxx caller
# windows from their actual containing PE sections.

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

$tempPy = Join-Path $env:TEMP ('a8p_slot_setter_callers_v2_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path=sys.argv[1]
IMAGE_BASE=0x00400000
TARGETS={
    0x0084B01B:'GAMEINFO_SLOT_SETTER',
    0x0084A825:'PLAYERINFO_COPY_ASSIGN',
    0x008A0318:'SESSION_ENDPOINT_ACCESSOR',
    0x008014F1:'PLAYERINFO_ASSIGN_TYPE6',
    0x0084DF19:'PLAYERINFO_STACK_COPY',
    0x00649242:'PLAYERINFO_HELPER_A',
    0x00649279:'PLAYERINFO_HELPER_B',
}
KNOWN_CALLS={
    0x0098A482:0x0084B01B,
    0x0098A6DD:0x0084B01B,
    0x0098AD9D:0x0084B01B,
    0x0098A477:0x0084DF19,
    0x0098A6D2:0x0084DF19,
    0x0098AD94:0x0084DF19,
    0x0098A40E:0x008014F1,
    0x0098A6BB:0x008014F1,
    0x0098A736:0x008014F1,
    0x0098ACB2:0x008014F1,
}
FOCUS=[
    ('PATH_A_98A4XX',0x0098A360,0x0098A520),
    ('PATH_B_98A6XX',0x0098A5F0,0x0098A780),
    ('PATH_C_98ADXX',0x0098AC20,0x0098AE20),
]

with open(path,'rb') as f: data=f.read()
if data[:2] != b'MZ': raise SystemExit('Not MZ')
pe=struct.unpack_from('<I',data,0x3c)[0]
if data[pe:pe+4] != b'PE\0\0': raise SystemExit('Bad PE')
num=struct.unpack_from('<H',data,pe+6)[0]
opt_size=struct.unpack_from('<H',data,pe+20)[0]
sec0=pe+24+opt_size
secs=[]
for i in range(num):
    o=sec0+i*40
    name=data[o:o+8].split(b'\0',1)[0].decode('ascii','replace')
    vs,rva,rs,rp=struct.unpack_from('<IIII',data,o+8)
    ch=struct.unpack_from('<I',data,o+36)[0]
    secs.append(dict(name=name,vs=vs,rva=rva,rs=rs,rp=rp,ch=ch))

def va_to_section(va):
    rva=va-IMAGE_BASE
    for s in secs:
        span=max(s['vs'],s['rs'])
        if s['rva'] <= rva < s['rva']+span:
            return s
    return None

def va_to_off(va):
    s=va_to_section(va)
    if not s: return None,None
    delta=(va-IMAGE_BASE)-s['rva']
    if delta >= s['rs']: return None,s
    return s['rp']+delta,s

exec_secs=[s for s in secs if s['ch'] & 0x20000000]
md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=False

print('============================================================')
print(' AOTR WOTR SLOT SETTER CALLER PATHS PROBE V2 - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print('')
print('================ PE EXECUTABLE SECTIONS ================')
for s in exec_secs:
    print(f"{s['name']:<8} VA=0x{IMAGE_BASE+s['rva']:08X} VS=0x{s['vs']:X} RAW=0x{s['rs']:X} PTR=0x{s['rp']:X}")

refs={t:[] for t in TARGETS}
for s in exec_secs:
    blob=data[s['rp']:s['rp']+s['rs']]
    base=IMAGE_BASE+s['rva']
    n=len(blob)
    for i in range(0,max(0,n-4)):
        op=blob[i]
        if op not in (0xE8,0xE9):
            continue
        rel=struct.unpack_from('<i',blob,i+1)[0]
        src=base+i
        dst=(src+5+rel) & 0xffffffff
        if dst in refs:
            refs[dst].append((src,op,s['name']))

print('\n================ RAW E8/E9 TARGET REFS ================')
for t,name in TARGETS.items():
    hits=refs[t]
    print(f'{name} 0x{t:08X}: {len(hits)} refs')
    for src,op,secname in hits:
        print(f'  0x{src:08X} {"CALL" if op==0xE8 else "JMP ":<4} -> 0x{t:08X}  section={secname}')
    print('')

print('================ KNOWN CALLSITE BYTE VALIDATION ================')
for src,expected in KNOWN_CALLS.items():
    off,s=va_to_off(src)
    if off is None:
        print(f'0x{src:08X}: NOT MAPPED/NOT RAW (section={s["name"] if s else "none"})')
        continue
    raw=data[off:off+5]
    if len(raw)<5:
        print(f'0x{src:08X}: truncated')
        continue
    op=raw[0]
    rel=struct.unpack_from('<i',raw,1)[0] if op in (0xE8,0xE9) else None
    dst=((src+5+rel)&0xffffffff) if rel is not None else None
    b=' '.join(f'{x:02X}' for x in raw)
    print(f'0x{src:08X} [{s["name"]}] bytes={b} op=0x{op:02X} decoded={"0x%08X"%dst if dst is not None else "<not rel32>"} expected=0x{expected:08X} match={dst==expected}')

# Cache disassembly per executable section, then print exact VA windows.
sec_ins={}
for s in exec_secs:
    blob=data[s['rp']:s['rp']+s['rs']]
    base=IMAGE_BASE+s['rva']
    sec_ins[s['name']]=list(md.disasm(blob,base))

print('\n================ FOCUSED 0x98Axxx PATHS ================')
for name,start,end in FOCUS:
    s=va_to_section(start)
    print(f'\n---------------- {name} 0x{start:08X}..0x{end:08X} section={s["name"] if s else "none"} ----------------')
    if not s or s['name'] not in sec_ins:
        print('<not in executable section>')
        continue
    shown=0
    for x in sec_ins[s['name']]:
        if x.address < start: continue
        if x.address >= end: break
        mark='>>' if x.address in KNOWN_CALLS else '  '
        b=' '.join(f'{v:02X}' for v in x.bytes)
        extra=''
        if x.address in KNOWN_CALLS:
            extra=f'  ; expected -> 0x{KNOWN_CALLS[x.address]:08X}'
        print(f'{mark} 0x{x.address:08X}: {b:<34} {x.mnemonic:<8} {x.op_str}{extra}')
        shown+=1
    if shown==0:
        print('<no decoded instructions in requested range>')

print('\nInterpretation targets:')
print('  1) Validate the known 0x98Axxx callsites byte-for-byte.')
print('  2) Identify the actual PE section containing those callers.')
print('  3) Read slot argument and Type6/endpoint build order around each 0x84B01B call.')
print('  4) Treat any prior zero-ref result as scanner failure if known-call validation passes.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'slot setter caller paths probe v2 failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
