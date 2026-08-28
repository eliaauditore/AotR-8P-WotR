param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Focused follow-up after the 2026-08-28 two-machine packet trace proved that
# the controlled native Join Request leaves the VM and physically reaches the
# host, while the host produces no Type6 slot commit.  This probe does NOT
# patch or execute game code.  It maps the five known PATH_C ID=0x05 failure
# writes and the single ID=0x04 success write to their surrounding predicates.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) {
    throw "game.dat not found: $GameDat"
}
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) {
    throw "HASH MISMATCH. Expected $ExpectedHash, got $hash"
}

$py = Get-Command py.exe -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python.exe -ErrorAction SilentlyContinue }
if (-not $py) { throw 'Python not found.' }
$pyPath = $py.Source
& $pyPath -c "import capstone" 2>$null
if ($LASTEXITCODE -ne 0) {
    throw ('Python capstone missing. Install with: "{0}" -m pip install --user capstone' -f $pyPath)
}

$tempPy = Join-Path $env:TEMP ('a8p_pathc_id5_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86_const import X86_OP_IMM

path = sys.argv[1]
reported_hash = sys.argv[2]
IMAGE_BASE = 0x00400000
PATH_C_START = 0x0098A7F1
PATH_C_END   = 0x0098AF2C
SEND_CALL    = 0x0098AF02
SEND_HELPER  = 0x0084C257
FREE_PRED    = 0x004512D7

ANCHORS = [
    (0x0098A87D, 0x05, 'FAIL_1'),
    (0x0098A95A, 0x05, 'FAIL_2'),
    (0x0098AB5C, 0x05, 'FAIL_3'),
    (0x0098ABF6, 0x04, 'SUCCESS'),
    (0x0098ADE8, 0x05, 'FAIL_4'),
    (0x0098AE96, 0x05, 'FAIL_5'),
]
ANCHOR_BY_VA = {va:(mid,label) for va,mid,label in ANCHORS}

with open(path,'rb') as f:
    data=f.read()
if data[:2] != b'MZ':
    raise SystemExit('Not an MZ image')
pe=struct.unpack_from('<I',data,0x3c)[0]
if data[pe:pe+4] != b'PE\0\0':
    raise SystemExit('Bad PE signature')
num=struct.unpack_from('<H',data,pe+6)[0]
opt_size=struct.unpack_from('<H',data,pe+20)[0]
sec0=pe+24+opt_size
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
        if s['rva'] <= rva < s['rva'] + max(s['vs'],s['rs']):
            return s
    return None

def va_to_raw(va):
    s=sec_for_va(va)
    if not s:
        raise ValueError(f'VA 0x{va:08X} not in PE section')
    return s['rp'] + ((va-IMAGE_BASE)-s['rva']), s

def read_bytes(va,n):
    raw,s=va_to_raw(va)
    return data[raw:raw+n],s,raw

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=True

def disasm(start,end):
    b,s,raw=read_bytes(start,end-start)
    return list(md.disasm(b,start)),s,raw

def fmt(x,mark='  '):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<43} {x.mnemonic:<8} {x.op_str}'

def direct_target(x):
    if not x.operands:
        return None
    op=x.operands[0]
    if op.type == X86_OP_IMM:
        return op.imm & 0xffffffff
    return None

def is_jcc(x):
    return x.mnemonic.startswith('j') and x.mnemonic != 'jmp'

def is_direct_call(x):
    return x.mnemonic == 'call' and direct_target(x) is not None

ins,s,raw=disasm(PATH_C_START,PATH_C_END)
idx_by_va={x.address:i for i,x in enumerate(ins)}

print('============================================================')
print(' AOTR WOTR PATH_C ID5 FAILURE BRANCH PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash       : {reported_hash}')
print(f'PATH_C range     : 0x{PATH_C_START:08X}..0x{PATH_C_END:08X}')
print(f'Section/raw      : {s["name"]} / 0x{raw:X}')
print(f'Common send      : 0x{SEND_CALL:08X} -> 0x{SEND_HELPER:08X}')
print(f'Free predicate   : 0x{FREE_PRED:08X}')
print('')

print('================ MESSAGE WRITE ANCHOR VALIDATION ================')
for va,expected_id,label in ANCHORS:
    i=idx_by_va.get(va)
    if i is None:
        print(f'{label:<8} 0x{va:08X}: <NOT DECODED>')
        continue
    x=ins[i]
    raw_bytes=' '.join(f'{v:02X}' for v in x.bytes)
    print(f'{label:<8} ID=0x{expected_id:02X} 0x{va:08X}: {raw_bytes}  {x.mnemonic} {x.op_str}')
print('')

# Show the exact first-free success loop as a stable reference.
print('================ FIRST-FREE / ID4 SUCCESS REFERENCE ================')
for x in ins:
    if 0x0098ABCD <= x.address <= 0x0098AC30:
        mark='>>' if x.address in (FREE_PRED,0x0098ABE1,0x0098ABF6) else '  '
        print(fmt(x,mark))
