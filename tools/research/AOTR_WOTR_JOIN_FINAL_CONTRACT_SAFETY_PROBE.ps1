# AOTR WOTR JOIN FINAL CONTRACT / SAFETY PROBE
# DISK ONLY / READ ONLY
# Purpose: resolve the object returned by 0x00846D4F and the zero-endpoint semantics used by the proven vtable+0x40 join call.

$ErrorActionPreference = 'Stop'
$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'

Write-Host '============================================================'
Write-Host ' AOTR WOTR JOIN FINAL CONTRACT / SAFETY - DISK ONLY'
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
peoff = struct.unpack_from('<I', data, 0x3c)[0]
if data[peoff:peoff+4] != b'PE\0\0': raise SystemExit('Not a PE image')
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
        if sva <= rva < sva+max(vs,rs):
            off=rp+(rva-sva)
            if off < len(data): return off,name
    return None,None

md=Cs(CS_ARCH_X86, CS_MODE_32)
md.detail=False

def disasm_range(start,end,marks=None):
    marks=set(marks or [])
    off,name=va_to_raw(start)
    off2,_=va_to_raw(end-1)
    print(f'section={name} range=0x{start:08X}..0x{end:08X}')
    if off is None or off2 is None:
        print('<unmapped>'); return []
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
        if not (ch & 0x20000000): continue
        blob=data[rp:rp+rs]; base=IMAGE_BASE+sva
        for i in range(0,max(0,len(blob)-5)):
            if blob[i]!=0xE8: continue
            rel=struct.unpack_from('<i',blob,i+1)[0]
            src=base+i; dst=(src+5+rel)&0xffffffff
            if dst==target: out.append((src,name))
    return out

def show_refs(target,label,limit=12):
    refs=e8_refs(target)
    print(f'{label} 0x{target:08X} direct E8 refs={len(refs)}')
    for src,name in refs[:limit]: print(f'  0x{src:08X} section={name}')

print('\n================ PROVEN JOIN CALL CONTRACT ================')
disasm_range(0x0084933E,0x0084937A,{0x00849340,0x00849360,0x00849369,0x00849373,0x00849374})
print('Expected proven shape: ECX=[DE4394], arg1=EDI from 0x846D4F, arg2=&zero endpoint, call [vtable+0x40].')

print('\n================ ARG1 PRODUCER CORE 0x846D4F ================')
disasm_range(0x00846D4F,0x00846D9A,{0x00846D56,0x00846D69,0x00846D79,0x00846D8A,0x00846D95})
print('Key chain: this+0x6A8 -> helper 0x7261BF -> resolver 0x726E0A(..., index, 3) -> candidate -> session validator 0x84C61E(candidate).')

print('\n================ RESOLVER 0x726E0A ================')
disasm_range(0x00726E0A,0x00726F70,{0x00726E0A})
show_refs(0x00726E0A,'resolver')

print('\n================ SESSION VALIDATOR 0x84C61E ================')
disasm_range(0x0084C61E,0x0084C6B4,{0x0084C61E})
show_refs(0x0084C61E,'session validator')

print('\n================ ARG1 CONSUMER COMPATIBILITY ================')
print('0x84CB34 consumes arg1 through 0x800B55(slot0). Trace helper and two other observed consumers of the 0x846D4F return object.')
print('\n--- GET_ROW-like 0x800B55 ---')
disasm_range(0x00800B55,0x00800C10,{0x00800B55})
print('\n--- observed consumer 0x800ACE ---')
disasm_range(0x00800ACE,0x00800B55,{0x00800ACE})
print('\n--- observed consumer 0x801360 ---')
disasm_range(0x00801360,0x00801415,{0x00801360})

print('\n================ NATIVE SEND ZERO-ENDPOINT PATH ================')
print('The join API passes arg2 directly to 0x84C257. Trace the sender and its lower transport target.')
disasm_range(0x0084C257,0x0084C311,{0x0084C257})
print('\n--- lower transport 0x8D925A ---')
disasm_range(0x008D925A,0x008D93A0,{0x008D925A})
show_refs(0x008D925A,'lower transport')

print('\n================ ZERO-ENDPOINT RELATED CALLERS ================')
print('Direct calls to 0x84C257 near the session implementation are shown only as evidence for endpoint conventions.')
for src,name in e8_refs(0x0084C257):
    if 0x0084C000 <= src <= 0x0084E700 or 0x00989000 <= src <= 0x0098B100:
        print(f'  0x{src:08X} section={name}')

print('\n================ FINAL INTERPRETATION TARGETS ================')
print('1) Classify the 0x846D4F return object from resolver + validator + GET_ROW-compatible consumers.')
print('2) Determine whether it is safe to call C54CE0 vtable+0x40 with the same object contract.')
print('3) Resolve whether a non-NULL endpoint pointer containing {0,0} means broadcast/discovery/sentinel or is transformed lower in the send path.')
print('4) Identify any state preconditions visible in 0x84C61E or 0x84CB34 that a runtime PoC must verify first.')
print('5) No file or process memory is modified.')
print('\nREAD-ONLY COMPLETE. No file or process memory was modified.')
'@

$tmp = Join-Path $env:TEMP ('aotr_join_final_contract_' + [guid]::NewGuid().ToString('N') + '.py')
try {
    Set-Content -LiteralPath $tmp -Value $py -Encoding UTF8
    & python $tmp $GameDat
    if ($LASTEXITCODE -ne 0) { throw "Python probe failed with exit code $LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
