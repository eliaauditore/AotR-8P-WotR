param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Traces the proven C54CE0 vtable +0x6C method (0x0084E1F4), focusing on
# the origin/lifecycle of EDI before it is published to session+0x44 at
# 0x0084E3E1, and traces the immediate post-publish helper 0x0084DF84.
# No file or process memory is modified.

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

$tempPy = Join-Path $env:TEMP ('a8p_publish_edi_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86 import X86_OP_REG, X86_REG_EDI

path=sys.argv[1]
IMAGE_BASE=0x00400000
METHOD=0x0084E1F4
METHOD_END=0x0084E5AF
PUBLISH=0x0084E3E1
POST=0x0084DF84
POST_END=0x0084E135

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
    secs.append(dict(name=name,rva=rva,vs=vs,rp=rp,rs=rs))

def va_to_off(va):
    rva=va-IMAGE_BASE
    for s in secs:
        span=max(s['vs'],s['rs'])
        if s['rva'] <= rva < s['rva']+span:
            return s['rp']+(rva-s['rva']),s
    return None,None

def read_range(start,end):
    o,s=va_to_off(start)
    if o is None: raise RuntimeError(f'VA not mapped: 0x{start:08X}')
    return data[o:o+(end-start)]

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=True

method_ins=list(md.disasm(read_range(METHOD,METHOD_END),METHOD))
post_ins=list(md.disasm(read_range(POST,POST_END),POST))

print('============================================================')
print(' AOTR WOTR SESSION PUBLISH EDI ORIGIN TRACE - DISK ONLY')
print('============================================================')
print(f'Image hash          : {sys.argv[2]}')
print(f'Session method +0x6C: 0x{METHOD:08X}')
print(f'Publish instruction : 0x{PUBLISH:08X}  mov [esi+0x44],edi')
print(f'Post-publish helper : 0x{POST:08X}')
print('')

print('================ METHOD 0x0084E1F4 FULL TRACE ================')
for ins in method_ins:
    mark='>>' if ins.address==PUBLISH else '  '
    b=' '.join(f'{x:02X}' for x in ins.bytes)
    print(f'{mark} 0x{ins.address:08X}: {b:<32} {ins.mnemonic:<8} {ins.op_str}')

print('')
print('================ EDI DEFINITIONS BEFORE PUBLISH ================')
edi_defs=[]
for ins in method_ins:
    if ins.address >= PUBLISH: break
    if not ins.operands: continue
    op0=ins.operands[0]
    if op0.type==X86_OP_REG and op0.reg==X86_REG_EDI:
        edi_defs.append(ins)
for ins in edi_defs:
    b=' '.join(f'{x:02X}' for x in ins.bytes)
    print(f'0x{ins.address:08X}: {b:<32} {ins.mnemonic:<8} {ins.op_str}')
if not edi_defs: print('<none>')

print('')
print('================ CALLS BEFORE PUBLISH ================')
for ins in method_ins:
    if ins.address >= PUBLISH: break
    if ins.mnemonic in ('call','jmp'):
        b=' '.join(f'{x:02X}' for x in ins.bytes)
        print(f'0x{ins.address:08X}: {b:<32} {ins.mnemonic:<8} {ins.op_str}')

print('')
print('================ PUBLISH NEIGHBORHOOD ================')
idx=next((i for i,x in enumerate(method_ins) if x.address==PUBLISH),None)
if idx is None:
    print('Publish instruction not decoded at expected VA.')
else:
    for ins in method_ins[max(0,idx-20):min(len(method_ins),idx+24)]:
        mark='>>' if ins.address==PUBLISH else '  '
        b=' '.join(f'{x:02X}' for x in ins.bytes)
        print(f'{mark} 0x{ins.address:08X}: {b:<32} {ins.mnemonic:<8} {ins.op_str}')

print('')
print('================ POST-PUBLISH HELPER 0x0084DF84 TRACE ================')
for ins in post_ins:
    b=' '.join(f'{x:02X}' for x in ins.bytes)
    print(f'   0x{ins.address:08X}: {b:<32} {ins.mnemonic:<8} {ins.op_str}')
    if ins.mnemonic=='ret':
        # Do not stop globally; a nearby helper can contain internal ret paths.
        pass

# Direct E8/E9 xrefs to the method and post helper in .text.
text=next(s for s in secs if s['name']=='.text')
text_va=IMAGE_BASE+text['rva']
text_blob=data[text['rp']:text['rp']+text['rs']]

def rel_refs(target):
    out=[]
    for i in range(len(text_blob)-5):
        op=text_blob[i]
        if op not in (0xE8,0xE9): continue
        rel=struct.unpack_from('<i',text_blob,i+1)[0]
        src=text_va+i
        dst=(src+5+rel)&0xffffffff
        if dst==target: out.append((src,op))
    return out

print('')
print('================ DIRECT REFS TO METHOD +0x6C ================')
refs=rel_refs(METHOD)
print(f'Count: {len(refs)}')
for src,op in refs:
    print(f'0x{src:08X} {"CALL" if op==0xE8 else "JMP"} -> 0x{METHOD:08X}')

print('')
print('================ DIRECT REFS TO POST HELPER ================')
refs=rel_refs(POST)
print(f'Count: {len(refs)}')
for src,op in refs:
    print(f'0x{src:08X} {"CALL" if op==0xE8 else "JMP"} -> 0x{POST:08X}')

print('')
print('Interpretation targets:')
print('  1) Identify the final definition/source of EDI before 0x0084E3E1.')
print('  2) Determine whether EDI is allocated/constructed in this method or supplied by a helper/caller.')
print('  3) Determine what 0x0084DF84 does to the newly published GameInfo.')
print('  4) Keep clears/destructors separate from the non-null publish path.')
print('  5) No bytes are modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'session publish EDI origin trace failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
