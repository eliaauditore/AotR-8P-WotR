param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Traces all executable references to displacement +0xB04 and highlights writes,
# then resolves nearby function boundaries, DE4364 global references and direct
# call structure. Goal: identify where the per-node Reason-4 value DE4364+0xB04
# is initialized or updated. No file/process memory is modified.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

$py = Get-Command py.exe -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python.exe -ErrorAction SilentlyContinue }
if (-not $py) { throw 'Python not found.' }
$pyPath = $py.Source
& $pyPath -c "import capstone" 2>$null
if ($LASTEXITCODE -ne 0) { throw ('Python capstone missing. Install with: "{0}" -m pip install --user capstone' -f $pyPath) }

$tempPy = Join-Path $env:TEMP ('a8p_b04_provenance_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_AC_READ, CS_AC_WRITE
from capstone.x86_const import X86_OP_MEM, X86_OP_IMM

path=sys.argv[1]
reported_hash=sys.argv[2]
IMAGE_BASE=0x00400000
DE4364=0x00DE4364
PROLOG_HELPER=0x00A3CEF0
TARGET_DISP=0xB04
RELATED=(0xB04,0xB08,0xB38)

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
    chars=struct.unpack_from('<I',data,o+36)[0]
    secs.append(dict(name=name,rva=rva,vs=vs,rs=rs,rp=rp,chars=chars,exec=bool(chars & 0x20000000)))

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def sec_for_va(va):
    rva=va-IMAGE_BASE
    for s in secs:
        if s['rva'] <= rva < s['rva']+max(s['vs'],s['rs']): return s
    return None

def va_to_raw(va):
    s=sec_for_va(va)
    if not s: return None,None
    raw=s['rp']+((va-IMAGE_BASE)-s['rva'])
    return raw,s

def raw_to_va(raw,s): return IMAGE_BASE+s['rva']+(raw-s['rp'])

def rb(va,n):
    raw,s=va_to_raw(va)
    if raw is None: raise ValueError(f'VA 0x{va:08X} not mapped')
    return data[raw:raw+n],s,raw

def fmt(x,mark='  ',note=''):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    line=f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'
    return line + ((' ; '+note) if note else '')

def direct_target(x):
    if x.mnemonic not in ('call','jmp') or not x.operands: return None
    if x.operands[0].type==X86_OP_IMM: return x.operands[0].imm & 0xffffffff
    return None

def op_access(op):
    a=[]
    try:
        if op.access & CS_AC_READ: a.append('R')
        if op.access & CS_AC_WRITE: a.append('W')
    except Exception: pass
    return ''.join(a) or '?'

def find_standard_start(hit_va):
    raw,s=va_to_raw(hit_va)
    if raw is None: return None
    lo=max(s['rp'],raw-0x3000)
    best=None
    for p in range(lo,max(lo,raw-9)):
        if data[p]!=0xB8 or data[p+5]!=0xE8: continue
        callva=raw_to_va(p+5,s)
        rel=struct.unpack_from('<i',data,p+6)[0]
        dst=(callva+5+rel)&0xffffffff
        if dst==PROLOG_HELPER: best=raw_to_va(p,s)
    return best

def decode(start,limit=0x4000):
    raw,s=va_to_raw(start)
    if raw is None: return []
    end=min(s['rp']+s['rs'],raw+limit)
    out=[]
    for x in md.disasm(data[raw:end],start):
        out.append(x)
        if len(out)>8 and x.mnemonic.startswith('ret'): break
    return out

# Synchronize instructions around raw little-endian displacement bytes 04 0B 00 00.
hits=[]; seen=set()
needle=struct.pack('<I',TARGET_DISP)
for s in secs:
    if not s['exec']: continue
    beg=s['rp']; end=min(len(data),beg+s['rs']); blob=data[beg:end]
    pos=0
    while True:
        k=blob.find(needle,pos)
        if k<0: break
        disp_raw=beg+k
        for st in range(max(beg,disp_raw-10),disp_raw+1):
            va=raw_to_va(st,s)
            one=list(md.disasm(data[st:min(end,st+20)],va,count=1))
            if not one: continue
            x=one[0]
            matched=False; acc=[]
            for op in x.operands:
                if op.type==X86_OP_MEM and (op.mem.disp & 0xffffffff)==TARGET_DISP:
                    matched=True; acc.append(op_access(op))
            if not matched: continue
            if not (st <= disp_raw and disp_raw+4 <= st+x.size): continue
            key=x.address
            if key in seen: continue
            seen.add(key); hits.append((x,s,''.join(acc) or '?'))
        pos=k+1

hits.sort(key=lambda z:z[0].address)
print('============================================================')
print(' AOTR WOTR DE4364 +B04 PROVENANCE PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash      : {reported_hash}')
print(f'DE4364 global   : 0x{DE4364:08X}')
print(f'+B04 references : {len(hits)}')
print('')

print('================ ALL EXECUTABLE +0xB04 REFERENCES ================')
for x,s,acc in hits:
    tag='WRITE-CANDIDATE' if 'W' in acc else 'READ'
    print(fmt(x,'>>',f'access={acc} {tag} section={s["name"]}'))
print('')

funcs={}
for x,s,acc in hits:
    st=find_standard_start(x.address)
    funcs.setdefault(st if st is not None else x.address,[]).append((x,acc))

print('================ FUNCTIONS CONTAINING +0xB04 ================')
for st in sorted(funcs):
    ins=decode(st)
    localhits={x.address:acc for x,acc in funcs[st]}
    print(f'\n---------------- function 0x{st:08X} ----------------')
    print('B04 hits: '+', '.join(f'0x{x.address:08X}({acc})' for x,acc in funcs[st]))
    de_refs=[]; related=[]; calls=[]
    for x in ins:
        for op in x.operands:
            if op.type!=X86_OP_MEM: continue
            m=op.mem
            d=m.disp & 0xffffffff
            if m.base==0 and m.index==0 and d==DE4364: de_refs.append(x.address)
            if d in RELATED: related.append((x.address,d,op_access(op)))
        t=direct_target(x)
        if x.mnemonic=='call' and t is not None: calls.append((x.address,t))
    print('DE4364 refs: '+(', '.join(f'0x{a:08X}' for a in de_refs) if de_refs else '<none>'))
    print('Related field refs: '+(', '.join(f'0x{a:08X}:+0x{d:X}({ac})' for a,d,ac in related) if related else '<none>'))
    print('Direct calls: '+(', '.join(f'0x{a:08X}->0x{t:08X}' for a,t in calls) if calls else '<none>'))

    # Print compact windows around every B04 hit.
    amap={x.address:i for i,x in enumerate(ins)}
    printed=set()
    for h,acc in funcs[st]:
        if h.address not in amap: continue
        i=amap[h.address]
        print(f'\n  -- B04 {acc} window @ 0x{h.address:08X} --')
        for j in range(max(0,i-22),min(len(ins),i+28)):
            if (h.address,j) in printed: continue
            printed.add((h.address,j))
            x=ins[j]
            note=[]
            for op in x.operands:
                if op.type==X86_OP_MEM:
                    m=op.mem; d=m.disp & 0xffffffff
                    if m.base==0 and m.index==0 and d==DE4364: note.append('ABS [DE4364]')
                    if d in RELATED: note.append(f'FIELD +0x{d:X} {op_access(op)}')
            if x.mnemonic=='call':
                t=direct_target(x)
                if t is not None: note.append(f'CALL 0x{t:08X}')
            mark='>>' if x.address==h.address else '  '
            print(fmt(x,mark,', '.join(note)))

print('\n================ WRITE-CANDIDATE SUMMARY ================')
writes=[(x,acc) for x,s,acc in hits if 'W' in acc]
if not writes:
    print('No direct +0xB04 memory writes were synchronized in executable sections.')
    print('If so, B04 may be filled by a block copy/helper; use the caller/function context above to trace the producer.')
else:
    for x,acc in writes:
        st=find_standard_start(x.address)
        print(f'write=0x{x.address:08X} function='+(f'0x{st:08X}' if st else '<unknown>')+f' instruction="{x.mnemonic} {x.op_str}"')

print('\n================ INTERPRETATION TARGETS ================')
print('1) Identify the exact write(s) or copy path that populate DE4364+0xB04.')
print('2) Trace the source operand/callee feeding that value; do not infer semantics from the numeric value alone.')
print('3) Determine whether B04 is deterministic content/config metadata or process/session-local generated state.')
print('4) Reason-4 is already proven to compare incoming ID3+0x32 against host DE4364+0xB04.')
print('5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'DE4364 B04 provenance probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
