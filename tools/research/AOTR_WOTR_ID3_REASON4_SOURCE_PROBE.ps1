param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Focused follow-up for the native ID3 -> PATH_C reject investigation.
# Traces the exact sources of ID3 message fields +0x32, +0x36 and +0x3A in
# the corrected C54CE0 +0x40 Join Request method (0x84CB34), then prints the
# PATH_C reason-4 comparison block and resolves C54CE0 vtable +0x88 used by
# the client ID5 handler. No file or process memory is modified.

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

$tempPy = Join-Path $env:TEMP ('a8p_id3_reason4_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86_const import X86_OP_MEM, X86_OP_IMM, X86_REG_EBP

path=sys.argv[1]
reported_hash=sys.argv[2]
IMAGE_BASE=0x00400000
VTABLE=0x00C54CE0
JOIN_START=0x0084CB34
JOIN_END=0x0084CC82
MSG_BASE=-0x1EC
MSG_SIZE=0x1D8
DE4364=0x00DE4364
GET_ROW=0x00800B55
SEND=0x0084C257
PATHC_R4_START=0x0098A8C4
PATHC_R4_END=0x0098A9C0
ID5_HANDLER_START=0x00989EB3

with open(path,'rb') as f: data=f.read()
if data[:2]!=b'MZ': raise SystemExit('Not MZ')
pe=struct.unpack_from('<I',data,0x3c)[0]
if data[pe:pe+4]!=b'PE\0\0': raise SystemExit('Bad PE')
num=struct.unpack_from('<H',data,pe+6)[0]
opt=struct.unpack_from('<H',data,pe+20)[0]
sec0=pe+24+opt
secs=[]
for i in range(num):
    o=sec0+i*40
    name=data[o:o+8].split(b'\0',1)[0].decode('ascii','replace')
    vs,rva,rs,rp=struct.unpack_from('<IIII',data,o+8)
    chars=struct.unpack_from('<I',data,o+36)[0]
    secs.append(dict(name=name,rva=rva,vs=vs,rs=rs,rp=rp,chars=chars))

def sec_for_va(va):
    rva=va-IMAGE_BASE
    for s in secs:
        if s['rva'] <= rva < s['rva']+max(s['vs'],s['rs']): return s
    return None

def raw_for_va(va):
    s=sec_for_va(va)
    if not s: raise ValueError(f'VA 0x{va:08X} not mapped')
    return s['rp']+((va-IMAGE_BASE)-s['rva']),s

def rb(va,n):
    raw,s=raw_for_va(va)
    return data[raw:raw+n],s,raw

def u32(va): return struct.unpack('<I',rb(va,4)[0])[0]

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def dis(start,end):
    b,s,raw=rb(start,end-start)
    return list(md.disasm(b,start)),s,raw

def fmt(x,mark='  ',note=''):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    z=f'{mark} 0x{x.address:08X}: {bs:<43} {x.mnemonic:<8} {x.op_str}'
    return z + ((' ; '+note) if note else '')

def direct_target(x):
    if x.mnemonic not in ('call','jmp') or not x.operands: return None
    if x.operands[0].type==X86_OP_IMM: return x.operands[0].imm & 0xffffffff
    return None

def msg_off(op):
    if op.type!=X86_OP_MEM or op.mem.base!=X86_REG_EBP: return None
    off=op.mem.disp-MSG_BASE
    return off if 0 <= off < MSG_SIZE else None

def notes(x):
    out=[]
    for op in x.operands:
        if op.type!=X86_OP_MEM: continue
        m=op.mem
        mo=msg_off(op)
        if mo is not None and mo in (0,0x1e,0x32,0x36,0x3a,0x50): out.append(f'MSG+0x{mo:X}')
        if m.base==0 and m.index==0 and (m.disp & 0xffffffff)==DE4364: out.append('ABS [DE4364]')
        if (m.disp & 0xffffffff) in (0xB04,0xB08,0xB38): out.append(f'FIELD +0x{m.disp & 0xffffffff:X}')
        if m.base==X86_REG_EBP and m.disp==8: out.append('ARG1')
        if m.base==X86_REG_EBP and m.disp==0xC: out.append('ARG2')
    t=direct_target(x)
    if t==GET_ROW: out.append('GET_ROW')
    if t==SEND: out.append('SEND')
    return ', '.join(dict.fromkeys(out))

join,s,raw=dis(JOIN_START,JOIN_END)
idx={x.address:i for i,x in enumerate(join)}

print('============================================================')
print(' AOTR WOTR ID3 REASON-4 SOURCE PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash       : {reported_hash}')
print(f'Join method      : 0x{JOIN_START:08X}..0x{JOIN_END:08X}')
print(f'Section/raw      : {s["name"]} / 0x{raw:X}')
print(f'DE4364 global    : 0x{DE4364:08X}')
print('')

print('================ C54CE0 VTABLE VALIDATION ================')
for off in (0x40,0x88,0xC4,0x100):
    t=u32(VTABLE+off)
    print(f'+0x{off:03X} -> 0x{t:08X}')
print('')

print('================ TRUE ID3 JOIN METHOD - FULL FOCUSED DISASSEMBLY ================')
for x in join:
    n=notes(x)
    mark='>>' if n or x.address in (JOIN_START,0x0084CB80,0x0084CBC5,0x0084CBDA,0x0084CC2B,0x0084CC4D) else '  '
    print(fmt(x,mark,n))
print('')

print('================ ID3 FIELD WRITE WINDOWS ================')
anchors=[
    (0x0084CBC5,'MSG+0x32'),
    (0x0084CBDA,'MSG+0x36'),
    (0x0084CC2B,'MSG+0x3A copy region'),
]
for a,label in anchors:
    print(f'\n--- {label} anchor 0x{a:08X} ---')
    i=idx.get(a)
    if i is None:
        # Some anchors are inside a short copy sequence; locate closest preceding instruction.
        prior=[(va,j) for va,j in idx.items() if va<=a]
        if not prior:
            print('<anchor not decoded>'); continue
        _,i=max(prior)
    lo=max(0,i-18); hi=min(len(join),i+12)
    for x in join[lo:hi]:
        print(fmt(x,'>>' if x.address==a else '  ',notes(x)))
print('')

print('================ DE4364 / B04 / B08 / B38 REFERENCES INSIDE JOIN METHOD ================')
hits=0
for x in join:
    n=notes(x)
    if 'DE4364' in n or 'FIELD +0xB04' in n or 'FIELD +0xB08' in n or 'FIELD +0xB38' in n:
        hits+=1
        print(fmt(x,'>>',n))
print(f'count={hits}')
print('')

print('================ ARG1 REFERENCES NEAR ID3 METADATA BUILDER ================')
for x in join:
    if 0x0084CB70 <= x.address <= 0x0084CC40:
        n=notes(x)
        if 'ARG1' in n or 'GET_ROW' in n:
            print(fmt(x,'>>',n))
print('')

print('================ PATH_C REASON-4 COMPARE BLOCK ================')
r4,s2,r2=dis(PATHC_R4_START,PATHC_R4_END)
for x in r4:
    mark='>>' if x.address in (0x0098A927,0x0098A92F,0x0098A93C,0x0098A946,0x0098A94A,0x0098A950,0x0098A95A) else '  '
    print(fmt(x,mark))
print('')

print('================ ID5 REJECT CALLBACK (+0x88) ================')
cb=u32(VTABLE+0x88)
print(f'C54CE0 +0x88 -> 0x{cb:08X}')
try:
    ci,cs,cr=dis(cb,cb+0x180)
    print(f'section/raw={cs["name"]}/0x{cr:X}')
    for x in ci:
        print(fmt(x,'>>' if x.address==cb else '  '))
        if x.address>cb+8 and x.mnemonic.startswith('ret'): break
except Exception as e:
    print(f'<callback decode failed: {e}>')
print('')

print('================ DECISION TARGET ================')
print('If MSG+0x32 is loaded from the local node manager [DE4364]+0xB04, the observed')
print('HOST/VM B04 mismatch directly satisfies the PATH_C reason-4 reject condition.')
print('If MSG+0x32 instead comes from arg1/discovered host GameInfo, the B04 node mismatch')
print('is not sufficient and reasons 3/5 remain live.')
print('Do not infer semantics for B04/B08/B38 beyond the proven comparisons.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'ID3 reason4 source probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
