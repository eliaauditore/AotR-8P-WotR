param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Runtime proved B04 component B ([DE3D84]+0x200) identical on HOST/VM and
# component A alone different. This probe corrects the 0x638C52 argument map,
# traces the [ebp-0x6C] localRoot lifecycle, and follows how localRoot is routed
# through 0x638C52 -> 0x5B4A7C. No file/process memory is modified.

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

$tempPy = Join-Path $env:TEMP ('a8p_b04_a_localroot_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86_const import X86_OP_IMM, X86_OP_MEM, X86_OP_REG, X86_REG_EBP

path=sys.argv[1]
IMAGE_BASE=0x00400000
OWNER=0x0063AD4F
OWNER_END=0x0063C830
CALLSITE=0x0063C7E8
SIBLINGS=[0x00638B68,0x00638BDD,0x00638C52]
DOWNSTREAM=0x005B4A7C
DOWNSTREAM_END=0x005B4B9A
CLEANUP=0x00A205AD
LOCAL_DISP=-0x6C
TARGET_DISP=-0x28

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

def u32(va): return struct.unpack('<I',rb(va,4)[0])[0]

def cstr(va,limit=160):
    try:
        b,_,_=rb(va,limit)
    except Exception:
        return None
    out=[]
    for x in b:
        if x==0: break
        if 0x20 <= x < 0x7f or x in (9,10,13): out.append(chr(x))
        else:
            if not out: return None
            break
    s=''.join(out)
    return s if s else None

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def dis(start,end):
    b,s,raw=rb(start,end-start)
    return list(md.disasm(b,start)),s,raw

def fmt(x,mark='  ',note=''):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    q=f'{mark} 0x{x.address:08X}: {bs:<43} {x.mnemonic:<8} {x.op_str}'
    return q + ((' ; '+note) if note else '')

def target(x):
    if x.mnemonic not in ('call','jmp') or len(x.operands)!=1: return None
    op=x.operands[0]
    return (op.imm & 0xffffffff) if op.type==X86_OP_IMM else None

def ebp_disps(x):
    out=[]
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.base==X86_REG_EBP:
            out.append(op.mem.disp)
    return out

print('============================================================')
print(' AOTR WOTR B04 COMPONENT-A LOCALROOT PROVENANCE - DISK ONLY')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print(f'Owner            : 0x{OWNER:08X}')
print(f'Component A read : [ebp-0x28] @ 0x0063C806')
print(f'localRoot        : [ebp-0x6C], target is localRoot+0x44')
print('')

owner,_,_=dis(OWNER,OWNER_END)
idx={x.address:i for i,x in enumerate(owner)}

print('================ CORRECTED 0x638C52 ARGUMENT MAP ================')
print('Resynchronized caller sequence 0x63C7C7..0x63C7E8 leaves seven DWORD arguments.')
print('Because arguments are pushed right-to-left and the 0x4374E0 call constructs the')
print('temporary object in the already-reserved stack slot, the native map is:')
print('  0x638C52 arg1 [ebp+0x08] = 0x00DE8B1C (global pointer)')
print('  0x638C52 arg2 [ebp+0x0C] = temporary object built from literal 0x00BFE9C8')
print('  0x638C52 arg3 [ebp+0x10] = EAX returned by 0x63A899')
print('  0x638C52 arg4 [ebp+0x14] = &localRoot ([owner ebp-0x6C])')
print('  0x638C52 arg5 [ebp+0x18] = 0')
print('  0x638C52 arg6 [ebp+0x1C] = 0')
print('  0x638C52 arg7 [ebp+0x20] = 0')
print('Therefore wrapper+4 stores arg1 (0xDE8B1C), NOT localRoot.')
for va in (0x00BFE9C8,0x00BFEA08):
    s=cstr(va)
    print(f'  literal 0x{va:08X}: {repr(s) if s is not None else "<non-ASCII/non-string>"}')
print('')

print('================ OWNER LOCALROOT LIFECYCLE ================')
# Show every direct reference into the stack object range [ebp-0x6C .. ebp-0x20].
for x in owner:
    hits=[]
    for d in ebp_disps(x):
        if -0x6C <= d <= -0x20:
            off=d-LOCAL_DISP
            hits.append(f'localRoot+0x{off:X}')
    if hits:
        note=', '.join(hits)
        if TARGET_DISP in ebp_disps(x): note += ' <-- Component A field'
        print(fmt(x,'>>',note))
print('')

print('================ ALL &localRoot PASS WINDOWS ================')
for i,x in enumerate(owner):
    # Exact LEA of [ebp-0x6C].
    found=False
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.base==X86_REG_EBP and op.mem.disp==LOCAL_DISP:
            found=True
    if not found: continue
    print(f'\n--- &localRoot reference @ 0x{x.address:08X} ---')
    for y in owner[max(0,i-5):min(len(owner),i+12)]:
        notes=[]
        if y.address==x.address: notes.append('&localRoot')
        if y.mnemonic=='call':
            t=target(y); notes.append('CALL '+(f'0x{t:08X}' if t is not None else y.op_str))
        print(fmt(y,'>>' if notes else '  ', ', '.join(notes)))
print('')

print('================ SIBLING PRODUCER SHAPES ================')
# The three adjacent helpers are likely generated siblings. Show bounded complete bodies.
for n,start in enumerate(SIBLINGS):
    end = SIBLINGS[n+1] if n+1<len(SIBLINGS) else 0x00638CC7
    print(f'\n--- helper 0x{start:08X} ---')
    ii,_,_=dis(start,end)
    for x in ii:
        notes=[]
        for d in ebp_disps(x):
            if d in (8,0xC,0x10,0x14,0x18,0x1C,0x20): notes.append(f'ARG +0x{d:X}')
        if x.mnemonic=='call':
            t=target(x); notes.append('CALL '+(f'0x{t:08X}' if t is not None else x.op_str))
        if x.address in (0x00638C6A,0x00638C76,0x00638CA8): notes.append('KNOWN 0x638C52 routing point')
        print(fmt(x,'>>' if notes else '  ', ', '.join(notes)))
print('')

print('================ 0x638C52 -> 0x5B4A7C DOWNSTREAM MAP ================')
print('Inside 0x638C52, a temporary copy of original arg2 is first reserved on stack,')
print('then six more pushes occur before the thiscall to 0x5B4A7C. Thus 0x5B4A7C gets:')
print('  ECX               = [0xDE3380]')
print('  downstream +0x08  = original arg3 (0x63A899 result)')
print('  downstream +0x0C  = wrapper (vtable 0xBFE4BC; wrapper+4 = 0xDE8B1C)')
print('  downstream +0x10  = original arg5 = 0')
print('  downstream +0x14  = original arg6 = 0')
print('  downstream +0x18  = original arg7 = 0')
print('  downstream +0x1C  = original arg4 = &localRoot   <-- Component-A context')
print('  downstream +0x20  = temporary copy of original arg2')
print('')

print('================ COMPLETE 0x5B4A7C BODY ================')
down,_,_=dis(DOWNSTREAM,DOWNSTREAM_END)
for x in down:
    notes=[]
    for d in ebp_disps(x):
        if d in (8,0xC,0x10,0x14,0x18,0x1C,0x20):
            label='localRoot' if d==0x1C else ('wrapper' if d==0x0C else 'arg')
            notes.append(f'{label} [ebp+0x{d:X}]')
        if d==-0x10: notes.append('local copy of wrapper')
    if x.mnemonic=='call':
        t=target(x); notes.append('CALL '+(f'0x{t:08X}' if t is not None else x.op_str))
    print(fmt(x,'>>' if notes else '  ', ', '.join(notes)))
print('')

print('================ LOCALROOT-RELATED CALL TARGET EXCERPTS ================')
# Collect direct calls in a small forward window after an access to downstream [ebp+0x1C].
seen=[]
for i,x in enumerate(down):
    if 0x1C not in ebp_disps(x): continue
    for y in down[i:min(len(down),i+9)]:
        if y.mnemonic=='call':
            t=target(y)
            if t is not None and t not in seen:
                seen.append(t)
                print(f'\n--- after localRoot access 0x{x.address:08X}: call 0x{t:08X} ---')
                try:
                    ii,_,_=dis(t,t+0x120)
                    for z in ii[:80]:
                        notes=[]
                        for op in z.operands:
                            if op.type==X86_OP_MEM and op.mem.disp==0x44: notes.append('MEM +0x44')
                        if z.mnemonic=='call':
                            tt=target(z); notes.append('CALL '+(f'0x{tt:08X}' if tt is not None else z.op_str))
                        print(fmt(z,'>>' if notes else '  ', ', '.join(notes)))
                        if z.mnemonic.startswith('ret'): break
                except Exception as e:
                    print(f'<decode failed: {e}>')
print('')

print('================ LOCALROOT CLEANUP / END MARKER ================')
ci,_,_=dis(CLEANUP,CLEANUP+0x40)
for x in ci:
    notes=[]
    if any(op.type==X86_OP_IMM and (op.imm & 0xffffffff)==0x00454E44 for op in x.operands):
        notes.append('literal 0x00454E44 = ASCII "END"')
    if x.mnemonic=='call':
        t=target(x); notes.append('CALL '+(f'0x{t:08X}' if t is not None else x.op_str))
    print(fmt(x,'>>' if notes else '  ', ', '.join(notes)))
    if x.mnemonic.startswith('ret'): break
print('')

print('================ INTERPRETATION TARGETS ================')
print('1) Correct prior assumption: wrapper+4 is 0xDE8B1C, not localRoot.')
print('2) localRoot is original 0x638C52 arg4 and downstream 0x5B4A7C [ebp+0x1C].')
print('3) Identify which downstream helper mutates/accumulates localRoot and ultimately localRoot+0x44.')
print('4) Use the localRoot lifecycle and END marker to classify A only when code supports it; do not label it a content checksum prematurely.')
print('5) Runtime proof remains: HOST/VM component B identical; component A alone causes B04/Reason-4 mismatch.')
print('6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'B04 Component-A localRoot provenance probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
