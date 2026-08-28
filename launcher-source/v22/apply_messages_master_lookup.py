from pathlib import Path
import argparse
import hashlib

EXPECTED_INPUT = "4BC7F23B763C8F38AD36557B95A68717A101E2290A9CDAFAEEA104909BB301AE"
OLD = b"$query = [Uri]::EscapeDataString('repo:eliaauditore/AotR-8P-WotR label:master-ticket \"' + $Fingerprint + '\"')"
NEW = b"$query = [Uri]::EscapeDataString('repo:eliaauditore/AotR-8P-WotR is:issue label:master-ticket \"' + $Fingerprint + '\"')"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("gui_path")
    args = parser.parse_args()
    path = Path(args.gui_path)
    data = path.read_bytes()
    actual = hashlib.sha256(data).hexdigest().upper()
    if actual != EXPECTED_INPUT:
        raise SystemExit(f"messages lookup input GUI hash mismatch: expected {EXPECTED_INPUT}, got {actual}")
    count = data.count(OLD)
    if count != 1:
        raise SystemExit(f"messages lookup anchor count={count}; expected 1")
    patched = data.replace(OLD, NEW, 1)
    if patched.count(OLD) != 0 or patched.count(NEW) != 1:
        raise SystemExit("messages lookup transform verification failed")
    path.write_bytes(patched)
    print("MESSAGES_MASTER_LOOKUP_PATCH_PASS")
    print(f"GUI_SHA256={sha256(path)}")


if __name__ == "__main__":
    main()
