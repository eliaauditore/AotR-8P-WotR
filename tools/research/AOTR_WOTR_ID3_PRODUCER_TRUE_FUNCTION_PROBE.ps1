param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Corrects the previous false function-boundary assumption around 0x84C844.
# Locates the true function containing the proven ID 0x03 builder at 0x84CB80
# and sender at 0x84CC4D, maps it against the C54CE0 vtable, inventories
# its real stack arguments, and re-confirms the shared ID6/ID8 receive handler.

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

$tempPy = Join-Path $env:TEMP ('a8p_id3_true_func_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86 import X86_OP_MEM, X86_REG_EBP

path=sys.argv[1]
IMAGE_BASE=0x00400000
VTABLE=0x00C54CE0
VTABLE_SPAN=0x104
FALSE_API=0x0084C844
ID3_WRITE=0x0084CB80
ID3_SEND=0x0084CC4D
SEND=0x0084C257
DISPATCH_TABLE=0x0084DEC9
PATH_B=0x0098A50D

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

def va_to_raw(va):
    s=sec_for_va(va)
    if not s: raise ValueError(f'VA 0x{va:08X} not mapped')
    return s['rp'] + ((va-IMAGE_BASE)-s['rva']), s

def rb(va,n):
    raw,s=va_to_raw(va)
    return data[raw:raw+n],s,raw

def u32(va):
    b,_,_=rb(va,4)
    return struct.unpack('<I',b)[0]

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def dis(start,n):
    b,s,raw=rb(start,n)
    return s,raw,list(md.disasm(b,start))

def fmt(x,mark='  '):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<38} {x.mnemonic:<8} {x.op_str}'

print('============================================================')
print(' AOTR WOTR ID3 PRODUCER TRUE FUNCTION PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print('')

print('================ FALSE +0x004 BOUNDARY CORRECTION ================')
s,raw,ins=dis(FALSE_API,0x110)
for x in ins:
    mark='>>' if x.address in (FALSE_API,0x0084C943) else '  '
    print(fmt(x,mark))
    if x.address>=0x0084C943: break
print('Expected correction: 0x84C844 terminates at 0x84C943 and cannot own 0x84CB80/0x84CC4D.')
print('')

print('================ C54CE0 VTABLE FULL EXECUTABLE TARGET MAP ================')
vtargets=[]
for off in range(0,VTABLE_SPAN+1,4):
    try: t=u32(VTABLE+off)
    except Exception: continue
    s=sec_for_va(t)
    if s and (s['chars'] & 0x20000000):
        vtargets.append((off,t,s['name']))
        tag=''
        if t==FALSE_API: tag=' << +0x004 FALSE_JOIN_API / SESSION_INIT'
        if 0x0084CB20 <= t <= 0x0084CC82: tag+=' << ID3_REGION_TARGET'
        if t==0x0084CD69: tag+=' << LEAVE_REMOVE_API'
        print(f'+0x{off:03X} -> 0x{t:08X} section={s["name"]}{tag}')
print('')

print('================ PROLOG CANDIDATES AROUND ID3 REGION ================')
start=0x0084CB20; end=0x0084CC82
b,s,raw=rb(start,end-start)
prologs=[]
for i in range(len(b)-2):
    if b[i:i+3] == b'\x55\x8b\xec':
        prologs.append(start+i)
        print(f'prolog 55 8B EC at 0x{start+i:08X}')
print('')

# Prefer exact vtable target that is <= ID3_WRITE and lies in region; otherwise nearest prolog.
cands=[t for off,t,_ in vtargets if 0x0084CB20 <= t <= ID3_WRITE]
true_start=max(cands) if cands else (max([p for p in prologs if p<=ID3_WRITE]) if any(p<=ID3_WRITE for p in prologs) else None)
print('================ TRUE ID3 FUNCTION START RESOLUTION ================')
print('candidate=' + (f'0x{true_start:08X}' if true_start else '<NONE>'))
if true_start:
    slots=[off for off,t,_ in vtargets if t==true_start]
    print('vtableSlots=' + (','.join(f'+0x{x:03X}' for x in slots) if slots else '<NONE>'))
print('')

if true_start:
    print('================ TRUE ID3 FUNCTION DISASSEMBLY ================')
    s,raw,ins=dis(true_start,0x500)
    ended=False
    for x in ins:
        mark='>>' if x.address in (true_start,ID3_WRITE,ID3_SEND) else '  '
        print(fmt(x,mark))
        if x.address>ID3_SEND and x.mnemonic.startswith('ret'):
            ended=True
            break
    print('')

    print('================ TRUE ID3 FUNCTION STACK ARG USES ================')
    for x in ins:
        if x.address < true_start: continue
        if x.address>ID3_SEND+0x80: break
        hit=False
        for op in x.operands:
            if op.type==X86_OP_MEM and op.mem.base==X86_REG_EBP and op.mem.disp in (8,0xC,0x10,0x14):
                hit=True
        if hit: print(fmt(x,'>>'))
    print('')

    print('================ TRUE ID3 FUNCTION DIRECT CALLERS ================')
    # raw E8 refs over all executable sections
    refs=[]
    for sec in secs:
        if not (sec['chars'] & 0x20000000): continue
        raw0=sec['rp']; raw1=min(len(data),raw0+sec['rs'])
        blob=data[raw0:raw1]
        sva=IMAGE_BASE+sec['rva']
        for i in range(0,max(0,len(blob)-5)):
            if blob[i]!=0xE8: continue
            disp=struct.unpack_from('<i',blob,i+1)[0]
            src=sva+i; dst=(src+5+disp)&0xffffffff
            if dst==true_start: refs.append((src,sec['name']))
    print(f'count={len(refs)}')
    for src,sn in refs: print(f'  0x{src:08X} CALL section={sn}')
    print('')

print('================ ID6 / ID8 SHARED RECEIVE HANDLER ================')
for mid in (6,8):
    target=u32(DISPATCH_TABLE+mid*4)
    print(f'ID 0x{mid:02X} -> 0x{target:08X}')
    s,raw,ii=dis(target,0x24)
    for x in ii: print(fmt(x,'>>' if x.address==target else '  '))
print('')
print('Expected: ID8 enters at 0x84D8E1, sets flag=1, then falls into ID6 target 0x84D8E5; both call 0x98A50D.')

print('\nInterpretation targets:')
print('  1) Falsify the old claim that vtable +0x004 / 0x84C844 owns the ID3 producer.')
print('  2) Resolve the exact function start containing 0x84CB80 and 0x84CC4D.')
print('  3) Map that true function to a C54CE0 vtable slot if present.')
print('  4) Inventory only the true function stack arguments and call contract.')
print('  5) Confirm ID6 and ID8 are the same receive helper with an ID8 flag=1 prefix.')
print('  6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'ID3 true-function probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'