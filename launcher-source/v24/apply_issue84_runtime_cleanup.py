from pathlib import Path
import argparse
import re

GUI_RESET_RUNTIME = r'''function Remove-AotR8PLegacyRuntimeFolders([string]$InstallRoot, [string]$DriveFormat) {
    if ([string]::IsNullOrWhiteSpace($InstallRoot)) { return 0 }
    if ([string]::IsNullOrWhiteSpace($DriveFormat)) { return 0 }
    if ($DriveFormat -ieq "NTFS") { return 0 }
    if (-not (Test-Path -LiteralPath $InstallRoot -PathType Container)) { return 0 }

    $removed = 0
    foreach ($item in @(Get-ChildItem -LiteralPath $InstallRoot -Directory -ErrorAction SilentlyContinue)) {
        $name = [string]$item.Name
        $managed = ($name -eq "_AOTR_8P_WOTR_RUNTIME") -or
            ($name -match '^_AOTR_8P_WOTR_RUNTIME_V4_\d+$') -or
            ($name -match '^_AOTR_8P_WOTR_RUNTIME_REPAIR_\d{8}_\d{6}_\d+$') -or
            ($name -match '^_AOTR_8P_WOTR_RUNTIME_V4_\d+_REPAIR_\d{8}_\d{6}_\d+$')
        if (-not $managed) { continue }

        try {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
            $removed++
            Write-RepairLog ("Issue84 removed stale non-NTFS runtime folder: " + $item.FullName)
        }
        catch {
            Write-RepairLog ("Issue84 stale runtime cleanup skipped: " + $item.FullName + " :: " + $_.Exception.Message)
        }
    }
    return $removed
}

function Reset-PortableRuntime {
    if (-not $Install) { return }

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $localStateRoot = Join-Path $env:LOCALAPPDATA "AotR 8P WotR Mod"
    $localRuntimeRoot = Join-Path $localStateRoot "runtime"
    $paths = New-Object System.Collections.Generic.List[string]

    $localPrimary = Join-Path $localRuntimeRoot "_AOTR_8P_WOTR_RUNTIME"
    $paths.Add($localPrimary)
    if (Test-Path -LiteralPath $localRuntimeRoot -PathType Container) {
        foreach ($item in @(Get-ChildItem -LiteralPath $localRuntimeRoot -Directory -Filter "_AOTR_8P_WOTR_RUNTIME_V4_*" -ErrorAction SilentlyContinue)) {
            $paths.Add([string]$item.FullName)
        }
    }

    # Issue84: once Issue78 redirects a non-NTFS/exFAT install to LOCALAPPDATA,
    # every strictly named runtime folder left beside AotR is legacy. Remove
    # only those known launcher-owned folders after stop_legacy_runtime /
    # stop_failed_game have already run. Unknown filesystem state stays
    # conservative and uses the existing quarantine behavior instead.
    $installDriveFormat = ""
    try {
        $installVolumeRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Install.Root))
        if (-not [string]::IsNullOrWhiteSpace($installVolumeRoot)) {
            $installDrive = New-Object IO.DriveInfo($installVolumeRoot)
            if ($installDrive.IsReady) { $installDriveFormat = [string]$installDrive.DriveFormat }
        }
    }
    catch {}

    $legacyExternalOnly = -not [string]::IsNullOrWhiteSpace($installDriveFormat) -and $installDriveFormat -ine "NTFS"
    if ($legacyExternalOnly) {
        [void](Remove-AotR8PLegacyRuntimeFolders $Install.Root $installDriveFormat)
    }
    else {
        # 1.1.3 and normal NTFS installs may stage beside AotR. Preserve the
        # original quarantine path when the install volume is NTFS or unknown.
        $legacyPrimary = Join-Path $Install.Root "_AOTR_8P_WOTR_RUNTIME"
        $paths.Add($legacyPrimary)
        if (Test-Path -LiteralPath $Install.Root -PathType Container) {
            foreach ($item in @(Get-ChildItem -LiteralPath $Install.Root -Directory -Filter "_AOTR_8P_WOTR_RUNTIME_V4_*" -ErrorAction SilentlyContinue)) {
                $paths.Add([string]$item.FullName)
            }
        }
    }

    $seen = @{}
    $index = 0
    foreach ($runtimePath in $paths) {
        if ([string]::IsNullOrWhiteSpace([string]$runtimePath)) { continue }
        $key = ([IO.Path]::GetFullPath([string]$runtimePath)).ToUpperInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        if (-not (Test-Path -LiteralPath $runtimePath -PathType Container)) { continue }

        $index++
        $parent = Split-Path $runtimePath -Parent
        $leaf = Split-Path $runtimePath -Leaf
        $quarantine = Join-Path $parent ($leaf + "_REPAIR_" + $stamp + "_" + $index)
        $isLocalRuntime = $key.StartsWith(([IO.Path]::GetFullPath($localRuntimeRoot)).ToUpperInvariant())

        try {
            Move-Item -LiteralPath $runtimePath -Destination $quarantine -Force -ErrorAction Stop
            Write-RepairLog ("Runtime quarantined without recursive deletion: " + $quarantine)
        }
        catch {
            Write-RepairLog ("Runtime quarantine failed: " + $_.Exception.Message)
            if ($isLocalRuntime) { throw }
        }
    }
}
'''


def replace_function(text: str, name: str, replacement: str) -> str:
    pattern = rf"(?ms)^function\s+{re.escape(name)}\b.*?^}}\s*\n"
    text2, count = re.subn(pattern, replacement + "\n", text, count=1)
    if count != 1:
        raise SystemExit(f"expected exactly one function {name}, found {count}")
    return text2


def patch_gui(path: Path) -> None:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    text = replace_function(text, "Reset-PortableRuntime", GUI_RESET_RUNTIME)

    required = [
        "Remove-AotR8PLegacyRuntimeFolders",
        "Issue84 removed stale non-NTFS runtime folder",
        "installDriveFormat",
        "legacyExternalOnly",
        "A8P-RUNTIME-FS-001",
        "LOCALAPPDATA",
    ]
    for needle in required:
        if needle not in text:
            raise SystemExit(f"Issue84 GUI contract missing: {needle}")

    path.write_text(text, encoding="utf-8-sig", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("gui")
    args = parser.parse_args()
    patch_gui(Path(args.gui))
    print("ISSUE84_RUNTIME_CLEANUP_PATCH_PASS")


if __name__ == "__main__":
    main()
