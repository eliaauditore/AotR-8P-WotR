from pathlib import Path
import argparse


def patch_engine(path: Path) -> None:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")

    fallback_old = '''    if ($needBuild -and (Test-Path -LiteralPath $test)) {
        # Never recurse-delete a folder that may contain junctions to the user's AotR.
        # Use a fresh sibling runtime instead.
        $script:test = Join-Path $runtimeStageRoot ("_AOTR_8P_WOTR_RUNTIME_V4_" + $PID)
        $test = $script:test
        $script:uiActive = Join-Path $test "!!!WOTR_8P_UI_TEST.big"
        $uiActive = $script:uiActive
        $marker = Join-Path $test "AOTR8P_V4_SOURCE.txt"
    }
'''
    fallback_new = '''    if ($needBuild -and (Test-Path -LiteralPath $test)) {
        # Session names are unique. If a collision somehow exists, allocate a
        # second session ID instead of creating any legacy V4/persistent name.
        $sessionId = "AOTR8P_SESSION_" + $PID + "_" + [Guid]::NewGuid().ToString("N")
        $script:test = Join-Path $runtimeStageRoot $sessionId
        $test = $script:test
        $script:AotR8PSessionPath = $test
        $script:uiActive = Join-Path $test "!!!WOTR_8P_UI_TEST.big"
        $uiActive = $script:uiActive
        $marker = Join-Path $test "AOTR8P_V4_SOURCE.txt"
    }
'''
    if text.count(fallback_old) != 1:
        raise SystemExit(f"legacy V4 fallback anchor count={text.count(fallback_old)}")
    text = text.replace(fallback_old, fallback_new, 1)

    prepare_anchor = "function Prepare-PortableModLayer {\n"
    marker_fn = r'''function Write-AotR8PSessionMarker([int]$GameLauncherPid, [int]$GamePid) {
    if (-not (Test-Path -LiteralPath $test -PathType Container)) { return }
    $sessionMarker = Join-Path $test "AOTR8P_SESSION.json"
    $sessionState = [ordered]@{
        schema = 1
        launcher_pid = [int]$PID
        game_launcher_pid = [int]$GameLauncherPid
        game_pid = [int]$GamePid
        created_utc = [DateTime]::UtcNow.ToString("o")
    }
    $sessionState | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $sessionMarker -Encoding UTF8
}

'''
    if text.count(prepare_anchor) != 1:
        raise SystemExit(f"Prepare-PortableModLayer anchor count={text.count(prepare_anchor)}")
    text = text.replace(prepare_anchor, marker_fn + prepare_anchor, 1)

    create_anchor = '''    if ($needBuild) {
        New-Item -ItemType Directory -Force -Path $test | Out-Null
        Write-Host "Baue saubere AotR-8P-Laufzeitschicht..." -ForegroundColor Cyan
'''
    create_new = '''    if ($needBuild) {
        New-Item -ItemType Directory -Force -Path $test | Out-Null
        Write-AotR8PSessionMarker -GameLauncherPid 0 -GamePid 0
        Write-Host "Baue saubere AotR-8P-Laufzeitschicht..." -ForegroundColor Cyan
'''
    if text.count(create_anchor) != 1:
        raise SystemExit(f"session creation marker anchor count={text.count(create_anchor)}")
    text = text.replace(create_anchor, create_new, 1)

    if '_AOTR_8P_WOTR_RUNTIME_V4_" + $PID' in text:
        raise SystemExit("legacy V4 runtime creation remains after hardening")
    if "Write-AotR8PSessionMarker -GameLauncherPid 0 -GamePid 0" not in text:
        raise SystemExit("prelaunch session marker missing")
    path.write_text(text, encoding="utf-8-sig", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("engine")
    args = parser.parse_args()
    patch_engine(Path(args.engine))
    print("ISSUE84_SESSION_RUNTIME_HARDENING_PASS")


if __name__ == "__main__":
    main()
