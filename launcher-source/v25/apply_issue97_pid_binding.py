from pathlib import Path
import hashlib
import re
import sys

ENGINE = Path(sys.argv[1])
FINAL = Path(sys.argv[2])
GUI = Path(sys.argv[3])

EXPECTED_ENGINE_IN = "E9E2452FF56A66D57FF63C0B1654CFE0C856F4D5FA66C558E8F237C9ABABF641"
EXPECTED_FINAL_IN = "72D00490538BE2222F5BAAF3D8A1648A86071D3A098946A7B8751E7D337300E2"
EXPECTED_GUI_IN = "222B5DC9EC8B787BF11B2913601FDB06C277EB20697488DDF034852E3F253B70"
EXPECTED_GUI_OUT = "F17D8DE40DAAD271D9A85FC7C52F8B28DFAF18B35010AF587BF1D6076BA75F5F"
EXPECTED_ENGINE_OUT = "954D2FD4E23547998D2BC5323BB7026C21384CA4FCA59F7E786E6F0E18088880"
EXPECTED_FINAL_OUT = "F16522820D7B25CDD4ACF1267B8A300C6BFE661C7FEF636BB611819F7BDC84D3"

def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()

def sha_file(path: Path) -> str:
    return sha_bytes(path.read_bytes())

def require_hash(path: Path, expected: str, role: str) -> None:
    actual = sha_file(path)
    if actual != expected:
        raise SystemExit(f"{role} input hash mismatch: expected {expected}, got {actual}")

def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label} anchor count is {count}, expected 1")
    return text.replace(old, new, 1)

def regex_once(text: str, pattern: str, repl: str, label: str) -> str:
    found = re.findall(pattern, text, flags=re.MULTILINE | re.DOTALL)
    if len(found) != 1:
        raise SystemExit(f"{label} match count is {len(found)}, expected 1")
    return re.sub(pattern, repl, text, count=1, flags=re.MULTILINE | re.DOTALL)

def read_ps(path: Path) -> str:
    return path.read_bytes().decode("utf-8-sig").replace("\r\n", "\n")

