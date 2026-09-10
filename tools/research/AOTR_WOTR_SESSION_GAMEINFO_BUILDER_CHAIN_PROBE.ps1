param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Traces the proven C54CE0 +0x6C GameInfo creation path and the helper chain that
# constructs/populates the new 0xFCC GameInfo before session+0x44 publication.

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

$tempPy = Join-Path $env:TEMP ('a8p_builder_chain_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_OP_MEM

path=sys.argv[1]
IMAGE_BASE=0x00400000
TARGETS=[
    (0x0084AEA1,'GAMEINFO_CTOR_0x84AEA1',0x260),
    (0x0084B01B,'GAMEINFO_POSTCONSTRUCT_0x84B01B',0x220),
    (0x0084DF19,'PLAYERINFO_STACK_COPY_0x84DF19',0x180),
    (0x00649242,'PLAYERINFO_HELPER_A_0x649242',0x180),
    (0x00649279,'PLAYERINFO_HELPER_B_0x649279',0x180),
    (0x0084A86A,'GAMEINFO_FINALIZE_0x84A86A',0x180),
    (0x00800B1E,'GAMEINFO_INIT_0x800B1E',0x160),
    (0x008014F1,'PLAYERINFO_ASSIGN_0x8014F1',0x180),
]
SESSION_METHOD=0x0084E1F4
SESSION_GLOBAL=0x00DE4394

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

def va_to_off(va):
    rva=va-IMAGE_BASE
    for s in secs:
        span=max(s['vs'],s['rs'])
        if s['rva'] <= rva < s['rva']+span:
            return s['rp']+(rva-s['rva']),s
    return None,None

text=next(s for s in secs if s['name']=='.text')
text_blob=data[text['rp']:text['rp']+text['rs']]
text_va=IMAGE_BASE+text['rva']
text_end=text_va+text['rs']

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=True

print('============================================================')
print(' AOTR WOTR SESSION GAMEINFO BUILDER CHAIN PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash          : {sys.argv[2]}')
print(f'Session method +0x6C: 0x{SESSION_METHOD:08X}')
print('Known allocation     : 0xFCC bytes')
print('Known publish        : [session+0x44] = EDI')
print('')

# Dump bounded traces for the key helper chain.
for va,name,span in TARGETS:
    off,sec=va_to_off(va)
    print(f'================ {name} ================')
    if off is None:
        print('VA not mapped')
        print('')
        continue
    blob=data[off:off+span]
    count=0
    for ins in md.disasm(blob,va):
        b=' '.join(f'{x:02X}' for x in ins.bytes)
        print(f'0x{ins.address:08X}: {b:<32} {ins.mnemonic:<8} {ins.op_str}')
        count+=1
        # Stop at a convincing function return after at least a few instructions.
        if count>8 and ins.mnemonic.startswith('ret'):
            break
    print('')

# Exact direct E8/E9 refs to helper targets.
print('================ DIRECT E8/E9 REFS TO BUILDER HELPERS ================')
for target,name,_ in TARGETS:
    refs=[]
    for i in range(0,len(text_blob)-5):
        op=text_blob[i]
        if op not in (0xE8,0xE9):
            continue
        rel=struct.unpack_from('<i',text_blob,i+1)[0]
        src=text_va+i
        dst=(src+5+rel)&0xffffffff
        if dst==target:
            refs.append((src,'CALL' if op==0xE8 else 'JMP'))
    print(f'{name}: {len(refs)} refs')
    for src,kind in refs[:40]:
        print(f'  0x{src:08X} {kind} -> 0x{target:08X}')
print('')

# Scan all instructions for direct virtual calls/jumps through +0x6C.
print('================ INDIRECT VTABLE DISPATCH +0x6C ================')
all_ins=list(md.disasm(text_blob,text_va))
hits=[]
for idx,ins in enumerate(all_ins):
    if ins.mnemonic not in ('call','jmp'):
        continue
    for op in ins.operands:
        if op.type==CS_OP_MEM and op.mem.disp==0x6c:
            hits.append(idx)
            break
print(f'Count: {len(hits)}')
for n,idx in enumerate(hits,1):
    ins=all_ins[idx]
    print(f'--- +0x6C DISPATCH #{n}: 0x{ins.address:08X} {ins.mnemonic} {ins.op_str} ---')
    for j in range(max(0,idx-10),min(len(all_ins),idx+8)):
        x=all_ins[j]
        mark='>>' if j==idx else '  '
        b=' '.join(f'{v:02X}' for v in x.bytes)
        print(f'{mark} 0x{x.address:08X}: {b:<30} {x.mnemonic:<8} {x.op_str}')
    print('')

# Session-global-nearby +0x6C dispatch candidates: search local windows for literal DE4394.
print('================ SESSION GLOBAL NEAR +0x6C DISPATCH ================')
pat=struct.pack('<I',SESSION_GLOBAL)
for idx in hits:
    ins=all_ins[idx]
    start=max(text_va,ins.address-0x80)
    end=min(text_end,ins.address+0x20)
    s_off=start-text_va; e_off=end-text_va
    if pat in text_blob[s_off:e_off]:
        print(f'candidate dispatch at 0x{ins.address:08X}: {ins.mnemonic} {ins.op_str}')
print('')

print('Interpretation targets:')
print('  1) Confirm exact 0xFCC object constructor layout/vtable in 0x84AEA1.')
print('  2) Identify how the temporary Type6 PlayerInfo reaches the new GameInfo.')
print('  3) Identify endpoint/name/slot fields written by 0x649242 / 0x649279 / 0x84B01B.')
print('  4) Identify native call sites that invoke session vtable +0x6C.')
print('  5) No bytes are modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'session GameInfo builder chain probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
