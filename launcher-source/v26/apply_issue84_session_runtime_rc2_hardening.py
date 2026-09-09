from pathlib import Path
import argparse
import re

ENGINE_STAGE_ROOT_RC2 = r'''function Get-AotR8PRuntimeStageRoot([string]$InstallRoot, [string]$StateRoot) {
    $stateRootFull = [IO.Path]::GetFullPath($StateRoot)
    $runtimeRoot = Join-Path $stateRootFull "runtime"
    $sessionRoot = Join-Path $runtimeRoot "sessions"

    foreach ($candidate in @($stateRootFull, $runtimeRoot, $sessionRoot)) {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $item = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "A8P transient runtime state must not use a reparse/junction directory: $candidate"
            }
        }
    }

    New-Item -ItemType Directory -Force -Path $sessionRoot | Out-Null

    foreach ($candidate in @($stateRootFull, $runtimeRoot, $sessionRoot)) {
        $item = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "A8P transient runtime state became a reparse/junction directory: $candidate"
        }
    }

    return [IO.Path]::GetFullPath($sessionRoot)
}
'''

ENGINE_MARKER_RC2 = r'''function Write-AotR8PSessionMarker(
    [int]$GameLauncherPid,
    [long]$GameLauncherStartUtcTicks,
    [int]$GamePid,
    [long]$GameStartUtcTicks
) {
    if (-not (Test-Path -LiteralPath $test -PathType Container)) { return }

    $launcherProcess = Get-Process -Id $PID -ErrorAction Stop
    $launcherStartUtcTicks = [long]$launcherProcess.StartTime.ToUniversalTime().Ticks
    if ($launcherStartUtcTicks -le 0) {
        throw "Could not capture launcher process identity for transient runtime session."
    }

    $sessionMarker = Join-Path $test "AOTR8P_SESSION.json"
    $sessionState = [ordered]@{
        schema = 2
        session_id = [string](Split-Path $test -Leaf)
        launcher_pid = [int]$PID
        launcher_start_utc_ticks = [long]$launcherStartUtcTicks
        game_launcher_pid = [int]$GameLauncherPid
        game_launcher_start_utc_ticks = [long]$GameLauncherStartUtcTicks
        game_pid = [int]$GamePid
        game_start_utc_ticks = [long]$GameStartUtcTicks
        updated_utc = [DateTime]::UtcNow.ToString("o")
    }

    $json = $sessionState | ConvertTo-Json -Depth 3
    $tmpMarker = $sessionMarker + ".tmp." + [Guid]::NewGuid().ToString("N")
    try {
        [IO.File]::WriteAllText($tmpMarker, $json, (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $sessionMarker -PathType Leaf) {
            try {
                [IO.File]::Replace($tmpMarker, $sessionMarker, $null)
            }
            catch {
                Copy-Item -LiteralPath $tmpMarker -Destination $sessionMarker -Force -ErrorAction Stop
                Remove-Item -LiteralPath $tmpMarker -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            [IO.File]::Move($tmpMarker, $sessionMarker)
        }
    }
    finally {
        Remove-Item -LiteralPath $tmpMarker -Force -ErrorAction SilentlyContinue
    }
}
'''

