from pathlib import Path
import argparse


def patch_gui(path: Path) -> None:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    old = '''        $managed = ($name -eq "_AOTR_8P_WOTR_RUNTIME") -or
            ($name -match '^_AOTR_8P_WOTR_RUNTIME_V4_\\d+$') -or
            ($name -match '^_AOTR_8P_WOTR_RUNTIME_REPAIR_\\d{8}_\\d{6}_\\d+$') -or
            ($name -match '^_AOTR_8P_WOTR_RUNTIME_V4_\\d+_REPAIR_\\d{8}_\\d{6}_\\d+$')
'''
    new = '''        $managed = ($name -eq "_AOTR_8P_WOTR_RUNTIME") -or
            ($name -match '^_AOTR_8P_WOTR_RUNTIME_V4_\\d+$') -or
            ($name -match '^_AOTR_8P_WOTR_RUNTIME(?:_V4_\\d+)?(?:_REPAIR_\\d{8}_\\d{6}_\\d+)+$')
'''
    if text.count(old) != 1:
        raise SystemExit(f"legacy cleanup matcher anchor count={text.count(old)}")
    text = text.replace(old, new, 1)
    required = [
        "(?:_V4_\\d+)?",
        "(?:_REPAIR_\\d{8}_\\d{6}_\\d+)+",
    ]
    for needle in required:
        if needle not in text:
            raise SystemExit(f"chained legacy cleanup contract missing: {needle}")
    path.write_text(text, encoding="utf-8-sig", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("gui")
    args = parser.parse_args()
    patch_gui(Path(args.gui))
    print("ISSUE84_CHAINED_LEGACY_CLEANUP_HARDENING_PASS")


if __name__ == "__main__":
    main()
