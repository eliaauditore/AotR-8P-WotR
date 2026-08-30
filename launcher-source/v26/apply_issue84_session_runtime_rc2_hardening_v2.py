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
    pattern = re.compile(
        r'(?m)^[ \t]*\$launcherPid = \$launcher\.Id[ \t]*\n'
        r'[ \t]*Write-Host "lotrbfme2ep1\.exe PID: \$launcherPid" -ForegroundColor Green[ \t]*\n'
    )
    canonical = (
        '$launcherPid = $launcher.Id\n'
        'Write-Host "lotrbfme2ep1.exe PID: $launcherPid" -ForegroundColor Green\n'
    )
    text2, count = pattern.subn(canonical, text, count=1)
    if count != 1:
        raise SystemExit(f"launcher PID canonicalization count={count}")
    path.write_text(text2, encoding="utf-8-sig", newline="\n")


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
