param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Correctly enumerates direct CALL/JMP refs with Capstone operand decoding and
# traces the native GameInfo slot-setter callers around 0x98Axxx. These paths
# sit beside PlayerInfo Type6 construction/copy calls and are prime candidates
# for native remote-join / remote-slot update logic.

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

$tempPy = Join-Path $env:TEMP ('a8p_slot_setter_callers_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_OP_IMM

path=sys.argv[1]
IMAGE_BASE=0x00400000
TARGETS={
    0x0084B01B:'GAMEINFO_SLOT_SETTER',
    0x0084A825:'PLAYERINFO_COPY_ASSIGN',
    0x008A0318:'SESSION_ENDPOINT_ACCESSOR',
    0x008014F1:'PLAYERINFO_ASSIGN_TYPE6',
    0x0084DF19:'PLAYERINFO_STACK_COPY',
    0x00649242:'PLAYERINFO_HELPER_A',
    0x00649279:'PLAYERINFO_HELPER_B',
}

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
    secs.append(dict(name=name,rva=rva,vs=vs,rs=rs,rp=rp))
text=next(s for s in secs if s['name']=='.text')
blob=data[text['rp']:text['rp']+text['rs']]
text_va=IMAGE_BASE+text['rva']

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=True
insns=list(md.disasm(blob,text_va))
addr_to_idx={x.address:i for i,x in enumerate(insns)}

refs={t:[] for t in TARGETS}
for i,x in enumerate(insns):
    if x.mnemonic not in ('call','jmp') or not x.operands:
        continue
    op=x.operands[0]
    if op.type != CS_OP_IMM:
        continue
    dst=op.imm & 0xffffffff
    if dst in refs:
        refs[dst].append((i,x))

print('============================================================')
print(' AOTR WOTR SLOT SETTER CALLER PATHS PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print('')
print('================ CORRECT DIRECT CALL/JMP REFS ================')
for t,name in TARGETS.items():
    print(f'{name} 0x{t:08X}: {len(refs[t])} refs')
    for _,x in refs[t]:
        print(f'  0x{x.address:08X} {x.mnemonic.upper()} -> 0x{t:08X}')
    print('')

def candidate_start(idx):
    lo=max(0,idx-500)
    for j in range(idx-1,lo-1,-1):
        if insns[j].mnemonic.startswith('ret'):
            return insns[j+1].address if j+1 < len(insns) else None
    return None

def fmt(x,mark='  '):
    b=' '.join(f'{v:02X}' for v in x.bytes)
    extra=''
    if x.mnemonic in ('call','jmp') and x.operands and x.operands[0].type==CS_OP_IMM:
        dst=x.operands[0].imm & 0xffffffff
        if dst in TARGETS:
            extra='  ; '+TARGETS[dst]
    return f'{mark} 0x{x.address:08X}: {b:<34} {x.mnemonic:<8} {x.op_str}{extra}'

slot_refs=refs[0x0084B01B]
print('================ SLOT SETTER CALLER CONTEXTS ================')
for n,(idx,callins) in enumerate(slot_refs,1):
    st=candidate_start(idx)
    print(f'\n---------------- CALLER #{n}: callsite=0x{callins.address:08X} candidateStart={"0x%08X"%st if st else "<unknown>"} ----------------')
    a=max(0,idx-70); z=min(len(insns),idx+28)
    for j in range(a,z):
        mark='>>' if j==idx else '  '
        print(fmt(insns[j],mark))

# Focused windows for the three non-host setter paths already correlated with
# Type6 / PlayerInfo build calls in prior probes.
focus=[
    ('PATH_A_98A4XX',0x0098A360,0x0098A520),
    ('PATH_B_98A6XX',0x0098A5F0,0x0098A780),
    ('PATH_C_98ADXX',0x0098AC20,0x0098AE20),
]
print('\n================ FOCUSED 0x98Axxx PATHS ================')
for name,start,end in focus:
    print(f'\n---------------- {name} 0x{start:08X}..0x{end:08X} ----------------')
    for x in insns:
        if x.address < start: continue
        if x.address >= end: break
        mark='>>' if x.mnemonic in ('call','jmp') and x.operands and x.operands[0].type==CS_OP_IMM and (x.operands[0].imm & 0xffffffff) in TARGETS else '  '
        print(fmt(x,mark))

print('\nInterpretation targets:')
print('  1) The previous zero-ref result was a scanner bug; this probe decodes real CALL/JMP operands.')
print('  2) For each 0x84B01B caller, identify the slot argument immediately before the call.')
print('  3) Track how 0x8014F1 receives Type=6, name/string and endpoint pair in the same function.')
print('  4) Determine whether 0x98Axxx paths are remote join/update/deserialization paths for arbitrary slots 0..7.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'slot setter caller paths probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
