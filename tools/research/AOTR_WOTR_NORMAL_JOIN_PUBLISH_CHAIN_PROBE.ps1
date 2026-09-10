param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Purpose: classify the proven runtime DE892C publisher 0x8467EB/0x846827 and
# connect its normal-join caller at 0x84965F to the known low-level join owner
# around 0x849374. No process memory or file bytes are modified.

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

$tempPy = Join-Path $env:TEMP ('a8p_publish_chain_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys,struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]; image_hash=sys.argv[2]
BASE=0x00400000
PUBLISH=0x008467EB
WRITE=0x00846827
BREAK_EIP=0x0084682D
LOWJOIN=0x00849374
POSTJOIN=0x008472BF
PUBCALL=0x0084965F
OWNER_LO=0x008492C0
OWNER_HI=0x00849720
VT=0x00C54CE0
SESSION_GLOBAL=0x00DE4394
NETWORK_GI=0x00DE892C
STAGING=0x00DE8930

with open(path,'rb') as f: data=f.read()
if data[:2]!=b'MZ': raise SystemExit('Not MZ')
pe=struct.unpack_from('<I',data,0x3c)[0]
if data[pe:pe+4]!=b'PE\0\0': raise SystemExit('Bad PE')
num=struct.unpack_from('<H',data,pe+6)[0]; opt=struct.unpack_from('<H',data,pe+20)[0]
sec0=pe+24+opt; secs=[]
for i in range(num):
    o=sec0+i*40
    name=data[o:o+8].split(b'\0',1)[0].decode('ascii','replace')
    vs,rva,rs,rp=struct.unpack_from('<IIII',data,o+8)
    ch=struct.unpack_from('<I',data,o+36)[0]
    secs.append((name,rva,vs,rs,rp,ch))

def va2raw(va):
    rva=va-BASE
    for s in secs:
        name,srva,vs,rs,rp,ch=s
        if srva <= rva < srva+max(vs,rs):
            rel=rva-srva
            if rel < rs: return rp+rel,s
    raise ValueError(hex(va))

def read(va,n):
    r,s=va2raw(va); return data[r:r+n]

def u32(va): return struct.unpack('<I',read(va,4))[0]

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

def dis(va,n): return list(md.disasm(read(va,n),va))

def rel32_edges():
    out=[]
    for name,rva,vs,rs,rp,ch in secs:
        if not (ch & 0x20000000): continue
        blob=data[rp:rp+rs]; base=BASE+rva
        for i in range(max(0,len(blob)-5)):
            op=blob[i]
            if op not in (0xE8,0xE9): continue
            d=struct.unpack_from('<i',blob,i+1)[0]
            out.append((base+i,(base+i+5+d)&0xffffffff,'CALL' if op==0xE8 else 'JMP',name))
    return out
EDGES=rel32_edges()

def refs(dst): return [(s,k,n) for s,d,k,n in EDGES if d==dst]

def reaches(start,target,maxbytes=0x2000):
    if start>target: return False
    try: ins=dis(start,min(maxbytes,target-start+0x40))
    except: return False
    for x in ins:
        if x.address==target: return True
        if x.address>target: return False
        if x.mnemonic.startswith('ret'): return False
    return False

def owner_candidates(target,back=0x1800):
    low=target-back
    starts=set(d for _,d,_,_ in EDGES if low<=d<=target)
    out=[]
    for st in starts:
        if reaches(st,target): out.append((len(refs(st)),st))
    out.sort(reverse=True)
    return out

def dump_until_ret(start,maxbytes=0x500):
    ins=dis(start,maxbytes)
    for x in ins:
        mark='>>' if x.address in (PUBLISH,WRITE,BREAK_EIP,LOWJOIN,PUBCALL,POSTJOIN) else '  '
        if x.address==WRITE: mark='!!'
        print(fmt(x,mark))
        if x.mnemonic.startswith('ret'): break

print('============================================================')
print(' AOTR WOTR NORMAL JOIN PUBLISH CHAIN - DISK ONLY')
print('============================================================')
print(f'Image hash : {image_hash}')
print(f'Publisher  : 0x{PUBLISH:08X}')
print(f'Writer     : 0x{WRITE:08X}')
print(f'Break EIP  : 0x{BREAK_EIP:08X}')
print(f'Join call  : 0x{LOWJOIN:08X}')
print(f'Publish call:0x{PUBCALL:08X}')
print('')

print('================ PROVEN WRITER ================')
for x in dis(WRITE,0x20):
    print(fmt(x,'!!' if x.address==WRITE else '  '))
    if x.address>=BREAK_EIP+8: break
print('')

print('================ PUBLISH HELPER 0x8467EB ================')
dump_until_ret(PUBLISH,0x500)
print('')

print('================ SESSION VTABLE SLOTS ================')
for off in (0x40,0x50,0x6C,0xC4,0xE0,0xFC,0x100):
    t=u32(VT+off)
    print(f'C54CE0+0x{off:02X} -> 0x{t:08X}')
print('')

slot50=u32(VT+0x50); slote0=u32(VT+0xE0)
for t,label in ((slot50,'SESSION +0x50'),(slote0,'SESSION +0xE0')):
    print(f'================ {label} BODY 0x{t:08X} ================')
    dump_until_ret(t,0x300)
    print(f'DIRECT_REFS={len(refs(t))}')
    for s,k,n in refs(t)[:20]: print(f'  {k} from 0x{s:08X} section={n}')
    print('')

print('================ NORMAL FRONTEND OWNER REGION ================')
for x in dis(OWNER_LO,OWNER_HI-OWNER_LO):
    mark='  '
    if x.address==LOWJOIN: mark='JJ'
    elif x.address==PUBCALL: mark='PP'
    elif x.address==POSTJOIN: mark='RF'
    elif x.mnemonic=='call' and x.operands and x.operands[0].type==X86_OP_IMM and (x.operands[0].imm & 0xffffffff)==PUBLISH: mark='PP'
    elif any(op.type==X86_OP_MEM and (op.mem.disp & 0xffffffff) in (SESSION_GLOBAL,NETWORK_GI,STAGING) for op in x.operands): mark='**'
    print(fmt(x,mark))
print('')

print('================ CONTAINING OWNER CANDIDATES ================')
for target,label in ((LOWJOIN,'LOW_JOIN_0x849374'),(PUBCALL,'PUBLISH_CALL_0x84965F')):
    cs=owner_candidates(target)
    print(label)
    if not cs: print('  NONE')
    for n,(rc,st) in enumerate(cs[:8],1): print(f'  #{n} entry=0x{st:08X} direct_refs={rc}')
print('')

print('================ DIRECT CALLERS OF 0x8467EB ================')
for s,k,n in refs(PUBLISH):
    print(f'{k} from 0x{s:08X} section={n}')
    lo=max(s-0x70,BASE)
    try:
        for x in dis(lo,0xA0):
            if x.address < s-0x40: continue
            if x.address > s+0x18: break
            print(fmt(x,'>>' if x.address==s else '  '))
    except Exception as e: print('  <decode failed>',e)
    print('')

print('================ RELATION SUMMARY INPUTS ================')
print(f'LOW_JOIN direct callsite          : 0x{LOWJOIN:08X}')
print(f'NORMAL publish-helper callsite    : 0x{PUBCALL:08X}')
print(f'Delta publish_call - low_join     : 0x{PUBCALL-LOWJOIN:X}')
print(f'Publisher direct refs             : {len(refs(PUBLISH))}')
print('')
print('INTERPRETATION TARGETS')
print('  1) Confirm 0x8467EB signature/ret cleanup and first/second arguments.')
print('  2) Identify what session vtable +0xE0 returns at the normal publish caller.')
print('  3) Determine whether 0x849374 and 0x84965F belong to the same containing frontend routine or adjacent handlers of the same owner.')
print('  4) Trace the completion/event condition that reaches 0x84965F after session current is established.')
print('  5) Do not call 0x8467EB or write DE892C until the caller contract is classified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'publish-chain probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
