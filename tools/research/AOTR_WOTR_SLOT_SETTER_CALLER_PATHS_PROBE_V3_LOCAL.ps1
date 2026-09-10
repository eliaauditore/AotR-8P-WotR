param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# V3 deliberately avoids whole-.text linear disassembly. Capstone can stop on
# undecodable/embedded data long before the 0x98Axxx region. We instead map
# each known VA directly to its PE raw offset, byte-validate the anchor CALLs,
# and disassemble forward from already-proven instruction boundaries.

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

$tempPy = Join-Path $env:TEMP ('a8p_slot_setter_v3_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_OP_IMM

path=sys.argv[1]
IMAGE_BASE=0x00400000
TARGETS={
    0x0084B01B:'GAMEINFO_SLOT_SETTER',
    0x008014F1:'PLAYERINFO_ASSIGN',
    0x0084DF19:'PLAYERINFO_STACK_COPY',
    0x00649242:'PLAYERINFO_HELPER_A',
    0x00649279:'PLAYERINFO_HELPER_B',
}
KNOWN={
    0x0098A40E:0x008014F1,
    0x0098A446:0x00649242,
    0x0098A460:0x00649279,
    0x0098A477:0x0084DF19,
    0x0098A482:0x0084B01B,
    0x0098A6BB:0x008014F1,
    0x0098A6D2:0x0084DF19,
    0x0098A6DD:0x0084B01B,
    0x0098A736:0x008014F1,
    0x0098ACB2:0x008014F1,
    0x0098AD94:0x0084DF19,
    0x0098AD9D:0x0084B01B,
}
PATHS=[
    ('PATH_A',0x0098A40E,0x0098A4F0,[0x0098A40E,0x0098A446,0x0098A460,0x0098A477,0x0098A482]),
    ('PATH_B',0x0098A6BB,0x0098A770,[0x0098A6BB,0x0098A6D2,0x0098A6DD,0x0098A736]),
    ('PATH_C',0x0098ACB2,0x0098ADE0,[0x0098ACB2,0x0098AD94,0x0098AD9D]),
]

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

def va_to_off(va):
    rva=va-IMAGE_BASE
    for s in secs:
        span=max(s['vs'],s['rs'])
        if s['rva'] <= rva < s['rva']+span:
            off=s['rp']+(rva-s['rva'])
            if off < len(data): return off,s
    return None,None

def read_va(start,end):
    off,s=va_to_off(start)
    if off is None: raise RuntimeError(f'VA 0x{start:08X} unmapped')
    off2,s2=va_to_off(end-1)
    if off2 is None or s2 is not s: raise RuntimeError(f'range 0x{start:08X}..0x{end:08X} crosses/unmaps section')
    return data[off:off+(end-start)],s

def decode_rel32(site):
    b,_=read_va(site,site+5)
    if b[0] not in (0xE8,0xE9): return b[0],None,b
    rel=struct.unpack_from('<i',b,1)[0]
    return b[0],(site+5+rel)&0xffffffff,b

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=True

print('============================================================')
print(' AOTR WOTR SLOT SETTER CALLER PATHS V3 - LOCAL DISASM')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print('')
print('================ ANCHOR BYTE VALIDATION ================')
all_ok=True
for site,expected in KNOWN.items():
    op,dst,b=decode_rel32(site)
    ok=(op==0xE8 and dst==expected)
    all_ok &= ok
    sec=va_to_off(site)[1]
    print(f'0x{site:08X} [{sec["name"] if sec else "?"}] bytes={" ".join(f"{x:02X}" for x in b)} decoded={"0x%08X"%dst if dst is not None else "<not rel32>"} expected=0x{expected:08X} match={ok}')
print(f'ANCHOR VALIDATION PASS : {all_ok}')

# Show raw bytes immediately before every Type6/slot-setter anchor. This is
# useful even if the preceding x86 instruction boundary is ambiguous.
print('\n================ RAW PRE-CALL BYTES ================')
for site in sorted(KNOWN):
    if KNOWN[site] not in (0x008014F1,0x0084B01B): continue
    start=site-32
    b,_=read_va(start,site+5)
    print(f'0x{site:08X} -> {TARGETS.get(KNOWN[site],hex(KNOWN[site]))}')
    print(f'  VA 0x{start:08X}: '+ ' '.join(f'{x:02X}' for x in b))

# Because each path starts at an already byte-proven CALL instruction, the
# forward stream is synchronized at a real instruction boundary.
print('\n================ SYNCHRONIZED LOCAL PATHS ================')
for name,start,end,anchors in PATHS:
    print(f'\n---------------- {name} 0x{start:08X}..0x{end:08X} ----------------')
    blob,sec=read_va(start,end)
    print(f'section={sec["name"]} rawStart=0x{va_to_off(start)[0]:X}')
    ins=list(md.disasm(blob,start))
    if not ins:
        print('<no instructions decoded from proven anchor>')
        continue
    anchor_set=set(anchors)
    for x in ins:
        mark='>>' if x.address in anchor_set else '  '
        bs=' '.join(f'{v:02X}' for v in x.bytes)
        extra=''
        if x.mnemonic in ('call','jmp') and x.operands and x.operands[0].type==CS_OP_IMM:
            dst=x.operands[0].imm & 0xffffffff
            if dst in TARGETS: extra=' ; '+TARGETS[dst]
        print(f'{mark} 0x{x.address:08X}: {bs:<34} {x.mnemonic:<8} {x.op_str}{extra}')
        # If Capstone stops before end, the last printed address exposes it.
    last=ins[-1]
    print(f'lastDecodedEnd=0x{last.address+last.size:08X} requestedEnd=0x{end:08X}')

# Backward predecessor candidates for the four setter calls. x86 has no native
# reverse decode, so report every single instruction within 15 bytes that ends
# exactly at the callsite. The real immediate predecessor will be among them.
print('\n================ SLOT-SETTER IMMEDIATE PREDECESSOR CANDIDATES ================')
for site in (0x0084E38B,0x0098A482,0x0098A6DD,0x0098AD9D):
    print(f'\nsetter callsite 0x{site:08X}')
    found=[]
    for d in range(1,16):
        st=site-d
        try: blob,_=read_va(st,site)
        except: continue
        one=list(md.disasm(blob,st,count=1))
        if one and one[0].address==st and one[0].address+one[0].size==site:
            found.append(one[0])
    for x in found:
        bs=' '.join(f'{v:02X}' for v in x.bytes)
        print(f'  0x{x.address:08X}: {bs:<34} {x.mnemonic:<8} {x.op_str}')
    if not found: print('  <none>')

print('\nInterpretation targets:')
print('  1) Read the three 0x98Axxx paths from proven instruction anchors, not from section start.')
print('  2) Around each 0x8014F1 call, identify pushed Type=6, name/string, and endpoint argument.')
print('  3) Around each 0x84B01B call, identify the slot argument passed immediately before the PlayerInfo value blob.')
print('  4) Determine whether PATH_A/B/C are native remote create/update/deserialization flows for arbitrary slots.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'slot setter caller paths V3 probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
