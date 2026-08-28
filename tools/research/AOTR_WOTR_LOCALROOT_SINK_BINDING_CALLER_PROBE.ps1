param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Follow-up after static proof that 0xA20DD0 assigns its first argument to
# this+0x04 (the localRoot END-sink field). Also fixes the previous scan for
# DE3380+0x24 consumers by following the two-step [DE3380] -> manager+0x24 form.

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

$tempPy = Join-Path $env:TEMP ('a8p_localroot_sinkbind_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86_const import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
SETTER=0x00A20DD0
SETTER_END=0x00A20E79
DE3380=0x00DE3380
OWNER_START=0x0063AD4F
OWNER_END=0x0063C830
LOCALROOT_READ=0x0063C806

with open(path,'rb') as f: data=f.read()
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

def rb(va,n):
    s=sec_for_va(va)
    if not s: raise ValueError(f'VA 0x{va:08X} not mapped')
    raw=s['rp']+((va-IMAGE_BASE)-s['rva'])
    return data[raw:raw+n],s,raw

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def dis(start,end):
    b,s,raw=rb(start,end-start)
    return list(md.disasm(b,start)),s,raw

def fmt(x,mark='  ',note=''):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    q=f'{mark} 0x{x.address:08X}: {bs:<43} {x.mnemonic:<8} {x.op_str}'
    return q + ((' ; '+note) if note else '')

def direct_target(x):
    if x.mnemonic not in ('call','jmp') or len(x.operands)!=1: return None
    op=x.operands[0]
    return (op.imm & 0xffffffff) if op.type==X86_OP_IMM else None

def abs_mem_target(op):
    if op.type != X86_OP_MEM: return None
    m=op.mem
    if m.base==0 and m.index==0:
        return m.disp & 0xffffffff
    return None

# Decode all executable sections separately so instruction boundaries are section-rooted.
exec_ins=[]
for s in secs:
    if not (s['chars'] & 0x20000000): continue
    start=IMAGE_BASE+s['rva']
    size=min(s['rs'], max(s['vs'],s['rs']))
    try:
        ins,_,_=dis(start,start+size)
        exec_ins.extend(ins)
    except Exception:
        pass

print('============================================================')
print(' AOTR WOTR LOCALROOT SINK-BINDING / CURRENT-ROOT PROBE')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print(f'Exact setter     : 0x{SETTER:08X}')
print(f'Current-root mgr : [0x{DE3380:08X}] + 0x24')
print('')

print('================ EXACT 0xA20DD0 SETTER CONTRACT ================')
sins,_,_=dis(SETTER,SETTER_END)
for x in sins:
    notes=[]
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.base==X86_REG_EBP and 8 <= op.mem.disp <= 0x20:
            notes.append(f'ARG [ebp+0x{op.mem.disp:X}]')
        if op.type==X86_OP_MEM and op.mem.disp==4:
            notes.append('FIELD +0x04')
        if op.type==X86_OP_MEM and op.mem.disp==8:
            notes.append('FIELD +0x08')
    if x.address==0x00A20DE7: notes.append('EDI = arg1 / candidate sink object')
    if x.address==0x00A20E50: notes.append('PROVEN setter: this+0x04 = arg1')
    if x.address==0x00A20E53: notes.append('mode/status byte stored at this+0x08')
    if x.mnemonic=='call':
        t=direct_target(x); notes.append('CALL '+(f'0x{t:08X}' if t is not None else x.op_str))
    print(fmt(x,'>>' if notes else '  ', ', '.join(notes)))
print('')

print('================ DIRECT CALLERS / THUNKS OF 0xA20DD0 ================')
hits=[]
for i,x in enumerate(exec_ins):
    if direct_target(x)==SETTER:
        hits.append((i,x))
print(f'count={len(hits)}')
for n,(i,x) in enumerate(hits,1):
    print(f'\n--- caller {n} @ 0x{x.address:08X} ({x.mnemonic}) ---')
    lo=max(0,i-24); hi=min(len(exec_ins),i+12)
    # Avoid crossing huge gaps between executable sections.
    for y in exec_ins[lo:hi]:
        if abs(y.address-x.address) > 0x180: continue
        note='TARGET 0xA20DD0' if y.address==x.address else ''
        print(fmt(y,'>>' if y.address==x.address else '  ',note))
print('')

print('================ NON-EXEC POINTER XREFS TO 0xA20DD0 ================')
needle=struct.pack('<I',SETTER)
px=[]
for s in secs:
    if s['chars'] & 0x20000000: continue
    raw0=s['rp']; blob=data[raw0:raw0+s['rs']]
    p=0
    while True:
        j=blob.find(needle,p)
        if j<0: break
        va=IMAGE_BASE+s['rva']+j
        px.append((va,s['name']))
        p=j+1
print(f'count={len(px)}')
for va,name in px[:100]: print(f'  0x{va:08X} section={name}')
print('')

# Find two-step [DE3380] -> manager register -> [manager+0x24].
print('================ [DE3380] -> manager+0x24 CURRENT-localRoot CONSUMERS ================')
cons=[]
for i,x in enumerate(exec_ins):
    # mov REG, dword ptr [DE3380]
    if x.mnemonic!='mov' or len(x.operands)!=2: continue
    dst,src=x.operands
    if dst.type!=X86_OP_REG or abs_mem_target(src)!=DE3380: continue
    mgr=dst.reg
    # follow a short straight-line window, stopping at hard control transfer except calls
    for j in range(i+1,min(i+18,len(exec_ins))):
        y=exec_ins[j]
        if y.address-x.address > 0x90: break
        found=False
        for op in y.operands:
            if op.type==X86_OP_MEM and op.mem.base==mgr and op.mem.disp==0x24:
                found=True
        if found:
            cons.append((i,j,x,y,mgr))
        if y.mnemonic in ('ret','jmp'):
            break
print(f'count={len(cons)}')
for n,(i,j,x,y,mgr) in enumerate(cons,1):
    print(f'\n--- current-root consumer {n}: manager load 0x{x.address:08X}, +0x24 access 0x{y.address:08X} ---')
    lo=max(0,i-8); hi=min(len(exec_ins),j+18)
    for z in exec_ins[lo:hi]:
        if z.address < x.address-0x50 or z.address > y.address+0x90: continue
        notes=[]
        if z.address==x.address: notes.append('[DE3380] manager load')
        if z.address==y.address: notes.append('manager+0x24 current localRoot')
        # Highlight any subsequent +0x44 access in the same small window.
        for op in z.operands:
            if op.type==X86_OP_MEM and op.mem.disp==0x44:
                notes.append('+0x44 access nearby')
        if z.mnemonic=='call':
            t=direct_target(z); notes.append('CALL '+(f'0x{t:08X}' if t is not None else z.op_str))
        print(fmt(z,'>>' if notes else '  ', ', '.join(notes)))
print('')

print('================ OWNER PUBLICATION / FINAL READ REFERENCE ================')
oins,_,_=dis(OWNER_START,OWNER_END)
for x in oins:
    if 0x0063AEF0 <= x.address <= 0x0063AF10 or 0x0063C7E8 <= x.address <= 0x0063C820:
        notes=[]
        if x.address==0x0063AF03: notes.append('publish &localRoot to [DE3380]+0x24')
        if x.address==LOCALROOT_READ: notes.append('final Component A read localRoot+0x44')
        if x.address==0x0063C7FD: notes.append('clear [DE3380]+0x24')
        print(fmt(x,'>>' if notes else '  ', ', '.join(notes)))
print('')

print('================ INTERPRETATION TARGETS ================')
print('1) 0xA20DD0 is already proven to assign arg1 into this+0x04; identify its real caller and arg1 producer.')
print('2) Bind that caller to the active localRoot instance, not merely the base class generically.')
print('3) Correctly locate consumers of the published current localRoot via [DE3380] then manager+0x24.')
print('4) If a current-root consumer updates +0x44, follow only that function/helper next.')
print('5) If the setter caller exposes a concrete sink vtable, then disassemble that vtable+0x10 END receiver.')
print('6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'LocalRoot sink-binding/current-root probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
