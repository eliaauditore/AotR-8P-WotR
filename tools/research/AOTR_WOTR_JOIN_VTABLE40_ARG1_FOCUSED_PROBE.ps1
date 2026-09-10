# AOTR WOTR JOIN VTABLE +0x40 ARG1 FOCUSED PROBE
# DISK ONLY / READ ONLY
# Purpose: isolate the proven C54CE0 session call at 0x00849374 and resolve arg1 from 0x00846D4F.

$ErrorActionPreference = 'Stop'
$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'

Write-Host '============================================================'
Write-Host ' AOTR WOTR JOIN VTABLE +0x40 ARG1 FOCUSED - DISK ONLY'
Write-Host '============================================================'

if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $GameDat).Hash.ToUpperInvariant()
Write-Host "Image hash : $hash"
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash" }

$py = @'
import sys, struct
from pathlib import Path
try:
    from capstone import Cs, CS_ARCH_X86, CS_MODE_32
except Exception as e:
    print('ERROR: Python capstone module required:', e)
    sys.exit(2)

path = Path(sys.argv[1])
data = path.read_bytes()
IMAGE_BASE = 0x00400000

# PE sections
peoff = struct.unpack_from('<I', data, 0x3c)[0]
if data[peoff:peoff+4] != b'PE\0\0':
    raise SystemExit('Not a PE image')
num_sections = struct.unpack_from('<H', data, peoff+6)[0]
opt_size = struct.unpack_from('<H', data, peoff+20)[0]
sec_off = peoff + 24 + opt_size
sections=[]
for i in range(num_sections):
    o=sec_off+i*40
    name=data[o:o+8].split(b'\0',1)[0].decode('ascii','replace')
    vs, va, rawsz, rawptr = struct.unpack_from('<IIII', data, o+8)
    chars=struct.unpack_from('<I', data, o+36)[0]
    sections.append((name,va,vs,rawptr,rawsz,chars))

def va_to_raw(va):
    rva=va-IMAGE_BASE
    for name,sva,vs,rp,rs,ch in sections:
        size=max(vs,rs)
        if sva <= rva < sva+size:
            off=rp+(rva-sva)
            if off < len(data): return off,name
    return None,None

md=Cs(CS_ARCH_X86, CS_MODE_32)
md.detail=False

def disasm_range(start,end,marks=None):
    marks=set(marks or [])
    off,name=va_to_raw(start)
    off2,_=va_to_raw(end-1)
    if off is None or off2 is None:
        print(f'<unmapped 0x{start:08X}..0x{end:08X}>')
        return []
    blob=data[off:off+(end-start)]
    ins=list(md.disasm(blob,start))
    for x in ins:
        p='>>' if x.address in marks else '  '
        b=' '.join(f'{z:02X}' for z in x.bytes)
        print(f'{p} 0x{x.address:08X}: {b:<38} {x.mnemonic:<8} {x.op_str}')
    return ins

def e8_refs(target):
    out=[]
    for name,sva,vs,rp,rs,ch in sections:
        # IMAGE_SCN_MEM_EXECUTE
        if not (ch & 0x20000000):
            continue
        blob=data[rp:rp+rs]
        base=IMAGE_BASE+sva
        for i in range(0,max(0,len(blob)-5)):
            if blob[i] != 0xE8: continue
            rel=struct.unpack_from('<i',blob,i+1)[0]
            src=base+i
            dst=(src+5+rel)&0xffffffff
            if dst==target:
                out.append((src,name))
    return out

print('\n================ PROVEN SESSION CALL 0x00849374 ================')
disasm_range(0x00849320,0x008493A0,{0x00849360,0x00849369,0x00849373,0x00849374})
print('\nContract from machine code:')
print('  ECX = [0x00DE4394] native C54CE0 session singleton')
print('  push &local_zero_endpoint   -> arg2')
print('  push EDI                    -> arg1')
print('  call [session_vtable+0x40]  -> 0x0084CB34')
print('  EDI is return value of call 0x00846D4F immediately before this sequence.')

print('\n================ CONTAINING CALLER CONTEXT ================')
disasm_range(0x00849240,0x00849420,{0x00849340,0x00849345,0x00849360,0x00849374})

print('\n================ ARG1 PRODUCER 0x00846D4F ================')
disasm_range(0x00846D4F,0x00847020,{0x00846D4F})

print('\n================ DIRECT E8 REFS TO ARG1 PRODUCER 0x00846D4F ================')
refs=e8_refs(0x00846D4F)
print('count=',len(refs))
for src,name in refs:
    print(f'0x{src:08X} section={name}')

print('\n================ FOCUSED REF CONTEXTS TO 0x00846D4F ================')
for src,name in refs[:20]:
    print(f'\n--- ref 0x{src:08X} section={name} ---')
    disasm_range(max(IMAGE_BASE,src-0x40),src+0x30,{src})

print('\n================ KNOWN-ANCHOR BYTE/XREF CHECKS NEAR ARG1 HELPER ================')
# These are evidence aids only; labels are not inferred unless exact calls/literals appear.
known_calls={
    0x00800B55:'GET_ROW-like helper',
    0x0084AEA1:'Network GameInfo ctor',
    0x0084B01B:'8-slot PlayerInfo setter',
    0x0084A419:'GameInfo get-row helper',
    0x0084A43A:'network GameInfo local-slot resolver',
}
helper_ins=disasm_range(0x00846D4F,0x00847020,[])
for x in helper_ins:
    if x.mnemonic=='call' and x.op_str.startswith('0x'):
        try: dst=int(x.op_str,16)
        except: continue
        if dst in known_calls:
            print(f'ANCHOR call 0x{x.address:08X} -> 0x{dst:08X} {known_calls[dst]}')

# Literal references in helper raw bytes to useful globals/vtables.
off,_=va_to_raw(0x00846D4F)
endoff,_=va_to_raw(0x0084701F)
blob=data[off:endoff+1]
for val,label in [
    (0x00C54B78,'Network GameInfo vtable C54B78'),
    (0x00C54CE0,'Session vtable C54CE0'),
    (0x00DE892C,'Network GameInfo global'),
    (0x00DE4394,'Session singleton global'),
    (0x00DE7D6C,'TheGameInfo global'),
]:
    needle=struct.pack('<I',val)
    pos=0
    hits=[]
    while True:
        j=blob.find(needle,pos)
        if j<0: break
        hits.append(0x00846D4F+j)
        pos=j+1
    if hits:
        print(f'LITERAL {label} 0x{val:08X}: '+', '.join(f'0x{x:08X}' for x in hits))

print('\n================ INTERPRETATION TARGETS ================')
print('1) Confirm 0x00849374 is the genuine DE4394/C54CE0 vtable+0x40 call.')
print('2) Resolve exactly what 0x00846D4F returns in EAX/EDI.')
print('3) Determine whether that return object is the GameInfo-like arg1 consumed by 0x84CB34 -> GET_ROW(0).')
print('4) Explain why arg2 is a zeroed 6-byte endpoint structure at this callsite (sentinel/broadcast/discovery vs other).')
print('5) No file or process memory is modified.')
print('\nREAD-ONLY COMPLETE. No file or process memory was modified.')
'@

$tmp = Join-Path $env:TEMP ('aotr_join_arg1_' + [guid]::NewGuid().ToString('N') + '.py')
try {
    Set-Content -LiteralPath $tmp -Value $py -Encoding UTF8
    & python $tmp $GameDat
    if ($LASTEXITCODE -ne 0) { throw "Python probe failed with exit code $LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
