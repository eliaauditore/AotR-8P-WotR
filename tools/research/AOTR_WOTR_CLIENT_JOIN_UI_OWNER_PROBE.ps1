param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Robust owner discovery for the proven native join callsite 0x00849374.
# Unlike V1, this does NOT require a classic 55 8B EC frame prologue.
# It ranks direct CALL/JMP destinations that decode through the join callsite,
# then falls back to post-RET boundaries. It never modifies game.dat/process memory.

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

$tempPy = Join-Path $env:TEMP ('a8p_join_ui_owner_v2_' + [guid]::NewGuid().ToString('N') + '.py')
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

def all_rel32_edges():
    out=[]
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        base=IMAGE_BASE+s['rva']
        for i in range(0,max(0,len(blob)-5)):
            op=blob[i]
            if op not in (0xE8,0xE9): continue
            disp=struct.unpack_from('<i',blob,i+1)[0]
            src=base+i; dst=(src+5+disp)&0xffffffff
            out.append((src,dst,'CALL' if op==0xE8 else 'JMP',s['name']))
    return out

EDGES=all_rel32_edges()

def rel32_refs(target):
    return [(src,kind,sn) for src,dst,kind,sn in EDGES if dst==target]

def synchronized_context(callva,back=0x90,ahead=0x50):
    raw,s=va_to_raw(callva)
    lo=max(s['rp'],raw-back); hi=min(s['rp']+s['rs'],raw+ahead)
    blob=data[lo:hi]; sva=raw_to_va(lo,s)
    best=None
    for shift in range(0,min(96,raw-lo)+1):
        ins=list(md.disasm(blob[shift:],sva+shift))
        idx=next((i for i,x in enumerate(ins) if x.address==callva),None)
        if idx is None: continue
        if best is None or idx>best[0]: best=(idx,ins)
    return best

def stream_reaches(start, end=CALLSITE, forward=0x500):
    try:
        raw,s=va_to_raw(start)
        raw_end,_=va_to_raw(end)
    except Exception:
        return None
    if raw>raw_end: return None
    blob=data[raw:min(s['rp']+s['rs'],raw_end+forward)]
    ins=list(md.disasm(blob,start))
    by={x.address:i for i,x in enumerate(ins)}
    if end not in by: return None
    idx=by[end]
    # Reject a candidate if normal decoding hits RET before the callsite.
    for x in ins[:idx]:
        if x.mnemonic.startswith('ret'):
            return None
    return ins,idx

def owner_candidates():
    low=CALLSITE-0x2000
    c=[]
    # Strongest signal: actual direct CALL/JMP targets into the containing routine.
    targets={dst for _,dst,_,_ in EDGES if low <= dst <= CALLSITE}
    for start in sorted(targets):
        r=stream_reaches(start)
        if r:
            ins,idx=r
            refs=rel32_refs(start)
            c.append((100 + min(len(refs),20), start, 'REL32_TARGET', len(refs), ins, idx))

    # Classic/common prologues are secondary evidence, not a hard requirement.
    raw_t,s=va_to_raw(CALLSITE)
    raw_low=max(s['rp'],raw_t-0x2000)
    patterns=[
        (b'\x55\x8B\xEC','55 8B EC'),
        (b'\x53\x56\x57','PUSH EBX/ESI/EDI'),
        (b'\x56\x57','PUSH ESI/EDI'),
    ]
    for pat,label in patterns:
        p=raw_low
        while True:
            p=data.find(pat,p,raw_t)
            if p<0: break
            start=raw_to_va(p,s)
            r=stream_reaches(start)
            if r:
                ins,idx=r
                c.append((60,start,'PROLOGUE '+label,len(rel32_refs(start)),ins,idx))
            p+=1

    # Fallback: byte immediately after a nearby RET/RET n, if it decodes through callsite.
    for p in range(raw_low+1,raw_t):
        boundary=False
        if data[p-1]==0xC3: boundary=True
        if p>=3 and data[p-3]==0xC2: boundary=True
        if not boundary: continue
        start=raw_to_va(p,s)
        r=stream_reaches(start)
        if r:
            ins,idx=r
            c.append((40,start,'POST_RET_BOUNDARY',len(rel32_refs(start)),ins,idx))

    # Dedup by start, keep highest score/reason.
    best={}
    for item in c:
        score,start,*rest=item
        if start not in best or score>best[start][0]: best[start]=item
    vals=list(best.values())
    vals.sort(key=lambda t:(t[0],t[1]),reverse=True)
    return vals

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
print(' AOTR WOTR CLIENT JOIN UI OWNER PROBE V2 - DISK ONLY')
print('============================================================')
print(f'Image hash    : {sys.argv[2]}')
print(f'Join callsite : 0x{CALLSITE:08X}')
print('')

