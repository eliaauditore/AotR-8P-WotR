param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Resolves the argument semantics of C54CE0 vtable +0x004 (0x84C844),
# inventories the proven ID 0x03 request builder, and compares the receive
# cases for message IDs 0x06 and 0x08 selected by C54CE0 vtable +0x048.

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

$tempPy = Join-Path $env:TEMP ('a8p_join_args_leave_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_AC_READ, CS_AC_WRITE
from capstone.x86_const import X86_REG_EBP, X86_OP_MEM, X86_OP_IMM

path=sys.argv[1]
IMAGE_BASE=0x00400000
VTABLE=0x00C54CE0
JOIN=0x0084C844
REMOVE=0x0084CD69
SEND=0x0084C257
GET_ROW=0x00800B55
JUMPTABLE=0x0084DEC9
PATH_B=0x0098A50D
MSG_BASE_DISP=-0x1EC
MSG_SIZE=0x1D8

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
    if not s: raise ValueError(f'VA 0x{va:08X} not in PE')
    return s['rp'] + ((va-IMAGE_BASE)-s['rva']), s

def read_bytes(va,n):
    raw,s=va_to_raw(va)
    return data[raw:raw+n],s,raw

def read_u32(va):
    b,_,_=read_bytes(va,4)
    return struct.unpack_from('<I',b)[0]

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def disasm(start,n):
    b,s,raw=read_bytes(start,n)
    return s,raw,list(md.disasm(b,start))

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<38} {x.mnemonic:<8} {x.op_str}'

def print_window(title,start,n,marks=()):
    print(f'\n================ {title} ================')
    s,raw,ins=disasm(start,n)
    print(f'section={s["name"]} raw=0x{raw:X}')
    for x in ins:
        print(fmt(x,'>>' if x.address in marks else '  '))
    return ins

print('============================================================')
print(' AOTR WOTR JOIN API ARGS + LEAVE CASES - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print('')

print('================ C54CE0 VTABLE API VALIDATION ================')
for off,label,expected in [(0x004,'JOIN_REQUEST_API',JOIN),(0x048,'LEAVE_REMOVE_API',REMOVE)]:
    got=read_u32(VTABLE+off)
    print(f'vtable +0x{off:03X} -> 0x{got:08X} {label} expected=0x{expected:08X} match={got==expected}')

print_window('JOIN ARG2 / TARGET-ENDPOINT USE',0x0084C930,0x70,marks=(0x0084C959,))
print_window('JOIN ARG1 / GAMEINFO-LIKE USE A',0x0084CA80,0xA0,marks=(0x0084CAB9,0x0084CAD7))
print_window('JOIN ID3 BUILDER + SEND',0x0084CB70,0xE8,marks=(0x0084CB80,0x0084CB90,0x0084CB94,0x0084CC3B,0x0084CC3E,0x0084CC4D))

print('\n================ JOIN CALL CONTRACT EVIDENCE ================')
print('Expected x86 thiscall shape: ECX=session, arg1=[ebp+8], arg2=[ebp+0xC].')
print('At send site 0x84CC4D, push order should be target endpoint then message pointer.')
# Validate exact send tail and GET_ROW call.
for callsite,expected,label in [(0x0084CB94,GET_ROW,'arg1 used as this for GET_ROW(slot0)'),(0x0084CC4D,SEND,'native send')]:
    b,s,raw=read_bytes(callsite,5)
    op=b[0]; dst=None
    if op in (0xE8,0xE9): dst=(callsite+5+struct.unpack_from('<i',b,1)[0])&0xffffffff
    print(f'{label:<38} call=0x{callsite:08X} decoded={"0x%08X"%dst if dst is not None else "<not rel32>"} expected=0x{expected:08X} match={dst==expected}')

print('\n================ ID3 MESSAGE FIELD INVENTORY ================')
# Inventory direct EBP-relative accesses to the exact [ebp-0x1EC] packet in the
# proven ID3 builder/send region. This deliberately labels LEA as address-taking,
# not a read/write of packet contents.
_,_,ins=disasm(0x0084CB77,0xD8)
for x in ins:
    for oi,op in enumerate(x.operands):
        if op.type != X86_OP_MEM or op.mem.base != X86_REG_EBP: continue
        d=op.mem.disp
        off=d-MSG_BASE_DISP
        if 0 <= off < MSG_SIZE:
            role='ADDR' if x.mnemonic=='lea' else ('MEM')
            access=[]
            try:
                if op.access & CS_AC_READ: access.append('R')
                if op.access & CS_AC_WRITE: access.append('W')
            except Exception: pass
            acc=''.join(access) if access else role
            print(f'MSG+0x{off:03X} {acc:<4} {fmt(x,">>")}')

print('\n================ ID3 HIGH-CONFIDENCE FIELDS ================')
print('MSG+0x000 = 0x03 at 0x84CB80')
print('MSG+0x01E receives row0 PlayerInfo endpoint IPv4 at 0x84CBA2 after arg1->GET_ROW(0)->+0x38')
print('MSG+0x032 receives global/session-derived DWORD at 0x84CBC5')
print('MSG+0x036 receives global/session-derived DWORD at 0x84CBDA')
print('MSG+0x03A is destination of a 0x17-byte copy at 0x84CC2B..0x84CC32')
print('MSG+0x050 byte is cleared at 0x84CC47')
print('arg2 [ebp+0xC] is pushed as explicit destination endpoint at 0x84CC3B')

print('\n================ LEAVE SENDER ID8 / ID6 DECISION ================')
print_window('LEAVE API BRANCH',0x0084CD69,0xC8,marks=(0x0084CD9B,0x0084CDA7,0x0084CE22))

print('\n================ RECEIVE CASE TARGETS FOR ID 0x06 / 0x08 ================')
for mid in (0x06,0x08):
    target=read_u32(JUMPTABLE+mid*4)
    s=sec_for_va(target)
    print(f'ID 0x{mid:02X} table@0x{JUMPTABLE+mid*4:08X} -> 0x{target:08X} section={s["name"] if s else "<none>"}')
    try:
        _,_,caseins=disasm(target,0x58)
        for x in caseins: print(fmt(x,'>>' if x.address==target else '  '))
    except Exception as e:
        print(f'  decode error: {e}')

print('\n================ RECEIVE CASE DIRECT HELPER CHECKS ================')
# Raw rel32 scan in a conservative range around the dispatcher cases for PATH_B.
for name,target in [('PATH_B_SLOT_REMOVE_CLEAR',PATH_B)]:
    refs=[]
    start=0x0084D780; end=0x0084DF20
    b,_,_=read_bytes(start,end-start)
    for i in range(0,len(b)-4):
        if b[i] not in (0xE8,0xE9): continue
        src=start+i
        dst=(src+5+struct.unpack_from('<i',b,i+1)[0])&0xffffffff
        if dst==target: refs.append(src)
    print(f'{name} 0x{target:08X}: ' + (', '.join(f'0x{x:08X}' for x in refs) if refs else '<no rel32 refs in dispatcher range>'))

print('\nInterpretation targets:')
print('  1) Confirm vtable +0x004 is the native join-request API and +0x048 is the leave/remove API.')
print('  2) Prove arg2 of +0x004 is the explicit destination endpoint passed to 0x84C257.')
print('  3) Determine whether arg1 is GameInfo-like by its GET_ROW(slot0) use and surrounding field accesses.')
print('  4) Inventory stable fields in the ID 0x03 packet without guessing unknown semantics.')
print('  5) Compare ID 0x06 and 0x08 receive cases to resolve the two leave/remove variants.')
print('  6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'join args / leave cases probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
