param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Runtime proved B04 component A alone differs HOST vs VM. Static provenance
# proved A is localRoot+0x44, with localRoot constructed by 0x6251F5 and later
# finalized through vfunc +0x10 with ASCII "END". This probe identifies the
# localRoot class/vtable and follows the +0x10 method and one level of direct
# callees looking specifically for this+0x44 reads/writes.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

$py = Get-Command py.exe -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python.exe -ErrorAction SilentlyContinue }
if (-not $py) { throw 'Python not found.' }
$pyPath = $py.Source
& $pyPath -c "import capstone" 2>$null
if ($LASTEXITCODE -ne 0) { throw ('Python capstone missing. Install with: "{0}" -m pip install --user capstone' -f $pyPath) }

$tempPy = Join-Path $env:TEMP ('a8p_localroot_acc_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct, string
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86_const import *

path=sys.argv[1]
IMAGE_BASE=0x00400000
CTOR=0x006251F5
CLEANUP=0x00A205AD
OWNER_A_READ=0x0063C806

with open(path,'rb') as f: data=f.read()
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
    chars=struct.unpack_from('<I',data,o+36)[0]
    secs.append(dict(name=name,rva=rva,vs=vs,rs=rs,rp=rp,chars=chars))

def sec_for_va(va):
    rva=va-IMAGE_BASE
    for s in secs:
        if s['rva'] <= rva < s['rva']+max(s['vs'],s['rs']): return s
    return None

def rb(va,n):
    s=sec_for_va(va)
    if not s: raise ValueError(f'VA 0x{va:08X} not mapped')
    raw=s['rp']+((va-IMAGE_BASE)-s['rva'])
    return data[raw:raw+n],s,raw

def u32(va): return struct.unpack('<I',rb(va,4)[0])[0]

def printable_at(va,limit=96):
    try: b,_,_=rb(va,limit)
    except: return None
    out=[]
    for c in b:
        if c==0: break
        if c not in b'\t\r\n' and (c<0x20 or c>0x7e): return None
        out.append(c)
    if len(out)<4: return None
    try: return bytes(out).decode('ascii')
    except: return None

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def dis(start,size):
    b,s,raw=rb(start,size)
    return list(md.disasm(b,start)),s,raw

def fmt(x,mark='  ',note=''):
    bs=' '.join(f'{v:02X}' for v in x.bytes)
    q=f'{mark} 0x{x.address:08X}: {bs:<43} {x.mnemonic:<8} {x.op_str}'
    return q + ((' ; '+note) if note else '')

def direct_target(x):
    if x.mnemonic not in ('call','jmp') or len(x.operands)!=1: return None
    op=x.operands[0]
    return (op.imm & 0xffffffff) if op.type==X86_OP_IMM else None

def executable(va):
    s=sec_for_va(va)
    return bool(s and (s['chars'] & 0x20000000))

def mapped_nonexec(va):
    s=sec_for_va(va)
    return bool(s and not (s['chars'] & 0x20000000))

print('============================================================')
print(' AOTR WOTR LOCALROOT ACCUMULATOR CLASS PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash       : {sys.argv[2]}')
print(f'Constructor      : 0x{CTOR:08X}')
print(f'Cleanup          : 0x{CLEANUP:08X} (sends ASCII END via vfunc +0x10)')
print(f'Component A read : 0x{OWNER_A_READ:08X} = localRoot+0x44')
print('')

# Constructor: decode bounded body and track aliases of incoming ECX/this.
ctor_ins,_,_=dis(CTOR,0x500)
# stop at first plausible RET after some body
body=[]
for x in ctor_ins:
    body.append(x)
    if x.address > CTOR+0x10 and x.mnemonic.startswith('ret'):
        break

aliases={X86_REG_ECX}
vtable_candidates=[]
print('================ 0x6251F5 CONSTRUCTOR / THIS FIELD MAP ================')
for x in body:
    notes=[]
    # Track simple register aliases of this.
    if x.mnemonic=='mov' and len(x.operands)==2 and x.operands[0].type==X86_OP_REG and x.operands[1].type==X86_OP_REG:
        dst=x.operands[0].reg; src=x.operands[1].reg
        if src in aliases: aliases.add(dst)
    for op in x.operands:
        if op.type==X86_OP_MEM and op.mem.base in aliases:
            notes.append(f'THIS{op.mem.disp:+#x}')
    # vtable-like immediate store to [this+0]
    if x.mnemonic=='mov' and len(x.operands)==2:
        d,s=x.operands
        if d.type==X86_OP_MEM and d.mem.base in aliases and d.mem.disp==0 and s.type==X86_OP_IMM:
            imm=s.imm & 0xffffffff
            if mapped_nonexec(imm):
                vtable_candidates.append((x.address,imm))
                notes.append(f'VTABLE_CANDIDATE 0x{imm:08X}')
    if x.mnemonic=='call':
        t=direct_target(x); notes.append('CALL '+(f'0x{t:08X}' if t else x.op_str))
    if notes or x.address < CTOR+0x40:
        print(fmt(x,'>>' if notes else '  ', ', '.join(notes)))
print('')
print('this aliases seen : '+', '.join(sorted(md.reg_name(r) for r in aliases)))
print('vtable candidates : '+(', '.join(f'0x{v:08X}@0x{a:08X}' for a,v in vtable_candidates) if vtable_candidates else '<none found by direct immediate store>'))
print('')

# If constructor did not directly expose one, scan its immediate operands for a mapped non-exec
# table whose +0x10 entry is executable. This remains explicitly heuristic.
heur=[]
for x in body:
    for op in x.operands:
        if op.type==X86_OP_IMM:
            imm=op.imm & 0xffffffff
            if mapped_nonexec(imm):
                try:
                    t=u32(imm+0x10)
                    if executable(t): heur.append((x.address,imm,t))
                except: pass
if not vtable_candidates and heur:
    print('================ HEURISTIC TABLE CANDIDATES ================')
    for a,v,t in heur[:20]: print(f'0x{a:08X}: table 0x{v:08X}, +0x10 -> 0x{t:08X}')
    print('')

vtables=[]
for _,v in vtable_candidates:
    if v not in vtables: vtables.append(v)
if not vtables:
    for _,v,t in heur:
        if v not in vtables: vtables.append(v)
        if len(vtables)>=4: break

for vt in vtables:
    print(f'================ VTABLE 0x{vt:08X} ================')
    entries=[]
    for off in range(0,0x60,4):
        try: t=u32(vt+off)
        except: break
        sec=sec_for_va(t)
        ex=executable(t)
        print(f'+0x{off:02X} -> 0x{t:08X} section={sec["name"] if sec else "<none>"} exec={ex}')
        if ex: entries.append((off,t))
    print('')

    # Prioritize +0x10, then any method that touches +0x44.
    for off,t in entries:
        try: ins,_,_=dis(t,0x500)
        except Exception as e:
            print(f'--- +0x{off:02X} -> 0x{t:08X} decode failed: {e} ---')
            continue
        method=[]
        for x in ins:
            method.append(x)
            if x.address>t+5 and x.mnemonic.startswith('ret'): break
        hits=[]
        direct_calls=[]
        for x in method:
            local_notes=[]
            for op in x.operands:
                if op.type==X86_OP_MEM and op.mem.disp==0x44:
                    local_notes.append('MEM +0x44')
                if op.type==X86_OP_MEM and op.mem.disp in (0x40,0x48):
                    local_notes.append(f'MEM +0x{op.mem.disp:X}')
            if x.mnemonic=='call':
                dt=direct_target(x)
                if dt: direct_calls.append(dt)
            if local_notes: hits.append((x,local_notes))
        if off==0x10 or hits:
            print(f'--- vtable +0x{off:02X} -> 0x{t:08X} {"[END/finalize method]" if off==0x10 else "[+0x44 hit]"} ---')
            for x in method:
                notes=[]
                for op in x.operands:
                    if op.type==X86_OP_MEM and op.mem.disp==0x44: notes.append('MEM +0x44 COMPONENT-A FIELD')
                    elif op.type==X86_OP_MEM and op.mem.disp in (0x40,0x48): notes.append(f'neighbor +0x{op.mem.disp:X}')
                    if op.type==X86_OP_IMM:
                        s=printable_at(op.imm & 0xffffffff)
                        if s: notes.append('STRING='+repr(s[:70]))
                if x.mnemonic=='call':
                    dt=direct_target(x); notes.append('CALL '+(f'0x{dt:08X}' if dt else x.op_str))
                if notes or x.address < t+0x60:
                    print(fmt(x,'>>' if notes else '  ', ', '.join(notes)))
            print('')

            # One direct-call level from +0x10 only, focused on +0x44 usage.
            if off==0x10:
                uniq=[]
                for dt in direct_calls:
                    if executable(dt) and dt not in uniq: uniq.append(dt)
                if uniq:
                    print('   [one-level direct callees from +0x10]')
                for dt in uniq[:24]:
                    try: ci,_,_=dis(dt,0x380)
                    except: continue
                    cb=[]
                    for x in ci:
                        cb.append(x)
                        if x.address>dt+5 and x.mnemonic.startswith('ret'): break
                    ch=[]
                    for x in cb:
                        for op in x.operands:
                            if op.type==X86_OP_MEM and op.mem.disp==0x44:
                                ch.append(x); break
                    if ch:
                        print(f'   callee 0x{dt:08X} touches +0x44:')
                        for x in cb:
                            notes=[]
                            for op in x.operands:
                                if op.type==X86_OP_MEM and op.mem.disp==0x44: notes.append('MEM +0x44')
                            if x.mnemonic=='call':
                                d2=direct_target(x); notes.append('CALL '+(f'0x{d2:08X}' if d2 else x.op_str))
                            if notes: print(fmt(x,'   >>',', '.join(notes)))
                print('')

# Static cleanup excerpt to bind END -> vfunc +0x10.
print('================ CLEANUP END BINDING ================')
ci,_,_=dis(CLEANUP,0x40)
for x in ci:
    notes=[]
    if x.address==0x00A205C6: notes.append('ASCII END literal')
    if x.address==0x00A205D0: notes.append('virtual call +0x10')
    print(fmt(x,'>>' if notes else '  ', ', '.join(notes)))
    if x.mnemonic.startswith('ret'): break
print('')

print('================ CLASSIFICATION TARGETS ================')
print('1) Prove the concrete localRoot vtable/class from constructor 0x6251F5.')
print('2) Bind cleanup ASCII END to the concrete vtable +0x10 method.')
print('3) Determine whether that method or one direct callee mutates localRoot+0x44.')
print('4) If +0x44 is an accumulator/hash state, classify the exact update algorithm before naming it CRC/checksum.')
print('5) Runtime proof remains: HOST/VM component B identical; component A alone causes B04/Reason-4 mismatch.')
print('6) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'localRoot accumulator class probe failed.' }
}
finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
