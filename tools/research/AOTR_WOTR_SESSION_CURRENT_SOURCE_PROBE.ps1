param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Focus:
#  - resolve C54CE0 vtable+0xC4 -> 0x84E5AF
#  - prove the exact non-NULL source written to session+0x44 at 0x98A366
#  - classify PATH_A (0x98A2FC) versus PATH_B (0x98A50D) current-pointer writes
#  - show literal/vtable references to these functions without modifying the game

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

$tempPy = Join-Path $env:TEMP ('a8p_session_current_source_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path=sys.argv[1]
IMAGE_BASE=0x00400000
SESSION_VT=0x00C54CE0
CURRENT_SOURCE=0x0084E5AF
PATH_A=0x0098A2FC
PATH_B=0x0098A50D
PATH_C=0x0098A7F1
CURRENT_WRITE=0x0098A366

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
            rel=rva-s['rva']
            if rel < s['rs']:
                return s['rp']+rel,s
    return None,None

def off_to_va(off):
    for s in secs:
        if s['rp'] <= off < s['rp']+s['rs']:
            return IMAGE_BASE+s['rva']+(off-s['rp']),s
    return None,None

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=False

def fmt(x,mark='  '):
    b=' '.join(f'{v:02X}' for v in x.bytes)
    return f'{mark} 0x{x.address:08X}: {b:<38} {x.mnemonic:<8} {x.op_str}'

def dump(start,size,label,marks=None):
    marks=marks or set()
    off,s=va_to_off(start)
    print('================ '+label+' ================')
    if off is None:
        print(f'<VA 0x{start:08X} unmapped>\n')
        return
    print(f'start=0x{start:08X} section={s["name"]} raw=0x{off:X}')
    end=min(s['rp']+s['rs'],off+size)
    for x in md.disasm(data[off:end],start):
        print(fmt(x,'>>' if x.address in marks else '  '))
    print('')

def direct_refs(target):
    out=[]
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        base=IMAGE_BASE+s['rva']
        for i in range(max(0,len(blob)-5)):
            if blob[i] not in (0xE8,0xE9): continue
            rel=struct.unpack_from('<i',blob,i+1)[0]
            src=base+i
            dst=(src+5+rel)&0xffffffff
            if dst==target:
                out.append((src,'CALL' if blob[i]==0xE8 else 'JMP',s['name']))
    return out

def literal_refs(target):
    pat=struct.pack('<I',target)
    out=[]; pos=0
    while True:
        j=data.find(pat,pos)
        if j<0: break
        va,s=off_to_va(j)
        out.append((j,va,s['name'] if s else '<unmapped>', bool(s and (s['ch'] & 0x20000000))))
        pos=j+1
    return out

print('============================================================')
print(' AOTR WOTR SESSION CURRENT SOURCE PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print(f'Session vtable   : 0x{SESSION_VT:08X}')
print(f'vtable +0xC4     : 0x{CURRENT_SOURCE:08X}')
print(f'PATH_A           : 0x{PATH_A:08X}')
print(f'PATH_B           : 0x{PATH_B:08X}')
print('')

vt_off,vt_sec=va_to_off(SESSION_VT)
if vt_off is None: raise SystemExit('Session vtable unmapped')
print('================ SESSION VTABLE CURRENT-RELATED SLOTS ================')
for slot in (0xB8,0xBC,0xC0,0xC4,0xC8,0xCC,0xFC,0x100):
    val=struct.unpack_from('<I',data,vt_off+slot)[0]
    tag=''
    if slot==0xC4: tag='  <<< CURRENT SOURCE'
    if val==PATH_A: tag+='  <<< PATH_A'
    if val==PATH_B: tag+='  <<< PATH_B'
    if val==PATH_C: tag+='  <<< PATH_C'
    print(f'  +0x{slot:03X} -> 0x{val:08X}{tag}')
print('')

dump(CURRENT_SOURCE,0x180,'VTABLE +0xC4 SOURCE 0x84E5AF',{CURRENT_SOURCE})
dump(PATH_A,0x230,'PATH_A LOCAL BIND / CURRENT SET',{PATH_A,CURRENT_WRITE})
dump(PATH_B,0x2E8,'PATH_B REMOVE / CURRENT CLEAR',{PATH_B,0x0098A5A7,0x0098A7C2})
dump(PATH_C,0x80,'PATH_C START BOUNDARY',{PATH_C})

print('================ DIRECT E8/E9 REFERENCES ================')
for name,target in (
    ('CURRENT_SOURCE_84E5AF',CURRENT_SOURCE),
    ('PATH_A_98A2FC',PATH_A),
    ('PATH_B_98A50D',PATH_B),
    ('PATH_C_98A7F1',PATH_C),
):
    refs=direct_refs(target)
    print(f'{name}: count={len(refs)}')
    for src,kind,sec in refs:
        print(f'  0x{src:08X} {kind} section={sec}')
print('')

print('================ RAW/LITERAL REFERENCES ================')
for name,target in (
    ('CURRENT_SOURCE_84E5AF',CURRENT_SOURCE),
    ('PATH_A_98A2FC',PATH_A),
    ('PATH_B_98A50D',PATH_B),
    ('PATH_C_98A7F1',PATH_C),
):
    refs=literal_refs(target)
    print(f'{name}: count={len(refs)}')
    for off,va,sec,execflag in refs:
        vas=f'0x{va:08X}' if va is not None else '<unmapped>'
        slot=''
        if va is not None and SESSION_VT <= va < SESSION_VT+0x200:
            slot=f' SESSION_VTABLE_SLOT=+0x{va-SESSION_VT:X}'
        print(f'  fileOff=0x{off:X} VA={vas} section={sec} exec={execflag}{slot}')
print('')

print('STATIC CHECKPOINT')
print('  At 0x98A35C the session virtual +0xC4 is called.')
print('  C54CE0 +0xC4 resolves to 0x84E5AF.')
print('  At 0x98A366 the returned EAX is written to session+0x44.')
print('  This probe classifies what 0x84E5AF returns and whether PATH_B only clears current.')
print('')
print('READ-ONLY COMPLETE. No file or process memory was modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw "session current source probe failed. Python exit=$LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}
