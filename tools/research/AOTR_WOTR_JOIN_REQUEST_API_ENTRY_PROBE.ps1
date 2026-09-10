param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Maps the native 0x03 join-request producer function (0x84C844) and the
# 0x08 remove/clear sender function (0x84CD69): direct refs, C54CE0 vtable
# identity, stack arguments, exact message-buffer field accesses, and send calls.

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

$tempPy = Join-Path $env:TEMP ('a8p_join_api_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
JOIN_FUNC=0x0084C844
JOIN_SEND=0x0084CC4D
JOIN_ID_WRITE=0x0084CB80
JOIN_MSG_DISP=-0x1EC
REMOVE_FUNC=0x0084CD69
REMOVE_SEND=0x0084CE22
REMOVE_ID_WRITE=0x0084CD9B
REMOVE_MSG_DISP=-0x1E0
SEND_HELPER=0x0084C257
SESSION_VT=0x00C54CE0

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

def va_to_raw(va):
    s=sec_for_va(va)
    if not s: raise ValueError(f'VA 0x{va:08X} not mapped')
    return s['rp'] + ((va-IMAGE_BASE)-s['rva']), s

def read_bytes(va,n):
    raw,s=va_to_raw(va)
    return data[raw:raw+n],s,raw

def read_u32(va):
    b,_,_=read_bytes(va,4)
    return struct.unpack('<I',b)[0]

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def disasm(va,n):
    b,s,raw=read_bytes(va,n)
    return list(md.disasm(b,va)),s,raw

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<40} {x.mnemonic:<8} {x.op_str}'