def write_ps(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8-sig", newline="\n")

require_hash(ENGINE, EXPECTED_ENGINE_IN, "Engine")
require_hash(FINAL, EXPECTED_FINAL_IN, "FINAL_STABLE_V7")
require_hash(GUI, EXPECTED_GUI_IN, "GUI")

final = read_ps(FINAL)

final = replace_once(
    final,
    '    [Parameter(Mandatory=$true)]\n    [byte[]]$V7Shellcode\n)',
    '    [Parameter(Mandatory=$true)]\n    [byte[]]$V7Shellcode,\n    [int]$TargetPid = 0\n)',
    "FINAL_STABLE_V7 TargetPid parameter",
)

discovery_pattern = r'^\$target = Get-RunningTarget \$GameDat\nif \(\$null -eq \$target\) \{\n.*?^\$process\.Refresh\(\)\n'
discovery_replacement = '''$target = $null
$pidValue = [UInt32]0
$process = $null

if ($TargetPid -gt 0) {
    $pidValue = [UInt32]$TargetPid
    try {
        $process = Get-Process -Id $pidValue -ErrorAction Stop
    }
    catch {
        throw "Launcher-bound game.dat PID $TargetPid is no longer running."
    }

    # The launcher already identified this exact child process and verified its runtime
    # signatures before entering FINAL_STABLE_V7. Do not re-bind by ExecutablePath:
    # hardlink/copy fallback runtimes can legitimately execute the same game.dat bytes
    # from a different path than the original AotR installation.
    $target = Get-CimInstance Win32_Process -Filter "ProcessId = $pidValue" -ErrorAction SilentlyContinue |
        Select-Object -First 1

    Write-Host "[OK] Launcher-bound game.dat PID verwendet: $pidValue"
    if ($target -and $target.ExecutablePath) {
        $runtimePath = [IO.Path]::GetFullPath($target.ExecutablePath)
        Write-Host "RUNTIME EXE   : $runtimePath"
        if (-not [string]::Equals($runtimePath, $GameDat, [StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "[INFO] Runtime game.dat path differs from install game.dat; PID binding keeps the verified child identity."
        }
    }
    if ($target -and $target.CommandLine) {
        Write-Host "CMDLINE       : $($target.CommandLine)"
    }
}
else {
    $target = Get-RunningTarget $GameDat
    if ($null -eq $target) {
        throw @"
Die passende game.dat laeuft noch nicht. V7 wurde absichtlich nicht installiert.

Richtige Reihenfolge:
  1. Normalen AotR-8P-WotR-Launcher starten.
  2. Auf LAUNCH klicken und bis ins Spiel-Hauptmenue warten.
  3. Erst danach dieses V7-Skript als Administrator ausfuehren.

Damit kann der Launcher den Runtime-Hook nicht wieder ueberschreiben.
"@
    }

    Write-Host "[OK] Bereits laufende passende game.dat gefunden."
    $pidValue = [UInt32]$target.ProcessId
    Write-Host "[OK] Passende game.dat erkannt. PID: $pidValue"
    if ($target.CommandLine) {
        Write-Host "CMDLINE  : $($target.CommandLine)"
    }
    $process = Get-Process -Id $pidValue -ErrorAction Stop
}

$process.Refresh()
'''
final = regex_once(final, discovery_pattern, discovery_replacement, "FINAL_STABLE_V7 process binding")

write_ps(FINAL, final)
final_hash = sha_file(FINAL)

engine = read_ps(ENGINE)
engine = replace_once(
    engine,
    '$FinalStableV7Sha256 = "72D00490538BE2222F5BAAF3D8A1648A86071D3A098946A7B8751E7D337300E2"\n',
    f'$FinalStableV7Sha256 = "{final_hash}"\n',
    "Engine FINAL_STABLE_V7 dependency hash",
)
engine = replace_once(
    engine,
    '        [void]$v7.AddParameter("V7Shellcode", [byte[]]$global:AOTR8P_V7_SHELLCODE_BYTES)\n',
    '        [void]$v7.AddParameter("V7Shellcode", [byte[]]$global:AOTR8P_V7_SHELLCODE_BYTES)\n'
    '        [void]$v7.AddParameter("TargetPid", [int]$GamePid)\n',
    "Engine exact child PID handoff",
)
invoke_old = '''        $null = $v7.Invoke()

        if ($v7.HadErrors) {
            $detail = ($v7.Streams.Error | ForEach-Object { $_.ToString() }) -join " | "
            throw "FINAL_STABLE_V7 In-Memory PowerShell failed: $detail"
        }
'''
invoke_new = '''        try {
            $null = $v7.Invoke()
        }
        catch {
            $invokeError = $_
            $detail = ($v7.Streams.Error | ForEach-Object { $_.ToString() }) -join " | "
            if ([string]::IsNullOrWhiteSpace($detail)) {
                $detail = [string]$invokeError.Exception.Message
            }
            throw "FINAL_STABLE_V7 In-Memory PowerShell failed: $detail"
        }

        if ($v7.HadErrors) {
            $detail = ($v7.Streams.Error | ForEach-Object { $_.ToString() }) -join " | "
            throw "FINAL_STABLE_V7 In-Memory PowerShell failed: $detail"
        }
'''
engine = replace_once(engine, invoke_old, invoke_new, "Engine V7 child error propagation")
write_ps(ENGINE, engine)

gui = read_ps(GUI)
changelog_anchor = '''Launcher 1.16.1

- New maintainer MESSAGES play one short notification sound when first detected.
'''
changelog_new = '''Launcher 1.16.2

- Fixed V7 launch binding to use the exact game.dat child PID already verified by the launcher.
- Runtime hardlink/copy paths no longer need to equal the original AotR game.dat path for V7.
- V7 child failures now preserve the underlying error detail in support reports.

Launcher 1.16.1

- New maintainer MESSAGES play one short notification sound when first detected.
'''
gui = replace_once(gui, changelog_anchor, changelog_new, "GUI 1.16.2 changelog")
write_ps(GUI, gui)

engine_out = sha_file(ENGINE)
final_out = sha_file(FINAL)
gui_out = sha_file(GUI)

if engine_out != EXPECTED_ENGINE_OUT:
    raise SystemExit(f"Engine output hash mismatch: expected {EXPECTED_ENGINE_OUT}, got {engine_out}")
if final_out != EXPECTED_FINAL_OUT:
    raise SystemExit(f"FINAL_STABLE_V7 output hash mismatch: expected {EXPECTED_FINAL_OUT}, got {final_out}")
if gui_out != EXPECTED_GUI_OUT:
    raise SystemExit(f"GUI output hash mismatch: expected {EXPECTED_GUI_OUT}, got {gui_out}")

for required in (
    'AddParameter("TargetPid", [int]$GamePid)',
    'FINAL_STABLE_V7 In-Memory PowerShell failed: $detail',
    '$invokeError = $_',
):
    if required not in engine:
        raise SystemExit("Engine contract missing: " + required)

for required in (
    '[int]$TargetPid = 0',
    'if ($TargetPid -gt 0)',
    'Launcher-bound game.dat PID verwendet',
    '$target = Get-RunningTarget $GameDat',
):
    if required not in final:
        raise SystemExit("FINAL_STABLE_V7 contract missing: " + required)

if "Launcher 1.16.2" not in gui:
    raise SystemExit("GUI changelog contract missing")

print("ISSUE97_PID_BINDING_TRANSFORM_PASS")
print("ENGINE_SHA256=" + engine_out)
print("FINAL_STABLE_V7_SHA256=" + final_out)
print("GUI_SHA256=" + gui_out)
