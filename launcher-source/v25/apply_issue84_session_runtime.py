from pathlib import Path
import argparse
import re

ENGINE_STAGE_ROOT = r'''function Get-AotR8PRuntimeStageRoot([string]$InstallRoot, [string]$StateRoot) {
    $sessionRoot = Join-Path $StateRoot "runtime\sessions"
    New-Item -ItemType Directory -Force -Path $sessionRoot | Out-Null
    return [IO.Path]::GetFullPath($sessionRoot)
}
'''

GUI_RESET_RUNTIME = r'''function Remove-AotR8PLegacyRuntimeFolders([string]$InstallRoot, [string]$DriveFormat) {
    if ([string]::IsNullOrWhiteSpace($InstallRoot)) { return 0 }
    if ([string]::IsNullOrWhiteSpace($DriveFormat)) { return 0 }
    $safeLegacyFormats = @("exFAT", "FAT32", "FAT")
    if (-not ($safeLegacyFormats -contains $DriveFormat)) { return 0 }
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
            Write-RepairLog ("Issue84 removed legacy install-root runtime folder: " + $item.FullName)
        }
        catch {
            Write-RepairLog ("Issue84 legacy runtime cleanup skipped: " + $item.FullName + " :: " + $_.Exception.Message)
        }
    }
    return $removed
}

function Reset-PortableRuntime {
    if (-not $Install) { return }

    $launcherExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $localStateRoot = Join-Path $env:LOCALAPPDATA "AotR 8P WotR Mod"
    $sessionRoot = Join-Path $localStateRoot "runtime\sessions"

    if (Test-Path -LiteralPath $sessionRoot -PathType Container) {
        foreach ($item in @(Get-ChildItem -LiteralPath $sessionRoot -Directory -Filter "AOTR8P_SESSION_*" -ErrorAction SilentlyContinue)) {
            try {
                $p = Start-Process -FilePath $launcherExe -ArgumentList @(
                    "--cleanup-runtime",
                    ('"' + $item.FullName + '"'),
                    "0","0","0"
                ) -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
                if ($p.ExitCode -eq 0) {
                    Write-RepairLog ("Transient runtime session removed: " + $item.FullName)
                }
                else {
                    Write-RepairLog ("Transient runtime cleanup helper returned exit code " + $p.ExitCode + ": " + $item.FullName)
                }
            }
            catch {
                Write-RepairLog ("Transient runtime cleanup failed: " + $item.FullName + " :: " + $_.Exception.Message)
            }
        }
    }

    # Compatibility cleanup for old FAT/exFAT installs only. New builds never
    # create runtime folders beside the AotR installation.
    $installDriveFormat = ""
    try {
        $installVolumeRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Install.Root))
        if (-not [string]::IsNullOrWhiteSpace($installVolumeRoot)) {
            $installDrive = New-Object IO.DriveInfo($installVolumeRoot)
            if ($installDrive.IsReady) { $installDriveFormat = [string]$installDrive.DriveFormat }
        }
    }
    catch {}
    [void](Remove-AotR8PLegacyRuntimeFolders $Install.Root $installDriveFormat)
}
'''

