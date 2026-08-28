param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Runtime hardware watch on a normal client join trapped immediately after a write to
# VA 0x00DE892C with EIP=0x0084682D and EBX equal to the newly published C54B78 pointer.
# This probe resolves the exact instruction that ends at 0x0084682D, dumps its containing
# code path, and finds direct rel32 callers/targets that can reach the writer.

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

$tempPy = Join-Path $env:TEMP ('a8p_de892c_writer_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
NEXT_EIP=0x0084682D
TARGET=0x00DE892C

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

def direct_target(x):
    if x.mnemonic not in ('call','jmp'): return None
    if len(x.operands)==1 and x.operands[0].type==X86_OP_IMM:
        return x.operands[0].imm & 0xffffffff
    return None

def writes_target(x):
    if not x.operands: return False
    dst=x.operands[0]
    if dst.type!=X86_OP_MEM: return False
    m=dst.mem
    if m.base==0 and m.index==0 and (m.disp & 0xffffffff)==TARGET:
        return True
    return False

# All instruction starts in the previous 15 bytes whose first decoded instruction ends exactly at NEXT_EIP.
print('============================================================')
print(' AOTR WOTR DE892C RUNTIME WRITER @ EIP 0x84682D - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print(f'Watch VA   : 0x{TARGET:08X}')
print(f'Break EIP  : 0x{NEXT_EIP:08X}')
print('')

print('================ EXACT PRECEDING-INSTRUCTION CANDIDATES ================')
cands=[]
for start in range(NEXT_EIP-15,NEXT_EIP):
    try:
        b,s,r=read_bytes(start,NEXT_EIP-start)
    except Exception:
        continue
    ins=list(md.disasm(b,start,count=1))
    if ins and ins[0].address+ins[0].size==NEXT_EIP:
        cands.append(ins[0])
for x in cands:
    mark='>>' if writes_target(x) else '  '
    print(fmt(x,mark))
    if writes_target(x):
        print('     DIRECT_DE892C_WRITE=YES')
        if len(x.operands)>1 and x.operands[1].type==X86_OP_REG:
            print('     SOURCE_REGISTER='+x.reg_name(x.operands[1].reg).upper())
if not cands: print('  <none>')

# Choose strongest exact writer candidate, otherwise longest predecessor candidate.
writer=None
for x in cands:
    if writes_target(x): writer=x; break
if writer is None and cands:
    writer=max(cands,key=lambda z:z.size)
writer_va=writer.address if writer else NEXT_EIP

print('\n================ SYNCHRONIZED LOCAL WINDOW ================')
# Search backward for a decode start that reaches NEXT_EIP exactly and yields a long coherent stream.
raw_e,s=va_to_raw(NEXT_EIP)
best=None
for back in range(0x20,0x220):
    start=NEXT_EIP-back
    try:
        b,ss,r=read_bytes(start,back+0x180)
    except Exception:
        continue
    ins=list(md.disasm(b,start))
    by={x.address:i for i,x in enumerate(ins)}
    if NEXT_EIP in by:
        idx=by[NEXT_EIP]
        # Prefer streams with many instructions and no RET in the 30 instructions before EIP.
        pre=ins[max(0,idx-30):idx]
        if any(x.mnemonic.startswith('ret') for x in pre):
            continue
        score=len(pre)
        if best is None or score>best[0]: best=(score,ins,idx,start)
if best:
    score,ins,idx,start=best
    print(f'decode_start=0x{start:08X} score={score}')
    for j in range(max(0,idx-60),min(len(ins),idx+45)):
        x=ins[j]
        mark='>>' if x.address==writer_va else ('**' if x.address==NEXT_EIP else '  ')
        print(fmt(x,mark))
else:
    print('  <coherent window not found>')

# Raw rel32 edge inventory.
edges=[]
for s in secs:
    if not (s['ch'] & 0x20000000): continue
    blob=data[s['rp']:s['rp']+s['rs']]
    base=IMAGE_BASE+s['rva']
    for i in range(max(0,len(blob)-5)):
        op=blob[i]
        if op not in (0xE8,0xE9): continue
        disp=struct.unpack_from('<i',blob,i+1)[0]
        src=base+i; dst=(src+5+disp)&0xffffffff
        edges.append((src,dst,'CALL' if op==0xE8 else 'JMP',s['name']))

# Candidate function entries: rel32 targets within 0x1000 before writer that decode through writer without RET.
print('\n================ CONTAINING-ROUTINE ENTRY CANDIDATES ================')
def stream_reaches(start,end):
    try:
        raw,s=va_to_raw(start); raw2,s2=va_to_raw(end)
    except Exception:
        return None
    if s is not s2 or raw>raw2: return None
    blob=data[raw:min(s['rp']+s['rs'],raw2+0x100)]
    ins=list(md.disasm(blob,start))
    by={x.address:i for i,x in enumerate(ins)}
    if end not in by: return None
    idx=by[end]
    if any(x.mnemonic.startswith('ret') for x in ins[:idx]): return None
    return ins,idx

targets={dst for _,dst,_,_ in edges if writer_va-0x1000 <= dst <= writer_va}
entries=[]
for start in sorted(targets):
    r=stream_reaches(start,writer_va)
    if not r: continue
    refs=[e for e in edges if e[1]==start]
    entries.append((len(refs),start,refs,r))
entries.sort(reverse=True)
for refs_n,start,refs,r in entries[:12]:
    print(f'entry=0x{start:08X} direct_refs={refs_n}')
    for src,dst,kind,sn in refs[:12]: print(f'  {kind} from 0x{src:08X} section={sn}')
if not entries: print('  <none>')

selected=entries[0][1] if entries else None
if selected is not None:
    print(f'\nSELECTED_ENTRY=0x{selected:08X}')
    print('================ DIRECT CALLERS OF SELECTED ENTRY ================')
    rr=[e for e in edges if e[1]==selected]
    for src,dst,kind,sn in rr:
        print(f'\n{kind} from 0x{src:08X} section={sn}')
        # synchronized context around caller
        try:
            raw,s=va_to_raw(src)
        except Exception:
            continue
        lo=max(s['rp'],raw-0x90); hi=min(s['rp']+s['rs'],raw+0x70)
        blob=data[lo:hi]; sva=raw_to_va(lo,s)
        bestctx=None
        for sh in range(min(96,raw-lo)+1):
            ii=list(md.disasm(blob[sh:],sva+sh))
            by={x.address:i for i,x in enumerate(ii)}
            if src in by:
                idx=by[src]
                if bestctx is None or idx>bestctx[0]: bestctx=(idx,ii)
        if bestctx:
            idx,ii=bestctx
            for j in range(max(0,idx-22),min(len(ii),idx+14)):
                print(fmt(ii[j],'>>' if ii[j].address==src else '  '))

print('\n================ KNOWN JOIN-OWNER RELATION CHECK ================')
for va,label in [(0x00849374,'LOW_LEVEL_JOIN_CALL'),(0x008472BF,'POST_JOIN_REFRESH'),(0x00917C2D,'UI_INDEX_SETTER')]:
    refs=[e for e in edges if e[1]==va]
    print(f'{label} 0x{va:08X} direct_refs={len(refs)}')
    for src,dst,kind,sn in refs[:20]: print(f'  {kind} from 0x{src:08X} section={sn}')

print('\nINTERPRETATION TARGETS')
print('  1) A hardware data breakpoint fires after the write instruction; identify the instruction ending at 0x84682D.')
print('  2) If the exact predecessor is MOV [0x00DE892C], EBX, runtime EBX already proves the published value is the C54B78 pointer.')
print('  3) Classify the containing routine and its direct callers before reproducing any callback in a PoC.')
print('  4) Do not manually write DE892C and do not patch game.dat/process memory.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'runtime writer probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
