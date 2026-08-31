param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Final pause-checkpoint probe: inspect the proven C54CE0 session class for
# accesses/writes to session+0x10 and session+0x44, the two fields that both
# point at the live pre-start Network GameInfo at runtime.
#
# It walks C54CE0 vtable methods plus the constructor, tracks simple this-register
# aliases (ECX -> ESI/EDI/EBX/etc.), and reports reads/writes to +0x10/+0x44.
# No process or file memory is modified.

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

$tempPy = Join-Path $env:TEMP ('a8p_session_writer_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
SESSION_VTABLE=0x00C54CE0
SESSION_CTOR=0x0084C76D
TARGET_DISPS={0x10:'+0x10',0x44:'+0x44'}

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
    secs.append(dict(name=name,rva=rva,vs=vs,rp=rp,rs=rs,ch=ch))

def va_to_off(va):
    rva=va-IMAGE_BASE
    for s in secs:
        span=max(s['vs'],s['rs'])
        if s['rva'] <= rva < s['rva']+span:
            return s['rp']+(rva-s['rva']),s
    return None,None

text=next(s for s in secs if s['name']=='.text')
text_va=IMAGE_BASE+text['rva']
text_end=text_va+text['rs']

vt_off,vt_sec=va_to_off(SESSION_VTABLE)
if vt_off is None: raise SystemExit('Session vtable not mapped')

methods=[]
for slot in range(0,0x104,4):
    fn=struct.unpack_from('<I',data,vt_off+slot)[0]
    if text_va <= fn < text_end:
        methods.append((slot,fn))

# constructor is not necessarily a vtable target; inspect it explicitly.
targets=[('CTOR',None,SESSION_CTOR)] + [('VTABLE',slot,fn) for slot,fn in methods]

md=Cs(CS_ARCH_X86,CS_MODE_32)
md.detail=True

REG_NAMES={
    X86_REG_EAX:'eax',X86_REG_EBX:'ebx',X86_REG_ECX:'ecx',X86_REG_EDX:'edx',
    X86_REG_ESI:'esi',X86_REG_EDI:'edi',X86_REG_EBP:'ebp',X86_REG_ESP:'esp'
}

def read_window(fn,max_len=0x700):
    off,sec=va_to_off(fn)
    if off is None: return b''
    avail=min(max_len, len(data)-off)
    return data[off:off+avail]

def is_reg_op(op): return op.type==X86_OP_REG

def regname(r): return REG_NAMES.get(r, md.reg_name(r) or f'reg{r}')

def print_context(insns,idx,radius=5):
    lo=max(0,idx-radius); hi=min(len(insns),idx+radius+1)
    for j in range(lo,hi):
        x=insns[j]
        mark='>>' if j==idx else '  '
        bs=' '.join(f'{b:02X}' for b in x.bytes)
        print(f'{mark} 0x{x.address:08X}: {bs:<30} {x.mnemonic:<8} {x.op_str}')

print('============================================================')
print(' AOTR WOTR SESSION GAMEINFO FIELD WRITER PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print(f'Session vtable   : 0x{SESSION_VTABLE:08X}')
print(f'Session ctor     : 0x{SESSION_CTOR:08X}')
print('Target fields    : +0x10, +0x44')
print(f'Vtable methods   : {len(methods)}')
print('')

all_hits=[]
seen=set()
for kind,slot,fn in targets:
    # avoid reporting same implementation repeatedly for aliased vtable slots
    key=(fn,kind=='CTOR')
    if key in seen: continue
    seen.add(key)
    blob=read_window(fn)
    if not blob: continue
    insns=list(md.disasm(blob,fn))
    if not insns: continue

    aliases={X86_REG_ECX}
    fn_hits=[]
    ret_seen=0

    for idx,x in enumerate(insns):
        # Track simple copies of this: mov reg,alias or lea reg,[alias].
        if len(x.operands)>=2 and x.operands[0].type==X86_OP_REG:
            dst=x.operands[0].reg
            src=x.operands[1]
            made_alias=False
            if x.mnemonic=='mov' and src.type==X86_OP_REG and src.reg in aliases:
                made_alias=True
            elif x.mnemonic=='lea' and src.type==X86_OP_MEM and src.mem.base in aliases and src.mem.index==0 and src.mem.disp==0:
                made_alias=True
            if made_alias:
                aliases.add(dst)
            else:
                # If a known alias register is overwritten by a normal value, stop trusting it.
                if dst in aliases and dst!=X86_REG_ECX and x.mnemonic not in ('push',):
                    aliases.discard(dst)

        for oi,op in enumerate(x.operands):
            if op.type!=X86_OP_MEM: continue
            base=op.mem.base
            disp=op.mem.disp & 0xffffffff
            if base not in aliases or disp not in TARGET_DISPS: continue

            access=[]
            try:
                if op.access & CS_AC_READ: access.append('READ')
                if op.access & CS_AC_WRITE: access.append('WRITE')
            except Exception:
                pass
            # Conservative fallback for old Capstone access metadata.
            if not access:
                if oi==0 and x.mnemonic not in ('cmp','test','push','call','jmp'):
                    access=['WRITE?']
                else:
                    access=['READ?']

            hit=dict(idx=idx,ins=x,field=TARGET_DISPS[disp],base=regname(base),access='/'.join(access))
            fn_hits.append(hit); all_hits.append((kind,slot,fn,hit,insns))

        # A ret is a strong local function-end signal. Keep a little room only for
        # odd shared-epilogue layouts, but do not wander into the next function.
        if x.mnemonic.startswith('ret'):
            ret_seen += 1
            if ret_seen>=1:
                break

    if fn_hits:
        label='CTOR' if kind=='CTOR' else f'VTABLE +0x{slot:03X}'
        print(f'================ {label} -> 0x{fn:08X} ================')
        for h in fn_hits:
            print(f'{h["field"]} {h["access"]} via {h["base"]} at 0x{h["ins"].address:08X}: {h["ins"].mnemonic} {h["ins"].op_str}')
            print_context(insns,h['idx'],4)
            print('')

print('================ ACCESSOR +0xE0 TRACE ================')
accessor=next((fn for slot,fn in methods if slot==0xE0),None)
if accessor:
    ins=list(md.disasm(read_window(accessor,0x100),accessor))
    for i,x in enumerate(ins[:32]):
        bs=' '.join(f'{b:02X}' for b in x.bytes)
        print(f'0x{x.address:08X}: {bs:<30} {x.mnemonic:<8} {x.op_str}')
        if x.mnemonic.startswith('ret'): break
else:
    print('No +0xE0 vtable target resolved.')

print('')
print('================ SUMMARY ================')
write_hits=[]
for kind,slot,fn,h,insns in all_hits:
    if 'WRITE' in h['access']:
        write_hits.append((kind,slot,fn,h))
print(f'Total +0x10/+0x44 accesses : {len(all_hits)}')
print(f'Write-like accesses        : {len(write_hits)}')
for kind,slot,fn,h in write_hits:
    label='CTOR' if kind=='CTOR' else f'VTABLE+0x{slot:03X}'
    print(f'  {label} 0x{fn:08X} -> {h["field"]} {h["access"]} @ 0x{h["ins"].address:08X}')

print('')
print('Interpretation:')
print('  - Constructor zero-initialization is expected and is not by itself the bridge setter.')
print('  - A non-constructor WRITE to +0x10 or +0x44 is a prime native lifecycle/update candidate.')
print('  - +0xE0 is already proven by call sites to return the current GameInfo-like object; its exact field access is printed separately.')
print('  - Alias tracking is intentionally conservative; absence of a hit is negative evidence, not proof that no writer exists.')
print('  - No bytes are modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'session GameInfo field writer probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