CS_HELPERS = r'''
    private sealed class RuntimeSessionMarker
    {
        public int launcher_pid { get; set; }
        public int game_launcher_pid { get; set; }
        public int game_pid { get; set; }
        public string created_utc { get; set; }
    }

    private static string RuntimeSessionRoot()
    {
        return Path.GetFullPath(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "AotR 8P WotR Mod", "runtime", "sessions"));
    }

    private static bool IsHex32(string value)
    {
        if (String.IsNullOrEmpty(value) || value.Length != 32) return false;
        for (int i = 0; i < value.Length; i++)
        {
            char c = value[i];
            bool hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
            if (!hex) return false;
        }
        return true;
    }

    private static bool IsValidRuntimeSessionPath(string path)
    {
        if (String.IsNullOrWhiteSpace(path)) return false;
        string root = RuntimeSessionRoot().TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        string full;
        try { full = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar); }
        catch { return false; }
        string prefix = root + Path.DirectorySeparatorChar;
        if (!full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return false;
        string leaf = Path.GetFileName(full);
        const string sessionPrefix = "AOTR8P_SESSION_";
        if (!leaf.StartsWith(sessionPrefix, StringComparison.Ordinal)) return false;
        string tail = leaf.Substring(sessionPrefix.Length);
        int split = tail.IndexOf('_');
        if (split <= 0 || split == tail.Length - 1) return false;
        int pid;
        if (!Int32.TryParse(tail.Substring(0, split), out pid) || pid <= 0) return false;
        return IsHex32(tail.Substring(split + 1));
    }

    private static bool IsPidAlive(int pid)
    {
        if (pid <= 0) return false;
        try
        {
            using (Process p = Process.GetProcessById(pid))
            {
                return !p.HasExited;
            }
        }
        catch { return false; }
    }

    private static void WaitForPidExit(int pid)
    {
        if (pid <= 0) return;
        try
        {
            using (Process p = Process.GetProcessById(pid))
            {
                p.WaitForExit();
            }
        }
        catch (ArgumentException) { }
        catch { }
    }

    private static void DeleteRuntimeTreeNoFollow(string path)
    {
        if (!Directory.Exists(path)) return;
        FileAttributes rootAttributes = File.GetAttributes(path);
        if ((rootAttributes & FileAttributes.ReparsePoint) != 0)
            throw new InvalidDataException("Runtime session root must not be a reparse point.");

        foreach (string file in Directory.GetFiles(path))
        {
            try { File.SetAttributes(file, FileAttributes.Normal); } catch { }
            File.Delete(file);
        }
        foreach (string dir in Directory.GetDirectories(path))
        {
            FileAttributes attributes = File.GetAttributes(dir);
            if ((attributes & FileAttributes.ReparsePoint) != 0)
            {
                Directory.Delete(dir, false);
            }
            else
            {
                DeleteRuntimeTreeNoFollow(dir);
            }
        }
        Directory.Delete(path, false);
    }

    private static void DeleteRuntimeSessionWithRetries(string path)
    {
        Exception last = null;
        for (int attempt = 0; attempt < 120; attempt++)
        {
            try
            {
                if (!Directory.Exists(path)) return;
                DeleteRuntimeTreeNoFollow(path);
                return;
            }
            catch (IOException ex) { last = ex; Thread.Sleep(250); }
            catch (UnauthorizedAccessException ex) { last = ex; Thread.Sleep(250); }
        }
        throw new IOException("Could not delete transient runtime session after repeated retries.", last);
    }

    private static void RunRuntimeCleanupHelper(string[] args)
    {
        if (args == null || args.Length < 5) Environment.Exit(2);
        string path = args[1];
        int launcherPid, gameLauncherPid, gamePid;
        if (!Int32.TryParse(args[2], out launcherPid)) Environment.Exit(2);
        if (!Int32.TryParse(args[3], out gameLauncherPid)) Environment.Exit(2);
        if (!Int32.TryParse(args[4], out gamePid)) Environment.Exit(2);
        if (!IsValidRuntimeSessionPath(path)) Environment.Exit(3);

        WaitForPidExit(launcherPid);
        WaitForPidExit(gameLauncherPid);
        WaitForPidExit(gamePid);
        try
        {
            DeleteRuntimeSessionWithRetries(path);
            Environment.Exit(0);
        }
        catch
        {
            Environment.Exit(4);
        }
    }

    private static void CleanupStaleRuntimeSessions()
    {
        string root = RuntimeSessionRoot();
        if (!Directory.Exists(root)) return;
        foreach (string path in Directory.GetDirectories(root, "AOTR8P_SESSION_*", SearchOption.TopDirectoryOnly))
        {
            if (!IsValidRuntimeSessionPath(path)) continue;
            bool active = false;
            string markerPath = Path.Combine(path, "AOTR8P_SESSION.json");
            try
            {
                if (File.Exists(markerPath))
                {
                    JavaScriptSerializer ser = new JavaScriptSerializer();
                    RuntimeSessionMarker marker = ser.Deserialize<RuntimeSessionMarker>(File.ReadAllText(markerPath, Encoding.UTF8));
                    if (marker != null)
                        active = IsPidAlive(marker.launcher_pid) || IsPidAlive(marker.game_launcher_pid) || IsPidAlive(marker.game_pid);
                }
                else
                {
                    active = (DateTime.UtcNow - Directory.GetLastWriteTimeUtc(path)).TotalMinutes < 10;
                }
            }
            catch { active = true; }
            if (active) continue;
            try { DeleteRuntimeSessionWithRetries(path); } catch { }
        }
        try
        {
            if (Directory.Exists(root) && Directory.GetFileSystemEntries(root).Length == 0)
                Directory.Delete(root, false);
        }
        catch { }
    }
'''


def replace_function(text: str, name: str, replacement: str) -> str:
    pattern = rf"(?ms)^function\s+{re.escape(name)}\b.*?^}}\s*\n"
    text2, count = re.subn(pattern, lambda _m: replacement + "\n", text, count=1)
    if count != 1:
        raise SystemExit(f"expected exactly one function {name}, found {count}")
    return text2


