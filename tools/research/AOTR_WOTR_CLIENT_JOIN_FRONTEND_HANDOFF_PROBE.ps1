param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Narrows the proven native WotR join caller around 0x00849374 and the
# immediately adjacent selector/post-join functions. No process memory writes.

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

$tempPy = Join-Path $env:TEMP ('a8p_client_join_handoff_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path=sys.argv[1]
IMAGE_BASE=0x00400000
JOIN_CALL=0x00849374
SELECTOR=0x00846D4F
POST_JOIN=0x008472BF
SESSION_GLOBAL=0x00DE4394
THE_GAMEINFO=0x00DE7D6C
NETWORK_GI=0x00DE892C

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

def va_to_raw(va):
    rva=va-IMAGE_BASE
    for s in secs:
        if s['rva'] <= rva < s['rva']+max(s['vs'],s['rs']):
            rel=rva-s['rva']
            if rel < s['rs']: return s['rp']+rel,s
    raise ValueError(f'VA 0x{va:08X} not mapped')

def raw_to_va(raw,s):
    return IMAGE_BASE+s['rva']+(raw-s['rp'])

def read_bytes(va,n):
    raw,s=va_to_raw(va)
    return data[raw:raw+n],s,raw

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=False

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<38} {x.mnemonic:<8} {x.op_str}'

def direct_refs(target):
    out=[]
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        base=IMAGE_BASE+s['rva']
        for i in range(0,max(0,len(blob)-5)):
            op=blob[i]
            if op not in (0xE8,0xE9): continue
            rel=struct.unpack_from('<i',blob,i+1)[0]
            src=base+i
            dst=(src+5+rel)&0xffffffff
            if dst==target: out.append((src,'CALL' if op==0xE8 else 'JMP',s['name']))
    return out

def synced_context(target,back=0x180,ahead=0x100):
    raw_t,s=va_to_raw(target)
    raw_lo=max(s['rp'],raw_t-back)
    raw_hi=min(s['rp']+s['rs'],raw_t+ahead)
    best=None
    # Try many candidate starts. Keep streams that land exactly on target.
    for raw_start in range(raw_lo,raw_t+1):
        sva=raw_to_va(raw_start,s)
        ins=list(md.disasm(data[raw_start:raw_hi],sva))
        idx=next((i for i,x in enumerate(ins) if x.address==target),None)
        if idx is None: continue
        crossed=sum(1 for x in ins[:idx] if x.mnemonic.startswith('ret'))
        score=(0 if crossed else 1, idx)
        if best is None or score>best[0]: best=(score,ins,idx)
    return best

def dump_context(title,target,back=0x180,ahead=0x100,pre=45,post=35):
    print('')
    print('================ '+title+' ================')
    print(f'target=0x{target:08X}')
    w=synced_context(target,back,ahead)
    if not w:
        print('<could not synchronize disassembly>')
        b,s,raw=read_bytes(target-back,min(back+ahead,len(data)-raw if False else back+ahead))
        print('raw fallback:', ' '.join(f'{v:02X}' for v in b[:256]))
        return
    _,ins,idx=w
    lo=max(0,idx-pre); hi=min(len(ins),idx+post+1)
    for j in range(lo,hi):
        print(fmt(ins[j],'>>' if j==idx else '  '))

def dump_body(title,start,maxlen=0x380):
    print('')
    print('================ '+title+' ================')
    print(f'entry=0x{start:08X}')
    b,s,raw=read_bytes(start,maxlen)
    ins=list(md.disasm(b,start))
    rets=0
    for x in ins:
        mark='>>' if x.address==start else '  '
        print(fmt(x,mark))
        if x.mnemonic.startswith('ret'):
            rets+=1
            if rets>=2: break

def print_refs(title,target):
    refs=direct_refs(target)
    print('')
    print('================ DIRECT XREFS TO '+title+' ================')
    print(f'target=0x{target:08X} count={len(refs)}')
    for src,kind,sn in refs:
        print(f'  0x{src:08X} {kind} section={sn}')

print('============================================================')
print(' AOTR WOTR CLIENT JOIN FRONTEND HANDOFF PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash      : {sys.argv[2]}')
print(f'Session global  : 0x{SESSION_GLOBAL:08X}')
print(f'Join callsite   : 0x{JOIN_CALL:08X}')
print(f'Select function : 0x{SELECTOR:08X}')
print(f'Post-join func  : 0x{POST_JOIN:08X}')
print(f'TheGameInfo     : 0x{THE_GAMEINFO:08X}')
print(f'NetworkGI       : 0x{NETWORK_GI:08X}')

anchor,_,_=read_bytes(JOIN_CALL,3)
print('')
print('JOIN CALLSITE BYTE VALIDATION')
print('  bytes    : '+ ' '.join(f'{b:02X}' for b in anchor))
print('  expected : FF 50 40')
print('  match    : '+str(anchor==b'\xFF\x50\x40'))
if anchor!=b'\xFF\x50\x40': raise SystemExit('Join callsite bytes do not match expected vtable+0x40 call')

dump_context('PROVEN REAL SESSION +0x40 CALLSITE',JOIN_CALL,0x260,0x180,65,55)
print_refs('SELECTOR 0x846D4F',SELECTOR)
print_refs('POST_JOIN 0x8472BF',POST_JOIN)
dump_body('SELECTOR BODY 0x846D4F',SELECTOR,0x300)
dump_body('POST_JOIN BODY 0x8472BF',POST_JOIN,0x500)

print('')
print('INTERPRETATION TARGETS')
print('  1) Confirm 0x849374 is reached with ECX=[0xDE4394], arg1=selected GameInfo and arg2={0,0} endpoint sentinel.')
print('  2) Identify what 0x846D4F returns and how the selected remote GameInfo is chosen.')
print('  3) Identify every state/global/frontend write performed by 0x8472BF immediately after the native join call.')
print('  4) Specifically watch for writes/calls tied to 0xDE7D6C (TheGameInfo), 0xDE892C (NetworkGI), screen transitions, lobby mode/state, or Ready enablement.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'client join frontend handoff probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
