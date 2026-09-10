param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Focused static trace for the proven direct writers of:
#   DE892C NetworkGI
#   DE8930 alternate GI pointer
#   DE7D6C TheGameInfo
# Writer sites were established by the robust byte-xref probe.

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

$tempPy = Join-Path $env:TEMP ('a8p_network_gi_writer_path_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
WRITERS={
  0x0078853D:'THE_GAMEINFO_WRITE_78853D',
  0x00788542:'NETWORK_GI_WRITE_788542',
  0x0082BE92:'NETWORK_GI_ALT_WRITE_82BE92',
  0x0082BE97:'NETWORK_GI_WRITE_82BE97',
}
TARGETS={
  0x00DE892C:'NETWORK_GI_DE892C',
  0x00DE8930:'NETWORK_GI_ALT_DE8930',
  0x00DE7D6C:'THE_GAMEINFO_DE7D6C',
  0x00DE4394:'SESSION_GLOBAL_DE4394',
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

def va_to_raw(va):
    rva=va-IMAGE_BASE
    for s in secs:
        if s['rva'] <= rva < s['rva']+max(s['vs'],s['rs']):
            rel=rva-s['rva']
            if rel < s['rs']: return s['rp']+rel,s
    raise ValueError(hex(va))

def raw_to_va(raw,s): return IMAGE_BASE+s['rva']+(raw-s['rp'])
def is_exec(s): return bool(s['ch'] & 0x20000000)

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

def sync_context(va,back=0x180,ahead=0x180):
    raw,s=va_to_raw(va)
    lo=max(s['rp'],raw-back); hi=min(s['rp']+s['rs'],raw+ahead)
    choices=[]
    for shift in range(0,min(96,raw-lo)+1):
        st=lo+shift
        sva=raw_to_va(st,s)
        ins=list(md.disasm(data[st:hi],sva))
        idx=next((i for i,x in enumerate(ins) if x.address==va),None)
        if idx is not None: choices.append((idx,ins))
    if not choices: return None
    return max(choices,key=lambda z:z[0])

def rel32_refs(target):
    out=[]
    for s in secs:
        if not is_exec(s): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        base=IMAGE_BASE+s['rva']
        for i in range(0,max(0,len(blob)-5)):
            op=blob[i]
            if op not in (0xE8,0xE9): continue
            disp=struct.unpack_from('<i',blob,i+1)[0]
            src=base+i; dst=(src+5+disp)&0xffffffff
            if dst==target: out.append((src,'CALL' if op==0xE8 else 'JMP',s['name']))
    return out

def find_standard_owner(va,limit=0x1000):
    raw_t,s=va_to_raw(va)
    lo=max(s['rp'],raw_t-limit)
    c=[]
    for p in range(lo,raw_t):
        if data[p:p+3] != b'\x55\x8B\xEC': continue
        start=raw_to_va(p,s)
        blob=data[p:min(s['rp']+s['rs'],raw_t+0x240)]
        ins=list(md.disasm(blob,start))
        by={x.address:i for i,x in enumerate(ins)}
        if va not in by: continue
        idx=by[va]
        if any(x.mnemonic.startswith('ret') for x in ins[:idx]): continue
        c.append((start,ins,idx))
    return max(c,key=lambda z:z[0]) if c else None

def operand_hits_target(x):
    hits=[]
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.base==0 and op.mem.index==0:
            d=op.mem.disp & 0xffffffff
            if d in TARGETS: hits.append(TARGETS[d])
        elif op.type==X86_OP_IMM:
            d=op.imm & 0xffffffff
            if d in TARGETS: hits.append(TARGETS[d])
    return hits

def eax_source_window(ins,idx,n=18):
    # Human-readable backward slice: retain instructions that directly write EAX,
    # calls, and nearby control/data movement. This is intentionally conservative.
    lo=max(0,idx-n)
    return ins[lo:idx+1]

print('============================================================')
print(' AOTR WOTR NETWORK GI WRITER PATH PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print('')

for va,label in WRITERS.items():
    print(f'================ {label} 0x{va:08X} ================')
    ctx=sync_context(va)
    if not ctx:
        print('<context decode failed>\n'); continue
    idx,ins=ctx
    for j in range(max(0,idx-40),min(len(ins),idx+36)):
        x=ins[j]
        tags=operand_hits_target(x)
        mark='>>' if j==idx else ('**' if tags else '  ')
        suffix=('    ['+', '.join(tags)+']') if tags else ''
        print(fmt(x,mark)+suffix)

    print('\n-- EAX SOURCE WINDOW --')
    for x in eax_source_window(ins,idx,24):
        print(fmt(x,'>>' if x.address==va else '  '))

    owner=find_standard_owner(va)
    if owner:
        start,oins,oidx=owner
        print(f'\n-- STANDARD OWNER CANDIDATE 0x{start:08X} --')
        refs=rel32_refs(start)
        print(f'direct refs={len(refs)}')
        for src,kind,sn in refs:
            print(f'  0x{src:08X} {kind} section={sn}')
    else:
        print('\n-- STANDARD OWNER CANDIDATE: none --')
    print('')

# The 0x82BE92/97 pair is adjacent, so dump a larger unified window once.
print('================ UNIFIED 0x82BE92/0x82BE97 PRODUCER WINDOW ================')
ctx=sync_context(0x0082BE92,0x300,0x240)
if ctx:
    idx,ins=ctx
    for j in range(max(0,idx-80),min(len(ins),idx+80)):
        x=ins[j]
        mark='>>' if x.address in (0x0082BE92,0x0082BE97) else ('**' if operand_hits_target(x) else '  ')
        print(fmt(x,mark))

print('\n================ UNIFIED 0x78853D/0x788542 PRODUCER WINDOW ================')
ctx=sync_context(0x0078853D,0x300,0x240)
if ctx:
    idx,ins=ctx
    for j in range(max(0,idx-80),min(len(ins),idx+80)):
        x=ins[j]
        mark='>>' if x.address in (0x0078853D,0x00788542) else ('**' if operand_hits_target(x) else '  ')
        print(fmt(x,mark))

print('\nINTERPRETATION TARGETS')
print('  1) Determine what value is in EAX at 0x82BE92/0x82BE97 and where it comes from.')
print('  2) Determine whether DE8930 and DE892C intentionally receive the same pointer.')
print('  3) Determine what value is in EAX at 0x78853D/0x788542 and why it is installed into both TheGameInfo and NetworkGI.')
print('  4) Identify the normal pre-start producer path relevant to the host Strategic lobby.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'network GI writer path probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
