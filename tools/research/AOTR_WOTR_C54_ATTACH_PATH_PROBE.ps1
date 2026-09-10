param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Focus:
#  - classify 0x84DF84, which receives a freshly constructed C54B78 GameInfo
#  - inspect the real session+0x44 writers in PATH_A/B/C
#  - map the relevant C54CE0 vtable slots used by the attach path
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

$tempPy = Join-Path $env:TEMP ('a8p_c54_attach_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
ATTACH=0x0084DF84
PREP=0x0084C736
W44=[0x0098A366,0x0098A5A7,0x0098A7C2]
SESSION_VT=0x00C54CE0

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

def va_to_raw(va):
    s=sec_for_va(va)
    if not s: raise ValueError(hex(va))
    return s['rp']+(va-IMAGE_BASE-s['rva'])

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def exact_context(target,before=0x80,after=0x100):
    # Try nearby starts and retain a stream that lands exactly on target.
    best=None
    lo=max(IMAGE_BASE,target-before)
    for start in range(lo,target+1):
        try: raw=va_to_raw(start); s=sec_for_va(start)
        except: continue
        hi=min(s['rp']+s['rs'],raw+(target-start)+after)
        ins=list(md.disasm(data[raw:hi],start))
        if not any(x.address==target for x in ins): continue
        # Prefer streams with a RET boundary before target rather than garbage crossing it.
        cand=[x for x in ins if target-before <= x.address <= target+after]
        score=len(cand)
        if any(x.mnemonic.startswith('ret') and x.address < target for x in cand): score += 1000
        if best is None or score>best[0]: best=(score,cand)
    return best[1] if best else []

def direct_callers(target):
    out=[]
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        for i in range(len(blob)-5):
            if blob[i] != 0xE8: continue
            va=IMAGE_BASE+s['rva']+i
            rel=struct.unpack_from('<i',blob,i+1)[0]
            if ((va+5+rel)&0xffffffff)==target: out.append((va,s['name']))
    return out

def dump_target(label,target,before=0x80,after=0x100):
    print('================ '+label+' ================')
    print(f'Target: 0x{target:08X}')
    ctx=exact_context(target,before,after)
    if not ctx:
        print('  <no alignment-safe context>')
    else:
        for x in ctx: print(fmt(x,'>>' if x.address==target else '  '))
    print('Direct CALL refs:')
    refs=direct_callers(target)
    print('  count='+str(len(refs)))
    for va,sec in refs: print(f'  0x{va:08X} section={sec}')
    print('')

print('============================================================')
print(' AOTR WOTR C54 ATTACH PATH PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash    : {sys.argv[2]}')
print(f'Attach helper : 0x{ATTACH:08X}')
print(f'Prep helper   : 0x{PREP:08X}')
print('')

dump_target('FRESH C54 ATTACH HELPER 0x84DF84',ATTACH,0x90,0x180)
dump_target('C54 PREP HELPER 0x84C736',PREP,0x70,0x100)

for n,t in enumerate(W44,1):
    dump_target(f'SESSION +0x44 WRITER #{n}',t,0x90,0x100)

print('================ C54CE0 SESSION VTABLE KEY SLOTS ================')
for off in (0x00,0x28,0x30,0x34,0x40,0x44,0x80,0xBC,0xC4,0xFC,0x100,0x108):
    raw=va_to_raw(SESSION_VT+off)
    val=struct.unpack_from('<I',data,raw)[0]
    tags=[]
    if val==ATTACH: tags.append('ATTACH')
    if val==PREP: tags.append('PREP')
    print(f'  +0x{off:03X} -> 0x{val:08X}' + (('  ['+','.join(tags)+']') if tags else ''))
print('')

print('================ DIRECT CALLERS SUMMARY ================')
for name,target in [('84DF84',ATTACH),('84C736',PREP)]:
    refs=direct_callers(target)
    print(f'{name}: '+(', '.join(f'0x{x[0]:08X}' for x in refs) if refs else '<none>'))
print('')

print('INTERPRETATION TARGETS')
print('  1) Does 0x84DF84 directly attach/register the passed C54B78 pointer into the session list/current fields?')
print('  2) Which exact source register feeds session+0x44 at 0x98A366/0x98A5A7/0x98A7C2?')
print('  3) Which of those writers is reached by the normal create/join path around 0x989A89/0x989BC3?')
print('  4) Keep DE892C and session+0x44 untouched until this attach path is proven.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw "C54 attach path probe failed. Python exit=$LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