def raw_refs(target):
    out=[]
    for s in secs:
        if not (s['chars'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        base=IMAGE_BASE+s['rva']
        for i in range(0,max(0,len(blob)-5)):
            op=blob[i]
            if op not in (0xE8,0xE9): continue
            disp=struct.unpack_from('<i',blob,i+1)[0]
            src=base+i
            dst=(src+5+disp)&0xffffffff
            if dst==target: out.append((src,'CALL' if op==0xE8 else 'JMP',s['name']))
    return out

def mem_ebp_disp(op):
    if op.type != X86_OP_MEM: return None
    if op.mem.base != X86_REG_EBP: return None
    return op.mem.disp

def print_arg_uses(ins,start,end):
    for x in ins:
        if not (start <= x.address < end): continue
        hits=[]
        for op in x.operands:
            d=mem_ebp_disp(op)
            if d in (8,0xC,0x10): hits.append(d)
        if hits: print(fmt(x,'>>'))

def print_buffer_accesses(ins,start,end,msgdisp):
    rows=[]
    for x in ins:
        if not (start <= x.address < end): continue
        for oi,op in enumerate(x.operands):
            d=mem_ebp_disp(op)
            if d is None: continue
            off=d-msgdisp
            if 0 <= off < 0x1D8:
                kind='DEST' if oi==0 else 'SRC'
                rows.append((x,off,kind))
                break
    for x,off,kind in rows:
        print(f'{kind:<4} MSG+0x{off:03X}  '+fmt(x,'>>'))

print('============================================================')
print(' AOTR WOTR JOIN REQUEST API ENTRY PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print('')

print('================ C54CE0 VTABLE TARGET MAPPING ================')
for off in range(0,0x120,4):
    try: p=read_u32(SESSION_VT+off)
    except: continue
    if p in (JOIN_FUNC,REMOVE_FUNC,SEND_HELPER):
        label={JOIN_FUNC:'JOIN_REQUEST_PRODUCER',REMOVE_FUNC:'REMOVE_SENDER',SEND_HELPER:'SEND_HELPER'}[p]
        print(f'vtable +0x{off:03X} -> 0x{p:08X} {label}')
print('')

for target,label in [(JOIN_FUNC,'JOIN_REQUEST_PRODUCER_0x84C844'),(REMOVE_FUNC,'REMOVE_SENDER_0x84CD69')]:
    refs=raw_refs(target)
    print(f'================ DIRECT REFS TO {label} ================')
    print(f'count={len(refs)}')
    for src,k,sn in refs: print(f'  0x{src:08X} {k} section={sn}')
    print('')

join_ins,js,jraw=disasm(JOIN_FUNC,0x440)
print('================ JOIN FUNCTION ENTRY 0x84C844 ================')
print(f'section={js["name"]} raw=0x{jraw:X}')
for x in join_ins:
    if x.address >= JOIN_FUNC+0xB0: break
    print(fmt(x,'>>' if x.address==JOIN_FUNC else '  '))
print('')

print('================ JOIN STACK ARGUMENT USES ================')
print('[ebp+8], [ebp+0xC], [ebp+0x10] within 0x84C844..0x84CC82')
print_arg_uses(join_ins,JOIN_FUNC,0x0084CC82)
print('')

print('================ JOIN MESSAGE BUFFER ACCESSES ================')
print('Exact buffer base: [ebp-0x1EC], size 0x1D8')
print_buffer_accesses(join_ins,JOIN_FUNC,0x0084CC82,JOIN_MSG_DISP)
print('')

print('================ JOIN ID3 BUILDER / SEND WINDOW ================')
for x in join_ins:
    if 0x0084CB60 <= x.address <= 0x0084CC60:
        mark='>>' if x.address in (JOIN_ID_WRITE,JOIN_SEND) else '  '
        print(fmt(x,mark))
print('')

# byte-exact validate join send call
b,ss,_=read_bytes(JOIN_SEND,5)
dst=None
if len(b)==5 and b[0] in (0xE8,0xE9): dst=(JOIN_SEND+5+struct.unpack_from('<i',b,1)[0])&0xffffffff
print('================ JOIN SEND VALIDATION ================')
print(f'0x{JOIN_SEND:08X} [{ss["name"]}] bytes={" ".join(f"{v:02X}" for v in b)} decoded={"0x%08X"%dst if dst is not None else "<none>"} expected=0x{SEND_HELPER:08X} match={dst==SEND_HELPER}')
print('')

rem_ins,rs,rraw=disasm(REMOVE_FUNC,0x140)
print('================ REMOVE FUNCTION ENTRY 0x84CD69 ================')
print(f'section={rs["name"]} raw=0x{rraw:X}')
for x in rem_ins:
    if x.address >= REMOVE_FUNC+0x90: break
    print(fmt(x,'>>' if x.address==REMOVE_FUNC else '  '))
print('')

print('================ REMOVE STACK ARGUMENT USES ================')
print_arg_uses(rem_ins,REMOVE_FUNC,REMOVE_FUNC+0x140)
print('')

print('================ REMOVE MESSAGE BUFFER ACCESSES ================')
print('Exact buffer base: [ebp-0x1E0], size 0x1D8')
print_buffer_accesses(rem_ins,REMOVE_FUNC,REMOVE_FUNC+0x140,REMOVE_MSG_DISP)
print('')

print('================ REMOVE ID8 / ID6 BRANCH WINDOW ================')
for x in rem_ins:
    if 0x0084CD80 <= x.address <= 0x0084CE35:
        mark='>>' if x.address in (REMOVE_ID_WRITE,REMOVE_SEND) else '  '
        print(fmt(x,mark))
print('')

b,ss,_=read_bytes(REMOVE_SEND,5)
dst=None
if len(b)==5 and b[0] in (0xE8,0xE9): dst=(REMOVE_SEND+5+struct.unpack_from('<i',b,1)[0])&0xffffffff
print('================ REMOVE SEND VALIDATION ================')
print(f'0x{REMOVE_SEND:08X} [{ss["name"]}] bytes={" ".join(f"{v:02X}" for v in b)} decoded={"0x%08X"%dst if dst is not None else "<none>"} expected=0x{SEND_HELPER:08X} match={dst==SEND_HELPER}')
print('')

print('Interpretation targets:')
print('  1) Determine whether 0x84C844 and/or 0x84CD69 are direct C54CE0 vtable methods or internal helpers.')
print('  2) Resolve the semantic roles of JOIN [ebp+8] and [ebp+0xC] from their uses and caller contexts.')
print('  3) Inventory exact 0x03 message fields written relative to the 0x1D8 packet base.')
print('  4) Resolve the 0x08 vs 0x06 branch in 0x84CD69 and its target/slot arguments.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'join request API entry probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'