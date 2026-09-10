param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Finds native producers/builders for the proven session message IDs:
#   0x03 REMOTE_TYPE6_CREATE
#   0x04 LOCAL_SLOT_BIND
#   0x08 SLOT_REMOVE_CLEAR
# It does not linearly disassemble whole PE sections. Instead it finds raw
# immediate occurrences, synchronizes candidate MOV-to-memory instructions,
# resolves the binary's standard function prologue, then decodes locally.

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

$tempPy = Join-Path $env:TEMP ('a8p_join_msg_producer_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_OP_IMM, CS_OP_MEM

path=sys.argv[1]
IMAGE_BASE=0x00400000
PROLOG_HELPER=0x00A3CEF0
IDS={3:'REMOTE_TYPE6_CREATE',4:'LOCAL_SLOT_BIND',8:'SLOT_REMOVE_CLEAR'}

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
    secs.append(dict(name=name,rva=rva,vs=vs,rs=rs,rp=rp,ch=ch,exec=bool(ch & 0x20000000)))
execsecs=[s for s in secs if s['exec']]

md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True

def va_to_raw(va):
    rva=va-IMAGE_BASE
    for s in secs:
        span=max(s['vs'],s['rs'])
        if s['rva'] <= rva < s['rva']+span:
            off=s['rp']+(rva-s['rva'])
            if 0 <= off < len(data): return off,s
    return None,None

def raw_to_va(off,s):
    return IMAGE_BASE+s['rva']+(off-s['rp'])

def direct_target(x):
    if x.mnemonic in ('call','jmp') and x.operands and x.operands[0].type==CS_OP_IMM:
        return x.operands[0].imm & 0xffffffff
    return None

def find_standard_start(hit_va):
    hit_raw,s=va_to_raw(hit_va)
    if hit_raw is None: return None
    lo=max(s['rp'],hit_raw-0x1800)
    best=None
    # Signature: B8 imm32 ; E8 rel32 -> 0xA3CEF0
    for p in range(lo,hit_raw-9):
        if data[p] != 0xB8 or data[p+5] != 0xE8: continue
        call_va=raw_to_va(p+5,s)
        rel=struct.unpack_from('<i',data,p+6)[0]
        dst=(call_va+5+rel)&0xffffffff
        if dst==PROLOG_HELPER:
            best=raw_to_va(p,s)
    return best

def decode_function(start_va,limit=0x2400):
    ro,s=va_to_raw(start_va)
    if ro is None: return []
    end=min(s['rp']+s['rs'],ro+limit)
    out=[]
    for x in md.disasm(data[ro:end],start_va):
        out.append(x)
        # Do not stop at every RET immediately: compiler can place tiny helpers/data,
        # but after a reasonable body the first RET is sufficient for this probe.
        if len(out)>8 and x.mnemonic.startswith('ret'):
            break
    return out

def fmt(x,mark='  '):
    b=' '.join(f'{v:02X}' for v in x.bytes)
    return f'{mark} 0x{x.address:08X}: {b:<38} {x.mnemonic:<8} {x.op_str}'

# Synchronize exact MOV [mem], immediate-ID candidates. We raw-search the 4-byte
# little-endian immediate and try possible instruction starts up to 12 bytes before it.
cands=[]
seen=set()
for s in execsecs:
    beg=s['rp']; end=min(len(data),beg+s['rs'])
    blob=data[beg:end]
    for mid,name in IDS.items():
        needle=struct.pack('<I',mid)
        pos=0
        while True:
            k=blob.find(needle,pos)
            if k<0: break
            imm_raw=beg+k
            for st in range(max(beg,imm_raw-12),imm_raw+1):
                va=raw_to_va(st,s)
                ins=list(md.disasm(data[st:min(end,st+20)],va,count=1))
                if not ins: continue
                x=ins[0]
                if x.mnemonic!='mov' or len(x.operands)!=2: continue
                if x.operands[0].type!=CS_OP_MEM or x.operands[1].type!=CS_OP_IMM: continue
                if (x.operands[1].imm & 0xffffffff)!=mid: continue
                # Ensure the searched immediate is physically within this instruction.
                if not (st <= imm_raw and imm_raw+4 <= st+x.size): continue
                key=(x.address,mid)
                if key in seen: continue
                seen.add(key)
                cands.append((x.address,mid,name,s['name']))
            pos=k+1

print('============================================================')
print(' AOTR WOTR JOIN MESSAGE PRODUCER PROBE - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print('')
print('================ RAW SYNCHRONIZED ID WRITES ================')
print(f'Total MOV-to-memory candidates: {len(cands)}')
for va,mid,name,secname in cands:
    print(f'  0x{va:08X} ID=0x{mid:02X} {name} section={secname}')

# Group by resolved function and score for packet-builder evidence.
funcs={}
for va,mid,name,secname in cands:
    st=find_standard_start(va)
    if st is None: continue
    funcs.setdefault((st,mid),set()).add(va)

ranked=[]
for (st,mid),hits in funcs.items():
    ins=decode_function(st)
    if not ins: continue
    disps=[]; calls=[]; session_global=False
    for x in ins:
        for op in x.operands:
            if op.type==CS_OP_MEM:
                d=op.mem.disp & 0xffffffff
                disps.append(d)
                # absolute [0xDE4394]
                if op.mem.base==0 and op.mem.index==0 and d==0x00DE4394:
                    session_global=True
        t=direct_target(x)
        if t is not None: calls.append((x.address,t))
    score=4
    # ID=4 should contain the receiver-proven endpoint/slot fields if this is the ACK/bind builder.
    if mid==4:
        for d in (0x46,0x4a,0x4c):
            if d in disps: score+=6
    # Message-ish offsets seen around the proven handlers.
    for d in (0x1e,0x22,0x32,0x36,0x3a,0x46,0x4a,0x4c):
        if d in disps: score+=1
    if session_global: score+=5
    if len(calls)>=2: score+=2
    ranked.append((score,st,mid,hits,ins,disps,calls,session_global))

ranked.sort(key=lambda z:(-z[0],z[1],z[2]))
print('\n================ RANKED PRODUCER FUNCTIONS ================')
for n,(score,st,mid,hits,ins,disps,calls,sg) in enumerate(ranked[:24],1):
    print(f'\n---------------- CANDIDATE #{n} score={score} start=0x{st:08X} ID=0x{mid:02X} {IDS[mid]} ----------------')
    print('ID write(s): '+', '.join(f'0x{x:08X}' for x in sorted(hits)))
    present=[d for d in (0x1e,0x22,0x32,0x36,0x3a,0x46,0x4a,0x4c) if d in disps]
    print('Interesting displacements: '+(', '.join(f'+0x{d:X}' for d in present) if present else '<none>'))
    print(f'Session global 0xDE4394 referenced: {sg}')
    # Print full function only for strongest candidates; otherwise compact around ID writes.
    if score>=16:
        for x in ins:
            mark='>>' if x.address in hits else '  '
            print(fmt(x,mark))
    else:
        amap={x.address:i for i,x in enumerate(ins)}
        printed=set()
        for h in sorted(hits):
            if h not in amap: continue
            i=amap[h]
            for j in range(max(0,i-18),min(len(ins),i+45)):
                if j in printed: continue
                printed.add(j)
                print(fmt(ins[j],'>>' if ins[j].address==h else '  '))

print('\n================ ID 0x04 FIELD-COINCIDENCE SUMMARY ================')
for score,st,mid,hits,ins,disps,calls,sg in ranked:
    if mid!=4: continue
    fields=[d for d in (0x46,0x4a,0x4c) if d in disps]
    print(f'function=0x{st:08X} score={score} fields=' + (','.join(f'+0x{x:X}' for x in fields) if fields else '<none>') + ' writes=' + ','.join(f'0x{x:08X}' for x in sorted(hits)))

print('\nInterpretation targets:')
print('  1) Find the real builders/senders for message IDs 0x03, 0x04 and 0x08.')
print('  2) For ID 0x04, prioritize a function that also writes/uses +0x46, +0x4A and +0x4C.')
print('  3) Identify the common native send/enqueue call after message construction.')
print('  4) Resolve which endpoint and assigned-slot values are serialized by the 0x04 producer.')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy $GameDat $hash
    if ($LASTEXITCODE -ne 0) { throw 'join message producer probe failed.' }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
