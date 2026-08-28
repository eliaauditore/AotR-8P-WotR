param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Traces C54CE0 vtable +0x28 (0x0084D787), the native session dispatcher
# that directly calls the proven remote-Type6-create / local-slot-bind /
# slot-remove helpers. No game.dat or process memory is modified.

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

$tempPy = Join-Path $env:TEMP ('a8p_session_dispatch_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_OP_IMM

path=sys.argv[1]
IMAGE_BASE=0x00400000
VTABLE=0x00C54CE0
DISPATCH=0x0084D787
PATH_A=0x0098A2FC
PATH_B=0x0098A50D
PATH_C=0x0098A7F1
TARGETS={PATH_A:'PATH_A_LOCAL_SLOT_BIND',PATH_B:'PATH_B_SLOT_REMOVE_CLEAR',PATH_C:'PATH_C_REMOTE_TYPE6_CREATE'}

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
    ch=struct.unpack_from('<I',data,o+36)[0]
    secs.append(dict(name=name,rva=rva,vs=vs,rs=rs,rp=rp,ch=ch))

def sec_for_va(va):
    rva=va-IMAGE_BASE
    for s in secs:
        span=max(s['vs'],s['rs'])
        if s['rva'] <= rva < s['rva']+span:
            return s
    return None

def raw_for_va(va):
    s=sec_for_va(va)
    if not s: return None,None
    return s['rp'] + ((va-IMAGE_BASE)-s['rva']), s

def read_u32_va(va):
    off,s=raw_for_va(va)
    if off is None or off+4>len(data): return None
    return struct.unpack_from('<I',data,off)[0]

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=True

def fmt(x):
    b=' '.join(f'{v:02X}' for v in x.bytes)
    extra=''
    if x.mnemonic in ('call','jmp') and x.operands and x.operands[0].type==CS_OP_IMM:
        dst=x.operands[0].imm & 0xffffffff
        if dst in TARGETS: extra=' ; '+TARGETS[dst]
    return f'0x{x.address:08X}: {b:<34} {x.mnemonic:<8} {x.op_str}{extra}'

def disasm_range(start,end):
    off,s=raw_for_va(start)
    if off is None: return [],None
    maxlen=end-start
    blob=data[off:off+maxlen]
    return list(md.disasm(blob,start)),s

print('============================================================')
print(' AOTR WOTR SESSION DISPATCH +0x28 PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print('')

print('================ VTABLE +0x28 VALIDATION ================')
slot_va=VTABLE+0x28
ptr=read_u32_va(slot_va)
off,s=raw_for_va(slot_va)
print(f'vtable=0x{VTABLE:08X} slotVA=0x{slot_va:08X} section={s["name"] if s else "?"} raw=0x{off:X}' if off is not None else 'vtable slot unmapped')
print(f'+0x28 -> 0x{ptr:08X} expected=0x{DISPATCH:08X} match={ptr==DISPATCH}' if ptr is not None else '+0x28 unreadable')
print('')

# Direct refs to dispatcher: raw rel32 and literal DWORD refs.
print('================ REFS TO DISPATCH 0x84D787 ================')
rel=[]; lits=[]
needle=struct.pack('<I',DISPATCH)
for s in secs:
    blob=data[s['rp']:s['rp']+s['rs']]
    base=IMAGE_BASE+s['rva']
    # literal dword refs
    p=0
    while True:
        p=blob.find(needle,p)
        if p<0: break
        lits.append((base+p,s['name']))
        p+=1
    # E8/E9 rel32 refs
    for i in range(0,max(0,len(blob)-5)):
        if blob[i] not in (0xE8,0xE9): continue
        rel32=struct.unpack_from('<i',blob,i+1)[0]
        src=base+i
        dst=(src+5+rel32)&0xffffffff
        if dst==DISPATCH:
            rel.append((src,'CALL' if blob[i]==0xE8 else 'JMP',s['name']))
print(f'literal DWORD refs: {len(lits)}')
for va,sn in lits: print(f'  0x{va:08X} section={sn}')
print(f'direct E8/E9 refs : {len(rel)}')
for va,k,sn in rel: print(f'  0x{va:08X} {k} section={sn}')
print('')

# Main dispatcher from exact vtable entry. This should stay synchronized.
print('================ DISPATCH ENTRY / FIRST MESSAGE SWITCH ================')
ins,s=disasm_range(DISPATCH,0x0084D980)
print(f'section={s["name"] if s else "?"}')
for x in ins:
    mark='>> ' if (x.mnemonic in ('call','jmp') and x.operands and x.operands[0].type==CS_OP_IMM and (x.operands[0].imm & 0xffffffff) in TARGETS) else '   '
    print(mark+fmt(x))
print('')

focus=[
 ('REMOTE_CREATE_CALLSITE',0x0084D850,0x0084D8C0),
 ('LOCAL_BIND_CALLSITE',0x0084D8B0,0x0084D8E0),
 ('REMOVE_CALLSITE_1',0x0084D8D8,0x0084D920),
 ('REMOVE_CALLSITE_2',0x0084DBF0,0x0084DC60),
 ('REMOVE_CALLSITE_3',0x0084DD70,0x0084DDE8),
]
print('================ FOCUSED DISPATCH CALLS ================')
for name,a,z in focus:
    print(f'\n---------------- {name} 0x{a:08X}..0x{z:08X} ----------------')
    ins,s=disasm_range(a,z)
    if not ins:
        print('<no decoded instructions>')
        continue
    for x in ins:
        mark='>> ' if (x.mnemonic in ('call','jmp') and x.operands and x.operands[0].type==CS_OP_IMM and (x.operands[0].imm & 0xffffffff) in TARGETS) else '   '
        print(mark+fmt(x))

# Raw callsite validation independent of disassembler synchronization.
print('\n================ PROVEN HELPER CALLSITE VALIDATION ================')
known=[
 (0x0084D8AC,PATH_C),
 (0x0084D8C6,PATH_A),
 (0x0084D8EF,PATH_B),
 (0x0084DC34,PATH_B),
 (0x0084DDB7,PATH_B),
]
for src,expected in known:
    off,s=raw_for_va(src)
    if off is None or off+5>len(data):
        print(f'0x{src:08X}: unmapped')
        continue
    b=data[off:off+5]
    if b[0] in (0xE8,0xE9):
        rel32=struct.unpack_from('<i',b,1)[0]
        dst=(src+5+rel32)&0xffffffff
        print(f'0x{src:08X} [{s["name"]}] bytes={b.hex(" ").upper()} decoded=0x{dst:08X} expected=0x{expected:08X} match={dst==expected}')
    else:
        print(f'0x{src:08X} [{s["name"]}] bytes={b.hex(" ").upper()} not E8/E9')

print('\nInterpretation targets:')
print('  1) Prove C54CE0 vtable +0x28 is 0x84D787.')
print('  2) Determine which message/event discriminator branches to remote-create, local-bind, or remove.')
print('  3) Resolve the arguments passed to PATH_C and PATH_A at 0x84D8AC / 0x84D8C6.')
print('  4) Determine whether the other PATH_B calls are in the same dispatcher lifecycle or separate subflows.')
print('  5) Identify the safest native session-level bridge entry: dispatcher event injection vs direct helper invocation.')
print('  6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'session dispatch probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
