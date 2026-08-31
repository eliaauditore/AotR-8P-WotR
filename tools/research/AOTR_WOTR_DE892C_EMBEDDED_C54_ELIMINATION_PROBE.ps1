param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Goal:
#  - classify the only remaining non-null direct DE892C setter at 0x77F7D0
#  - prove whether the published embedded object (ESI+0x24) can be C54B78
#  - compare against the unique C54B78 constructor 0x84AEA1 and its callsites

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

$tempPy = Join-Path $env:TEMP ('a8p_de892c_embedded_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
FUNC=0x0077F66B
FUNC_END=0x0077F84C
PUBLISH=0x0077F7D0
C54CTOR=0x0084AEA1
C54VT=0x00C54B78
KNOWN_CALLS=[0x0084E24E,0x00989A89,0x00989BC3]
OWNER_CALLS=[0x0063CBD6,0x0081848C,0x00922222]

with open(path,'rb') as f: data=f.read()
if data[:2] != b'MZ': raise SystemExit('Not MZ')
pe=struct.unpack_from('<I',data,0x3c)[0]
num=struct.unpack_from('<H',data,pe+6)[0]
opt=struct.unpack_from('<H',data,pe+20)[0]
sec0=pe+24+opt
secs=[]
for i in range(num):
    o=sec0+i*40
    name=data[o:o+8].split(b'\0',1)[0].decode('ascii','replace')
    vs,rva,rs,rp=struct.unpack_from('<IIII',data,o+8)
    ch=struct.unpack_from('<I',data,o+36)[0]
    secs.append(dict(name=name,rva=rva,vs=vs,rs=rs,rp=rp,ch=ch))

def sec_for_va(va):
    rva=va-IMAGE_BASE
    for s in secs:
        if s['rva'] <= rva < s['rva']+max(s['vs'],s['rs']): return s
    return None

def raw_for_va(va):
    s=sec_for_va(va)
    if not s: return None,None
    return s['rp'] + ((va-IMAGE_BASE)-s['rva']), s

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def disasm(start,end):
    off,s=raw_for_va(start)
    if off is None: return []
    return list(md.disasm(data[off:off+(end-start)],start))

def fmt(x,mark='  '):
    b=' '.join(f'{v:02X}' for v in x.bytes)
    return f'{mark} 0x{x.address:08X}: {b:<40} {x.mnemonic:<8} {x.op_str}'

def direct_calls_to(target):
    out=[]
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        base=IMAGE_BASE+s['rva']
        for i in range(max(0,len(blob)-5)):
            if blob[i]!=0xE8: continue
            rel=struct.unpack_from('<i',blob,i+1)[0]
            src=base+i
            if ((src+5+rel)&0xffffffff)==target: out.append((src,s['name']))
    return out

def context(site,before=0x30,after=0x30):
    # Alignment-safe: try nearby decode starts and keep a stream that lands on site.
    best=None
    for start in range(max(IMAGE_BASE,site-before),site+1):
        off,s=raw_for_va(start)
        if off is None: continue
        ins=list(md.disasm(data[off:off+(site-start)+after],start))
        if not any(x.address==site for x in ins): continue
        cand=[x for x in ins if site-before <= x.address <= site+after]
        score=len(cand)
        if best is None or score>best[0]: best=(score,cand)
    return best[1] if best else []

print('============================================================')
print(' AOTR WOTR DE892C EMBEDDED C54 ELIMINATION - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print(f'Publisher  : 0x{PUBLISH:08X}  (DE892C = ESI+0x24)')
print(f'C54 ctor   : 0x{C54CTOR:08X}')
print(f'C54 vtable : 0x{C54VT:08X}')
print('')

print('================ FULL 0x77F66B FUNCTION ================')
ins=disasm(FUNC,FUNC_END)
for x in ins:
    mark='>>' if x.address==PUBLISH else '  '
    extra=''
    if x.mnemonic=='call' and x.operands and x.operands[0].type==CS_OP_IMM:
        dst=x.operands[0].imm & 0xffffffff
        if dst==C54CTOR: extra='  <<< DIRECT C54 CONSTRUCTOR'
    if '+ 0x24' in x.op_str or '+0x24' in x.op_str: extra += '  <<< +0x24 SUBOBJECT'
    print(fmt(x,mark)+extra)
print('')

print('================ C54 CONSTRUCTOR CALLSITE ENUMERATION ================')
refs=direct_calls_to(C54CTOR)
print(f'direct call count={len(refs)}')
for src,sec in refs:
    print(f'\n-- C54CTOR call @ 0x{src:08X} section={sec} --')
    for x in context(src,0x28,0x28): print(fmt(x,'>>' if x.address==src else '  '))
print('')

print('================ DOES 0x77F66B DIRECTLY CALL C54CTOR? ================')
inside=[]
for x in ins:
    if x.mnemonic=='call' and x.operands and x.operands[0].type==CS_OP_IMM and (x.operands[0].imm & 0xffffffff)==C54CTOR:
        inside.append(x.address)
print('YES: '+', '.join(f'0x{x:08X}' for x in inside) if inside else 'NO')
print('')

print('================ CALLERS OF 0x77F66B ================')
for src in OWNER_CALLS:
    print(f'\n-- owner callsite 0x{src:08X} --')
    for x in context(src,0x30,0x30): print(fmt(x,'>>' if x.address==src else '  '))
print('')

print('STATIC DECISION TARGET')
print('  - If the unique C54 constructor callsites remain only 0x84E24E/0x989A89/0x989BC3')
print('    and 0x77F66B never invokes C54CTOR for ESI+0x24, then 0x77F7D0 cannot')
print('    explain a live DE892C object whose first dword is C54B78.')
print('  - In that case all known direct non-null DE892C setters are eliminated as the')
print('    host C54 publisher, and the next search must cover base+offset / computed-address writes.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw "embedded C54 elimination probe failed. Python exit=$LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
