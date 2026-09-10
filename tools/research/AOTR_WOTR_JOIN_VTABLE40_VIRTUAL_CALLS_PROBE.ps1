param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash=(Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }
$py=Get-Command py.exe -ErrorAction SilentlyContinue
if (-not $py) { $py=Get-Command python.exe -ErrorAction SilentlyContinue }
if (-not $py) { throw 'Python not found.' }
$pyPath=$py.Source
& $pyPath -c "import capstone" 2>$null
if ($LASTEXITCODE -ne 0) { throw ('Python capstone missing. Install with: "{0}" -m pip install --user capstone' -f $pyPath) }
$tempPy=Join-Path $env:TEMP ('a8p_vt40_'+[guid]::NewGuid().ToString('N')+'.py')
try {
@'
import sys,struct
from capstone import Cs,CS_ARCH_X86,CS_MODE_32
path=sys.argv[1]; IMAGE_BASE=0x00400000; VT=0x00C54CE0; JOIN=0x0084CB34
with open(path,'rb') as f:data=f.read()
pe=struct.unpack_from('<I',data,0x3c)[0]; num=struct.unpack_from('<H',data,pe+6)[0]; opt=struct.unpack_from('<H',data,pe+20)[0]; sec0=pe+24+opt
secs=[]
for i in range(num):
 o=sec0+i*40; name=data[o:o+8].split(b'\0',1)[0].decode('ascii','replace'); vs,rva,rs,rp=struct.unpack_from('<IIII',data,o+8); ch=struct.unpack_from('<I',data,o+36)[0]
 secs.append(dict(name=name,vs=vs,rva=rva,rs=rs,rp=rp,ch=ch))
def executable(s): return bool(s['ch'] & 0x20000000)
def va_to_raw(va):
 rva=va-IMAGE_BASE
 for s in secs:
  if s['rva'] <= rva < s['rva']+max(s['vs'],s['rs']): return s['rp']+(rva-s['rva']),s
 raise ValueError(hex(va))
def raw_to_va(raw,s): return IMAGE_BASE+s['rva']+(raw-s['rp'])
md=Cs(CS_ARCH_X86,CS_MODE_32); md.detail=True
def fmt(x,mark='  '):
 bs=' '.join(f'{b:02X}' for b in x.bytes); return f'{mark} 0x{x.address:08X}: {bs:<35} {x.mnemonic:<8} {x.op_str}'
def local_decode(callva,back=0x90,ahead=0x20):
 raw,s=va_to_raw(callva); start=max(s['rp'],raw-back); end=min(s['rp']+s['rs'],raw+ahead)
 blob=data[start:end]; sva=raw_to_va(start,s)
 # choose a synchronized start whose stream contains the exact call VA
 best=None
 for off in range(min(back,64)+1):
  p=max(0,len(blob)-ahead-back+off)
  ins=list(md.disasm(blob[p:],sva+p))
  idx=next((i for i,x in enumerate(ins) if x.address==callva),None)
  if idx is None: continue
  score=idx
  if best is None or score>best[0]: best=(score,ins,idx,s,raw)
 if best:return best
 ins=list(md.disasm(blob,sva)); idx=next((i for i,x in enumerate(ins) if x.address==callva),None); return (0,ins,idx,s,raw)

print('============================================================')
print(' AOTR WOTR JOIN VTABLE +0x40 VIRTUAL CALLS - DISK ONLY')
print('============================================================')
print(f'Image hash : {sys.argv[2]}')
print(f'C54CE0 VT  : 0x{VT:08X}')
print(f'VT +0x040  : 0x{struct.unpack_from("<I",data,va_to_raw(VT+0x40)[0])[0]:08X} expected=0x{JOIN:08X}')
print('')

hits=[]
for s in secs:
 if not executable(s): continue
 blob=data[s['rp']:s['rp']+s['rs']]
 # call dword ptr [reg+0x40] : FF 50..57 40
 for i in range(len(blob)-3):
  if blob[i]==0xFF and 0x50 <= blob[i+1] <= 0x57 and blob[i+2]==0x40:
   hits.append((raw_to_va(s['rp']+i,s),s['name'],'disp8'))
 # call dword ptr [reg+0x40] disp32 : FF 90..97 40 00 00 00
 for i in range(len(blob)-6):
  if blob[i]==0xFF and 0x90 <= blob[i+1] <= 0x97 and blob[i+2:i+6]==b'\x40\x00\x00\x00':
   hits.append((raw_to_va(s['rp']+i,s),s['name'],'disp32'))
hits=sorted(set(hits))
print('================ ALL INDIRECT CALL [VTABLE_REG+0x40] CANDIDATES ================')
print(f'count={len(hits)}')
for va,sn,kind in hits: print(f'0x{va:08X} section={sn} encoding={kind}')
print('')

print('================ SYNCHRONIZED VIRTUAL-CALL CONTEXTS ================')
for n,(va,sn,kind) in enumerate(hits,1):
 print(f'\n---------------- CANDIDATE #{n:02d} call=0x{va:08X} ----------------')
 score,ins,idx,s,raw=local_decode(va)
 if idx is None:
  print('<decode could not synchronize to exact call>'); continue
 lo=max(0,idx-22); hi=min(len(ins),idx+7)
 for j in range(lo,hi): print(fmt(ins[j],'>>' if j==idx else '  '))
 # compact argument evidence: previous pushes within 12 decoded instructions
 prev=ins[max(0,idx-12):idx]
 pushes=[x for x in prev if x.mnemonic=='push']
 print('  recent pushes: '+(' | '.join(f'0x{x.address:08X}:{x.op_str}' for x in pushes[-5:]) if pushes else '<none>'))
 print('  target question: is the vtable register loaded from C54CE0 session, and what are the final two pushed args?')

print('\n================ JOIN API CONTRACT ANCHOR ================')
print('C54CE0 +0x040 -> 0x84CB34')
print('0x84CB34 returns RET 8 => two stack args.')
print('arg1 [ebp+8] must be non-null for ID3 path and is used as ECX for 0x800B55(slot0).')
print('arg2 [ebp+0xC] is passed as explicit destination endpoint to 0x84C257.')
print('')
print('Interpretation targets:')
print('  1) Find every virtual invocation of session vtable +0x40.')
print('  2) Identify which candidate has ECX=session/C54CE0 and recover the two pushed arguments.')
print('  3) Resolve arg1 provenance/type from the caller, without guessing from 0x800B55 alone.')
print('  4) Resolve arg2 endpoint provenance (discovery result, selected lobby host, etc.).')
print('  5) No file or process memory is modified.')
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII
& $pyPath $tempPy $GameDat $hash
if ($LASTEXITCODE -ne 0) { throw 'vtable +0x40 virtual-call probe failed.' }
} finally { Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue }
Write-Host ''
Write-Host 'READ-ONLY COMPLETE. No file or process memory was modified.'
