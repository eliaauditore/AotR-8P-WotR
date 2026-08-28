param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Traces the native C54CE0 session-object constructor (0x0084C76D),
# direct callers, and the repeated runtime stack return-site 0x0084CFC6.
# No process memory writes and no game.dat modification.

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

$tempPy = Join-Path $env:TEMP ('a8p_c54ce0_chain_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path=sys.argv[1]
IMAGE_BASE=0x00400000
CTOR=0x0084C76D
RET_SITE=0x0084CFC6

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
    secs.append((name,rva,vs,rp,rs))
text=next(s for s in secs if s[0]=='.text')
_,trva,tvs,trp,trs=text
text_va=IMAGE_BASE+trva
code=data[trp:trp+trs]

# Byte-accurate direct rel32 xref scan, independent of instruction alignment.
def direct_refs(target):
    out=[]
    for i in range(0,len(code)-5):
        op=code[i]
        if op not in (0xE8,0xE9): continue
        rel=struct.unpack_from('<i',code,i+1)[0]
        va=text_va+i
        dst=(va+5+rel)&0xffffffff
        if dst==target: out.append((va,op))
    return out

def va_to_raw(va):
    rva=va-IMAGE_BASE
    for name,srva,vs,rp,rs in secs:
        if srva <= rva < srva+max(vs,rs): return rp+(rva-srva)
    raise ValueError(hex(va))

def dump_hex(va,radius=0x30):
    raw=va_to_raw(va)
    lo=max(0,raw-radius); hi=min(len(data),raw+radius)
    blob=data[lo:hi]
    print('  raw context:', ' '.join(f'{b:02X}' for b in blob))

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=False

# Find an alignment-safe local disassembly containing an exact target boundary.
def aligned_window(target, back=0x180, forward=0x100):
    raw_t=va_to_raw(target)
    best=None
    # Try plausible MSVC starts and post-RET starts. Validate target as instruction boundary.
    raw_lo=max(trp,raw_t-back)
    candidates=[]
    for r in range(raw_lo,raw_t+1):
        if data[r:r+3]==b'\x55\x8B\xEC': candidates.append(r)
        if r+12 < len(data) and data[r]==0xB8 and data[r+5]==0xE8 and data[r+10:r+12] in (b'\x81\xEC',b'\x83\xEC'):
            candidates.append(r)
    # Also permit each byte after nearby RET variants as fallback.
    for r in range(raw_lo+1,raw_t+1):
        if data[r-1]==0xC3: candidates.append(r)
        if r>=3 and data[r-3]==0xC2: candidates.append(r)
    for r in sorted(set(candidates), reverse=True):
        sva=IMAGE_BASE+(trva+(r-trp))
        raw_end=min(len(data),raw_t+forward)
        ins=list(md.disasm(data[r:raw_end],sva))
        by={x.address:x for x in ins}
        if target in by:
            # Prefer nearest candidate that does not cross a RET before target.
            crossed=False
            for x in ins:
                if x.address>=target: break
                if x.mnemonic.startswith('ret'): crossed=True
            if not crossed:
                return sva,ins
            if best is None: best=(sva,ins)
    return best

print('============================================================')
print(' AOTR WOTR C54CE0 SESSION CALLCHAIN PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash        : {sys.argv[2]}')
print(f'C54CE0 ctor       : 0x{CTOR:08X}')
print(f'Runtime return VA : 0x{RET_SITE:08X}')
print('')

refs=direct_refs(CTOR)
print(f'Direct E8/E9 refs to ctor: {len(refs)}')
for n,(va,op) in enumerate(refs,1):
    print(f'CTOR REF #{n}: VA=0x{va:08X} opcode={"CALL" if op==0xE8 else "JMP"}')
    dump_hex(va,0x28)
print('')

# Decode the function containing the repeated stack return address.
w=aligned_window(RET_SITE)
print('================ RETURN-SITE 0x0084CFC6 =================')
if not w:
    print('No alignment-safe local function window found.')
    dump_hex(RET_SITE,0x50)
else:
    start,ins=w
    print(f'Validated local start candidate: 0x{start:08X}')
    prev=None
    for x in ins:
        if x.address > RET_SITE+0x50: break
        if x.address >= RET_SITE-0x70:
            mark='>>' if x.address==RET_SITE else ('>>PREV' if x.address < RET_SITE and x.address+len(x.bytes)==RET_SITE else '  ')
            b=' '.join(f'{v:02X}' for v in x.bytes)
            print(f'{mark:6} 0x{x.address:08X}: {b:<30} {x.mnemonic:<8} {x.op_str}')
        if x.address < RET_SITE and x.address+len(x.bytes)==RET_SITE:
            prev=x
    print('')
    if prev:
        print(f'Instruction ending exactly at return-site: 0x{prev.address:08X} {prev.mnemonic} {prev.op_str}')
    else:
        print('No instruction in selected window ends exactly at 0x0084CFC6.')

print('')
print('================ DIRECT REFS TO RETURN-SITE =================')
rr=direct_refs(RET_SITE)
print(f'Direct E8/E9 refs targeting 0x{RET_SITE:08X}: {len(rr)}')
for n,(va,op) in enumerate(rr,1):
    print(f'RET-SITE REF #{n}: VA=0x{va:08X} opcode={"CALL" if op==0xE8 else "JMP"}')
    dump_hex(va,0x20)

print('')
print('Interpretation:')
print('  - Constructor callers identify who allocates/owns the C54CE0 session object.')
print('  - 0x0084CFC6 appeared repeatedly beside live session-object stack copies; if it is the return address immediately after a CALL, the preceding CALL identifies the active method/path.')
print('  - Do not classify repeated MEM_PRIVATE copies as owner pointers without a concrete code/global provenance chain.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'C54CE0 session callchain probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
