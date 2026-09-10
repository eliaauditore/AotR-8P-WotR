param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Corrective probe: A205AD does NOT dispatch END to localRoot itself. It loads
# ECX=[localRoot+4] and calls that object's vtable+0x10. This probe identifies
# the +4 sink provenance, its concrete vtable where statically recoverable,
# and whether the sink/update path touches localRoot+0x44 (Component A).

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

$tempPy = Join-Path $env:TEMP ('a8p_localroot_sink_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86_const import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
OWNER=0x0063AD4F
OWNER_END=0x0063C830
DERIVED_CTOR=0x006251F5
BASE_CTOR=0x00A20EDC
CLEANUP=0x00A205AD
LOCALROOT_VT=0x00BFD2A0

with open(path,'rb') as f: data=f.read()
pe=struct.unpack_from('<I',data,0x3c)[0]
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

def rb(va,n):
    s=sec_for_va(va)
    if not s: raise ValueError(f'VA 0x{va:08X} not mapped')
    raw=s['rp']+((va-IMAGE_BASE)-s['rva'])
    return data[raw:raw+n]

def u32(va): return struct.unpack('<I',rb(va,4))[0]

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def dis(start,end): return list(md.disasm(rb(start,end-start),start))

def fmt(x,mark='  ',note=''):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    out=f'{mark} 0x{x.address:08X}: {bs:<43} {x.mnemonic:<8} {x.op_str}'
    return out + ((' ; '+note) if note else '')

def imm_target(x):
    if x.mnemonic not in ('call','jmp') or len(x.operands)!=1: return None
    op=x.operands[0]
    return (op.imm & 0xffffffff) if op.type==X86_OP_IMM else None

def mem_hits(x,disp):
    return any(op.type==X86_OP_MEM and op.mem.disp==disp for op in x.operands)

print('============================================================')
print(' AOTR WOTR LOCALROOT +0x04 END-SINK PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print('Correction       : A205AD dispatches END to [localRoot+0x04], not localRoot itself.')
print('Component A      : localRoot+0x44')
print('')

print('================ DERIVED CTOR 0x6251F5 ================')
for x in dis(DERIVED_CTOR,0x00625212):
    notes=[]
    if x.address==0x006251F8: notes.append('base ctor 0xA20EDC')
    if mem_hits(x,0x44): notes.append('localRoot+0x44')
    if mem_hits(x,0x40): notes.append('localRoot+0x40')
    if x.address==0x00625208: notes.append('localRoot vtable = 0xBFD2A0')
    print(fmt(x,'>>' if notes else '  ', ', '.join(notes)))
print('')

print('================ BASE CTOR 0xA20EDC ================')
base=dis(BASE_CTOR,BASE_CTOR+0x240)
for x in base:
    notes=[]
    if mem_hits(x,4): notes.append('FIELD +0x04')
    if mem_hits(x,8): notes.append('FIELD +0x08')
    if mem_hits(x,0x44): notes.append('FIELD +0x44')
    if x.mnemonic=='call':
        t=imm_target(x); notes.append('CALL '+(f'0x{t:08X}' if t else x.op_str))
    if notes or x.address < BASE_CTOR+0x80:
        print(fmt(x,'>>' if notes else '  ', ', '.join(notes)))
    if x.mnemonic.startswith('ret') and x.address>BASE_CTOR+0x10:
        break
print('')

print('================ OWNER DIRECT localRoot FIELD ACCESSES ================')
owner=dis(OWNER,OWNER_END)
for x in owner:
    notes=[]
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.base==X86_REG_EBP:
            # owner localRoot starts at EBP-0x6C. +4 => -0x68, +8 => -0x64, +0x44 => -0x28.
            if op.mem.disp==-0x68: notes.append('localRoot+0x04 SINK FIELD')
            elif op.mem.disp==-0x64: notes.append('localRoot+0x08')
            elif op.mem.disp==-0x28: notes.append('localRoot+0x44 COMPONENT A')
    if notes:
        print(fmt(x,'>>',', '.join(notes)))
print('')

print('================ CLEANUP / END DISPATCH ================')
for x in dis(CLEANUP,0x00A205DA):
    notes=[]
    if x.address==0x00A205B4: notes.append('ECX = [localRoot+0x04] -> END sink object')
    if x.address==0x00A205C6: notes.append('ASCII END')
    if x.address==0x00A205D0: notes.append('sink.vtable+0x10(payloadPtr,4)')
    print(fmt(x,'>>' if notes else '  ', ', '.join(notes)))
print('')

# Enumerate immediate vtable constants referenced near BASE_CTOR and localRoot-vtable methods.
print('================ CANDIDATE SINK / HELPER VTABLE CONSTANTS ================')
seen=[]
regions=[(BASE_CTOR,BASE_CTOR+0x240)]
# Add localRoot vtable methods as bounded regions because setters/binders may live there.
for off in range(0,0x60,4):
    try:
        t=u32(LOCALROOT_VT+off); s=sec_for_va(t)
        if s and (s['chars'] & 0x20000000): regions.append((t,t+0x140))
    except Exception: pass
for a,b in regions:
    try: ins=dis(a,b)
    except Exception: continue
    for x in ins:
        if x.mnemonic=='mov' and len(x.operands)==2 and x.operands[0].type==X86_OP_MEM and x.operands[1].type==X86_OP_IMM:
            val=x.operands[1].imm & 0xffffffff
            s=sec_for_va(val)
            # plausible vtable points into mapped non-code data and first entry points to executable code
            try:
                first=u32(val); fs=sec_for_va(first)
                if fs and (fs['chars'] & 0x20000000):
                    key=(val,x.address)
                    if key not in seen:
                        seen.append(key)
                        print(f'0x{x.address:08X}: candidate vtable 0x{val:08X} first=0x{first:08X}')
            except Exception: pass
print('')

print('================ LOCALROOT VTABLE METHODS TOUCHING +0x04/+0x44 ================')
for off in range(0,0x60,4):
    try: t=u32(LOCALROOT_VT+off)
    except Exception: continue
    s=sec_for_va(t)
    if not s or not (s['chars'] & 0x20000000): continue
    try: ins=dis(t,t+0x180)
    except Exception: continue
    hits=[]
    for x in ins:
        notes=[]
        if mem_hits(x,4): notes.append('THIS/OBJ +0x04')
        if mem_hits(x,0x44): notes.append('THIS/OBJ +0x44')
        if x.mnemonic=='call':
            tt=imm_target(x)
            if tt: notes.append(f'CALL 0x{tt:08X}')
        if notes: hits.append((x,notes))
        if x.mnemonic.startswith('ret'): break
    if hits:
        print(f'--- localRoot vtable +0x{off:02X} -> 0x{t:08X} ---')
        for x,notes in hits: print(fmt(x,'>>',', '.join(notes)))
print('')

print('================ CLASSIFICATION TARGETS ================')
print('1) Prove where localRoot+0x04 is initialized or assigned.')
print('2) Identify the concrete object/vtable stored in localRoot+0x04.')
print('3) Disassemble that sink vtable +0x10, which receives ASCII END.')
print('4) Determine whether sink processing updates localRoot+0x44 directly or through a parent/back-pointer.')
print('5) Do not call Component A CRC/checksum until the actual update algorithm is visible.')
print('6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'localRoot END-sink probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
