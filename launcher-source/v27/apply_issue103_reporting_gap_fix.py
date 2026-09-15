from pathlib import Path
import hashlib
import re
import sys

ENGINE = Path(sys.argv[1])
FINAL = Path(sys.argv[2])
GUI = Path(sys.argv[3])

EXPECTED_ENGINE_IN = "72967D49C4D35B4A3FAEBAC4F5866D8B910B9A7FC83568D04B9BA81364AC8917"
EXPECTED_FINAL_IN = "F16522820D7B25CDD4ACF1267B8A300C6BFE661C7FEF636BB611819F7BDC84D3"
EXPECTED_GUI_IN = "D887A562E7C5700EC4F98AF49F9B807D95A5A91773E1C80091D8D97C3FE9FED3"
EXPECTED_ENGINE_OUT = "D41F32EA8C138833255C3CCF383AC1712FFA379474DB0422859AAAD936983356"
EXPECTED_GUI_OUT = "C9640A3FD18228C895BF313C2574FFA5528305D13D817E79B40498E18C0BEF91"

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

def regex_once(text: str, pattern: str, repl: str, label: str) -> str:
    matches = re.findall(pattern, text, flags=re.MULTILINE | re.DOTALL)
    if len(matches) != 1:
        raise SystemExit(f"{label} match count is {len(matches)}, expected 1")
    return re.sub(pattern, repl, text, count=1, flags=re.MULTILINE | re.DOTALL)

require_hash(ENGINE, EXPECTED_ENGINE_IN, "Engine")
require_hash(FINAL, EXPECTED_FINAL_IN, "FINAL_STABLE_V7")
require_hash(GUI, EXPECTED_GUI_IN, "GUI")

engine = read_ps(ENGINE)

engine = replace_once(
    engine,
    '    $ErrorActionPreference = "Stop"\n',
    '    $ErrorActionPreference = "Stop"\n    $script:AotR8PStructuredDiagnosticJson = ""\n',
    "Engine diagnostic state initialization",
)

old_early_exit = '''        throw ("game.dat exited during initialization; pid={0}; observed_ms={1}; exit_code={2}; runtime_location={3}; runtime_sha256={4}; wer={5}" -f
            $gamePid,
            $observedMs,
            $exitCodeText,
            $runtimeLocation,
            $runtimeSha256,
            $werSignal
        )
'''
new_early_exit = '''        $structuredDiag = [ordered]@{
            schema = 2
            kind = "gameproc_early_exit"
            process_exit_code = $exitCodeText
            observed_ms = [Int64]$observedMs
            runtime_location = $runtimeLocation
            runtime_sha256 = $(if ($runtimeSha256 -match '^[A-Fa-f0-9]{64}$') { $runtimeSha256.ToUpperInvariant() } else { $null })
            wer_signal = $(if ([string]::IsNullOrWhiteSpace($werSignal) -or $werSignal -eq "none") { $null } else { $werSignal })
        }

        try {
            $script:AotR8PStructuredDiagnosticJson = $structuredDiag | ConvertTo-Json -Compress
        }
        catch {
            $script:AotR8PStructuredDiagnosticJson = ""
        }

        throw "game.dat exited during initialization."
'''
engine = replace_once(engine, old_early_exit, new_early_exit, "Engine early-exit structured diagnostic")

old_catch_tail = '''    Write-Host "STACK:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace
    Write-Host ""
    Write-Host "AOTR8P_ENGINE_EXIT=1" -ForegroundColor Red
'''
new_catch_tail = '''    Write-Host "STACK:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace
    Write-Host ""

    try {
        $errorMessageBytes = [Text.Encoding]::UTF8.GetBytes([string]$_.Exception.Message)
        Write-Host ("AOTR8P_ERROR_MESSAGE_B64=" + [Convert]::ToBase64String($errorMessageBytes))
    }
    catch {}

    if (-not [string]::IsNullOrWhiteSpace([string]$script:AotR8PStructuredDiagnosticJson)) {
        Write-Host ("AOTR8P_DIAG_JSON=" + [string]$script:AotR8PStructuredDiagnosticJson)
    }

    Write-Host "AOTR8P_ENGINE_EXIT=1" -ForegroundColor Red
'''
engine = replace_once(engine, old_catch_tail, new_catch_tail, "Engine machine-readable catch markers")
write_ps(ENGINE, engine)

