param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Maps the only C54B78 vtable installation site and all direct call targets/callers
# entering the surrounding constructor region. Also surfaces likely allocation-size
# constants for the inline 8-row C54B78 GameInfo layout.

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

$tempPy = Join-Path $env:TEMP ('a8p_c54_ctor_chain_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from collections import defaultdict
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
VT=0x00C54B78
VT_INSTALL=0x0084AED7
REGION_LO=0x0084AD80
REGION_HI=0x0084B100
LIKELY_LO=0x0084AE00
LIKELY_HI=0x0084AED7

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
    if not s: return None
    return s['rp']+(va-IMAGE_BASE-s['rva'])

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

def disasm(start,size):
    raw=va_to_raw(start); s=sec_for_va(start)
    if raw is None: return []
    hi=min(s['rp']+s['rs'],raw+size)
    return list(md.disasm(data[raw:hi],start))

def all_direct_calls():
    out=[]
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        for i in range(len(blob)-5):
            if blob[i] != 0xE8: continue
            va=IMAGE_BASE+s['rva']+i
            rel=struct.unpack_from('<i',blob,i+1)[0]
            tgt=(va+5+rel)&0xffffffff
            out.append((va,tgt,s['name']))
    return out

calls=all_direct_calls()
by_target=defaultdict(list)
for va,tgt,sec in calls: by_target[tgt].append((va,sec))

print('============================================================')
print(' AOTR WOTR C54B78 CONSTRUCTOR CALLCHAIN PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print(f'Known GI vtable  : 0x{VT:08X}')
print(f'Install site     : 0x{VT_INSTALL:08X}')
print('')

print('================ CONSTRUCTOR REGION ================')
for x in disasm(REGION_LO, REGION_HI-REGION_LO):
    mark='>>' if x.address==VT_INSTALL else '  '
    print(fmt(x,mark))
print('')

print('================ DIRECT CALL TARGETS ENTERING PRE-INSTALL REGION ================')
entries=[]
for tgt,sites in sorted(by_target.items()):
    if LIKELY_LO <= tgt <= LIKELY_HI:
        entries.append((tgt,sites))
if not entries:
    print('  <none>')
else:
    for tgt,sites in entries:
        print(f'candidate target 0x{tgt:08X} callers={len(sites)}')
        for va,sec in sites:
            print(f'  caller 0x{va:08X} section={sec}')
            ctx=disasm(max(REGION_LO,va-0x20),0x48)
            for x in ctx:
                print(fmt(x,'>>' if x.address==va else '  '))
        print('')

print('================ ALL DIRECT CALL TARGETS INSIDE C54 REGION ================')
inside=[]
for tgt,sites in sorted(by_target.items()):
    if REGION_LO <= tgt < REGION_HI:
        inside.append((tgt,sites))
if not inside:
    print('  <none>')
else:
    for tgt,sites in inside:
        print(f'0x{tgt:08X} callers={len(sites)} :: ' + ', '.join(f'0x{va:08X}' for va,_ in sites[:20]))
print('')

print('================ C54B78 INSTALL VALIDATION ================')
inst=[x for x in disasm(VT_INSTALL,0x20) if x.address==VT_INSTALL]
if not inst:
    print('  ERROR: install site did not decode')
else:
    x=inst[0]
    print(fmt(x,'>>'))
    hit=False
    for op in x.operands:
        if op.type==X86_OP_IMM and (op.imm & 0xffffffff)==VT: hit=True
    print('  exact C54B78 immediate = '+str(hit))
print('')

print('================ INLINE LAYOUT CONSTANT HITS ================')
# Runtime-proven layout: row0=base+0xDC, row stride=0x1DC, row8 boundary/next=base+0xFBC.
# Scan executable immediates for those constants in the nearby C54 region.
consts={0xDC:'row0',0x1DC:'row_stride',0xFBC:'row8_boundary_next',0xFC0:'post_rows',0xFC4:'post_rows',0xFC8:'post_rows'}
region=disasm(REGION_LO,REGION_HI-REGION_LO)
for val,label in consts.items():
    hits=[]
    for x in region:
        for op in x.operands:
            if op.type==X86_OP_IMM and (op.imm & 0xffffffff)==val:
                hits.append(x); break
            if op.type==X86_OP_MEM and (op.mem.disp & 0xffffffff)==val:
                hits.append(x); break
    print(f'0x{val:X} {label}: count={len(hits)}')
    for x in hits[:20]: print(fmt(x,'>>'))
print('')

print('INTERPRETATION TARGETS')
print('  1) Identify the exact function entry that reaches the sole C54B78 install at 0x84AED7.')
print('  2) Enumerate its direct callers / allocation wrappers.')
print('  3) Confirm the runtime-proven inline row layout: +0xDC, stride 0x1DC, +0xFBC next boundary.')
print('  4) Trace how a constructed C54B78 pointer is later installed into DE892C/session ownership.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw "C54B78 constructor callchain probe failed. Python exit=$LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