print('')

# For each ID5 write, print enough synchronized context to see the condition,
# helper calls, cleanup and merge toward the common sender.
for anchor,mid,label in ANCHORS:
    if mid != 0x05:
        continue
    i=idx_by_va.get(anchor)
    print(f'================ {label} / ID5 @ 0x{anchor:08X} ================')
    if i is None:
        print('<anchor not decoded>\n')
        continue

    lo=max(0,i-42)
    hi=min(len(ins),i+28)
    for x in ins[lo:hi]:
        mark='>>' if x.address==anchor else '  '
        print(fmt(x,mark))

    print('\n-- conditional edges in local window --')
    win_lo=max(PATH_C_START,anchor-0x180)
    win_hi=min(PATH_C_END,anchor+0x80)
    found=False
    for x in ins:
        if not (win_lo <= x.address < win_hi) or not is_jcc(x):
            continue
        dst=direct_target(x)
        if dst is None:
            continue
        # Keep edges that land near this failure block, skip over it, or stay
        # in the same focused control-flow neighborhood.
        if (anchor-0x90 <= dst <= anchor+0x90) or (x.address <= anchor <= dst) or (dst <= anchor <= x.address):
            found=True
            print(f'  0x{x.address:08X} {x.mnemonic:<6} -> 0x{dst:08X}')
    if not found:
        print('  <none found in focused window>')

    print('\n-- direct calls in 0x120 bytes before through 0x40 after anchor --')
    calls=[]
    for x in ins:
        if anchor-0x120 <= x.address <= anchor+0x40 and is_direct_call(x):
            calls.append((x.address,direct_target(x)))
    if not calls:
        print('  <none>')
    else:
        for src,dst in calls:
            tags=[]
            if dst==FREE_PRED: tags.append('FREE_PREDICATE')
            if dst==SEND_HELPER: tags.append('SEND_HELPER')
            tag=(' ; '+','.join(tags)) if tags else ''
            sec=sec_for_va(dst)
            secname=sec['name'] if sec else '<outside-image>'
            print(f'  0x{src:08X} -> 0x{dst:08X} section={secname}{tag}')
    print('')

print('================ ALL PATH_C CONDITIONAL EDGES ================')
for x in ins:
    if not is_jcc(x):
        continue
    dst=direct_target(x)
    if dst is None:
        continue
    tags=[]
    for va,mid,label in ANCHORS:
        if abs(dst-va) <= 0x20:
            tags.append(f'near_{label}')
    if dst in (0x0098ABCD,0x0098ABF0):
        tags.append('first_free_success_region')
    print(f'  0x{x.address:08X} {x.mnemonic:<6} -> 0x{dst:08X}' + ((' ; '+','.join(tags)) if tags else ''))
print('')

print('================ DIRECT CALL MAP IN PATH_C ================')
seen=[]
for x in ins:
    if not is_direct_call(x):
        continue
    dst=direct_target(x)
    tags=[]
    if dst==FREE_PRED: tags.append('FREE_PREDICATE')
    if dst==SEND_HELPER: tags.append('SEND_HELPER')
    print(f'  0x{x.address:08X} -> 0x{dst:08X}' + ((' ; '+','.join(tags)) if tags else ''))
    if dst not in seen:
        seen.append(dst)
print('')

# Small entry excerpts of helpers called close to an ID5 write.  This is only
# a disassembly aid; no semantic label is assigned unless already proven.
near_targets=[]
for anchor,mid,label in ANCHORS:
    if mid != 0x05:
        continue
    for x in ins:
        if anchor-0x90 <= x.address <= anchor+0x20 and is_direct_call(x):
            dst=direct_target(x)
            if dst not in near_targets and sec_for_va(dst) and sec_for_va(dst)['name']=='.text':
                near_targets.append(dst)

print('================ NEAR-FAILURE HELPER ENTRY EXCERPTS ================')
for dst in near_targets:
    print(f'\n--- helper 0x{dst:08X} ---')
    try:
        h,s2,r2=disasm(dst,dst+0x70)
        for x in h[:28]:
            print(fmt(x,'>>' if x.address==dst else '  '))
            if x.mnemonic.startswith('ret'):
                break
    except Exception as e:
        print(f'<decode failed: {e}>')

print('\n================ INTERPRETATION TARGETS ================')
print('1) Assign the exact predicate/validation condition that leads to each of the five ID=0x05 writes.')
print('2) Identify which failures occur before the first-free loop and which occur after it.')
print('3) Preserve 0x4512D7 as the already-proven free-row predicate; do not relabel unknown helpers without evidence.')
print('4) Explain how a host with P2 Type0 can still reach an ID5 response before any Type6 slot commit.')
print('5) Do not revisit VMware/broadcast transport unless this control-flow evidence contradicts the packet trace.')
print('6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'PATH_C ID5 failure branch probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
