param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Traces the native join reply/send pipeline after the proven 0x03 -> 0x04 handshake:
#   PATH_C 0x0098A7F1 builds message ID 0x04 at a local base,
#   fills endpoint + assigned-slot fields, then calls 0x0084C257.
# This probe resolves 0x0084C257 semantics and all direct E8/E9 callers.

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

$tempPy = Join-Path $env:TEMP ('a8p_join_send_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path=sys.argv[1]
IMAGE_BASE=0x00400000
SEND_HELPER=0x0084C257
PATH_C=0x0098A7F1
BUILDER_START=0x0098ABF0
BUILDER_END=0x0098AF2C
KNOWN_CALL=0x0098AF02

with open(path,'rb') as f:
    data=f.read()
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
    chars=struct.unpack_from('<I',data,o+36)[0]
    secs.append(dict(name=name,rva=rva,vs=vs,rs=rs,rp=rp,chars=chars))

def sec_for_va(va):
    rva=va-IMAGE_BASE
    for s in secs:
        span=max(s['vs'],s['rs'])
        if s['rva'] <= rva < s['rva']+span:
            return s
    return None

def va_to_raw(va):
    s=sec_for_va(va)
    if not s: raise ValueError(f'VA 0x{va:08X} not in PE section')
    return s['rp'] + ((va-IMAGE_BASE)-s['rva']),s

def read_bytes(va,n):
    raw,s=va_to_raw(va)
    return data[raw:raw+n],s,raw

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=True

def fmt(x,mark='  '):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

def disasm_exact(start,end):
    b,s,raw=read_bytes(start,end-start)
    return s,raw,list(md.disasm(b,start))

def direct_refs(target):
    out=[]
    for s in secs:
        if not (s['chars'] & 0x20000000):
            continue
        blob=data[s['rp']:s['rp']+s['rs']]
        base=IMAGE_BASE+s['rva']
        for i in range(0,max(0,len(blob)-4)):
            op=blob[i]
            if op not in (0xE8,0xE9):
                continue
            disp=struct.unpack_from('<i',blob,i+1)[0]
            va=base+i
            dst=(va+5+disp)&0xffffffff
            if dst==target:
                out.append((va,'CALL' if op==0xE8 else 'JMP',s))
    return out

def sync_context(callsite,before=0x90,after=0x40):
    sec=sec_for_va(callsite)
    sec_start=IMAGE_BASE+sec['rva']
    start_min=max(sec_start,callsite-before)
    best=None
    for start in range(start_min,callsite+1):
        try:
            b,_,_=read_bytes(start,(callsite+after)-start)
        except Exception:
            continue
        ins=list(md.disasm(b,start))
        hit=None
        for j,x in enumerate(ins):
            if x.address==callsite:
                hit=j; break
            if x.address>callsite:
                break
        if hit is None:
            continue
        x=ins[hit]
        if x.bytes and x.bytes[0] in (0xE8,0xE9) and len(x.bytes)>=5:
            disp=struct.unpack_from('<i',bytes(x.bytes),1)[0]
            dst=(x.address+5+disp)&0xffffffff
            if dst==SEND_HELPER:
                score=(hit, -start)
                if best is None or score>best[0]:
                    best=(score,start,ins)
    return None if best is None else (best[1],best[2])

print('============================================================')
print(' AOTR WOTR JOIN SEND PIPELINE PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print(f'Send/helper      : 0x{SEND_HELPER:08X}')
print(f'Proven PATH_C    : 0x{PATH_C:08X}')
print('')

print('================ PROVEN 0x04 BUILDER LAYOUT ================')
s,raw,ins=disasm_exact(BUILDER_START,BUILDER_END)
print(f'section={s["name"]} raw=0x{raw:X}')
interesting={
  0x0098ABF6:'MSG+0x00 = 0x04 LOCAL_SLOT_BIND',
  0x0098AC3D:'MSG+0x4C = assigned slot EBX',
  0x0098AC4B:'MSG+0x40 = local/session IPv4',
  0x0098AC5F:'MSG+0x44 = local/session port',
  0x0098AC68:'MSG+0x46 = remote/sender IPv4',
  0x0098AC78:'MSG+0x4A = remote/sender port',
  0x0098AEF5:'push original sender endpoint copy',
  0x0098AEF9:'push constructed message base',
  0x0098AF02:'call native send/helper',
}
for x in ins:
    label=interesting.get(x.address)
    mark='>>' if label else '  '
    line=fmt(x,mark)
    if label: line += ' ; ' + label
    print(line)
print('')

print('================ KNOWN 0x04 SEND CALL VALIDATION ================')
b,s,raw=read_bytes(KNOWN_CALL,5)
op=b[0] if b else None
dst=None
if len(b)>=5 and op in (0xE8,0xE9):
    disp=struct.unpack_from('<i',b,1)[0]
    dst=(KNOWN_CALL+5+disp)&0xffffffff
print(f'0x{KNOWN_CALL:08X} [{s["name"]}] bytes={" ".join(f"{v:02X}" for v in b)} decoded={"0x%08X"%dst if dst is not None else "<not E8/E9>"} expected=0x{SEND_HELPER:08X} match={dst==SEND_HELPER}')
print('')

print('================ SEND HELPER 0x84C257 TRACE ================')
s,raw,ins=disasm_exact(SEND_HELPER,SEND_HELPER+0x260)
print(f'section={s["name"]} raw=0x{raw:X}')
for x in ins:
    print(fmt(x,'>>' if x.address==SEND_HELPER else '  '))
    if x.mnemonic.startswith('ret'):
        # Keep a little tail only; first real return normally closes the helper.
        break
print('')

refs=direct_refs(SEND_HELPER)
print('================ ALL DIRECT REFS TO 0x84C257 ================')
print(f'count={len(refs)}')
for va,kind,s in refs:
    print(f'  0x{va:08X} {kind} section={s["name"]}')
print('')

print('================ SYNCHRONIZED CALLER CONTEXTS ================')
for n,(va,kind,s) in enumerate(refs,1):
    print(f'\n---------------- CALLER #{n} 0x{va:08X} {kind} ----------------')
    synced=sync_context(va)
    if not synced:
        print('<could not synchronize local disassembly>')
        continue
    start,ins=synced
    lo=max(0,next((i for i,x in enumerate(ins) if x.address==va),0)-24)
    hi=min(len(ins),next((i for i,x in enumerate(ins) if x.address==va),0)+14)
    for x in ins[lo:hi]:
        print(fmt(x,'>>' if x.address==va else '  '))

print('\n================ INTERPRETATION TARGETS ================')
print('  1) Resolve 0x84C257 argument order and whether it is send, enqueue, broadcast, or packet wrapper.')
print('  2) Confirm PATH_C passes constructed ID 0x04 plus the original sender endpoint to 0x84C257.')
print('  3) Identify other 0x84C257 callers that construct message ID 0x03 or 0x08 immediately before the call.')
print('  4) Prefer caller-anchored evidence over raw immediate-ID scans; the prior 1838 raw candidates are noisy.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'join send pipeline probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
