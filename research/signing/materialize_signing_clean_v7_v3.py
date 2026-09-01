#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

import materialize_signing_clean_v7_v2 as v2

CAMERA_CLEAN = bytes((0xA1, 0x58, 0x49, 0xDE, 0x00, 0x91))
CAMERA_CLEAN_HASH = "9DA68ED1751B90B68C7B15B1362ABE5C84720E0A9263FC1F0FF7B085778957BA"
EXPECTED_CAMERA_OFFSETS = (0x01E, 0x201, 0x54E)
EXPECTED_CLEAN_SHELL_SHA256 = "3C4B4B8B4E80B49877C1ADD090A8C96B94A361C8295B1DB9F4BC78CA7454AF4C"


def matching_window_offsets(data: bytes, length: int, digest: str) -> list[int]:
    return [
        offset
        for offset in range(0, len(data) - length + 1)
        if v2.sha256_bytes(data[offset:offset + length]) == digest
    ]


def clean_shellcode_v3(data: bytes) -> tuple[bytes, list[int]]:
    if len(data) != 1577:
        raise RuntimeError(f"Historical shellcode length changed: {len(data)}")
    if v2.sha256_bytes(data[:12]) != v2.RAW_HASH:
        raise RuntimeError("Historical shellcode no longer starts with the pinned Raw Wheel window")
    if len(v2.CLEAN_PREFIX) != 12 or v2.sha256_bytes(v2.CLEAN_PREFIX) != v2.CLEAN_PREFIX_HASH:
        raise RuntimeError("Clean Raw Wheel semantic prefix identity mismatch")
    if len(CAMERA_CLEAN) != 6 or v2.sha256_bytes(CAMERA_CLEAN) != CAMERA_CLEAN_HASH:
        raise RuntimeError("Clean Camera Global semantic replacement identity mismatch")

    # Discover historical Camera Global occurrences by digest only.
    camera_offsets = matching_window_offsets(data, 6, v2.CAMERA_HASH)
    if tuple(camera_offsets) != EXPECTED_CAMERA_OFFSETS:
        rendered = ", ".join(f"0x{x:X}" for x in camera_offsets)
        raise RuntimeError(f"Unexpected Camera Global occurrence map: [{rendered}]")

    clean = bytearray(data)
    clean[:12] = v2.CLEAN_PREFIX
    for offset in camera_offsets:
        clean[offset:offset + 6] = CAMERA_CLEAN
    clean_bytes = bytes(clean)

    if len(clean_bytes) != 1577:
        raise RuntimeError("Clean shellcode length changed")

    # Permit changes only in the four explicitly characterized regions.
    mutable = set(range(0, 12))
    for offset in camera_offsets:
        mutable.update(range(offset, offset + 6))
    for offset, (old, new) in enumerate(zip(data, clean_bytes)):
        if old != new and offset not in mutable:
            raise RuntimeError(f"Unexpected shellcode mutation at offset 0x{offset:X}")

    # Full post-transform scan: none of the five historical windows may remain.
    for name, length, digest in v2.FORBIDDEN_WINDOWS:
        offsets = matching_window_offsets(clean_bytes, length, digest)
        if offsets:
            rendered = ", ".join(f"0x{x:X}" for x in offsets)
            raise RuntimeError(f"Forbidden historical compatibility window remains: {name} at [{rendered}]")

    actual_sha = v2.sha256_bytes(clean_bytes)
    if actual_sha != EXPECTED_CLEAN_SHELL_SHA256:
        raise RuntimeError(f"Clean shellcode SHA256 mismatch: expected {EXPECTED_CLEAN_SHELL_SHA256}, got {actual_sha}")

    return clean_bytes, camera_offsets


def main(argv: list[str]) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    historical = repo_root / "launcher-source" / "v19-successor" / "resources"
    out = Path(argv[1]).resolve() if len(argv) > 1 else (repo_root / "_SIGNING_CLEAN_V7_MATERIALIZE_V3")
    out.mkdir(parents=True, exist_ok=True)

    engine_path = historical / "launcher_engine.ps1"
    final_path = historical / "final_stable_v7.ps1"
    shell_path = historical / "v7_shellcode.bin"
    v2.require_file(engine_path, v2.EXPECTED_ENGINE, "historical Engine")
    v2.require_file(final_path, v2.EXPECTED_FINAL, "historical FINAL_STABLE_V7")
    v2.require_file(shell_path, v2.EXPECTED_SHELL, "historical V7 shellcode")

    engine = v2.clean_engine(engine_path.read_text(encoding="utf-8-sig"))
    final = v2.clean_final(final_path.read_text(encoding="utf-8-sig"))
    historical_shell = shell_path.read_bytes()
    shell, camera_offsets = clean_shellcode_v3(historical_shell)

    clean_engine_path = out / "launcher_engine_signing_clean.ps1"
    clean_final_path = out / "final_stable_v7_signing_clean.ps1"
    clean_shell_path = out / "v7_shellcode_signing_clean.bin"
    clean_engine_path.write_text(engine, encoding="utf-8", newline="\n")
    clean_final_path.write_text(final, encoding="utf-8", newline="\n")
    clean_shell_path.write_bytes(shell)

    report = {
        "schema": 3,
        "state": "NON_RELEASE_SIGNING_CLEAN_V7_MATERIALIZATION",
        "strategy": "HASH_WINDOW_COMPATIBILITY_PLUS_SEMANTIC_TRAMPOLINE_REENCODING",
        "historical": {
            "engine_sha256": v2.EXPECTED_ENGINE,
            "final_sha256": v2.EXPECTED_FINAL,
            "shellcode_sha256": v2.EXPECTED_SHELL,
        },
        "clean": {
            "engine_sha256": v2.sha256_file(clean_engine_path),
            "final_sha256": v2.sha256_file(clean_final_path),
            "shellcode_sha256": v2.sha256_file(clean_shell_path),
            "shellcode_length": len(shell),
            "raw_wheel_prefix_sha256": v2.sha256_bytes(shell[:12]),
            "camera_replacement_sha256": CAMERA_CLEAN_HASH,
            "camera_replacement_offsets": [f"0x{x:X}" for x in camera_offsets],
        },
        "compatibility_window_hashes": {
            name: {"length": length, "sha256": digest}
            for name, length, digest in v2.FORBIDDEN_WINDOWS
        },
        "invariants": {
            "only_characterized_shellcode_regions_changed": True,
            "forbidden_historical_windows_absent_from_clean_shellcode": True,
            "engine_uses_hash_compatibility_windows": True,
            "final_uses_hash_compatibility_windows": True,
            "shellcode_offsets_preserved": True,
            "shellcode_length_preserved": True,
            "public_release_modified": False,
            "field_execution_allowed": False,
        },
    }
    report_path = out / "SIGNING_CLEAN_V7_MATERIALIZATION_REPORT.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print("SIGNING_CLEAN_V7_MATERIALIZATION_V3=PASS")
    print(f"CLEAN_ENGINE_SHA256={report['clean']['engine_sha256']}")
    print(f"CLEAN_FINAL_SHA256={report['clean']['final_sha256']}")
    print(f"CLEAN_SHELLCODE_SHA256={report['clean']['shellcode_sha256']}")
    print(f"CLEAN_RAW_PREFIX_SHA256={report['clean']['raw_wheel_prefix_sha256']}")
    print(f"CLEAN_CAMERA_REPLACEMENT_SHA256={CAMERA_CLEAN_HASH}")
    print(f"CAMERA_OFFSETS={','.join(report['clean']['camera_replacement_offsets'])}")
    print(f"REPORT={report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
