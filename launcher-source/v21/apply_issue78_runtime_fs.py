from pathlib import Path
import argparse
import re

ENGINE_LINK_FILE = r'''function Get-AotR8PVolumeRoot([string]$Path) {
    try {
        $full = [IO.Path]::GetFullPath($Path)
        $root = [IO.Path]::GetPathRoot($full)
        if ([string]::IsNullOrWhiteSpace($root)) { return "" }
        return $root.TrimEnd([char]'\\').ToUpperInvariant()
    }
    catch { return "" }
}

function Get-AotR8PRuntimeStageRoot([string]$InstallRoot, [string]$StateRoot) {
    try {
        $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($InstallRoot))
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $drive = New-Object IO.DriveInfo($root)
            # Preserve the established 1.1.3 layout on normal NTFS installs.
            # FAT/exFAT/removable layouts that cannot host our link staging are
            # redirected to the user's local Windows state volume instead.
            if ($drive.IsReady -and [string]$drive.DriveFormat -ieq "NTFS") {
                return [IO.Path]::GetFullPath($InstallRoot)
            }
        }
    }
    catch {}

    $localRuntimeRoot = Join-Path $StateRoot "runtime"
    New-Item -ItemType Directory -Force -Path $localRuntimeRoot | Out-Null
    return [IO.Path]::GetFullPath($localRuntimeRoot)
}

function New-LinkedFile([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    }

    # Hard links can only exist on the same volume. Avoid a guaranteed
    # terminating error when a non-NTFS/external AotR source is staged locally.
    $sourceRoot = Get-AotR8PVolumeRoot $Source
    $destinationRoot = Get-AotR8PVolumeRoot $Destination
    if (-not [string]::IsNullOrWhiteSpace($sourceRoot) -and $sourceRoot -eq $destinationRoot) {
        try {
            New-Item -ItemType HardLink -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
            return
        }
        catch {}
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
        return
    }
    catch {}

    Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
}
'''

ENGINE_LINK_DIR = r'''function New-LinkedDirectory([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Force -Recurse -ErrorAction SilentlyContinue
    }

    # The destination is always on a link-capable NTFS volume when the source
    # install itself is not. Prefer reparse points and copy only as last resort.
    try {
        New-Item -ItemType Junction -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
        return
    }
    catch {}

    try {
        New-Item -ItemType SymbolicLink -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
        return
    }
    catch {}

    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force -ErrorAction Stop
}
'''

GUI_RESET_RUNTIME = r'''function Reset-PortableRuntime {
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

    # 1.1.3 and normal NTFS installs may stage beside AotR. Also scan that
    # layout so a repair works correctly across upgrades in either direction.
    $legacyPrimary = Join-Path $Install.Root "_AOTR_8P_WOTR_RUNTIME"
    $paths.Add($legacyPrimary)
    if (Test-Path -LiteralPath $Install.Root -PathType Container) {
        foreach ($item in @(Get-ChildItem -LiteralPath $Install.Root -Directory -Filter "_AOTR_8P_WOTR_RUNTIME_V4_*" -ErrorAction SilentlyContinue)) {
            $paths.Add([string]$item.FullName)
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
            # A stale local fallback runtime can block a rebuild; old install-root
            # cleanup stays best-effort because a non-NTFS drive may deny it.
            if ($isLocalRuntime) { throw }
        }
    }
}
'''

FS_CLASSIFICATION = r'''    elseif ($d -match '(?i)Hard links? are not supported|Symbolic links? are not supported|Junctions? are not supported|reparse.*not supported') {
        $code = "A8P-RUNTIME-FS-001"
        $title = "Portable runtime filesystem does not support link staging"
        $actions = @("stop_legacy_runtime","stop_failed_game","reset_runtime","clear_compat_cache","retry_launch")
    }
'''


def replace_function(text: str, name: str, replacement: str) -> str:
    pattern = rf"(?ms)^function\s+{re.escape(name)}\b.*?^}}\s*\n"
    text2, count = re.subn(pattern, replacement + "\n", text, count=1)
    if count != 1:
        raise SystemExit(f"expected exactly one function {name}, found {count}")
    return text2


def patch_engine(path: Path) -> None:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    text = replace_function(text, "New-LinkedFile", ENGINE_LINK_FILE)
    text = replace_function(text, "New-LinkedDirectory", ENGINE_LINK_DIR)

    old_runtime = '$test      = Join-Path $install.Root "_AOTR_8P_WOTR_RUNTIME"'
    new_runtime = '''$runtimeStageRoot = Get-AotR8PRuntimeStageRoot $install.Root $stateRoot
$test      = Join-Path $runtimeStageRoot "_AOTR_8P_WOTR_RUNTIME"'''
    if text.count(old_runtime) != 1:
        raise SystemExit(f"engine primary runtime anchor count={text.count(old_runtime)}")
    text = text.replace(old_runtime, new_runtime, 1)

    old_sibling = '$script:test = Join-Path $install.Root ("_AOTR_8P_WOTR_RUNTIME_V4_" + $PID)'
    new_sibling = '$script:test = Join-Path $runtimeStageRoot ("_AOTR_8P_WOTR_RUNTIME_V4_" + $PID)'
    if text.count(old_sibling) != 1:
        raise SystemExit(f"engine fresh-runtime anchor count={text.count(old_sibling)}")
    text = text.replace(old_sibling, new_sibling, 1)

    if text.count('Get-AotR8PRuntimeStageRoot') < 2:
        raise SystemExit("runtime stage selector was not wired into engine")
    path.write_text(text, encoding="utf-8-sig", newline="\n")


def patch_gui(path: Path) -> None:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    text = replace_function(text, "Reset-PortableRuntime", GUI_RESET_RUNTIME)

    anchor = "    elseif ($d -match '(?i)PORTABLE RUNTIME|runtime.*verification|source folder missing while building runtime|Laufzeitschicht') {"
    if text.count(anchor) != 1:
        raise SystemExit(f"GUI runtime classification anchor count={text.count(anchor)}")
    text = text.replace(anchor, FS_CLASSIFICATION + anchor, 1)

    if text.count('A8P-RUNTIME-FS-001') != 1:
        raise SystemExit("A8P-RUNTIME-FS-001 classification was not inserted exactly once")
    path.write_text(text, encoding="utf-8-sig", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("engine")
    parser.add_argument("gui")
    args = parser.parse_args()
    patch_engine(Path(args.engine))
    patch_gui(Path(args.gui))
    print("ISSUE78_RUNTIME_FS_PATCH_PASS")


if __name__ == "__main__":
    main()
