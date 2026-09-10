param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Traces dispatcher ID 0x05 -> 0x00989EB3 and the exact client-side
# native join-failure handler. No file or process memory is modified.

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

$tempPy = Join-Path $env:TEMP ('a8p_id5_handler_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86_const import X86_OP_MEM, X86_OP_IMM, X86_REG_EBP

path=sys.argv[1]
IMAGE_BASE=0x00400000
DISPATCH_CASE=0x0084D8D0
HANDLER=0x00989EB3
NEXT_FUNC=0x0098A1AD

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
    secs.append(dict(name=name,rva=rva,vs=vs,rs=rs,rp=rp,chars=chars))

def sec_for_va(va):
    rva=va-IMAGE_BASE
    for s in secs:
        if s['rva'] <= rva < s['rva']+max(s['vs'],s['rs']): return s
    return None

def read_bytes(va,n):
    s=sec_for_va(va)
    if not s: raise ValueError(f'VA 0x{va:08X} not in section')
    raw=s['rp']+((va-IMAGE_BASE)-s['rva'])
    return data[raw:raw+n],s,raw

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def dis(start,end):
    b,s,raw=read_bytes(start,end-start)
    return s,raw,list(md.disasm(b,start))

def fmt(x,mark='  ',note=''):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    line=f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'
    return line + ((' ; '+note) if note else '')

def direct_target(x):
    if x.mnemonic not in ('call','jmp'): return None
    if len(x.operands)==1 and x.operands[0].type==X86_OP_IMM:
        return x.operands[0].imm & 0xffffffff
    return None

def notes(x):
    out=[]
    for op in x.operands:
        if op.type==X86_OP_MEM:
            m=op.mem
            if m.disp==0x4c: out.append('+0x4C ACCESS (ID5 reason / assigned-slot field family)')
            if m.base==X86_REG_EBP and m.disp==8: out.append('ARG1/message stack access')
            if m.base==X86_REG_EBP and m.disp==0xc: out.append('ARG2/sender-endpoint stack access')
    if x.mnemonic=='call' and '[' in x.op_str: out.append('INDIRECT/VIRTUAL CALL')
    return ', '.join(dict.fromkeys(out))

print('============================================================')
print(' AOTR WOTR ID5 CLIENT HANDLER PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash        : {sys.argv[2]}')
print(f'Dispatch ID5 case : 0x{DISPATCH_CASE:08X}')
print(f'ID5 handler       : 0x{HANDLER:08X}')
print(f'Handler bound     : 0x{NEXT_FUNC:08X} (next known function)')
print('')

print('================ DISPATCH ID5 ANCHOR ================')
s,raw,ins=dis(DISPATCH_CASE,DISPATCH_CASE+0x15)
for x in ins:
    mark='>>' if x.address in (DISPATCH_CASE,0x0084D8D7) else '  '
    note='ID 0x05 case' if x.address==DISPATCH_CASE else ('calls 0x989EB3' if x.address==0x0084D8D7 else '')
    print(fmt(x,mark,note))
print('')

print('================ FULL ID5 HANDLER 0x989EB3..0x98A1AD ================')
s,raw,ins=dis(HANDLER,NEXT_FUNC)
print(f'section={s["name"]} raw=0x{raw:X} bytes=0x{NEXT_FUNC-HANDLER:X}')
for x in ins:
    n=notes(x)
    mark='>>' if x.address==HANDLER or n else '  '
    print(fmt(x,mark,n))
print('')

print('================ ID5 HANDLER CONDITIONAL EDGES ================')
for x in ins:
    if x.mnemonic.startswith('j') and x.mnemonic!='jmp':
        t=direct_target(x)
        print(f'  0x{x.address:08X} {x.mnemonic:<6} -> {"0x%08X"%t if t is not None else x.op_str}')
print('')

print('================ ID5 HANDLER DIRECT CALL MAP ================')
for x in ins:
    if x.mnemonic=='call':
        t=direct_target(x)
        if t is not None:
            print(f'  0x{x.address:08X} -> 0x{t:08X}')
        else:
            print(f'  0x{x.address:08X} -> {x.op_str}  [indirect]')
print('')

print('================ +0x4C FIELD ACCESSES ================')
hits=0
for x in ins:
    hit=False
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.disp==0x4c:
            hit=True; break
    if hit:
        hits+=1
        print(fmt(x,'>>','candidate ID5 reason-field consumer'))
print(f'count={hits}')
print('')

print('================ INTERPRETATION TARGETS ================')
print('1) Determine whether ID5 message+0x4C is read directly by the client handler.')
print('2) Determine whether the reason is persisted in session state or passed to a callback/vtable method.')
print('3) Map native reason values 2/3/4/5/6/8 without relying on the packet transport encoding.')
print('4) Keep dispatcher ID5 -> 0x989EB3 separate from PATH_C, which PRODUCES ID5 on the host.')
print('5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'ID5 client handler probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