CS_HELPERS_RC2 = r'''
    private sealed class RuntimeSessionMarker
    {
        public int schema { get; set; }
        public string session_id { get; set; }
        public int launcher_pid { get; set; }
        public long launcher_start_utc_ticks { get; set; }
        public int game_launcher_pid { get; set; }
        public long game_launcher_start_utc_ticks { get; set; }
        public int game_pid { get; set; }
        public long game_start_utc_ticks { get; set; }
        public string updated_utc { get; set; }
    }

    private static string RuntimeSessionRoot()
    {
        return Path.GetFullPath(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "AotR 8P WotR Mod", "runtime", "sessions"));
    }

    private static bool ExistingDirectoryIsSafeNonReparse(string path)
    {
        if (!Directory.Exists(path)) return true;
        try
        {
            return (File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0;
        }
        catch { return false; }
    }

    private static bool RuntimeSessionRootComponentsSafe()
    {
        try
        {
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string state = Path.GetFullPath(Path.Combine(local, "AotR 8P WotR Mod"));
            string runtime = Path.Combine(state, "runtime");
            string sessions = Path.Combine(runtime, "sessions");
            return ExistingDirectoryIsSafeNonReparse(state) &&
                   ExistingDirectoryIsSafeNonReparse(runtime) &&
                   ExistingDirectoryIsSafeNonReparse(sessions);
        }
        catch { return false; }
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

    private static bool TryParseRuntimeSessionPath(string path, out string full, out string sessionId, out int launcherPid)
    {
        full = null;
        sessionId = null;
        launcherPid = 0;
        if (String.IsNullOrWhiteSpace(path)) return false;
        if (!RuntimeSessionRootComponentsSafe()) return false;

        string root = RuntimeSessionRoot().TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        try { full = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar); }
        catch { return false; }

        string parent = Path.GetDirectoryName(full);
        if (String.IsNullOrWhiteSpace(parent) ||
            !String.Equals(parent.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
                           root, StringComparison.OrdinalIgnoreCase))
            return false;

        string leaf = Path.GetFileName(full);
        const string sessionPrefix = "AOTR8P_SESSION_";
        if (!leaf.StartsWith(sessionPrefix, StringComparison.Ordinal)) return false;
        string tail = leaf.Substring(sessionPrefix.Length);
        int split = tail.IndexOf('_');
        if (split <= 0 || split == tail.Length - 1) return false;
        if (!Int32.TryParse(tail.Substring(0, split), out launcherPid) || launcherPid <= 0) return false;
        if (!IsHex32(tail.Substring(split + 1))) return false;
        sessionId = leaf;
        return true;
    }

    private static bool IsValidRuntimeSessionPath(string path)
    {
        string full;
        string sessionId;
        int launcherPid;
        return TryParseRuntimeSessionPath(path, out full, out sessionId, out launcherPid);
    }

    private static bool TryReadRuntimeSessionMarker(string path, out RuntimeSessionMarker marker)
    {
        marker = null;
        string full;
        string sessionId;
        int launcherPid;
        if (!TryParseRuntimeSessionPath(path, out full, out sessionId, out launcherPid)) return false;
        string markerPath = Path.Combine(full, "AOTR8P_SESSION.json");
        if (!File.Exists(markerPath)) return false;

        try
        {
            JavaScriptSerializer ser = new JavaScriptSerializer();
            marker = ser.Deserialize<RuntimeSessionMarker>(File.ReadAllText(markerPath, Encoding.UTF8));
            if (marker == null || marker.schema != 2) return false;
            if (!String.Equals(marker.session_id, sessionId, StringComparison.Ordinal)) return false;
            if (marker.launcher_pid != launcherPid || marker.launcher_pid <= 0) return false;
            if (marker.launcher_start_utc_ticks <= 0) return false;
            if (marker.game_launcher_pid < 0 || marker.game_pid < 0) return false;
            if (marker.game_launcher_start_utc_ticks < 0 || marker.game_start_utc_ticks < 0) return false;
            return true;
        }
        catch
        {
            marker = null;
            return false;
        }
    }

    private static bool IsAnyProcessAlive(int pid)
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

    private static bool IsRecordedProcessAlive(int pid, long expectedStartUtcTicks, string expectedProcessName)
    {
        if (pid <= 0) return false;
        try
        {
            using (Process p = Process.GetProcessById(pid))
            {
                if (p.HasExited) return false;

                if (!String.IsNullOrWhiteSpace(expectedProcessName) &&
                    !String.Equals(p.ProcessName, expectedProcessName, StringComparison.OrdinalIgnoreCase))
                    return false;

                if (expectedStartUtcTicks <= 0)
                    return true;

                try
                {
                    long actual = p.StartTime.ToUniversalTime().Ticks;
                    long diff = actual >= expectedStartUtcTicks
                        ? actual - expectedStartUtcTicks
                        : expectedStartUtcTicks - actual;
                    return diff <= TimeSpan.TicksPerSecond;
                }
                catch
                {
                    return true;
                }
            }
        }
        catch { return false; }
    }

    private static bool MarkerHasActiveProcesses(RuntimeSessionMarker marker)
    {
        if (marker == null) return false;
        return
            IsRecordedProcessAlive(marker.launcher_pid, marker.launcher_start_utc_ticks, null) ||
            IsRecordedProcessAlive(marker.game_launcher_pid, marker.game_launcher_start_utc_ticks, "lotrbfme2ep1") ||
            IsRecordedProcessAlive(marker.game_pid, marker.game_start_utc_ticks, "game");
    }

    private static bool AnyAotRGameProcessAlive()
    {
        foreach (string name in new string[] { "game", "lotrbfme2ep1" })
        {
            Process[] processes = null;
            try
            {
                processes = Process.GetProcessesByName(name);
                if (processes != null && processes.Length > 0) return true;
            }
            catch { }
            finally
            {
                if (processes != null)
                {
                    foreach (Process p in processes)
                    {
                        try { p.Dispose(); } catch { }
                    }
                }
            }
        }
        return false;
    }

    private static double RuntimeSessionAgeMinutes(string path)
    {
        try
        {
            DateTime stamp = Directory.GetLastWriteTimeUtc(path);
            return Math.Max(0.0, (DateTime.UtcNow - stamp).TotalMinutes);
        }
        catch { return 0.0; }
    }

    private static bool CanDeleteRuntimeSessionNow(string path, bool allowInvalidAgedMarker)
    {
        string full;
        string sessionId;
        int launcherPidFromName;
        if (!TryParseRuntimeSessionPath(path, out full, out sessionId, out launcherPidFromName))
            return false;

        RuntimeSessionMarker marker;
        if (TryReadRuntimeSessionMarker(full, out marker))
        {
            if (MarkerHasActiveProcesses(marker)) return false;

            if (marker.game_launcher_pid <= 0 && marker.game_pid <= 0 && AnyAotRGameProcessAlive())
                return false;

            return true;
        }

        if (!allowInvalidAgedMarker) return false;
        if (IsAnyProcessAlive(launcherPidFromName)) return false;
        if (AnyAotRGameProcessAlive()) return false;
        return RuntimeSessionAgeMinutes(full) >= 30.0;
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
        if (!IsValidRuntimeSessionPath(path))
            throw new InvalidDataException("Refusing to delete a path outside the direct runtime-session root.");

        Exception last = null;
        for (int attempt = 0; attempt < 120; attempt++)
        {
            try
            {
                if (!Directory.Exists(path)) return;
                if (!RuntimeSessionRootComponentsSafe())
                    throw new InvalidDataException("Runtime-session parent chain is a reparse point.");
                DeleteRuntimeTreeNoFollow(path);
                return;
            }
            catch (IOException ex) { last = ex; Thread.Sleep(250); }
            catch (UnauthorizedAccessException ex) { last = ex; Thread.Sleep(250); }
        }
        throw new IOException("Could not delete transient runtime session after repeated retries.", last);
    }

    private static void CleanupEmptyRuntimeSessionRoot()
    {
        try
        {
            string root = RuntimeSessionRoot();
            if (RuntimeSessionRootComponentsSafe() &&
                Directory.Exists(root) &&
                Directory.GetFileSystemEntries(root).Length == 0)
                Directory.Delete(root, false);
        }
        catch { }
    }

    private static void RunRuntimeCleanupWatch(string[] args)
    {
        if (args == null || args.Length < 2) Environment.Exit(2);
        string path = args[1];
        if (!IsValidRuntimeSessionPath(path)) Environment.Exit(3);

        try
        {
            while (Directory.Exists(path))
            {
                if (CanDeleteRuntimeSessionNow(path, true))
                {
                    Thread.Sleep(750);
                    if (CanDeleteRuntimeSessionNow(path, true))
                    {
                        DeleteRuntimeSessionWithRetries(path);
                        CleanupEmptyRuntimeSessionRoot();
                        Environment.Exit(0);
                    }
                }
                Thread.Sleep(500);
            }
            CleanupEmptyRuntimeSessionRoot();
            Environment.Exit(0);
        }
        catch
        {
            Environment.Exit(4);
        }
    }

    private static void RunRuntimeCleanupStale(string[] args)
    {
        if (args == null || args.Length < 2) Environment.Exit(2);
        string path = args[1];
        if (!IsValidRuntimeSessionPath(path)) Environment.Exit(3);

        try
        {
            if (!CanDeleteRuntimeSessionNow(path, true))
                Environment.Exit(5);

            DeleteRuntimeSessionWithRetries(path);
            CleanupEmptyRuntimeSessionRoot();
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
        if (!RuntimeSessionRootComponentsSafe() || !Directory.Exists(root)) return;

        foreach (string path in Directory.GetDirectories(root, "AOTR8P_SESSION_*", SearchOption.TopDirectoryOnly))
        {
            if (!IsValidRuntimeSessionPath(path)) continue;
            if (!CanDeleteRuntimeSessionNow(path, true)) continue;
            try { DeleteRuntimeSessionWithRetries(path); } catch { }
        }
        CleanupEmptyRuntimeSessionRoot();
    }

    private static bool RuntimeLifecycleSelfTest()
    {
        try
        {
            using (Process self = Process.GetCurrentProcess())
            {
                long ticks = self.StartTime.ToUniversalTime().Ticks;
                if (!IsRecordedProcessAlive(self.Id, ticks, null)) return false;
                if (IsRecordedProcessAlive(self.Id, ticks + (TimeSpan.TicksPerSecond * 5L), null)) return false;

                string root = RuntimeSessionRoot();
                string direct = Path.Combine(root, "AOTR8P_SESSION_" +
                    self.Id.ToString(System.Globalization.CultureInfo.InvariantCulture) + "_" +
                    Guid.NewGuid().ToString("N"));
                if (!IsValidRuntimeSessionPath(direct)) return false;

                string nested = Path.Combine(root, "nested", Path.GetFileName(direct));
                if (IsValidRuntimeSessionPath(nested)) return false;

                return true;
            }
        }
        catch { return false; }
    }
'''


