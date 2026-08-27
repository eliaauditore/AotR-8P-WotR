from pathlib import Path
import base64
import hashlib
import re
import sys

SRC = Path(sys.argv[1])
OUT_SCRIPT = Path(sys.argv[2])
OUT_SHELLCODE = Path(sys.argv[3])

EXPECTED_INPUT = "FEAF40B3B231646CD8F7C7099D1E8544090D5010F1C6DB06E5B2F3EF8C0C5F44"
EXPECTED_SHELLCODE = "60EECE4660C3BA0AD183EB82B82DCDACF3ECA6DC892C8FAFCD629A92170ED45A"
EXPECTED_OUTPUT = "72D00490538BE2222F5BAAF3D8A1648A86071D3A098946A7B8751E7D337300E2"
EXPECTED_LENGTH = 1577


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def sha_file(path: Path) -> str:
    return sha_bytes(path.read_bytes())


raw = SRC.read_bytes()
if sha_bytes(raw) != EXPECTED_INPUT:
    raise SystemExit("FINAL_STABLE_V7 frozen input hash mismatch")

text = raw.decode("utf-8-sig").replace("\r\n", "\n")
param_anchor = "    [single]$DragSpeed = -16.0\n)"
param_replacement = "    [single]$DragSpeed = -16.0,\n    [Parameter(Mandatory=$true)]\n    [byte[]]$V7Shellcode\n)"
if text.count(param_anchor) != 1:
    raise SystemExit("V7 parameter block anchor is not unique")
text = text.replace(param_anchor, param_replacement, 1)
pattern = r"(?ms)^\$ShellcodeBase64\s*=\s*@'\n(.*?)\n'@\n\[byte\[\]\]\$ShellcodeTemplate\s*=\s*\[Convert\]::FromBase64String\(\(\$ShellcodeBase64\s+-replace\s+'\\s',\s*''\)\)\n"
match = re.search(pattern, text)
if not match:
    raise SystemExit("Could not locate frozen V7 shellcode block")
if len(re.findall(pattern, text)) != 1:
    raise SystemExit("V7 shellcode block is not unique")

payload = base64.b64decode("".join(match.group(1).split()), validate=True)
if len(payload) != EXPECTED_LENGTH:
    raise SystemExit(f"V7 shellcode length mismatch: {len(payload)}")
if sha_bytes(payload) != EXPECTED_SHELLCODE:
    raise SystemExit("V7 shellcode SHA256 mismatch")

replacement = '''[byte[]]$ShellcodeTemplate = [byte[]]$V7Shellcode
if ($null -eq $ShellcodeTemplate -or $ShellcodeTemplate.Length -eq 0) {
    throw "Interner V7-Shellcode-Resource fehlt."
}
'''
text = re.sub(pattern, replacement, text, count=1)

if "FromBase64String" in text or "ShellcodeBase64" in text:
    raise SystemExit("Legacy V7 Base64 decoder remains")
if "$V7Shellcode" not in text:
    raise SystemExit("Explicit V7 shellcode parameter missing")
if "AOTR8P_V7_SHELLCODE_BYTES" in text:
    raise SystemExit("V7 child still depends on parent global scope")

OUT_SCRIPT.parent.mkdir(parents=True, exist_ok=True)
OUT_SHELLCODE.parent.mkdir(parents=True, exist_ok=True)
# PowerShell 5.1 needs a BOM for reliable Unicode parsing of source files.
OUT_SCRIPT.write_text(text, encoding="utf-8-sig", newline="\n")
OUT_SHELLCODE.write_bytes(payload)

if sha_file(OUT_SCRIPT) != EXPECTED_OUTPUT:
    raise SystemExit("Clean FINAL_STABLE_V7 output hash mismatch")
if sha_file(OUT_SHELLCODE) != EXPECTED_SHELLCODE:
    raise SystemExit("Written V7 shellcode resource hash mismatch")

print("CLEAN_FINAL_STABLE_V7_SHA256=" + sha_file(OUT_SCRIPT))
print("V7_SHELLCODE_SHA256=" + sha_file(OUT_SHELLCODE))
print("V7_SHELLCODE_LENGTH=" + str(len(payload)))
