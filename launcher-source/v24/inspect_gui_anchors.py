from pathlib import Path
import argparse

KEYWORDS = (
    "MESSAGES",
    "latest_message_id",
    "last_seen_message_id",
    "REFRESH",
)
RANGES = ((930, 1045), (1240, 1310), (1770, 1820), (1875, 1900), (2558, 2615))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("gui_path")
    args = parser.parse_args()
    path = Path(args.gui_path)
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    lines = text.splitlines()
    hits = set()
    for start, end in RANGES:
        for line_no in range(start, min(end, len(lines)) + 1):
            hits.add(line_no - 1)
    for i, line in enumerate(lines):
        if any(k in line for k in KEYWORDS):
            for j in range(max(0, i - 3), min(len(lines), i + 4)):
                hits.add(j)
    for i in sorted(hits):
        print(f"{i+1:04d}: {lines[i]}")


if __name__ == "__main__":
    main()