cands=owner_candidates()
print('================ OWNER CANDIDATES ================')
print(f'count={len(cands)}')
for n,item in enumerate(cands[:12],1):
    score,start,reason,refs,ins,idx=item
    print(f'#{n:02d} start=0x{start:08X} score={score} reason={reason} direct_refs={refs} join_index={idx}')

if not cands:
    print('NO OWNER CANDIDATE FOUND. Dumping synchronized local window only; probe does not abort.')
    ctx=synchronized_context(CALLSITE,0x400,0x300)
    if ctx:
        idx,ins=ctx
        for j in range(max(0,idx-100),min(len(ins),idx+80)):
            print(fmt(ins[j],'>>' if j==idx else '  '))
    raise SystemExit(0)

score,start,reason,refs,ins,idx=cands[0]
print('\n================ SELECTED OWNER ================')
print(f'owner start   : 0x{start:08X}')
print(f'reason        : {reason}')
print(f'score         : {score}')
print(f'direct refs   : {refs}')
print(f'join index    : {idx}')
print('')
for j,x in enumerate(ins):
    if j > idx+120: break
    if j < max(0,idx-140): continue
    mark='>>' if x.address==CALLSITE else ('**' if touches_field(x) or touches_global(x) else '  ')
    print(fmt(x,mark))

print('\n================ OWNER FIELD / GLOBAL ACCESSES ================')
for j,x in enumerate(ins):
    if j > idx+180: break
    fh=touches_field(x); gh=touches_global(x)
    if fh or gh:
        print(fmt(x,'**')+'    ['+', '.join(fh+gh)+']')

print('\n================ DIRECT CALLERS OF SELECTED OWNER ================')
rr=rel32_refs(start)
print(f'count={len(rr)}')
for n,(src,kind,sn) in enumerate(rr,1):
    print(f'\nCALLER #{n}: 0x{src:08X} {kind} section={sn}')
    ctx=synchronized_context(src,0x120,0x80)
    if not ctx:
        print('  <context decode failed>'); continue
    cidx,cins=ctx
    for j in range(max(0,cidx-30),min(len(cins),cidx+16)):
        print(fmt(cins[j],'>>' if j==cidx else '  '))

for target,label in [(FOLLOWUP,'POST_JOIN_REFRESH'),(UI_SELECT,'UI_SELECT_917C2D'),(UI_SWITCH,'UI_SWITCH_784148')]:
    print(f'\n================ DIRECT XREFS {label} 0x{target:08X} ================')
    rr=rel32_refs(target)
    print(f'count={len(rr)}')
    for src,kind,sn in rr: print(f'  0x{src:08X} {kind} section={sn}')

print('\n================ UI_SWITCH BODY 0x00784148 ================')
b,s,raw=read_bytes(UI_SWITCH,0x200)
for x in md.disasm(b,UI_SWITCH):
    print(fmt(x,'>>' if x.address==UI_SWITCH else '  '))
    if x.mnemonic.startswith('ret'): break

print('\nINTERPRETATION TARGETS')
print('  1) Pick the highest-confidence containing function without assuming a frame pointer.')
print('  2) Identify direct event/callback callers of that function.')
print('  3) Track +0x6A4/+0x6A8/+0x6B4/+0x6BA/+0x6BC lifecycle around join.')
print('  4) Determine where the normal UI path initializes DEA110 / UI manager.')
print('  5) Classify 0x784148 and the browser -> Strategic-lobby transition trigger.')
print('  6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'client join UI owner probe V2 failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