def replace_ps_function(text: str, name: str, replacement: str) -> str:
    pattern = rf"(?ms)^function\s+{re.escape(name)}\b.*?^}}\s*\n"
    text2, count = re.subn(pattern, lambda _m: replacement + "\n", text, count=1)
    if count != 1:
        raise SystemExit(f"expected exactly one PowerShell function {name}, found {count}")
    return text2


def patch_engine(path: Path) -> None:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    text = replace_ps_function(text, "Get-AotR8PRuntimeStageRoot", ENGINE_STAGE_ROOT_RC2)
    text = replace_ps_function(text, "Write-AotR8PSessionMarker", ENGINE_MARKER_RC2)

    old_initial = "Write-AotR8PSessionMarker -GameLauncherPid 0 -GamePid 0"
    new_initial = (
        "Write-AotR8PSessionMarker -GameLauncherPid 0 "
        "-GameLauncherStartUtcTicks 0 -GamePid 0 -GameStartUtcTicks 0"
    )
    if text.count(old_initial) != 1:
        raise SystemExit(f"initial marker call count={text.count(old_initial)}")
    text = text.replace(old_initial, new_initial, 1)

    launcher_anchor = '''$launcherPid = $launcher.Id
Write-Host "lotrbfme2ep1.exe PID: $launcherPid" -ForegroundColor Green
'''
    launcher_new = '''$launcherPid = $launcher.Id
$gameLauncherStartUtcTicks = 0
try {
    $gameLauncherStartUtcTicks = [long]$launcher.StartTime.ToUniversalTime().Ticks
}
catch {
    try {
        $gameLauncherStartUtcTicks = [long](Get-Process -Id $launcherPid -ErrorAction Stop).StartTime.ToUniversalTime().Ticks
    }
    catch {}
}
Write-AotR8PSessionMarker `
    -GameLauncherPid $launcherPid `
    -GameLauncherStartUtcTicks $gameLauncherStartUtcTicks `
    -GamePid 0 `
    -GameStartUtcTicks 0
try {
    $launcherExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    [void](Start-Process -FilePath $launcherExe -ArgumentList @(
        "--cleanup-runtime-watch",
        ('"' + $test + '"')
    ) -WindowStyle Hidden -ErrorAction Stop)
    Write-Host "Transient runtime lifecycle watcher armed." -ForegroundColor DarkGray
}
catch {
    Write-Host ("Runtime lifecycle watcher could not start; next launcher start will sweep stale session: " + $_.Exception.Message) -ForegroundColor Yellow
}
Write-Host "lotrbfme2ep1.exe PID: $launcherPid" -ForegroundColor Green
'''
    if text.count(launcher_anchor) != 1:
        raise SystemExit(f"launcher PID anchor count={text.count(launcher_anchor)}")
    text = text.replace(launcher_anchor, launcher_new, 1)

    old_game_block = r'''$gamePid = [int]$gameInfo.ProcessId
$sessionMarker = Join-Path $test "AOTR8P_SESSION.json"
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
    new_game_block = r'''$gamePid = [int]$gameInfo.ProcessId
