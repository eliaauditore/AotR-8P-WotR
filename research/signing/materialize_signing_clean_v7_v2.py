#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

RAW_HASH = "0D40841FEA16CCBF82D3ACF45F5D4F3E88DCEE25DEE3E8979CFC861D9DEBEB98"
MAP_HASH = "AA4F89C4B315D0CDE15CD3A90DF96C069E83EB4419AFB5AB9429B4630C98D731"
ZOOM_HASH = "13DB5AB30A882A36D343C74FD28182A5383740BAFD4A39061229B2DF552EE6F0"
CAMERA_HASH = "8D9A0E5FCD6B9396376D74BDCD71348F16619D3A688753683957208D39C99E51"
CANCEL_HASH = "4884272792A6E35438C4261E8D1F10905C24516654A148A0B6611B0B77B7BE7C"
CLEAN_PREFIX_HASH = "C2134A124371FD3DBB4BB7F5A20D46DE8CDAE3BF46EA6F248DD53A9488069811"

EXPECTED_ENGINE = "5DB2F749F10E84322BC471FFF04E25326EFF194FA440175FE9841ED13367F938"
EXPECTED_FINAL = "72D00490538BE2222F5BAAF3D8A1648A86071D3A098946A7B8751E7D337300E2"
EXPECTED_SHELL = "60EECE4660C3BA0AD183EB82B82DCDACF3ECA6DC892C8FAFCD629A92170ED45A"

# Different 12-byte implementation of the overwritten Raw Wheel semantics:
# lea eax,[ebp-4] ; mov eax,[eax] ; shr eax,16 ; cwde ; mov [esi+0x0C],eax
CLEAN_PREFIX = bytes((0x8D,0x45,0xFC,0x8B,0x00,0xC1,0xE8,0x10,0x98,0x89,0x46,0x0C))

