param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Traces the frontend 2-slot switch dispatcher at 0x00784063, its callers,
# and all executable references into the switch table 0x00DE7D40..0x00DE7D57.

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

$tempPy = Join-Path $env:TEMP ('a8p_ui_switch_dispatch_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
DISPATCH=0x00784063
SWITCH=0x00784148
TABLE_LO=0x00DE7D40
TABLE_HI=0x00DE7D57

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

def read_bytes(va,n):
    raw,s=va_to_raw(va)
    return data[raw:min(raw+n,s['rp']+s['rs'])],s,raw

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

def rel32_refs(target):
    out=[]
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        base=IMAGE_BASE+s['rva']
        for i in range(0,max(0,len(blob)-5)):
            if blob[i] not in (0xE8,0xE9): continue
            disp=struct.unpack_from('<i',blob,i+1)[0]
            src=base+i; dst=(src+5+disp)&0xffffffff
            if dst==target: out.append((src,'CALL' if blob[i]==0xE8 else 'JMP',s['name']))
    return out

def synchronized_context(addr,back=0x80,ahead=0x50):
    raw,s=va_to_raw(addr)
    lo=max(s['rp'],raw-back); hi=min(s['rp']+s['rs'],raw+ahead)
    blob=data[lo:hi]; sva=raw_to_va(lo,s)
    best=None
    for shift in range(0,min(96,raw-lo)+1):
        ins=list(md.disasm(blob[shift:],sva+shift))
        idx=next((i for i,x in enumerate(ins) if x.address==addr),None)
        if idx is None: continue
        if best is None or idx>best[0]: best=(idx,ins)
    return best

def abs_mem_refs_in_table():
    hits=[]
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        base=IMAGE_BASE+s['rva']
        for x in md.disasm(blob,base):
            found=[]
            for op in x.operands:
                if op.type==X86_OP_MEM and op.mem.base==0 and op.mem.index==0:
                    d=op.mem.disp & 0xffffffff
                    if TABLE_LO <= d <= TABLE_HI: found.append(d)
                elif op.type==X86_OP_IMM:
                    d=op.imm & 0xffffffff
                    if TABLE_LO <= d <= TABLE_HI: found.append(d)
            if found:
                hits.append((x,s['name'],sorted(set(found))))
    return hits

print('============================================================')
print(' AOTR WOTR UI SWITCH DISPATCH PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print(f'Dispatch   : 0x{DISPATCH:08X}')
print(f'Switch     : 0x{SWITCH:08X}')
print(f'Table      : 0x{TABLE_LO:08X}..0x{TABLE_HI:08X}')

print('\n================ DISPATCH BODY 0x00784063 ================')
b,s,raw=read_bytes(DISPATCH,0x500)
ret_seen=0
for x in md.disasm(b,DISPATCH):
    print(fmt(x,'>>' if x.address==DISPATCH else '  '))
    if x.mnemonic.startswith('ret'):
        ret_seen+=1
        if ret_seen>=1: break

print('\n================ DIRECT XREFS TO DISPATCH ================')
rr=rel32_refs(DISPATCH)
print(f'count={len(rr)}')
for n,(src,kind,sn) in enumerate(rr,1):
    print(f'\nCALLER #{n}: 0x{src:08X} {kind} section={sn}')
    ctx=synchronized_context(src,0xA0,0x60)
    if not ctx:
        print('  <context decode failed>'); continue
    idx,ins=ctx
    for j in range(max(0,idx-24),min(len(ins),idx+14)):
        print(fmt(ins[j],'>>' if j==idx else '  '))

print('\n================ DIRECT XREFS TO SWITCH 0x00784148 ================')
rr=rel32_refs(SWITCH)
print(f'count={len(rr)}')
for src,kind,sn in rr:
    print(f'  0x{src:08X} {kind} section={sn}')

print('\n================ EXECUTABLE REFS TO TABLE 0xDE7D40..0xDE7D57 ================')
hits=abs_mem_refs_in_table()
print(f'count={len(hits)}')
for n,(x,sn,vals) in enumerate(hits,1):
    print(f'\nREF #{n}: section={sn} table_refs='+','.join(f'0x{v:08X}' for v in vals))
    ctx=synchronized_context(x.address,0x80,0x60)
    if not ctx:
        print(fmt(x,'>>')); continue
    idx,ins=ctx
    for j in range(max(0,idx-18),min(len(ins),idx+12)):
        print(fmt(ins[j],'>>' if j==idx else '  '))

print('\nINTERPRETATION TARGETS')
print('  1) Classify 0x784063 semantics and its two arguments from the slot table.')
print('  2) Identify any virtual/direct calls that perform the actual screen activation/deactivation.')
print('  3) Identify executable writes/initializers for slot 0 and slot 1 entries at 0xDE7D40..0xDE7D57.')
print('  4) Compare initialized slot-1 data with the VM runtime values 0x0942F740/0x0942F750.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'UI switch dispatch probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
