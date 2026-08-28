param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat',
    [uint32]$StartVA = 0x007882F0,
    [uint32]$StopVA  = 0x00788570
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Fast replacement for the full dumpbin disassembly probe.
# Disassembles only the small VA window around the known GameInfo publish tail.
# No process is opened and no file is modified.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ImageBase = [uint32]0x00400000

if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

# Prefer llvm-objdump because it supports exact start/stop addresses.
$llvm = Get-Command llvm-objdump.exe -ErrorAction SilentlyContinue
if (-not $llvm) {
    $roots = @(
        "$env:ProgramFiles\Microsoft Visual Studio\2022",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022"
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $roots) {
        $hit = Get-ChildItem -LiteralPath $root -Filter llvm-objdump.exe -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { $llvm = $hit; break }
    }
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR PUBLISH EDI TRACE - FAST RANGE ONLY'
Write-Host '============================================================'
Write-Host ("Image   : {0}" -f $GameDat)
Write-Host ("SHA256  : {0}" -f $hash)
Write-Host ("Range   : 0x{0:X8} - 0x{1:X8}" -f $StartVA,$StopVA)
Write-Host ''

if ($llvm) {
    $llvmPath = if ($llvm -is [System.Management.Automation.CommandInfo]) { $llvm.Source } else { $llvm.FullName }
    Write-Host ("Backend : llvm-objdump -> {0}" -f $llvmPath)
    Write-Host ''

    $args = @(
        '-d',
        '--x86-asm-syntax=intel',
        ('--start-address=0x{0:X}' -f $StartVA),
        ('--stop-address=0x{0:X}' -f $StopVA),
        $GameDat
    )
    $out = & $llvmPath @args 2>&1
    $out | ForEach-Object { $_ }

    Write-Host ''
    Write-Host '================ EDI TOUCHES ================='
    $out | Where-Object { $_ -match '\bedi\b' -or $_ -match '\bdi\b' } | ForEach-Object { $_ }

    Write-Host ''
    Write-Host '============= GAMEINFO GLOBAL TOUCHES ========='
    $out | Where-Object {
        $_ -match 'de892c' -or $_ -match 'de7d6c' -or $_ -match 'de8930'
    } | ForEach-Object { $_ }

    Write-Host ''
    Write-Host 'READ-ONLY COMPLETE.'
    exit 0
}

# Fast fallback: Python + capstone. We intentionally do NOT auto-install packages.
$py = Get-Command py.exe -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python.exe -ErrorAction SilentlyContinue }
if (-not $py) {
    throw 'No llvm-objdump and no Python found. Install LLVM tooling or Python+capstone.'
}

$pyPath = $py.Source
& $pyPath -c "import capstone" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'No llvm-objdump found. Python is available, but capstone is missing.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host ('Install once with:  "{0}" -m pip install --user capstone' -f $pyPath) -ForegroundColor Yellow
    Write-Host 'Then rerun this script. It will disassemble only ~640 bytes.' -ForegroundColor Yellow
    exit 2
}

Write-Host ("Backend : Python capstone -> {0}" -f $pyPath)
Write-Host ''

$tempPy = Join-Path $env:TEMP ('a8p_edi_fast_' + [guid]::NewGuid().ToString('N') + '.py')
try {
@'
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path = sys.argv[1]
start_va = int(sys.argv[2], 16)
stop_va = int(sys.argv[3], 16)
IMAGE_BASE = 0x00400000

with open(path, 'rb') as f:
    data = f.read()

if data[:2] != b'MZ':
    raise SystemExit('Not MZ')
pe = struct.unpack_from('<I', data, 0x3C)[0]
if data[pe:pe+4] != b'PE\\0\\0':
    raise SystemExit('Bad PE')
num = struct.unpack_from('<H', data, pe+6)[0]
opt_size = struct.unpack_from('<H', data, pe+20)[0]
sec = pe + 24 + opt_size
sections=[]
for i in range(num):
    o=sec+i*40
    name=data[o:o+8].split(b'\\0',1)[0].decode('ascii','replace')
    vs,rva,raw_size,raw_ptr=struct.unpack_from('<IIII', data, o+8)
    sections.append((name,rva,vs,raw_ptr,raw_size))

def va_to_raw(va):
    rva=va-IMAGE_BASE
    for name,srva,vs,rp,rs in sections:
        span=max(vs,rs)
        if srva <= rva < srva+span:
            return rp+(rva-srva)
    raise ValueError(f'VA 0x{va:08X} not in section')

raw0=va_to_raw(start_va)
raw1=va_to_raw(stop_va-1)+1
code=data[raw0:raw1]
md=Cs(CS_ARCH_X86, CS_MODE_32)
md.detail=False
lines=[]
for ins in md.disasm(code,start_va):
    b=' '.join(f'{x:02X}' for x in ins.bytes)
    line=f'0x{ins.address:08X}: {b:<30} {ins.mnemonic:<8} {ins.op_str}'
    lines.append(line)
    print(line)
print('\n================ EDI TOUCHES =================')
for line in lines:
    l=line.lower()
    if 'edi' in l or ', di' in l or ' di,' in l:
        print(line)
print('\n============= GAMEINFO GLOBAL TOUCHES =========')
for line in lines:
    l=line.lower()
    if '0xde892c' in l or '0xde7d6c' in l or '0xde8930' in l:
        print(line)
'@ | Set-Content -LiteralPath $tempPy -Encoding ASCII

    & $pyPath $tempPy ('0x{0:X}' -f $StartVA) ('0x{0:X}' -f $StopVA) $GameDat
    if ($LASTEXITCODE -ne 0) {
        # Correct argument order for the generated Python helper.
        & $pyPath $tempPy $GameDat ('0x{0:X}' -f $StartVA) ('0x{0:X}' -f $StopVA)
        if ($LASTEXITCODE -ne 0) { throw 'Python capstone disassembly failed.' }
    }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'READ-ONLY COMPLETE.'
