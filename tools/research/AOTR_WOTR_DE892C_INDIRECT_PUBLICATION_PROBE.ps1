param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Goal: find address-taken / register-indirect writers to DE892C that are missed by
# direct absolute-memory writer scans. Also prints the exact session dispatcher
# window around PATH_C/PATH_A/PATH_B so publication callbacks after local-bind can
# be inspected without another broad scan.

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

$tempPy = Join-Path $env:TEMP ('a8p_de892c_indirect_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import *
from capstone.x86 import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
TARGET=0x00DE892C
DISPATCH=0x0084D787
PATH_A=0x0098A2FC
PATH_B=0x0098A50D
PATH_C=0x0098A7F1

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
    rel=(va-IMAGE_BASE)-s['rva']
    if rel<0 or rel>=s['rs']: return None,s
    return s['rp']+rel,s

def fmt(x,mark='  '):
    b=' '.join(f'{v:02X}' for v in x.bytes)
    return f'{mark} 0x{x.address:08X}: {b:<42} {x.mnemonic:<8} {x.op_str}'

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def exact_instruction_candidates_for_literal(target):
    needle=struct.pack('<I',target)
    out={}
    for s in secs:
        if not (s['ch'] & 0x20000000): continue
        blob=data[s['rp']:s['rp']+s['rs']]
        pos=0
        while True:
            j=blob.find(needle,pos)
            if j<0: break
            occ=IMAGE_BASE+s['rva']+j
            for back in range(0,16):
                start=occ-back
                raw,_=raw_for_va(start)
                if raw is None: continue
                ins=list(md.disasm(data[raw:raw+24],start))
                for x in ins[:4]:
                    if not (x.address <= occ < x.address+x.size): continue
                    hit=False
                    for op in x.operands:
                        if op.type==X86_OP_IMM and (op.imm & 0xffffffff)==target:
                            hit=True
                        elif op.type==X86_OP_MEM and op.mem.base==0 and op.mem.index==0 and (op.mem.disp & 0xffffffff)==target:
                            hit=True
                    if hit:
                        out[(x.address,bytes(x.bytes))]=(x,s['name'])
            pos=j+1
    return sorted(out.values(),key=lambda t:t[0].address)

def reg_written(x,regid):
    try:
        rr,rw=x.regs_access()
        return regid in rw
    except:
        return False

def track_from(seed):
    # Only track explicit MOV/LEA address-takes in the same straight-line block.
    taint={}
    if len(seed.operands)>=2 and seed.operands[0].type==X86_OP_REG:
        dst=seed.operands[0].reg
        src=seed.operands[1]
        if src.type==X86_OP_IMM and (src.imm & 0xffffffff)==TARGET:
            taint[dst]=0
        elif src.type==X86_OP_MEM and src.mem.base==0 and src.mem.index==0 and (src.mem.disp & 0xffffffff)==TARGET and seed.mnemonic=='lea':
            taint[dst]=0
    if not taint: return []
    raw,s=raw_for_va(seed.address+seed.size)
    if raw is None: return []
    ins=list(md.disasm(data[raw:raw+0x100],seed.address+seed.size))
    notes=[]
    pushed=[]
    for x in ins[:40]:
        # stop at control-flow boundaries; do not pretend inter-block taint is proven
        if x.mnemonic.startswith('ret') or x.mnemonic in ('jmp','je','jne','jg','jge','jl','jle','ja','jae','jb','jbe','jo','jno','js','jns','jp','jnp'):
            break

        # detect writes through tainted register
        if x.operands:
            d=x.operands[0]
            if d.type==X86_OP_MEM and d.mem.index==0 and d.mem.base in taint:
                addr=(TARGET + taint[d.mem.base] + d.mem.disp) & 0xffffffff
                if addr==TARGET:
                    notes.append(('INDIRECT_WRITE',x.address,fmt(x,'>>')))

        # report address passed to a call through PUSH tainted-register
        if x.mnemonic=='push' and x.operands and x.operands[0].type==X86_OP_REG and x.operands[0].reg in taint:
            pushed.append((x.address,x.operands[0].reg,fmt(x,'>>')))
        elif x.mnemonic=='call':
            if pushed:
                for p in pushed[-3:]: notes.append(('ADDR_PASSED_TO_CALL',x.address,p[2]+' ; then '+fmt(x,'>>')))
            # volatile-register tracking is unsafe across calls; stop after reporting
            break

        # simple taint propagation
        if x.mnemonic=='mov' and len(x.operands)>=2 and x.operands[0].type==X86_OP_REG:
            dst=x.operands[0].reg; src=x.operands[1]
            if src.type==X86_OP_REG and src.reg in taint:
                taint[dst]=taint[src.reg]
            elif reg_written(x,dst):
                taint.pop(dst,None)
        elif x.mnemonic=='lea' and len(x.operands)>=2 and x.operands[0].type==X86_OP_REG and x.operands[1].type==X86_OP_MEM:
            dst=x.operands[0].reg; m=x.operands[1].mem
            if m.index==0 and m.base in taint:
                taint[dst]=taint[m.base]+m.disp
            elif reg_written(x,dst):
                taint.pop(dst,None)
        else:
            for r in list(taint):
                if reg_written(x,r): taint.pop(r,None)
        if not taint and x.mnemonic!='push':
            break
    return notes

def exact_context(start,end):
    raw,s=raw_for_va(start)
    if raw is None: return []
    return list(md.disasm(data[raw:raw+(end-start)],start))

print('============================================================')
print(' AOTR WOTR DE892C INDIRECT PUBLICATION PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print(f'Target     : 0x{TARGET:08X}')
print('')

refs=exact_instruction_candidates_for_literal(TARGET)
print('================ LEGITIMATE ADDRESS-TAKE CANDIDATES ================')
addr=[]
for x,sn in refs:
    is_addr=False
    if x.mnemonic in ('mov','lea') and len(x.operands)>=2 and x.operands[0].type==X86_OP_REG:
        src=x.operands[1]
        if src.type==X86_OP_IMM and (src.imm & 0xffffffff)==TARGET: is_addr=True
        if x.mnemonic=='lea' and src.type==X86_OP_MEM and src.mem.base==0 and src.mem.index==0 and (src.mem.disp & 0xffffffff)==TARGET: is_addr=True
    elif x.mnemonic=='push' and x.operands and x.operands[0].type==X86_OP_IMM and (x.operands[0].imm & 0xffffffff)==TARGET:
        is_addr=True
    if is_addr:
        addr.append((x,sn))
        print(f'  section={sn} {fmt(x,">>")}')
print('count='+str(len(addr)))
print('')

print('================ SAME-BLOCK REGISTER-INDIRECT RESULTS ================')
found=[]
for x,sn in addr:
    notes=track_from(x)
    for kind,va,text in notes:
        found.append((kind,va,x.address,sn,text))
for kind,va,seed,sn,text in found:
    print(f'{kind}: seed=0x{seed:08X} section={sn} event=0x{va:08X}')
    print('  '+text)
if not found: print('  <no same-block indirect writer/call handoff found>')
print('')

print('================ DIRECT ABSOLUTE WRITE-ISH REFS ================')
for x,sn in refs:
    if not x.operands: continue
    d=x.operands[0]
    if d.type==X86_OP_MEM and d.mem.base==0 and d.mem.index==0 and (d.mem.disp & 0xffffffff)==TARGET:
        print(f'  section={sn} {fmt(x,">>")}')
print('')

print('================ SESSION DISPATCH 0x84D787 WINDOW ================')
for x in exact_context(DISPATCH,0x0084D930):
    mark='  '
    if x.mnemonic=='call' and x.operands and x.operands[0].type==X86_OP_IMM:
        dst=x.operands[0].imm & 0xffffffff
        if dst in (PATH_A,PATH_B,PATH_C): mark='>>'
    print(fmt(x,mark))
print('')

print('STATIC CHECKPOINT')
print('  - PATH_A has already proven session+0x44 publication from the session list.')
print('  - Host runtime proves DE892C == session+0x44 == C54B78, while VM DE892C is NULL.')
print('  - This probe asks whether DE892C is written through an address-taken register/callback path and what the dispatcher does immediately after PATH_A.')
print('  - No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw "DE892C indirect publication probe failed. Python exit=$LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
