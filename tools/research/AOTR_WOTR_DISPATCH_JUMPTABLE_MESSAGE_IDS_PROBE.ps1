param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Maps the proven C54CE0 +0x28 dispatcher jump table at 0x84DEC9.
# Resolves message IDs 0x00..0x13 to exact case targets and highlights
# REMOTE_TYPE6_CREATE, LOCAL_SLOT_BIND and SLOT_REMOVE_CLEAR cases.

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

$tempPy = Join-Path $env:TEMP ('a8p_dispatch_ids_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path=sys.argv[1]
IMAGE_BASE=0x00400000
DISPATCH=0x0084D787
JUMPTABLE=0x0084DEC9
CASE_COUNT=0x14

KNOWN_TARGETS={
    0x0084D8A5:'REMOTE_TYPE6_CREATE_CASE',
    0x0084D8B6:'LOCAL_SLOT_BIND_CASE',
    0x0084D8E1:'SLOT_REMOVE_CLEAR_CASE',
}
KNOWN_HELPERS={
    0x0098A7F1:'PATH_C_REMOTE_TYPE6_CREATE',
    0x0098A2FC:'PATH_A_LOCAL_SLOT_BIND',
    0x0098A50D:'PATH_B_SLOT_REMOVE_CLEAR',
}

with open(path,'rb') as f:
    data=f.read()
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
        span=max(s['vs'],s['rs'])
        if s['rva'] <= rva < s['rva']+span:
            return s
    return None

def va_to_raw(va):
    s=sec_for_va(va)
    if not s: raise ValueError(f'VA 0x{va:08X} not in PE section')
    return s['rp'] + ((va-IMAGE_BASE)-s['rva']), s

def read_u32(va):
    raw,s=va_to_raw(va)
    if raw+4 > len(data): raise ValueError('read beyond file')
    return struct.unpack_from('<I',data,raw)[0]

def read_bytes(va,n):
    raw,s=va_to_raw(va)
    return data[raw:raw+n],s,raw

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=True

def disasm_local(start,nbytes=96):
    b,s,raw=read_bytes(start,nbytes)
    return s,raw,list(md.disasm(b,start))

def fmt(x,mark='  '):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<38} {x.mnemonic:<8} {x.op_str}'

print('============================================================')
print(' AOTR WOTR DISPATCH JUMPTABLE / MESSAGE IDS - DISK ONLY')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print(f'Dispatch         : 0x{DISPATCH:08X}')
print(f'Jump table       : 0x{JUMPTABLE:08X}')
print(f'Case count       : {CASE_COUNT} (0x00..0x13)')
print('')

# Validate the dispatcher switch bytes around the indirect jump.
print('================ DISPATCH SWITCH VALIDATION ================')
s,raw,ins=disasm_local(0x0084D848,0x28)
print(f'section={s["name"]} raw=0x{raw:X}')
for x in ins:
    print(fmt(x,'>>' if x.address==0x0084D85A else '  '))
print('')

print('================ MESSAGE ID -> CASE TARGET ================')
entries=[]
for i in range(CASE_COUNT):
    entry_va=JUMPTABLE+i*4
    target=read_u32(entry_va)
    label=KNOWN_TARGETS.get(target,'')
    entries.append((i,entry_va,target,label))
    sec=sec_for_va(target)
    secname=sec['name'] if sec else '<none>'
    suffix=f'  << {label}' if label else ''
    print(f'ID 0x{i:02X} ({i:2d})  table@0x{entry_va:08X} -> 0x{target:08X}  section={secname}{suffix}')
print('')

print('================ PROVEN JOIN MESSAGE IDS ================')
for wanted,label in [
    (0x0084D8A5,'REMOTE_TYPE6_CREATE'),
    (0x0084D8B6,'LOCAL_SLOT_BIND'),
    (0x0084D8E1,'SLOT_REMOVE_CLEAR'),
]:
    ids=[i for i,_,t,_ in entries if t==wanted]
    print(f'{label:<24} caseTarget=0x{wanted:08X} messageIDs=' + (','.join(f'0x{x:02X}' for x in ids) if ids else '<NONE>'))
print('')

print('================ UNIQUE CASE TARGET WINDOWS ================')
seen=set()
for i,entry_va,target,label in entries:
    if target in seen: continue
    seen.add(target)
    try:
        s,raw,ins=disasm_local(target,0x28)
    except Exception as e:
        print(f'\n--- target 0x{target:08X} ERROR: {e} ---')
        continue
    ids=[j for j,_,t,_ in entries if t==target]
    idtxt=','.join(f'0x{x:02X}' for x in ids)
    known=KNOWN_TARGETS.get(target,'')
    print(f'\n--- IDs {idtxt} -> 0x{target:08X} {known} section={s["name"]} raw=0x{raw:X} ---')
    for x in ins:
        mark='>>' if x.address==target else '  '
        print(fmt(x,mark))

print('\n================ KNOWN HELPER DIRECT CALL VALIDATION ================')
# Validate the three proven handler callsites again so the ID mapping and helper mapping
# are tied together in one output.
checks=[
    (0x0084D8AC,0x0098A7F1,'REMOTE_TYPE6_CREATE'),
    (0x0084D8C6,0x0098A2FC,'LOCAL_SLOT_BIND'),
    (0x0084D8EF,0x0098A50D,'SLOT_REMOVE_CLEAR'),
]
for callsite,expected,label in checks:
    b,s,raw=read_bytes(callsite,5)
    if len(b)<5:
        print(f'{label}: short read')
        continue
    op=b[0]
    disp=struct.unpack_from('<i',b,1)[0]
    dst=(callsite+5+disp)&0xffffffff if op in (0xE8,0xE9) else None
    print(f'{label:<24} 0x{callsite:08X} [{s["name"]}] bytes={" ".join(f"{v:02X}" for v in b)} decoded={"0x%08X"%dst if dst is not None else "<not E8/E9>"} expected=0x{expected:08X} match={dst==expected}')

print('\nInterpretation targets:')
print('  1) Assign exact message IDs to REMOTE_TYPE6_CREATE, LOCAL_SLOT_BIND and SLOT_REMOVE_CLEAR.')
print('  2) Check whether multiple IDs alias to the same case target.')
print('  3) Keep handler-call validation tied to the jump-table mapping.')
print('  4) Use the resolved IDs in the next producer/sender trace; do not guess event numbers.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'dispatch jumptable/message-id probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