$gameStartUtcTicks = 0
try {
    $gameStartUtcTicks = [long](Get-Process -Id $gamePid -ErrorAction Stop).StartTime.ToUniversalTime().Ticks
}
catch {
    try {
        if ($null -ne $gameInfo.CreationDate) {
            $gameStartUtcTicks = [long]([DateTime]$gameInfo.CreationDate).ToUniversalTime().Ticks
        }
    }
    catch {}
}
Write-AotR8PSessionMarker `
    -GameLauncherPid $launcherPid `
    -GameLauncherStartUtcTicks $gameLauncherStartUtcTicks `
    -GamePid $gamePid `
    -GameStartUtcTicks $gameStartUtcTicks
'''
    if text.count(old_game_block) != 1:
        raise SystemExit(f"RC1 game marker/helper block count={text.count(old_game_block)}")
    text = text.replace(old_game_block, new_game_block, 1)

    required = [
        "schema = 2",
        "launcher_start_utc_ticks",
        "game_launcher_start_utc_ticks",
        "game_start_utc_ticks",
        "--cleanup-runtime-watch",
        "runtime\\sessions",
        "ReparsePoint",
    ]
    for needle in required:
        if needle not in text:
            raise SystemExit(f"RC2 engine contract missing: {needle}")

    path.write_text(text, encoding="utf-8-sig", newline="\n")


def patch_gui(path: Path) -> None:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    old = '''                $p = Start-Process -FilePath $launcherExe -ArgumentList @(
                    "--cleanup-runtime",
                    ('"' + $item.FullName + '"'),
                    "0","0","0"
                ) -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