gui = read_ps(GUI)

gui = replace_once(
    gui,
    '$script:LastErrorDetail = ""\n',
    '$script:LastErrorDetail = ""\n$script:LastProcessDiagnostics = $null\n',
    "GUI process diagnostic state",
)

gui = replace_once(
    gui,
    "elseif ($d -match '(?i)Child game\\.dat|game\\.dat.*nicht gefunden|game\\.dat wurde.*beendet') {",
    "elseif ($d -match '(?i)Child game\\.dat|game\\.dat.*nicht gefunden|game\\.dat wurde.*beendet|game\\.dat exited during initialization') {",
    "GUI game-process classification",
)

helpers = r'''
function Get-EngineFailureDetailFromLog([string]$LogText) {
    if ([string]::IsNullOrWhiteSpace($LogText)) { return "" }

    try {
        $matches = [regex]::Matches($LogText, '(?m)^AOTR8P_ERROR_MESSAGE_B64=([A-Za-z0-9+/=]+)\s*$')
        if ($matches.Count -gt 0) {
            $encoded = [string]$matches[$matches.Count - 1].Groups[1].Value
            $bytes = [Convert]::FromBase64String($encoded)
            $decoded = [Text.Encoding]::UTF8.GetString($bytes)
            return (Limit-SupportText (Get-SanitizedText $decoded) 6000)
        }
    }
    catch {}

    try {
        $match = [regex]::Match($LogText,'(?ms)LAUNCHER-FEHLER\s*=+\s*(.*?)\s*POSITION:')
        if ($match.Success) {
            return (Limit-SupportText (Get-SanitizedText ([string]$match.Groups[1].Value).Trim()) 6000)
        }
    }
    catch {}

    return ""
}

function Get-StructuredEngineDiagnosticFromLog([string]$LogText) {
    if ([string]::IsNullOrWhiteSpace($LogText)) { return $null }

    try {
        $matches = [regex]::Matches($LogText, '(?m)^AOTR8P_DIAG_JSON=(\{[^\r\n]*\})\s*$')
        if ($matches.Count -eq 0) { return $null }

        $raw = [string]$matches[$matches.Count - 1].Groups[1].Value
        $diag = $raw | ConvertFrom-Json
        if ($null -eq $diag -or [string]$diag.kind -ne "gameproc_early_exit") { return $null }

        $exitCode = [string]$diag.process_exit_code
        if ([string]::IsNullOrWhiteSpace($exitCode) -or
            $exitCode -notmatch '^(?i:unavailable|0x[0-9a-f]{8}/-?\d+|-?\d+)$') {
            $exitCode = $null
        }

        $observed = 0L
        $observedValue = $null
        if ([Int64]::TryParse([string]$diag.observed_ms,[ref]$observed) -and $observed -ge 0 -and $observed -le 600000) {
            $observedValue = [Int64]$observed
        }

        $runtimeLocation = [string]$diag.runtime_location
        if ($runtimeLocation -notin @("LOCALAPPDATA","NON_LOCALAPPDATA","UNKNOWN")) {
            $runtimeLocation = $null
        }

        $runtimeSha256 = [string]$diag.runtime_sha256
        if ($runtimeSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
            $runtimeSha256 = $null
        }
        elseif (-not [string]::IsNullOrWhiteSpace($runtimeSha256)) {
            $runtimeSha256 = $runtimeSha256.ToUpperInvariant()
        }

        $werSignal = Limit-SupportText (Get-SanitizedText ([string]$diag.wer_signal)) 320
        if ([string]::IsNullOrWhiteSpace($werSignal) -or $werSignal -eq "none") {
            $werSignal = $null
        }

        return [PSCustomObject]@{
            process_exit_code = $exitCode
            observed_ms = $observedValue
            runtime_location = $runtimeLocation
            runtime_sha256 = $runtimeSha256
            wer_signal = $werSignal
        }
    }
    catch {
        Write-RepairLog ("Structured engine diagnostic could not be parsed: " + $_.Exception.Message)
        return $null
    }
}

'''
gui = replace_once(gui,'function New-SupportBundle {\n',helpers + 'function New-SupportBundle {\n',"GUI reporting helper insertion")

