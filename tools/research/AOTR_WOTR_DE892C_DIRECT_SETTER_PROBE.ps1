param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Corrective probe: traces every known direct non-clear DE892C writer, including
# writers missed by earlier over-narrow scans. For each writer it prints an
# alignment-safe function window, backward source-register provenance, and
# direct callers of the containing function candidate.

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

$tempPy = Join-Path $env:TEMP ('a8p_de892c_setters_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
DE892C=0x00DE892C
DE4394=0x00DE4394
WRITERS=[
    (0x006309BF,'ECX'),
    (0x0063153A,'EBX'),
    (0x0077F7D0,'EBX'),
    (0x00788542,'EAX'),
    (0x0082BE97,'EAX'),
    (0x0091BF9A,'ESI'),
    (0x00928398,'EBX'),
]
KNOWN={0x00788542:'KNOWN_C2FB98_PUBLISH',0x0082BE97:'KNOWN_BFD668_PUBLISH'}

with open(path,'rb') as f: data=f.read()
if data[:2] != b'MZ': raise SystemExit('Not MZ')
pe=struct.unpack_from('<I',data,0x3c)[0]
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

def sec_for_va(va):
    rva=va-IMAGE_BASE
    for s in secs:
        if s['rva'] <= rva < s['rva']+max(s['vs'],s['rs']): return s
    return None

def raw_for_va(va):
    s=sec_for_va(va)
    if not s: return None,None
    return s['rp']+(va-IMAGE_BASE-s['rva']),s

def fmt(x,mark='  '):
    bs=' '.join(f'{b:02X}' for b in x.bytes)
    return f'{mark} 0x{x.address:08X}: {bs:<42} {x.mnemonic:<8} {x.op_str}'

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def aligned_stream(target,back=0x180,forward=0x140):
    raw_t,s=raw_for_va(target)
    if raw_t is None: return None,[]
    raw_lo=max(s['rp'],raw_t-back)
    cands=[]
    for r in range(raw_lo,raw_t+1):
        if data[r:r+3]==b'\x55\x8b\xec': cands.append(r)
        if r>0 and data[r-1]==0xC3: cands.append(r)
        if r>=3 and data[r-3]==0xC2: cands.append(r)
    best=None
    for r in sorted(set(cands),reverse=True):
        va=IMAGE_BASE+s['rva']+(r-s['rp'])
        ins=list(md.disasm(data[r:min(s['rp']+s['rs'],raw_t+forward)],va))
        if not any(x.address==target for x in ins): continue
        # Avoid starts that cross a RET before target.
        crossed=False
        for x in ins:
            if x.address>=target: break
            if x.mnemonic.startswith('ret'): crossed=True
        score=(0 if crossed else 10000)+va
        if best is None or score>best[0]: best=(score,va,ins)
    if best: return best[1],best[2]
    # fallback brute alignment
    for start in range(max(IMAGE_BASE,target-back),target+1):
        raw,s2=raw_for_va(start)
        if raw is None: continue
        ins=list(md.disasm(data[raw:min(s2['rp']+s2['rs'],raw+(target-start)+forward)],start))
        if any(x.address==target for x in ins): return start,ins
    return None,[]

def direct_callers(target):
    out=[]
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        base=IMAGE_BASE+s['rva']
        for i in range(len(blob)-5):
            if blob[i]!=0xE8: continue
            rel=struct.unpack_from('<i',blob,i+1)[0]
            src=base+i
            if ((src+5+rel)&0xffffffff)==target: out.append((src,s['name']))
    return out

def reg_id(name):
    return {'EAX':X86_REG_EAX,'EBX':X86_REG_EBX,'ECX':X86_REG_ECX,'EDX':X86_REG_EDX,'ESI':X86_REG_ESI,'EDI':X86_REG_EDI}.get(name)

def writes_reg(x,rid):
    try:
        _,wr=x.regs_access()
        return rid in wr
    except:
        return False

def reads_abs(x,addr):
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.base==0 and op.mem.index==0 and (op.mem.disp&0xffffffff)==addr:
            return True
    return False

print('============================================================')
print(' AOTR WOTR DE892C DIRECT SETTER PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print(f'DE892C     : 0x{DE892C:08X}')
print('')
print('CORRECTION: earlier "only two direct setters" classification was incomplete.')
print('This probe traces all currently known non-clear MOV setters.')
print('')

for n,(target,rname) in enumerate(WRITERS,1):
    print(f'================ SETTER #{n}: 0x{target:08X} source={rname} {KNOWN.get(target,"")} ================')
    start,ins=aligned_stream(target)
    if not ins:
        print('  <no aligned function stream>\n'); continue
    print(f'Function/start candidate: 0x{start:08X}')
    refs=direct_callers(start)
    print('Direct callers of start: '+(', '.join(f'0x{x[0]:08X}' for x in refs) if refs else '<none>'))
    local=[x for x in ins if target-0x100 <= x.address <= target+0x90]
    for x in local:
        print(fmt(x,'>>' if x.address==target else '  '))
    rid=reg_id(rname)
    prior=[x for x in ins if x.address<target and x.address>=target-0x140]
    defs=[x for x in prior if rid and writes_reg(x,rid)]
    print('--- backward source-register definitions ---')
    for x in defs[-8:]:
        tags=[]
        if reads_abs(x,DE4394): tags.append('READS_SESSION_GLOBAL')
        if reads_abs(x,DE892C): tags.append('READS_DE892C')
        print(fmt(x,'  ')+(('  ['+','.join(tags)+']') if tags else ''))
    if not defs: print('  <no explicit definition in backward window>')
    print('')

print('INTERPRETATION TARGETS')
print('  1) Which setter source is a C54B78 GameInfo pointer?')
print('  2) Does any setter load session+0x44 or receive the current GameInfo as an argument/callback?')
print('  3) Which setter belongs to the normal pre-start Strategic-lobby lifecycle?')
print('  4) Do not patch DE892C yet; classify the native publisher first.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw "DE892C direct setter probe failed. Python exit=$LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
