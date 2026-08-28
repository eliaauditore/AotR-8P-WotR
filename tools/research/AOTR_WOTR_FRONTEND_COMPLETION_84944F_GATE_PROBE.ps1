param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Purpose: classify the normal-client completion handler at 0x84944F which
# retrieves session+0x44 via session vtable +0xE0 and calls the proven
# publisher 0x8467EB. No process memory or file bytes are modified.

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

$tempPy = Join-Path $env:TEMP ('a8p_frontend_completion_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys,struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]; image_hash=sys.argv[2]
BASE=0x00400000
LOWJOIN=0x00849374
LOWJOIN_END=0x0084940E
COMP=0x0084944F
PUBCALL=0x0084965F
PUBLISH=0x008467EB
SESSION_VT=0x00C54CE0
PROLOGUE_HELPER=0x00A3CEF0

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

def dis(va,n): return list(md.disasm(read(va,n),va))

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

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

def raw_dword_refs(dst):
    needle=struct.pack('<I',dst)
    out=[]
    for name,rva,vs,rs,rp,ch in secs:
        blob=data[rp:rp+rs]
        pos=0
        while True:
            i=blob.find(needle,pos)
            if i<0: break
            out.append((BASE+rva+i,name,ch))
            pos=i+1
    return out

def dump(start,end,marks=None):
    marks=marks or {}
    for x in dis(start,end-start):
        mark=marks.get(x.address,'  ')
        print(fmt(x,mark))

print('============================================================')
print(' AOTR WOTR FRONTEND COMPLETION 0x84944F GATE - DISK ONLY')
print('============================================================')
print(f'Image hash        : {image_hash}')
print(f'Low join call     : 0x{LOWJOIN:08X}')
print(f'Completion entry  : 0x{COMP:08X}')
print(f'Publisher call    : 0x{PUBCALL:08X}')
print('')

print('================ SESSION GETTER FACT ================')
e0=u32(SESSION_VT+0xE0)
d8=u32(SESSION_VT+0xD8)
e4=u32(SESSION_VT+0xE4)
print(f'C54CE0+0xD8 -> 0x{d8:08X}')
print(f'C54CE0+0xE0 -> 0x{e0:08X}')
print(f'C54CE0+0xE4 -> 0x{e4:08X}')
print('E0 body:')
for x in dis(e0,0x20):
    print(fmt(x,'>>' if x.address==e0 else '  '))
    if x.mnemonic.startswith('ret'): break
print('')

print('================ COMPLETION ENTRY REFERENCES ================')
r=refs(COMP)
print(f'DIRECT_REL32_REFS={len(r)}')
for s,k,n in r: print(f'  {k} from 0x{s:08X} section={n}')
rr=raw_dword_refs(COMP)
print(f'EXACT_DWORD_REFS={len(rr)}')
for va,n,ch in rr[:40]: print(f'  0x{va:08X} section={n} executable={bool(ch & 0x20000000)}')
print('')

print('================ COMPLETION FUNCTION 0x84944F..RET ================')
marks={COMP:'>>',PUBCALL:'PP',0x00849477:'S0',0x00849489:'D8',0x00849641:'50',0x00849655:'E0'}
# Function is known to return at 0x849676.
dump(COMP,0x00849677,marks)
print('')

print('================ EBX DATAFLOW TO ARG2 ================')
for x in dis(COMP,PUBCALL-COMP+1):
    writes_ebx=False
    if x.operands and x.operands[0].type==X86_OP_REG and x.reg_name(x.operands[0].reg)=='ebx':
        writes_ebx=True
    if x.mnemonic in ('push','call') and x.address in (0x00849654,0x00849655,0x0084965E,0x0084965F):
        writes_ebx=True
    if writes_ebx:
        print(fmt(x,'**'))
print('Expected normal-publish stack contract at 0x84965F:')
print('  earlier PUSH EBX remains as arg2 while session +0xE0 is called')
print('  PUSH EAX then supplies arg1=session+0x44')
print('  0x8467EB RET 8 confirms two stack arguments')
print('')

print('================ SESSION +0xD8 GATE BODY ================')
for x in dis(d8,0x180):
    print(fmt(x,'>>' if x.address==d8 else '  '))
    if x.mnemonic.startswith('ret'): break
print(f'DIRECT_REFS_TO_D8_TARGET={len(refs(d8))}')
print('')

print('================ LOW-JOIN ROUTINE START CANDIDATES ================')
# The compiler commonly begins these routines with MOV EAX,imm32 ; CALL 0xA3CEF0.
# Enumerate such prologue-helper callsites before the known low-join call.
for s,k,n in refs(PROLOGUE_HELPER):
    if 0x00848F00 <= s <= LOWJOIN:
        try:
            b=read(s-5,5)
        except:
            continue
        if b and b[0]==0xB8:
            imm=struct.unpack_from('<I',b,1)[0]
            cand=s-5
            print(f'  candidate=0x{cand:08X} prologue_tag=0x{imm:08X} helper_call=0x{s:08X}')
print('')

print('================ LOW-JOIN REGION 0x849000..0x84940F ================')
marks={LOWJOIN:'JJ',0x00849359:'UI',0x00849379:'RF'}
dump(0x00849000,0x0084940F,marks)
print('')

print('================ PUBLISH CONTRACT SUMMARY ================')
print(f'session +0xE0 target : 0x{e0:08X}')
print('Known body           : MOV EAX,[ECX+0x44] ; RET')
print('Therefore arg1       : session+0x44 current GameInfo (C54B78 in normal join)')
print('Normal arg2 target   : EBX value preserved on stack before +0xE0 getter')
print('Publisher this       : frontend owner +0x288 (saved at [EBP-0x18])')
print('')
print('INTERPRETATION TARGETS')
print('  1) Identify whether 0x84944F is called directly, through a vtable, or through another callback table.')
print('  2) Prove the normal arg2 value at the publish call.')
print('  3) Classify session +0xD8 as the branch controlling the richer pre-publish setup path.')
print('  4) Identify the low-join routine entry and relation to the same frontend owner class.')
print('  5) Do not invoke 0x8467EB yet; next runtime comparison should test whether 0x84944F executes after low-level PoC join.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'frontend completion gate probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