def patch_engine(path: Path) -> None:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    text = replace_function(text, "Get-AotR8PRuntimeStageRoot", ENGINE_STAGE_ROOT)

    old = '$test      = Join-Path $runtimeStageRoot "_AOTR_8P_WOTR_RUNTIME"'
    new = '''$sessionId = "AOTR8P_SESSION_" + $PID + "_" + [Guid]::NewGuid().ToString("N")
$test      = Join-Path $runtimeStageRoot $sessionId
$script:AotR8PSessionPath = $test'''
    if text.count(old) != 1:
        raise SystemExit(f"runtime session anchor count={text.count(old)}")
    text = text.replace(old, new, 1)

    anchor = '$gamePid = [int]$gameInfo.ProcessId\n'
    if text.count(anchor) != 1:
        raise SystemExit(f"game pid anchor count={text.count(anchor)}")
    insertion = anchor + r'''$sessionMarker = Join-Path $test "AOTR8P_SESSION.json"
$sessionState = [ordered]@{
    schema = 1
    launcher_pid = [int]$PID
    game_launcher_pid = [int]$launcherPid
    game_pid = [int]$gamePid
    created_utc = [DateTime]::UtcNow.ToString("o")
}
$sessionState | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $sessionMarker -Encoding UTF8
try {
    $launcherExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    [void](Start-Process -FilePath $launcherExe -ArgumentList @(
        "--cleanup-runtime",
        ('"' + $test + '"'),
        ([string]$PID),
        ([string]$launcherPid),
        ([string]$gamePid)
    ) -WindowStyle Hidden -ErrorAction Stop)
    Write-Host "Transient runtime cleanup watcher armed." -ForegroundColor DarkGray
}
catch {
    Write-Host ("Runtime cleanup watcher could not start; next launcher start will sweep stale session: " + $_.Exception.Message) -ForegroundColor Yellow
}
'''
    text = text.replace(anchor, insertion, 1)

    required = ["AOTR8P_SESSION_", "AOTR8P_SESSION.json", "--cleanup-runtime", "runtime\\sessions"]
    for needle in required:
        if needle not in text:
            raise SystemExit(f"engine session contract missing: {needle}")
    path.write_text(text, encoding="utf-8-sig", newline="\n")


def patch_gui(path: Path) -> None:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    text = replace_function(text, "Reset-PortableRuntime", GUI_RESET_RUNTIME)
    for forbidden in ['Move-Item -LiteralPath $runtimePath -Destination $quarantine', '$leaf + "_REPAIR_"']:
        if forbidden in text:
            raise SystemExit(f"persistent quarantine primitive remains in GUI: {forbidden}")
    required = ["--cleanup-runtime", "runtime\\sessions", "Remove-AotR8PLegacyRuntimeFolders"]
    for needle in required:
        if needle not in text:
            raise SystemExit(f"GUI session contract missing: {needle}")
    path.write_text(text, encoding="utf-8-sig", newline="\n")


def patch_csharp(source_in: Path, source_out: Path) -> None:
    text = source_in.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    old_mode = '''        if (args != null && args.Length > 0 &&
            String.Equals(args[0], "--apply-update", StringComparison.OrdinalIgnoreCase))
        {
            RunUpdateHelper(args);
            return;
        }

        CleanupStaleUpdateFiles();'''
    new_mode = '''        if (args != null && args.Length > 0 &&
            String.Equals(args[0], "--apply-update", StringComparison.OrdinalIgnoreCase))
        {
            RunUpdateHelper(args);
            return;
        }
        if (args != null && args.Length > 0 &&
            String.Equals(args[0], "--cleanup-runtime", StringComparison.OrdinalIgnoreCase))
        {
            RunRuntimeCleanupHelper(args);
            return;
        }

        CleanupStaleUpdateFiles();'''
    if text.count(old_mode) != 1:
        raise SystemExit(f"C# helper mode anchor count={text.count(old_mode)}")
    text = text.replace(old_mode, new_mode, 1)

    mutex_anchor = '''            string exePath = Process.GetCurrentProcess().MainModule.FileName;
            string root = Path.GetDirectoryName(exePath);

            try'''
    mutex_new = '''            string exePath = Process.GetCurrentProcess().MainModule.FileName;
            string root = Path.GetDirectoryName(exePath);
            CleanupStaleRuntimeSessions();

            try'''
    if text.count(mutex_anchor) != 1:
        raise SystemExit(f"C# startup stale sweep anchor count={text.count(mutex_anchor)}")
    text = text.replace(mutex_anchor, mutex_new, 1)

    helper_anchor = '    private static string FormatException(Exception ex)\n'
    if text.count(helper_anchor) != 1:
        raise SystemExit(f"C# helper insertion anchor count={text.count(helper_anchor)}")
    text = text.replace(helper_anchor, CS_HELPERS + "\n" + helper_anchor, 1)

    required = ["RunRuntimeCleanupHelper", "DeleteRuntimeTreeNoFollow", "CleanupStaleRuntimeSessions", "AOTR8P_SESSION_"]
    for needle in required:
        if needle not in text:
            raise SystemExit(f"C# session cleanup contract missing: {needle}")
    source_out.write_text(text, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("engine")
    parser.add_argument("gui")
    parser.add_argument("source_in")
    parser.add_argument("source_out")
    args = parser.parse_args()
    patch_engine(Path(args.engine))
    patch_gui(Path(args.gui))
    patch_csharp(Path(args.source_in), Path(args.source_out))
    print("ISSUE84_SESSION_RUNTIME_PATCH_PASS")


if __name__ == "__main__":
    main()
