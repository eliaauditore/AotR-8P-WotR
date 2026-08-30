from pathlib import Path
import argparse
import importlib.util
import re


def load_base_module():
    path = Path(__file__).with_name("apply_issue84_session_runtime_rc2_hardening.py")
    spec = importlib.util.spec_from_file_location("issue84_rc2_base", str(path))
    if spec is None or spec.loader is None:
        raise SystemExit("could not load RC2 base hardening module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def canonicalize_launcher_pid_anchor(path: Path) -> None:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")

    assign_pattern = re.compile(
        r'(?m)^[ \t]*\$launcherPid[ \t]*=[ \t]*(?:\[int\][ \t]*)?\$launcher\.Id[ \t]*$'
    )
    assign_matches = list(assign_pattern.finditer(text))
    if len(assign_matches) != 1:
        raise SystemExit(f"launcher PID assignment count={len(assign_matches)}")

    log_pattern = re.compile(
        r'(?m)^[ \t]*Write-Host[ \t]+["\']lotrbfme2ep1\.exe PID:[ ]*\$launcherPid["\'][ \t]+-ForegroundColor[ \t]+Green[ \t]*$'
    )
    log_matches = list(log_pattern.finditer(text))
    if len(log_matches) > 1:
        raise SystemExit(f"launcher PID log count={len(log_matches)}")

    # Remove the pre-existing PID log wherever it occurs so the base RC2 patch
    # receives exactly one stable two-line anchor. The log is presentation only.
    if len(log_matches) == 1:
        m = log_matches[0]
        start = m.start()
        end = m.end()
        if end < len(text) and text[end] == "\n":
            end += 1
        text = text[:start] + text[end:]

    assign_matches = list(assign_pattern.finditer(text))
    if len(assign_matches) != 1:
        raise SystemExit(f"launcher PID assignment after log normalization count={len(assign_matches)}")
    m = assign_matches[0]
    line_end = m.end()
    if line_end < len(text) and text[line_end] == "\n":
        line_end += 1

    canonical = (
        '$launcherPid = $launcher.Id\n'
        'Write-Host "lotrbfme2ep1.exe PID: $launcherPid" -ForegroundColor Green\n'
    )
    text = text[:m.start()] + canonical + text[line_end:]

    if text.count('$launcherPid = $launcher.Id\nWrite-Host "lotrbfme2ep1.exe PID: $launcherPid" -ForegroundColor Green\n') != 1:
        raise SystemExit("canonical launcher PID anchor was not produced exactly once")

    path.write_text(text, encoding="utf-8-sig", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("engine")
    parser.add_argument("gui")
    parser.add_argument("csharp")
    args = parser.parse_args()

    engine = Path(args.engine)
    canonicalize_launcher_pid_anchor(engine)

    base = load_base_module()
    base.patch_engine(engine)
    base.patch_gui(Path(args.gui))
    base.patch_csharp(Path(args.csharp))
    print("ISSUE84_SESSION_RUNTIME_RC2_HARDENING_V2_PASS")


if __name__ == "__main__":
    main()
