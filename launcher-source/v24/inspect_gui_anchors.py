from pathlib import Path
import argparse

KEYWORDS = (
    "MESSAGES",
    "latest_message_id",
    "last_seen_message_id",
    "latestMessage",
    "lastSeen",
    "messageButton",
    "btnMessage",
    "Button",
    "REFRESH",
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("gui_path")
    args = parser.parse_args()
    path = Path(args.gui_path)
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    lines = text.splitlines()
    hits = set()
    for i, line in enumerate(lines):
        if any(k in line for k in KEYWORDS):
            for j in range(max(0, i - 3), min(len(lines), i + 4)):
                hits.add(j)
    for i in sorted(hits):
        print(f"{i+1:04d}: {lines[i]}")


if __name__ == "__main__":
    main()
