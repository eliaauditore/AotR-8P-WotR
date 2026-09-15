from pathlib import Path
import hashlib
import sys

ENGINE = Path(sys.argv[1])
FINAL = Path(sys.argv[2])
GUI = Path(sys.argv[3])

EXPECTED_ENGINE_IN = "954D2FD4E23547998D2BC5323BB7026C21384CA4FCA59F7E786E6F0E18088880"
EXPECTED_FINAL_IN = "F16522820D7B25CDD4ACF1267B8A300C6BFE661C7FEF636BB611819F7BDC84D3"
EXPECTED_GUI_IN = "F17D8DE40DAAD271D9A85FC7C52F8B28DFAF18B35010AF587BF1D6076BA75F5F"

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def require_hash(path: Path, expected: str, role: str) -> None:
    actual = sha(path)
    if actual != expected:
        raise SystemExit(f"{role} input hash mismatch: expected {expected}, got {actual}")

def read_ps(path: Path) -> str:
    return path.read_bytes().decode("utf-8-sig").replace("\r\n", "\n")

def write_ps(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8-sig", newline="\n")

def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label} anchor count is {count}, expected 1")
    return text.replace(old, new, 1)

require_hash(ENGINE, EXPECTED_ENGINE_IN, "Engine")
require_hash(FINAL, EXPECTED_FINAL_IN, "FINAL_STABLE_V7")
require_hash(GUI, EXPECTED_GUI_IN, "GUI")

engine = read_ps(ENGINE)

pid_anchor = '$gamePid = [int]$gameInfo.ProcessId\n'
pid_insert = '''$gamePid = [int]$gameInfo.ProcessId

# Issue #100 diagnostics: retain the exact process object while it is alive so an
# early startup exit can report the real exit code instead of only "process gone".
$gameObserved = [Diagnostics.Stopwatch]::StartNew()
$gameTracker = $null
$runtimeLocation = "UNKNOWN"
$runtimeSha256 = "n/a"

try {
    $gameTracker = [Diagnostics.Process]::GetProcessById($gamePid)
}
catch {}

try {
    $runtimeExe = [string]$gameInfo.ExecutablePath
    if (-not [string]::IsNullOrWhiteSpace($runtimeExe)) {
        $runtimeFull = [IO.Path]::GetFullPath($runtimeExe)
        $localRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if (-not [string]::IsNullOrWhiteSpace($localRoot) -and
            $runtimeFull.StartsWith([IO.Path]::GetFullPath($localRoot), [StringComparison]::OrdinalIgnoreCase)) {
            $runtimeLocation = "LOCALAPPDATA"
        }
        else {
            $runtimeLocation = "NON_LOCALAPPDATA"
        }

        if (Test-Path -LiteralPath $runtimeFull -PathType Leaf) {
            $runtimeSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeFull).Hash
        }
    }
}
catch {}
'''
engine = replace_once(engine, pid_anchor, pid_insert, "game.dat PID tracking")

exit_anchor = '        throw "game.dat wurde während der Initialisierung beendet."\n'
exit_block = '''        $observedMs = [int64]$gameObserved.ElapsedMilliseconds
        $exitCodeText = "unavailable"

        if ($gameTracker) {
            try {
                [void]$gameTracker.WaitForExit(1000)
                if ($gameTracker.HasExited) {
                    $signedExitCode = [int]$gameTracker.ExitCode
                    $exitCodeHex = [BitConverter]::ToUInt32([BitConverter]::GetBytes($signedExitCode), 0)
                    $exitCodeText = ("0x{0:X8}/{1}" -f $exitCodeHex, $signedExitCode)
                }
            }
            catch {}
        }

        # Keep WER evidence privacy-safe: provider/id, exception code and module basename only.
        $werSignal = "none"
        try {
            $events = @(Get-WinEvent -FilterHashtable @{
                LogName = "Application"
                StartTime = (Get-Date).AddMinutes(-2)
                Id = 1000,1001
            } -MaxEvents 30 -ErrorAction SilentlyContinue)

            foreach ($evt in $events) {
                if ([string]$evt.Message -notmatch "(?i)game\\.dat") {
                    continue
                }

                $exceptionCode = ""
                $moduleName = ""
                try {
                    [xml]$eventXml = $evt.ToXml()
                    $dataMap = @{}
                    foreach ($node in @($eventXml.Event.EventData.Data)) {
                        $name = [string]$node.Name
                        if (-not [string]::IsNullOrWhiteSpace($name)) {
                            $dataMap[$name] = [string]$node.'#text'
                        }
                    }
                    if ($dataMap.ContainsKey("ExceptionCode")) {
                        $exceptionCode = [string]$dataMap["ExceptionCode"]
                    }
                    if ($dataMap.ContainsKey("ModuleName")) {
                        $moduleName = [IO.Path]::GetFileName([string]$dataMap["ModuleName"])
                    }
                }
                catch {}

                $werSignal = ("{0}/{1}/exception={2}/module={3}" -f
                    [string]$evt.ProviderName,
                    [int]$evt.Id,
                    $(if ([string]::IsNullOrWhiteSpace($exceptionCode)) { "n/a" } else { $exceptionCode }),
                    $(if ([string]::IsNullOrWhiteSpace($moduleName)) { "n/a" } else { $moduleName })
                )
                break
            }
        }
        catch {}

        throw ("game.dat exited during initialization; pid={0}; observed_ms={1}; exit_code={2}; runtime_location={3}; runtime_sha256={4}; wer={5}" -f
            $gamePid,
            $observedMs,
            $exitCodeText,
            $runtimeLocation,
            $runtimeSha256,
            $werSignal
        )
'''
engine = replace_once(engine, exit_anchor, exit_block, "early game.dat exit evidence")
write_ps(ENGINE, engine)

gui = read_ps(GUI)
changelog_anchor = '''Launcher 1.16.2

- Fixed V7 launch binding to use the exact game.dat child PID already verified by the launcher.
'''
changelog_new = '''Launcher 1.16.3

- Added automatic diagnostics for game.dat exiting during the initial 25-second startup window.
- Support reports now preserve the process exit code, observed lifetime, sanitized runtime location/hash, and available privacy-safe Windows crash signal.
- No gameplay, payload, WotR, or V7 patch behavior changed.

Launcher 1.16.2

- Fixed V7 launch binding to use the exact game.dat child PID already verified by the launcher.
'''
gui = replace_once(gui, changelog_anchor, changelog_new, "GUI 1.16.3 changelog")
write_ps(GUI, gui)

engine_out = sha(ENGINE)
gui_out = sha(GUI)
final_out = sha(FINAL)

for required in (
    '$gameTracker = [Diagnostics.Process]::GetProcessById($gamePid)',
    '$gameTracker.WaitForExit(1000)',
    'exit_code={2}',
    'runtime_location={3}',
    'runtime_sha256={4}',
    'wer={5}',
):
    if required not in engine:
        raise SystemExit("Engine diagnostic contract missing: " + required)

if "Launcher 1.16.3" not in gui:
    raise SystemExit("GUI diagnostic changelog missing")

print("ISSUE100_EARLY_EXIT_DIAGNOSTIC_TRANSFORM_PASS")
print("ENGINE_SHA256=" + engine_out)
print("GUI_SHA256=" + gui_out)
print("FINAL_STABLE_V7_SHA256=" + final_out)
