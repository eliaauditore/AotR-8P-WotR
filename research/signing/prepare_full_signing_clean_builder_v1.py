#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

SOURCE_ENGINE = "5DB2F749F10E84322BC471FFF04E25326EFF194FA440175FE9841ED13367F938"
SOURCE_FINAL = "72D00490538BE2222F5BAAF3D8A1648A86071D3A098946A7B8751E7D337300E2"
SOURCE_SHELL = "60EECE4660C3BA0AD183EB82B82DCDACF3ECA6DC892C8FAFCD629A92170ED45A"

CLEAN_ENGINE = "51AE0E2312F07065119DCA806A2211373F48366F7CC6DD520130751EA34D14C1"
CLEAN_FINAL = "125A29EEFE6DF8C38467BDFBA3502118A041B0243A1B72903D969356CA33F49C"
CLEAN_SHELL = "3C4B4B8B4E80B49877C1ADD090A8C96B94A361C8295B1DB9F4BC78CA7454AF4C"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one target, found {count}")
    return text.replace(old, new, 1)


def main(argv: list[str]) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    source_path = repo_root / "launcher-source" / "v19-successor" / "BUILD_SIGNING_CLEAN_VISUAL_PROOF_V3.ps1"
    if not source_path.is_file():
        raise RuntimeError(f"Visual V3 builder missing: {source_path}")

    out_path = Path(argv[1]).resolve() if len(argv) > 1 else (repo_root / "_FULL_SIGNING_CLEAN_PROOF_BUILDER.ps1")
    out_path.parent.mkdir(parents=True, exist_ok=True)

    text = source_path.read_text(encoding="utf-8-sig")

    text = replace_once(
        text,
        '$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))',
        '$RepoRoot = [IO.Path]::GetFullPath($env:GITHUB_WORKSPACE)',
        "repo root redirection",
    )
    text = replace_once(
        text,
        '$Resources = Join-Path $PSScriptRoot "resources"',
        '$Resources = [IO.Path]::GetFullPath($env:AOTR8P_CLEAN_RESOURCES_ROOT)',
        "clean resource root redirection",
    )
    text = replace_once(
        text,
        '$SourceTemplate = Join-Path $PSScriptRoot "..\\v19\\launcher.cs"',
        '$SourceTemplate = Join-Path $RepoRoot "launcher-source\\v19\\launcher.cs"',
        "C# template redirection",
    )
    text = replace_once(
        text,
        '$V7Verifier = Join-Path $PSScriptRoot "..\\v19\\VERIFY_V7_RESOURCE_CHAIN.ps1"',
        '$V7Verifier = $null',
        "historical V7 verifier path removal",
    )

    text = replace_once(
        text,
        f'    "launcher_engine.ps1"  = "{SOURCE_ENGINE}"',
        f'    "launcher_engine.ps1"  = "{CLEAN_ENGINE}"',
        "Engine hash pin",
    )
    text = replace_once(
        text,
        f'    "final_stable_v7.ps1"  = "{SOURCE_FINAL}"',
        f'    "final_stable_v7.ps1"  = "{CLEAN_FINAL}"',
        "FINAL hash pin",
    )
    text = replace_once(
        text,
        f'    "v7_shellcode.bin"     = "{SOURCE_SHELL}"',
        f'    "v7_shellcode.bin"     = "{CLEAN_SHELL}"',
        "shellcode hash pin",
    )

    first_verifier = '''if (-not (Test-Path -LiteralPath $V7Verifier -PathType Leaf)) { throw "V7 verifier missing: $V7Verifier" }
& $V7Verifier -ResourcesRoot $Resources'''
    text = replace_once(
        text,
        first_verifier,
        'Write-Host "SIGNING-CLEAN V4 source identities are pinned by the combined proof builder." -ForegroundColor Green',
        "historical source verifier invocation",
    )
    text = replace_once(
        text,
        '& $V7Verifier -ResourcesRoot $Resources -ExePath $Exe',
        'Write-Host "SIGNING-CLEAN V4 embedded identities verified by exact embedded-resource gate above." -ForegroundColor Green',
        "historical embedded verifier invocation",
    )

    # The generated builder must not silently retain the historical V7 identities or verifier path.
    forbidden = (
        SOURCE_ENGINE,
        SOURCE_FINAL,
        SOURCE_SHELL,
        'VERIFY_V7_RESOURCE_CHAIN.ps1',
    )
    for token in forbidden:
        if token in text:
            raise RuntimeError(f"Historical V7 proof token survived generated builder: {token}")

    required = (
        CLEAN_ENGINE,
        CLEAN_FINAL,
        CLEAN_SHELL,
        'AOTR8P_CLEAN_RESOURCES_ROOT',
        'launcher-source\\v19\\launcher.cs',
    )
    for token in required:
        if token not in text:
            raise RuntimeError(f"Required combined-proof token missing: {token}")

    out_path.write_text(text, encoding="utf-8", newline="\n")
    report = {
        "schema": 1,
        "state": "NON_RELEASE_FULL_SIGNING_CLEAN_BUILDER_PREP",
        "source_builder": str(source_path.relative_to(repo_root)).replace('\\', '/'),
        "clean_engine_sha256": CLEAN_ENGINE,
        "clean_final_sha256": CLEAN_FINAL,
        "clean_shellcode_sha256": CLEAN_SHELL,
        "historical_v7_verifier_removed": True,
        "visual_v3_build_logic_preserved": True,
        "field_execution_allowed": False,
    }
    report_path = out_path.with_suffix(out_path.suffix + ".prep.json")
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print("FULL_SIGNING_CLEAN_BUILDER_PREP=PASS")
    print(f"BUILDER={out_path}")
    print(f"REPORT={report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
