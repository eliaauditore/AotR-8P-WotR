from pathlib import Path
import argparse
import hashlib

EXPECTED_INPUT = "25F1BC0B00EED30144215D1979E3B00663FAF20941AB5929B9396AF66EFF1C81"
OLD = b'        $comments = @(Get-HttpText ("$GitHubApiRoot/issues/$MasterIssue/comments?per_page=100") | ConvertFrom-Json)'


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("gui_path")
    args = parser.parse_args()
    path = Path(args.gui_path)
    data = path.read_bytes()
    actual = sha256_bytes(data)
    if actual != EXPECTED_INPUT:
        raise SystemExit(f"messages comments input GUI hash mismatch: expected {EXPECTED_INPUT}, got {actual}")
    count = data.count(OLD)
    if count != 1:
        raise SystemExit(f"messages comments anchor count={count}; expected 1")
    nl = b"\r\n" if b"\r\n" in data else b"\n"
    new = (
        b'        $parsedComments = Get-HttpText ("$GitHubApiRoot/issues/$MasterIssue/comments?per_page=100") | ConvertFrom-Json'
        + nl
        + b'        $comments = @($parsedComments)'
    )
    data = data.replace(OLD, new, 1)
    if OLD in data or data.count(b'$comments = @($parsedComments)') != 1:
        raise SystemExit("messages comments transform verification failed")
    path.write_bytes(data)
    print("MESSAGES_PS5_COMMENTS_ARRAY_PATCH_PASS")
    print(f"GUI_SHA256={sha256_bytes(data)}")


if __name__ == "__main__":
    main()
