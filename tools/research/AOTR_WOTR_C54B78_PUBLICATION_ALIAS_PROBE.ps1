param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Focus:
#  - the three direct callers of the sole C54B78 constructor 0x84AEA1
#  - every executable reference to DE892C
#  - address-taken/data-alias candidates that could enable an indirect DE892C write

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

$tempPy = Join-Path $env:TEMP ('a8p_c54_pub_alias_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
CTOR=0x0084AEA1
DE892C=0x00DE892C
CALLS=[0x0084E24E,0x00989A89,0x00989BC3]

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
        span=max(s['vs'],s['rs'])
        if s['rva'] <= rva < s['rva']+span: return s
    return None

def va_to_raw(va):
    s=sec_for_va(va)
    if not s: return None
    return s['rp']+(va-IMAGE_BASE-s['rva'])

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def window(start,size):
    raw=va_to_raw(start); s=sec_for_va(start)
    if raw is None: return []
    hi=min(s['rp']+s['rs'],raw+size)
    return list(md.disasm(data[raw:hi],start))

def executable_sections():
    return [s for s in secs if s['ch'] & 0x20000000]

def direct_callers(target):
    out=[]
    for s in executable_sections():
        blob=data[s['rp']:s['rp']+s['rs']]
        for i in range(0,len(blob)-5):
            if blob[i] != 0xE8: continue
            va=IMAGE_BASE+s['rva']+i
            rel=struct.unpack_from('<i',blob,i+1)[0]
            if ((va+5+rel)&0xffffffff)==target:
                out.append((va,s['name']))
    return out

def ref_kind(x,target):
    kinds=[]
    for op in x.operands:
        if op.type==X86_OP_IMM and (op.imm & 0xffffffff)==target:
            kinds.append('IMM')
        elif op.type==X86_OP_MEM and op.mem.base==0 and op.mem.index==0 and (op.mem.disp & 0xffffffff)==target:
            kinds.append('MEM')
    return '+'.join(kinds) if kinds else None

def aligned_context(target_va,before=0x40,after=0x80):
    # Try many starts and select a stream that lands exactly on target_va.
    best=None
    lo=max(IMAGE_BASE,target_va-before)
    for start in range(lo,target_va+1):
        raw=va_to_raw(start); s=sec_for_va(start)
        if raw is None: continue
        hi=min(s['rp']+s['rs'],raw+(target_va-start)+after)
        ins=list(md.disasm(data[raw:hi],start))
        if any(x.address==target_va for x in ins):
            cand=[x for x in ins if target_va-before <= x.address <= target_va+after]
            if best is None or len(cand)>len(best): best=cand
    return best or []

def robust_refs_to_dword(target):
    # Raw little-endian hit first, then alignment validation around each occurrence.
    needle=struct.pack('<I',target)
    found={}
    for s in executable_sections():
        blob=data[s['rp']:s['rp']+s['rs']]
        pos=0
        while True:
            j=blob.find(needle,pos)
            if j<0: break
            occ_va=IMAGE_BASE+s['rva']+j
            for back in range(0,16):
                start=occ_va-back
                raw=va_to_raw(start)
                if raw is None: continue
                ins=list(md.disasm(data[raw:raw+32],start))
                for x in ins[:6]:
                    if not (x.address <= occ_va < x.address+x.size): continue
                    kind=ref_kind(x,target)
                    if kind:
                        found[(x.address,bytes(x.bytes))]=(x,s['name'],kind)
            pos=j+1
    return sorted(found.values(),key=lambda t:t[0].address)

def raw_occurrences(target):
    needle=struct.pack('<I',target)
    out=[]; pos=0
    while True:
        j=data.find(needle,pos)
        if j<0: break
        for s in secs:
            if s['rp'] <= j < s['rp']+s['rs']:
                va=IMAGE_BASE+s['rva']+(j-s['rp'])
                out.append((s,va)); break
        pos=j+1
    return out

print('============================================================')
print(' AOTR WOTR C54B78 PUBLICATION / ALIAS PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print(f'C54 ctor   : 0x{CTOR:08X}')
print(f'DE892C     : 0x{DE892C:08X}')
print('')

print('================ DIRECT C54 CONSTRUCTOR CALLERS ================')
cs=direct_callers(CTOR)
print('count='+str(len(cs)))
for va,sec in cs: print(f'  0x{va:08X} section={sec}')
print('')

for i,call in enumerate(CALLS,1):
    print(f'================ C54 ALLOCATION CALLER #{i} @ 0x{call:08X} ================')
    ctx=aligned_context(call,0x80,0x180)
    if not ctx:
        print('  <alignment-safe context not found>')
    else:
        for x in ctx: print(fmt(x,'>>' if x.address==call else '  '))
    print('')

print('================ DE892C ROBUST EXECUTABLE REFERENCES ================')
refs=robust_refs_to_dword(DE892C)
print('count='+str(len(refs)))
for idx,(x,secname,kind) in enumerate(refs,1):
    print(f'-- REF #{idx:02d} section={secname} kind={kind} --')
    ctx=aligned_context(x.address,0x28,0x48)
    if ctx:
        for y in ctx: print(fmt(y,'>>' if y.address==x.address else '  '))
    else:
        print(fmt(x,'>>'))
    print('')

print('================ RAW DWORD OCCURRENCES OF &DE892C ================')
occ=raw_occurrences(DE892C)
print('count='+str(len(occ)))
for s,va in occ:
    print(f'  VA=0x{va:08X} section={s["name"]} exec={bool(s["ch"] & 0x20000000)}')
print('')

for s,slotva in occ:
    if s['ch'] & 0x20000000: continue
    print(f'================ CODE REFS TO DATA ALIAS SLOT 0x{slotva:08X} ================')
    slotrefs=robust_refs_to_dword(slotva)
    print('count='+str(len(slotrefs)))
    for x,secname,kind in slotrefs:
        print(f'  {secname} {kind}: {fmt(x,">>")}')
    print('')

print('================ SESSION-REGION +0x44 WRITES ================')
for start,size,label in ((0x0084C700,0x1400,'SESSION_84C7_84DB'),(0x00989A00,0x1600,'PATH_989A_98B0')):
    print('-- '+label+' --')
    # Decode from every byte and dedupe validated instructions with destination displacement +0x44.
    hits={}
    s=sec_for_va(start); raw0=va_to_raw(start)
    if s and raw0 is not None:
        maxlen=min(size,s['rp']+s['rs']-raw0)
        for off in range(maxlen):
            va=start+off; raw=raw0+off
            ins=list(md.disasm(data[raw:raw+16],va))
            if not ins: continue
            x=ins[0]
            if x.mnemonic not in ('mov','xchg','and','or') or not x.operands: continue
            op=x.operands[0]
            if op.type==X86_OP_MEM and (op.mem.disp & 0xffffffff)==0x44:
                hits[(x.address,bytes(x.bytes))]=x
    for _,x in sorted(hits.items(),key=lambda kv:kv[1].address): print(fmt(x,'>>'))
    print('')

print('INTERPRETATION TARGETS')
print('  1) Which constructor caller allocates the persistent Host/VM session GameInfo?')
print('  2) Is DE892C ever address-taken or reached through a data alias?')
print('  3) Which session/path function writes object+0x44 and from what source pointer?')
print('  4) Do not patch DE892C or session+0x44; this probe is read-only.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw "C54 publication/alias probe failed. Python exit=$LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