gui = replace_once(
    gui,
    '    $fingerprint = [string]$script:LastFingerprint\n',
    '    $fingerprint = [string]$script:LastFingerprint\n    $processDiag = $script:LastProcessDiagnostics\n',
    "GUI support-bundle diagnostic state read",
)

gui = replace_once(
    gui,
    '''    [PSCustomObject]@{
        schema = 1
        launcher_version = [string]$global:AOTR8P_LAUNCHER_VERSION
''',
    '''    [PSCustomObject]@{
        schema = 2
        launcher_version = [string]$global:AOTR8P_LAUNCHER_VERSION
''',
    "GUI support-bundle schema",
)

gui = replace_once(
    gui,
    '        last_error = $errorText\n        log_files = @("launcher_current.log","repair.log")\n',
    '''        last_error = $errorText
        process_exit_code = $(if ($processDiag) { [string]$processDiag.process_exit_code } else { $null })
        observed_ms = $(if ($processDiag -and $null -ne $processDiag.observed_ms) { [Int64]$processDiag.observed_ms } else { $null })
        runtime_location = $(if ($processDiag) { [string]$processDiag.runtime_location } else { $null })
        runtime_sha256 = $(if ($processDiag) { [string]$processDiag.runtime_sha256 } else { $null })
        wer_signal = $(if ($processDiag) { [string]$processDiag.wer_signal } else { $null })
        log_files = @("launcher_current.log","repair.log")
''',
    "GUI structured support-bundle fields",
)

gui = replace_once(
    gui,
    '''        $payload = [ordered]@{
            schema = 1
            title = (Get-LauncherReportTitleText)
''',
    '''        $payload = [ordered]@{
            schema = 2
            title = (Get-LauncherReportTitleText)
''',
    "GUI direct-report request schema",
)

timer_pattern = r'''                if \(\$current -match "AOTR8P_ENGINE_EXIT=1"\) \{\n                    \$Timer\.Stop\(\)\n                    \$lastMeaningful = .*?\n                    Enter-RepairMode \$lastMeaningful\n                    return\n                \}\n'''
timer_repl = '''                if ($current -match "AOTR8P_ENGINE_EXIT=1") {
                    $Timer.Stop()
                    $script:LastProcessDiagnostics = Get-StructuredEngineDiagnosticFromLog $current
                    $engineDetail = Get-EngineFailureDetailFromLog $current
                    if ([string]::IsNullOrWhiteSpace($engineDetail)) {
                        $engineDetail = ([regex]::Split($current,'\\r?\\n') |
                            Where-Object { $_ -and $_ -notmatch '^\\*' -and $_ -notmatch '^AOTR8P_(?:ERROR_MESSAGE_B64|DIAG_JSON)=' } |
                            Select-Object -Last 18) -join " | "
                    }
                    Enter-RepairMode $engineDetail
                    return
                }
'''
gui = regex_once(gui,timer_pattern,timer_repl,"GUI timer engine failure extraction")

