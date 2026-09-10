param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Follow-up to CLIENT_JOIN_FRONTEND_HANDOFF_PROBE.
# Resolves the state helpers reached from 0x8472BF after the real session +0x40 join call.

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

$tempPy = Join-Path $env:TEMP ('a8p_client_join_sm_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path=sys.argv[1]
IMAGE_BASE=0x00400000
TARGETS={
  0x00846C6D:'STATE_HELPER_A',
  0x00846CDE:'STATE_HELPER_B',
  0x00917C2D:'PRE_JOIN_UI_CALL',
  0x008472BF:'POST_JOIN_REFRESH',
  0x008487F2:'OTHER_POST_JOIN_CALLSITE',
  0x00849374:'REAL_SESSION_JOIN_CALLSITE',
}

with open(path,'rb') as f:data=f.read()
if data[:2]!=b'MZ': raise SystemExit('Not MZ')
pe=struct.unpack_from('<I',data,0x3c)[0]
if data[pe:pe+4]!=b'PE\0\0': raise SystemExit('Bad PE')
num=struct.unpack_from('<H',data,pe+6)[0]
opt=struct.unpack_from('<H',data,pe+20)[0]
sec0=pe+24+opt
secs=[]
for i in range(num):
    o=sec0+i*40
    name=data[o:o+8].split(b'\0',1)[0].decode('ascii','replace')
    vs,rva,rs,rp=struct.unpack_from('<IIII',data,o+8)
    ch=struct.unpack_from('<I',data,o+36)[0]
    secs.append(dict(name=name,vs=vs,rva=rva,rs=rs,rp=rp,ch=ch))

def va_to_raw(va):
    rva=va-IMAGE_BASE
    for s in secs:
        if s['rva'] <= rva < s['rva']+max(s['vs'],s['rs']):
            rel=rva-s['rva']
            if rel < s['rs']: return s['rp']+rel,s
    raise ValueError(hex(va))

def raw_to_va(raw,s): return IMAGE_BASE+s['rva']+(raw-s['rp'])

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=False

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<40} {x.mnemonic:<8} {x.op_str}'

def dump_from(va,n=0x180):
    raw,s=va_to_raw(va)
    blob=data[raw:min(raw+n,s['rp']+s['rs'])]
    for x in md.disasm(blob,va): print(fmt(x,'>>' if x.address==va else '  '))

def context(va,back=0x90,ahead=0x50):
    raw,s=va_to_raw(va)
    start=max(s['rp'],raw-back); end=min(s['rp']+s['rs'],raw+ahead)
    best=None
    for off in range(0,min(96,raw-start)+1):
        sr=start+off; sva=raw_to_va(sr,s)
        ins=list(md.disasm(data[sr:end],sva))
        if any(x.address==va for x in ins):
            best=ins; break
    if not best:
        print('<decode failed>'); return
    for x in best:
        if x.address < va-back//2: continue
        if x.address > va+ahead//2: break
        print(fmt(x,'>>' if x.address==va else '  '))

def direct_refs(target):
    out=[]
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        base=IMAGE_BASE+s['rva']
        for i in range(len(blob)-5):
            if blob[i] not in (0xE8,0xE9): continue
            rel=struct.unpack_from('<i',blob,i+1)[0]
            src=base+i; dst=(src+5+rel)&0xffffffff
            if dst==target: out.append((src,'CALL' if blob[i]==0xE8 else 'JMP',s['name']))
    return out

print('============================================================')
print(' AOTR WOTR CLIENT JOIN STATE MACHINE PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print('')

for va,name in TARGETS.items():
    print(f'================ XREFS {name} 0x{va:08X} ================')
    rr=direct_refs(va)
    print(f'count={len(rr)}')
    for src,k,sn in rr: print(f'  0x{src:08X} {k} section={sn}')
    print('')

for va,name,size in [
    (0x00846C6D,'STATE_HELPER_A',0x90),
    (0x00846CDE,'STATE_HELPER_B',0x90),
    (0x00917C2D,'PRE_JOIN_UI_CALL',0x100),
    (0x008487F2,'OTHER_POST_JOIN_CALLSITE_CONTEXT',0x120),
]:
    print(f'================ {name} ================')
    if name.endswith('CONTEXT'): context(va,0x120,0x100)
    else: dump_from(va,size)
    print('')

print('================ REAL JOIN CALLSITE STATE WINDOW ================')
context(0x00849374,0x120,0x90)
print('')

print('INTERPRETATION TARGETS')
print('  1) Classify 0x846C6D versus 0x846CDE (enable/disable, show/hide, state bits, etc.).')
print('  2) Determine what the pre-join 0x917C2D(1,1) call changes before session +0x40.')
print('  3) Compare the second caller of 0x8472BF at 0x8487F2 with the real join caller.')
print('  4) Identify writes to the frontend object around +0x6A4/+0x6B4 and any transition trigger that occurs only after a successful reply.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'client join state-machine probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
