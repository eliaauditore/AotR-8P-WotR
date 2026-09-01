#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import materialize_signing_clean_v7_v2 as v2
import materialize_signing_clean_v7_v3 as v3

EXPECTED_CLEAN_FINAL_SHA256 = "125A29EEFE6DF8C38467BDFBA3502118A041B0243A1B72903D969356CA33F49C"


def bind_engine_to_clean_final(engine: str, clean_final_sha256: str) -> str:
    pattern = r'(?m)^\$FinalStableV7Sha256\s*=\s*"[A-Fa-f0-9]{64}"\s*$'
    replacement = f'$FinalStableV7Sha256 = "{clean_final_sha256}"'
    return v2.replace_once(engine, pattern, replacement, "Engine -> clean FINAL hash binding")


def read_bound_final_hash(engine: str) -> str:
    match = re.search(r'(?m)^\$FinalStableV7Sha256\s*=\s*"([A-Fa-f0-9]{64})"\s*$', engine)
    if not match:
        raise RuntimeError("Clean Engine FINAL_STABLE_V7 hash constant missing")
    return match.group(1).upper()


def main(argv: list[str]) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    historical = repo_root / "launcher-source" / "v19-successor" / "resources"
    out = Path(argv[1]).resolve() if len(argv) > 1 else (repo_root / "_SIGNING_CLEAN_V7_MATERIALIZE_V4")
    out.mkdir(parents=True, exist_ok=True)

    engine_path = historical / "launcher_engine.ps1"
    final_path = historical / "final_stable_v7.ps1"
    shell_path = historical / "v7_shellcode.bin"
    v2.require_file(engine_path, v2.EXPECTED_ENGINE, "historical Engine")
    v2.require_file(final_path, v2.EXPECTED_FINAL, "historical FINAL_STABLE_V7")
    v2.require_file(shell_path, v2.EXPECTED_SHELL, "historical V7 shellcode")

    # FINAL is produced first so Engine binds to the exact bytes that will be embedded.
    final = v2.clean_final(final_path.read_text(encoding="utf-8-sig"))
    clean_final_path = out / "final_stable_v7_signing_clean.ps1"
    clean_final_path.write_text(final, encoding="utf-8", newline="\n")
    clean_final_sha = v2.sha256_file(clean_final_path)
    if clean_final_sha != EXPECTED_CLEAN_FINAL_SHA256:
        raise RuntimeError(
            f"Clean FINAL identity changed: expected {EXPECTED_CLEAN_FINAL_SHA256}, got {clean_final_sha}"
        )

    engine = v2.clean_engine(engine_path.read_text(encoding="utf-8-sig"))
    engine = bind_engine_to_clean_final(engine, clean_final_sha)
    if read_bound_final_hash(engine) != clean_final_sha:
        raise RuntimeError("Clean Engine does not bind to the exact clean FINAL hash")

    historical_shell = shell_path.read_bytes()
    shell, camera_offsets = v3.clean_shellcode_v3(historical_shell)

    clean_engine_path = out / "launcher_engine_signing_clean.ps1"
    clean_shell_path = out / "v7_shellcode_signing_clean.bin"
    clean_engine_path.write_text(engine, encoding="utf-8", newline="\n")
    clean_shell_path.write_bytes(shell)

    # Re-read from disk: evidence is against actual output bytes, not only in-memory strings.
    disk_engine = clean_engine_path.read_text(encoding="utf-8")
    disk_final_sha = v2.sha256_file(clean_final_path)
    disk_bound_sha = read_bound_final_hash(disk_engine)
    if disk_bound_sha != disk_final_sha:
        raise RuntimeError(f"Engine/FINAL disk cross-resource mismatch: engine={disk_bound_sha} final={disk_final_sha}")

    report = {
        "schema": 4,
        "state": "NON_RELEASE_SIGNING_CLEAN_V7_MATERIALIZATION",
        "strategy": "HASH_WINDOW_COMPATIBILITY_PLUS_SEMANTIC_TRAMPOLINE_REENCODING",
        "historical": {
            "engine_sha256": v2.EXPECTED_ENGINE,
            "final_sha256": v2.EXPECTED_FINAL,
            "shellcode_sha256": v2.EXPECTED_SHELL,
        },
        "clean": {
            "engine_sha256": v2.sha256_file(clean_engine_path),
            "final_sha256": disk_final_sha,
            "engine_expected_final_sha256": disk_bound_sha,
            "shellcode_sha256": v2.sha256_file(clean_shell_path),
            "shellcode_length": len(shell),
            "raw_wheel_prefix_sha256": v2.sha256_bytes(shell[:12]),
            "camera_replacement_sha256": v3.CAMERA_CLEAN_HASH,
            "camera_replacement_offsets": [f"0x{x:X}" for x in camera_offsets],
        },
        "compatibility_window_hashes": {
            name: {"length": length, "sha256": digest}
            for name, length, digest in v2.FORBIDDEN_WINDOWS
        },
        "invariants": {
            "engine_final_cross_resource_hash_bound": True,
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

    print("SIGNING_CLEAN_V7_MATERIALIZATION_V4=PASS")
    print(f"CLEAN_ENGINE_SHA256={report['clean']['engine_sha256']}")
    print(f"CLEAN_FINAL_SHA256={report['clean']['final_sha256']}")
    print(f"ENGINE_EXPECTED_FINAL_SHA256={report['clean']['engine_expected_final_sha256']}")
    print(f"CLEAN_SHELLCODE_SHA256={report['clean']['shellcode_sha256']}")
    print(f"REPORT={report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
