param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Finds the function that owns the proven native join callsite 0x00849374,
# its direct callers, and all accesses to the frontend/session fields that
# surround the browser -> Strategic-lobby transition.

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

$tempPy = Join-Path $env:TEMP ('a8p_join_ui_owner_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
CALLSITE=0x00849374
FOLLOWUP=0x008472BF
UI_SELECT=0x00917C2D
UI_SWITCH=0x00784148
FIELDS={0x6A4:'MODE_6A4',0x6A8:'SELECTED_6A8',0x6B4:'TEXT_OR_STATE_6B4',0x6BA:'FLAG_6BA',0x6BC:'UI_BITS_6BC'}
GLOBALS={
  0x00DE4394:'SESSION_GLOBAL',
  0x00DEA110:'UI_MANAGER',
  0x00DEA114:'UI_INDEX',
  0x00DE892C:'NETWORK_GI',
  0x00DE7D6C:'THE_GAMEINFO',
  0x00DE412C:'FRONTEND_GLOBAL_DE412C',
  0x00DE4B04:'FRONTEND_GLOBAL_DE4B04',
}

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
    secs.append(dict(name=name,rva=rva,vs=vs,rs=rs,rp=rp,ch=ch))

def va_to_raw(va):
    rva=va-IMAGE_BASE
    for s in secs:
        if s['rva'] <= rva < s['rva']+max(s['vs'],s['rs']):
            rel=rva-s['rva']
            if rel < s['rs']: return s['rp']+rel,s
    raise ValueError(hex(va))

def raw_to_va(raw,s): return IMAGE_BASE+s['rva']+(raw-s['rp'])

def read_bytes(va,n):
    raw,s=va_to_raw(va); return data[raw:raw+n],s,raw

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

def rel32_refs(target):
    out=[]
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        base=IMAGE_BASE+s['rva']
        for i in range(max(0,len(blob)-5)):
            if blob[i] not in (0xE8,0xE9): continue
            disp=struct.unpack_from('<i',blob,i+1)[0]
            src=base+i; dst=(src+5+disp)&0xffffffff
            if dst==target: out.append((src,'CALL' if blob[i]==0xE8 else 'JMP',s['name']))
    return out

def synchronized_context(callva,back=0x90,ahead=0x50):
    raw,s=va_to_raw(callva)
    lo=max(s['rp'],raw-back); hi=min(s['rp']+s['rs'],raw+ahead)
    blob=data[lo:hi]; sva=raw_to_va(lo,s)
    best=None
    for shift in range(0,min(64,raw-lo)+1):
        ins=list(md.disasm(blob[shift:],sva+shift))
        idx=next((i for i,x in enumerate(ins) if x.address==callva),None)
        if idx is None: continue
        if best is None or idx>best[0]: best=(idx,ins)
    return best

def find_owner_start():
    raw_t,s=va_to_raw(CALLSITE)
    lo=max(s['rp'],raw_t-0x1200)
    cands=[]
    for raw in range(lo,raw_t):
        if data[raw:raw+3] != b'\x55\x8B\xEC': continue
        va=raw_to_va(raw,s)
        ins=list(md.disasm(data[raw:raw_t+0x200],va))
        by={x.address:i for i,x in enumerate(ins)}
        if CALLSITE not in by: continue
        idx=by[CALLSITE]
        crossed=False
        for x in ins[:idx]:
            if x.mnemonic.startswith('ret'):
                crossed=True; break
        if not crossed: cands.append((va,ins,idx))
    if not cands: return None
    return max(cands,key=lambda t:t[0])

def touches_field(x):
    hits=[]
    for op in x.operands:
        if op.type!=X86_OP_MEM: continue
        if op.mem.disp in FIELDS and op.mem.base in (X86_REG_ESI,X86_REG_ECX,X86_REG_EDI,X86_REG_EBX):
            hits.append(FIELDS[op.mem.disp])
    return hits

def touches_global(x):
    hits=[]
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.base==0 and op.mem.index==0:
            d=op.mem.disp & 0xffffffff
            if d in GLOBALS: hits.append(GLOBALS[d])
        if op.type==X86_OP_IMM:
            d=op.imm & 0xffffffff
            if d in GLOBALS: hits.append(GLOBALS[d])
    return hits

print('============================================================')
print(' AOTR WOTR CLIENT JOIN UI OWNER PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash    : {sys.argv[2]}')
print(f'Join callsite : 0x{CALLSITE:08X}')
print('')

owner=find_owner_start()
if not owner:
    print('ERROR: no alignment-safe standard-prologue owner found for 0x849374')
    raise SystemExit(2)
start,ins,idx=owner
print('================ OWNER FUNCTION ================')
print(f'owner start   : 0x{start:08X}')
print(f'join index    : {idx}')
print('')
for x in ins:
    if x.address > CALLSITE+0x180: break
    mark='>>' if x.address==CALLSITE else '  '
    if touches_field(x) or touches_global(x): mark='**'
    print(fmt(x,mark))

print('\n================ OWNER FIELD / GLOBAL ACCESSES ================')
for x in ins:
    if x.address > CALLSITE+0x300: break
    fh=touches_field(x); gh=touches_global(x)
    if fh or gh:
        tags=fh+gh
        print(fmt(x,'**')+'    ['+', '.join(tags)+']')

print('\n================ DIRECT CALLERS OF OWNER ================')
refs=rel32_refs(start)
print(f'count={len(refs)}')
for n,(src,kind,sn) in enumerate(refs,1):
    print(f'\nCALLER #{n}: 0x{src:08X} {kind} section={sn}')
    ctx=synchronized_context(src)
    if not ctx:
        print('  <context decode failed>'); continue
    cidx,cins=ctx
    for j in range(max(0,cidx-24),min(len(cins),cidx+12)):
        print(fmt(cins[j],'>>' if j==cidx else '  '))

for target,label in [(FOLLOWUP,'POST_JOIN_REFRESH'),(UI_SELECT,'UI_SELECT_917C2D'),(UI_SWITCH,'UI_SWITCH_784148')]:
    print(f'\n================ DIRECT XREFS {label} 0x{target:08X} ================')
    rr=rel32_refs(target)
    print(f'count={len(rr)}')
    for src,kind,sn in rr: print(f'  0x{src:08X} {kind} section={sn}')

print('\n================ UI_SWITCH BODY 0x00784148 ================')
b,s,raw=read_bytes(UI_SWITCH,0x180)
for x in md.disasm(b,UI_SWITCH):
    print(fmt(x,'>>' if x.address==UI_SWITCH else '  '))
    if x.mnemonic.startswith('ret'): break

print('\nINTERPRETATION TARGETS')
print('  1) Identify the exact frontend class/method that owns the real 0x849374 join call.')
print('  2) Identify the direct event/callback callers that enter this method.')
print('  3) Track +0x6A4/+0x6A8/+0x6B4/+0x6BA/+0x6BC lifecycle around the join.')
print('  4) Determine why DEA110 is NULL in the direct-call PoC state and where the normal UI path initializes it.')
print('  5) Classify 0x784148, which 0x917C2D invokes when its second argument is true.')
print('  6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'client join UI owner probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