FORBIDDEN_WINDOWS = (
    ("RawWheel", 12, RAW_HASH),
    ("MapHandler", 8, MAP_HASH),
    ("ZoomUpdate", 16, ZOOM_HASH),
    ("CameraGlobal", 6, CAMERA_HASH),
    ("CancelRelease", 16, CANCEL_HASH),
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def replace_once(text: str, pattern: str, replacement: str, label: str, flags: int = 0) -> str:
    rx = re.compile(pattern, flags)
    matches = list(rx.finditer(text))
    if len(matches) != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {len(matches)}")
    return rx.sub(lambda _m: replacement, text, count=1)


def require_file(path: Path, expected_hash: str, label: str) -> None:
    if not path.is_file():
        raise RuntimeError(f"{label} missing: {path}")
    actual = sha256_file(path)
    if actual != expected_hash:
        raise RuntimeError(f"{label} SHA256 mismatch: expected {expected_hash}, got {actual}")


def clean_engine(text: str) -> str:
    helper = r'''function Assert-CompatHash {
    param(
        [Int64]$Address,
        [int]$Length,
        [string]$ExpectedSha256,
        [string]$Name
    )
    if ($Length -le 0) { throw "$Name : invalid compatibility window length." }
    [byte[]]$actual = [byte[]]::new($Length)
    [IntPtr]$read = [IntPtr]::Zero
    $ok = [AotR8PChildPatch]::ReadProcessMemory($h,[IntPtr]$Address,$actual,$Length,[ref]$read)
    if ((-not $ok) -or ($read.ToInt64() -ne $Length)) {
        throw "$Name : compatibility read was incomplete. Nothing patched."
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actualSha = ([BitConverter]::ToString($sha.ComputeHash($actual))).Replace('-','').ToUpperInvariant() }
    finally { $sha.Dispose() }
    if ($actualSha -ne $ExpectedSha256) {
        throw "$Name changed in this AotR build. SHA256=$actualSha. Nothing patched."
    }
}

'''
    text = replace_once(text, r"(?m)^function Assert-CompatBytes \{", helper + "function Assert-CompatBytes {", "Engine hash helper")

    replacements = (
        (r'(?m)^Assert-CompatBytes -Address \(\$base \+ 0x0004128C\).*?-Name "V7 Raw Wheel Hook"\s*$', f'Assert-CompatHash -Address ($base + 0x0004128C) -Length 12 -ExpectedSha256 "{RAW_HASH}" -Name "V7 Raw Wheel Hook"', "Engine Raw Wheel"),
        (r'(?m)^Assert-CompatBytes -Address \(\$base \+ 0x00575507\).*?-Name "V7 Strategic Map Handler"\s*$', f'Assert-CompatHash -Address ($base + 0x00575507) -Length 8 -ExpectedSha256 "{MAP_HASH}" -Name "V7 Strategic Map Handler"', "Engine Map"),
        (r'(?m)^Assert-CompatBytes -Address \(\$base \+ 0x0009AB21\).*?-Name "V7 Zoom Update"\s*$', f'Assert-CompatHash -Address ($base + 0x0009AB21) -Length 16 -ExpectedSha256 "{ZOOM_HASH}" -Name "V7 Zoom Update"', "Engine Zoom"),
        (r'(?m)^Assert-CompatBytes -Address 0x0097548E .*?-Name "LivingWorld Camera Global Reference"\s*$', f'Assert-CompatHash -Address 0x0097548E -Length 6 -ExpectedSha256 "{CAMERA_HASH}" -Name "LivingWorld Camera Global Reference"', "Engine Camera"),
        (r'(?m)^Assert-CompatBytes -Address 0x009D9167 .*?-Name "Strategic Cancel/Release Callback"\s*$', f'Assert-CompatHash -Address 0x009D9167 -Length 16 -ExpectedSha256 "{CANCEL_HASH}" -Name "Strategic Cancel/Release Callback"', "Engine Cancel"),
    )
    for pattern, replacement, label in replacements:
        text = replace_once(text, pattern, replacement, label)

    # 8-player slot/row single-byte gates deliberately remain byte comparisons.
    for label in ("V7 Raw Wheel Hook", "V7 Strategic Map Handler", "V7 Zoom Update", "LivingWorld Camera Global Reference", "Strategic Cancel/Release Callback"):
        if re.search(rf'(?m)^Assert-CompatBytes .*?-Name "{re.escape(label)}"', text):
            raise RuntimeError(f"Engine still uses literal compatibility bytes for {label}")
    return text


def clean_final(text: str) -> str:
    text = replace_once(
        text,
        r"^\[byte\[\]\]\$OriginalRawWheelHook\s*=\s*@\(.*?^\)\s*",
        f'$RawWheelHookLength = 12\n$RawWheelHookSha256 = "{RAW_HASH}"\n\n',
        "FINAL original Raw Wheel block",
        re.MULTILINE | re.DOTALL,
    )
    text = replace_once(
        text,
        r"^\[byte\[\]\]\$OriginalMapHandler\s*=\s*@\(.*?^\)\s*",
        f'$MapHandlerLength = 8\n$MapHandlerSha256 = "{MAP_HASH}"\n\n',
        "FINAL original Map block",
        re.MULTILINE | re.DOTALL,
    )
    text = replace_once(
        text,
        r"^\[byte\[\]\]\$OriginalZoomUpdate\s*=\s*@\(.*?^\)\s*",
        f'$ZoomUpdateLength = 16\n$ZoomUpdateSha256 = "{ZOOM_HASH}"\n\n',
        "FINAL original Zoom block",
        re.MULTILINE | re.DOTALL,
    )
    text = replace_once(
        text,
        r"^\$CameraGlobalRefAddress\s*=\s*\[IntPtr\]0x0097548E\s*\n\[byte\[\]\]\$ExpectedCameraGlobalRef\s*=\s*@\(.*?\)\s*\n\$CancelReleaseAddress\s*=\s*\[IntPtr\]0x009D9167\s*\n\[byte\[\]\]\$ExpectedCancelRelease\s*=\s*@\(.*?^\)\s*",
        (
            f'$CameraGlobalRefAddress = [IntPtr]0x0097548E\n'
            f'$CameraGlobalRefLength = 6\n'
            f'$CameraGlobalRefSha256 = "{CAMERA_HASH}"\n'
            f'$CancelReleaseAddress = [IntPtr]0x009D9167\n'
            f'$CancelReleaseLength = 16\n'
            f'$CancelReleaseSha256 = "{CANCEL_HASH}"\n\n'
        ),
        "FINAL Camera/Cancel blocks",
        re.MULTILINE | re.DOTALL,
    )

    hash_helpers = r'''function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Test-BytesHash([byte[]]$Actual,[string]$ExpectedSha256) {
    if ($null -eq $Actual) { return $false }
    return (Get-BytesSha256 $Actual) -eq $ExpectedSha256
}

'''
    text = replace_once(text, r"(?m)^function Test-Bytes\(", hash_helpers + "function Test-Bytes(", "FINAL hash helpers")

    replacements = {
        "$OriginalRawWheelHook.Length": "$RawWheelHookLength",
        "$OriginalMapHandler.Length": "$MapHandlerLength",
        "$OriginalZoomUpdate.Length": "$ZoomUpdateLength",
        "$ExpectedCameraGlobalRef.Length": "$CameraGlobalRefLength",
        "$ExpectedCancelRelease.Length": "$CancelReleaseLength",
        "(Test-Bytes $rawBefore $OriginalRawWheelHook)": "(Test-BytesHash $rawBefore $RawWheelHookSha256)",
        "(Test-Bytes $mapBefore $OriginalMapHandler)": "(Test-BytesHash $mapBefore $MapHandlerSha256)",
        "(Test-Bytes $zoomBefore $OriginalZoomUpdate)": "(Test-BytesHash $zoomBefore $ZoomUpdateSha256)",
        "(Test-Bytes $cameraGlobalRefBefore $ExpectedCameraGlobalRef)": "(Test-BytesHash $cameraGlobalRefBefore $CameraGlobalRefSha256)",
        "(Test-Bytes $cancelReleaseBefore $ExpectedCancelRelease)": "(Test-BytesHash $cancelReleaseBefore $CancelReleaseSha256)",
        "(Test-Bytes $currentRaw $OriginalRawWheelHook)": "(Test-BytesHash $currentRaw $RawWheelHookSha256)",
        "(Test-Bytes $currentMap $OriginalMapHandler)": "(Test-BytesHash $currentMap $MapHandlerSha256)",
        "(Test-Bytes $currentZoom $OriginalZoomUpdate)": "(Test-BytesHash $currentZoom $ZoomUpdateSha256)",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)

    forbidden_vars = (
        "$OriginalRawWheelHook",
        "$OriginalMapHandler",
        "$OriginalZoomUpdate",
        "$ExpectedCameraGlobalRef",
        "$ExpectedCancelRelease",
    )
    for token in forbidden_vars:
        if token in text:
            raise RuntimeError(f"FINAL still references removed proprietary-byte variable: {token}")
    return text


def clean_shellcode(data: bytes) -> bytes:
    if len(data) != 1577:
        raise RuntimeError(f"Historical shellcode length changed: {len(data)}")
    if sha256_bytes(data[:12]) != RAW_HASH:
        raise RuntimeError("Historical shellcode no longer starts with the pinned Raw Wheel window")
    if len(CLEAN_PREFIX) != 12 or sha256_bytes(CLEAN_PREFIX) != CLEAN_PREFIX_HASH:
        raise RuntimeError("Clean semantic prefix identity mismatch")

    clean = CLEAN_PREFIX + data[12:]
    if len(clean) != 1577:
        raise RuntimeError("Clean shellcode length changed")
    if clean[12:] != data[12:]:
        raise RuntimeError("Unexpected shellcode change after offset 12")

    for name, length, digest in FORBIDDEN_WINDOWS:
        for offset in range(0, len(clean) - length + 1):
            if sha256_bytes(clean[offset:offset + length]) == digest:
                raise RuntimeError(f"Forbidden historical compatibility window remains: {name} at offset {offset}")
    return clean


def main(argv: list[str]) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    historical = repo_root / "launcher-source" / "v19-successor" / "resources"
    out = Path(argv[1]).resolve() if len(argv) > 1 else (repo_root / "_SIGNING_CLEAN_V7_MATERIALIZE_V2")
    out.mkdir(parents=True, exist_ok=True)

    engine_path = historical / "launcher_engine.ps1"
    final_path = historical / "final_stable_v7.ps1"
    shell_path = historical / "v7_shellcode.bin"
    require_file(engine_path, EXPECTED_ENGINE, "historical Engine")
    require_file(final_path, EXPECTED_FINAL, "historical FINAL_STABLE_V7")
    require_file(shell_path, EXPECTED_SHELL, "historical V7 shellcode")

    engine = clean_engine(engine_path.read_text(encoding="utf-8-sig"))
    final = clean_final(final_path.read_text(encoding="utf-8-sig"))
    shell = clean_shellcode(shell_path.read_bytes())

    clean_engine_path = out / "launcher_engine_signing_clean.ps1"
    clean_final_path = out / "final_stable_v7_signing_clean.ps1"
    clean_shell_path = out / "v7_shellcode_signing_clean.bin"
    clean_engine_path.write_text(engine, encoding="utf-8", newline="\n")
    clean_final_path.write_text(final, encoding="utf-8", newline="\n")
    clean_shell_path.write_bytes(shell)

    report = {
        "schema": 2,
        "state": "NON_RELEASE_SIGNING_CLEAN_V7_MATERIALIZATION",
        "historical": {
            "engine_sha256": EXPECTED_ENGINE,
            "final_sha256": EXPECTED_FINAL,
            "shellcode_sha256": EXPECTED_SHELL,
        },
        "clean": {
            "engine_sha256": sha256_file(clean_engine_path),
            "final_sha256": sha256_file(clean_final_path),
            "shellcode_sha256": sha256_file(clean_shell_path),
            "shellcode_length": len(shell),
            "shellcode_prefix_sha256": sha256_bytes(shell[:12]),
        },
        "compatibility_window_hashes": {name: {"length": length, "sha256": digest} for name, length, digest in FORBIDDEN_WINDOWS},
        "invariants": {
            "bytes_after_offset_12_unchanged": shell[12:] == shell_path.read_bytes()[12:],
            "forbidden_historical_windows_absent_from_clean_shellcode": True,
            "engine_uses_hash_compatibility_windows": True,
            "final_uses_hash_compatibility_windows": True,
            "public_release_modified": False,
            "field_execution_allowed": False,
        },
    }
    report_path = out / "SIGNING_CLEAN_V7_MATERIALIZATION_REPORT.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print("SIGNING_CLEAN_V7_MATERIALIZATION=PASS")
    print(f"CLEAN_ENGINE_SHA256={report['clean']['engine_sha256']}")
    print(f"CLEAN_FINAL_SHA256={report['clean']['final_sha256']}")
    print(f"CLEAN_SHELLCODE_SHA256={report['clean']['shellcode_sha256']}")
    print(f"CLEAN_SHELLCODE_PREFIX_SHA256={report['clean']['shellcode_prefix_sha256']}")
    print(f"REPORT={report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
