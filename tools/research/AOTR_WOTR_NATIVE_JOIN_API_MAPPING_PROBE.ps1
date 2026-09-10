param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Maps the now-proven local-slot bind / remote-network-human create / remove paths
# onto the native C54CE0 session vtable and validates the exact free-slot and
# GameInfo row getter helpers used by the remote create path.

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

$tempPy = Join-Path $env:TEMP ('a8p_native_join_api_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path=sys.argv[1]
IMAGE_BASE=0x00400000
VTABLE=0x00C54CE0
PATHS={
    0x0098A2FC:'PATH_A_LOCAL_SLOT_BIND',
    0x0098A50D:'PATH_B_SLOT_REMOVE_CLEAR',
    0x0098A7F1:'PATH_C_REMOTE_TYPE6_CREATE',
}
HELPERS={
    0x004512D7:'FREE_SLOT_PREDICATE',
    0x0084A419:'GAMEINFO_GET_ROW',
    0x0084B01B:'GAMEINFO_SLOT_SETTER',
    0x008014F1:'PLAYERINFO_ASSIGN',
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

def dword_refs(target):
    pat=struct.pack('<I',target)
    out=[]; p=0
    while True:
        p=data.find(pat,p)
        if p<0: break
        va,s=off_to_va(p)
        out.append((p,va,s['name'] if s else '<headers/unmapped>'))
        p+=1
    return out

def rel32_refs(target):
    out=[]
    for s in secs:
        if not (s['ch'] & 0x20000000):
            continue
        blob=data[s['rp']:s['rp']+s['rs']]
        base=IMAGE_BASE+s['rva']
        for i in range(0,max(0,len(blob)-5)):
            op=blob[i]
            if op not in (0xE8,0xE9): continue
            rel=struct.unpack_from('<i',blob,i+1)[0]
            src=base+i
            dst=(src+5+rel)&0xffffffff
            if dst==target:
                out.append((src,'CALL' if op==0xE8 else 'JMP',s['name']))
    return out

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=True

def disasm_local(start, size=0x180):
    off,s=va_to_off(start)
    if off is None:
        print(f'<VA 0x{start:08X} unmapped>')
        return
    end=min(len(data),off+size)
    print(f'section={s["name"]} raw=0x{off:X}')
    for x in md.disasm(data[off:end],start):
        b=' '.join(f'{v:02X}' for v in x.bytes)
        print(f'  0x{x.address:08X}: {b:<34} {x.mnemonic:<8} {x.op_str}')

print('============================================================')
print(' AOTR WOTR NATIVE JOIN API MAPPING PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print('')

print('================ C54CE0 VTABLE PATH MAPPING ================')
voff,vs=va_to_off(VTABLE)
if voff is None:
    print('C54CE0 vtable unmapped')
else:
    print(f'Vtable 0x{VTABLE:08X} section={vs["name"]} raw=0x{voff:X}')
    for off in range(0,0x120,4):
        val=struct.unpack_from('<I',data,voff+off)[0]
        tag=''
        if val in PATHS: tag='  <<< '+PATHS[val]
        elif val in HELPERS: tag='  <<< '+HELPERS[val]
        print(f'+0x{off:03X} -> 0x{val:08X}{tag}')

print('\n================ ALL DWORD REFS TO PATH FUNCTIONS ================')
for target,name in PATHS.items():
    refs=dword_refs(target)
    print(f'{name} 0x{target:08X}: {len(refs)} literal refs')
    for off,va,sec in refs:
        vas='0x%08X'%va if va is not None else '<unmapped>'
        vslot=''
        if va is not None and VTABLE <= va < VTABLE+0x200:
            vslot=f'  VTABLE_SLOT=+0x{va-VTABLE:X}'
        print(f'  fileOff=0x{off:X} VA={vas} section={sec}{vslot}')
    crefs=rel32_refs(target)
    print(f'  direct E8/E9 refs: {len(crefs)}')
    for src,kind,sec in crefs:
        print(f'    0x{src:08X} {kind} section={sec}')
    print('')

print('================ FREE SLOT PREDICATE 0x004512D7 ================')
disasm_local(0x004512D7,0x80)

print('\n================ GAMEINFO GET ROW 0x0084A419 ================')
disasm_local(0x0084A419,0x90)

print('\n================ GAMEINFO SLOT SETTER 0x0084B01B ================')
disasm_local(0x0084B01B,0x90)

print('\n================ PATH_C REMOTE CREATE CRITICAL WINDOW ================')
# Start at free-slot scan and continue through Type6 construction + slot setter.
disasm_local(0x0098ABBF,0x230)

print('\n================ PATH_A LOCAL BIND CRITICAL WINDOW ================')
# Shows message+0x4C -> slot and local endpoint -> PlayerInfo +0x38/+0x3C.
disasm_local(0x0098A3D7,0xC0)

print('\nInterpretation targets:')
print('  1) Resolve PATH_A / PATH_B / PATH_C to exact C54CE0 vtable slots where present.')
print('  2) Confirm 0x4512D7 is the Type0/free-row predicate used by PATH_C.')
print('  3) Confirm 0x84A419 indexes GameInfo rows 0..7 with stride 0x1DC.')
print('  4) Confirm PATH_C constructs Type6 with remote endpoint then commits via 0x84B01B.')
print('  5) Confirm PATH_A consumes assigned slot from message+0x4C and binds local endpoint.')
print('  6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'native join API mapping probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