old_async_fallback = '''        if (-not (Test-Path -LiteralPath $LogFile -PathType Leaf) -or
            -not (([IO.File]::ReadAllText($LogFile)) -match "AOTR8P_ENGINE_EXIT=0")) {
            $Timer.Stop()
            $detail = if (Test-Path -LiteralPath $LogFile -PathType Leaf) {
                (Get-Content -LiteralPath $LogFile -Tail 18 -ErrorAction SilentlyContinue) -join " | "
            } else { "Embedded engine stopped before logging initialized." }
            Enter-RepairMode $detail
        }
'''
new_async_fallback = '''        if (-not (Test-Path -LiteralPath $LogFile -PathType Leaf) -or
            -not (([IO.File]::ReadAllText($LogFile)) -match "AOTR8P_ENGINE_EXIT=0")) {
            $Timer.Stop()
            $detail = "Embedded engine stopped before logging initialized."
            if (Test-Path -LiteralPath $LogFile -PathType Leaf) {
                $fullLog = [IO.File]::ReadAllText($LogFile)
                $script:LastProcessDiagnostics = Get-StructuredEngineDiagnosticFromLog $fullLog
                $parsedDetail = Get-EngineFailureDetailFromLog $fullLog
                if (-not [string]::IsNullOrWhiteSpace($parsedDetail)) {
                    $detail = $parsedDetail
                }
                else {
                    $detail = (Get-Content -LiteralPath $LogFile -Tail 18 -ErrorAction SilentlyContinue |
                        Where-Object { $_ -notmatch '^AOTR8P_(?:ERROR_MESSAGE_B64|DIAG_JSON)=' }) -join " | "
                }
            }
            Enter-RepairMode $detail
        }
'''
gui = replace_once(gui,old_async_fallback,new_async_fallback,"GUI async engine failure extraction")

gui = replace_once(
    gui,
    '        $script:LastLog = ""\n        $script:RunningReached = $false\n',
    '        $script:LastLog = ""\n        $script:LastProcessDiagnostics = $null\n        $script:RunningReached = $false\n',
    "GUI clear diagnostics for new launch",
)

gui = replace_once(
    gui,
    '''Launcher 1.16.3

- Added automatic diagnostics for game.dat exiting during the initial 25-second startup window.
''',
    '''Launcher 1.16.4

- Fixed the 1.16.3 reporting gap: early game.dat exit diagnostics now survive Engine -> launcher -> support bundle -> direct-report submission.
- Added structured process_exit_code, observed_ms, runtime_location, runtime_sha256 and wer_signal fields.
- Engine error text now uses a machine-readable Base64 channel so PowerShell transcript tail formatting cannot truncate the real exception.
- Restored early game.dat exits to the A8P-GAMEPROC-001 error family.
- No gameplay, payload, WotR, V7 patch or shellcode behavior changed.

Launcher 1.16.3

- Added automatic diagnostics for game.dat exiting during the initial 25-second startup window.
''',
    "GUI 1.16.4 changelog",
)
write_ps(GUI, gui)

engine_out = sha(ENGINE)
gui_out = sha(GUI)
final_out = sha(FINAL)

if engine_out != EXPECTED_ENGINE_OUT:
    raise SystemExit(f"Engine output hash mismatch: expected {EXPECTED_ENGINE_OUT}, got {engine_out}")
if gui_out != EXPECTED_GUI_OUT:
    raise SystemExit(f"GUI output hash mismatch: expected {EXPECTED_GUI_OUT}, got {gui_out}")

for required in (
    'AOTR8P_ERROR_MESSAGE_B64=',
    'AOTR8P_DIAG_JSON=',
    'throw "game.dat exited during initialization."',
    'process_exit_code = $exitCodeText',
    'wer_signal =',
):
    if required not in engine:
        raise SystemExit("Engine reporting contract missing: " + required)

for required in (
    'function Get-EngineFailureDetailFromLog',
    'function Get-StructuredEngineDiagnosticFromLog',
    'process_exit_code = $(if ($processDiag)',
    'observed_ms = $(if ($processDiag -and',
    'runtime_location = $(if ($processDiag)',
    'runtime_sha256 = $(if ($processDiag)',
    'wer_signal = $(if ($processDiag)',
    'schema = 2',
    'game\\.dat exited during initialization',
    'Launcher 1.16.4',
):
    if required not in gui:
        raise SystemExit("GUI reporting contract missing: " + required)

if final_out != EXPECTED_FINAL_IN:
    raise SystemExit(f"FINAL_STABLE_V7 changed unexpectedly: {final_out}")

print("ISSUE103_REPORTING_GAP_TRANSFORM_PASS")
print("ENGINE_SHA256=" + engine_out)
print("GUI_SHA256=" + gui_out)
print("FINAL_STABLE_V7_SHA256=" + final_out)