'''
    new = '''                $p = Start-Process -FilePath $launcherExe -ArgumentList @(
                    "--cleanup-runtime-stale",
                    ('"' + $item.FullName + '"')
                ) -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
'''
    if text.count(old) != 1:
        raise SystemExit(f"Auto-Repair cleanup helper anchor count={text.count(old)}")
    text = text.replace(old, new, 1)

    if '"--cleanup-runtime",' in text:
        raise SystemExit("unsafe zero-PID cleanup mode remains in GUI")
    if "--cleanup-runtime-stale" not in text:
        raise SystemExit("stale-only Auto-Repair cleanup mode missing")
    path.write_text(text, encoding="utf-8-sig", newline="\n")


def patch_csharp(path: Path) -> None:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")

    old_mode = '''        if (args != null && args.Length > 0 &&
            String.Equals(args[0], "--cleanup-runtime", StringComparison.OrdinalIgnoreCase))
        {
            RunRuntimeCleanupHelper(args);
            return;
        }

        CleanupStaleUpdateFiles();'''
    new_mode = '''        if (args != null && args.Length > 0 &&
            String.Equals(args[0], "--cleanup-runtime-watch", StringComparison.OrdinalIgnoreCase))
        {
            RunRuntimeCleanupWatch(args);
            return;
        }
        if (args != null && args.Length > 0 &&
            String.Equals(args[0], "--cleanup-runtime-stale", StringComparison.OrdinalIgnoreCase))
        {
            RunRuntimeCleanupStale(args);
            return;
        }
        if (args != null && args.Length > 0 &&
            String.Equals(args[0], "--runtime-lifecycle-selftest", StringComparison.OrdinalIgnoreCase))
        {
            Environment.Exit(RuntimeLifecycleSelfTest() ? 0 : 9);
            return;
        }

        CleanupStaleUpdateFiles();'''
    if text.count(old_mode) != 1:
        raise SystemExit(f"RC1 C# cleanup mode anchor count={text.count(old_mode)}")
    text = text.replace(old_mode, new_mode, 1)

    pattern = r"(?ms)^    private sealed class RuntimeSessionMarker\b.*?(?=^    private static string FormatException\(Exception ex\))"
    text2, count = re.subn(pattern, lambda _m: CS_HELPERS_RC2 + "\n", text, count=1)
    if count != 1:
        raise SystemExit(f"RC1 C# helper block count={count}")
    text = text2

    required = [
        "launcher_start_utc_ticks",
        "TryReadRuntimeSessionMarker",
        "IsRecordedProcessAlive",
        "RuntimeSessionRootComponentsSafe",
        "Path.GetDirectoryName(full)",
        "--cleanup-runtime-watch",
        "--cleanup-runtime-stale",
        "--runtime-lifecycle-selftest",
        "CanDeleteRuntimeSessionNow",
        "RuntimeLifecycleSelfTest",
    ]
    for needle in required:
        if needle not in text:
            raise SystemExit(f"RC2 C# contract missing: {needle}")

    path.write_text(text, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("engine")
    parser.add_argument("gui")
    parser.add_argument("csharp")
    args = parser.parse_args()

    patch_engine(Path(args.engine))
    patch_gui(Path(args.gui))
    patch_csharp(Path(args.csharp))
    print("ISSUE84_SESSION_RUNTIME_RC2_HARDENING_PASS")


if __name__ == "__main__":
    main()
