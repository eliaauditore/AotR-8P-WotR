using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

[assembly: AssemblyTitle("AotR 8P War of the Ring")]
[assembly: AssemblyProduct("AotR 8P War of the Ring")]
[assembly: AssemblyCompany("AotR 8P WotR Community Mod")]
[assembly: AssemblyDescription("Official launcher for the AotR 8P War of the Ring community mod")]
[assembly: AssemblyFileVersion("__FILE_VERSION__")]
[assembly: AssemblyInformationalVersion("__LAUNCHER_VERSION__")]

internal static class Program
{
    private const string MutexName = @"Local\eliaauditore_AotR8P_WotR_Mod_SINGLE_EXE";
    private const string LauncherVersion = "__LAUNCHER_VERSION__";
    private const string UpdateManifestUrl = "__UPDATE_URL__";

    private const string SkinResourceName = "AotR8P.LauncherSkin";
    private const string GuiResourceName = "AotR8P.GuiScript";
    private const string EngineResourceName = "AotR8P.EngineScript";
    private const string FinalStableV7ResourceName = "AotR8P.FinalStableV7";
    private const string Row1PatchResourceName = "AotR8P.Row1Patch";
    private const string Row2PatchResourceName = "AotR8P.Row2Patch";
    private const string Row3PatchResourceName = "AotR8P.Row3Patch";
    private const string ReadyPatchResourceName = "AotR8P.ReadyPatch";

    private static byte[] ReadEmbeddedBytes(string resourceName)
    {
        Assembly assembly = Assembly.GetExecutingAssembly();
        using (Stream input = assembly.GetManifestResourceStream(resourceName))
        {
            if (input == null)
                throw new InvalidOperationException("Missing embedded resource: " + resourceName);
            using (MemoryStream output = new MemoryStream())
            {
                input.CopyTo(output);
                return output.ToArray();
            }
        }
    }

    private static string ReadEmbeddedUtf8(string resourceName)
    {
        byte[] bytes = ReadEmbeddedBytes(resourceName);
        string text = Encoding.UTF8.GetString(bytes);
        if (!String.IsNullOrEmpty(text) && text[0] == '\uFEFF')
            text = text.Substring(1);
        return text;
    }

    [STAThread]
    private static void Main(string[] args)
    {
        if (args != null && args.Length > 0 &&
            String.Equals(args[0], "--apply-update", StringComparison.OrdinalIgnoreCase))
        {
            RunUpdateHelper(args);
            return;
        }

        CleanupStaleUpdateFiles();

        bool createdNew;
        using (Mutex mutex = new Mutex(true, MutexName, out createdNew))
        {
            if (!createdNew)
            {
                MessageBox.Show(
                    "AotR 8P WotR Mod is already running.",
                    "AotR 8P War of the Ring",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
                return;
            }

            string exePath = Process.GetCurrentProcess().MainModule.FileName;
            string root = Path.GetDirectoryName(exePath);

            try
            {
                if (TrySelfUpdate(exePath, root))
                    return;
            }
            catch (Exception updateEx)
            {
                LogUpdate("Update check failed: " + FormatException(updateEx));
            }

            TryCreateDesktopShortcut(exePath, root);

            string guiScript = ReadEmbeddedUtf8(GuiResourceName);
            string engineScript = ReadEmbeddedUtf8(EngineResourceName);

            try
            {
                using (Runspace runspace = RunspaceFactory.CreateRunspace())
                {
                    runspace.ApartmentState = ApartmentState.STA;
                    runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                    runspace.Open();
                    runspace.SessionStateProxy.SetVariable("AOTR8P_PACKAGE_ROOT", root);
                    runspace.SessionStateProxy.SetVariable("AOTR8P_ENGINE_SCRIPT", engineScript);
                    runspace.SessionStateProxy.SetVariable("AOTR8P_SKIN_BYTES", ReadEmbeddedBytes(SkinResourceName));
                    runspace.SessionStateProxy.SetVariable("AOTR8P_LAUNCHER_VERSION", LauncherVersion);
                    runspace.SessionStateProxy.SetVariable("AOTR8P_UPDATE_MANIFEST_URL", UpdateManifestUrl);
                    runspace.SessionStateProxy.SetVariable("AOTR8P_FINAL_STABLE_V7_BYTES", ReadEmbeddedBytes(FinalStableV7ResourceName));
                    runspace.SessionStateProxy.SetVariable("AOTR8P_ROW1_PATCH", ReadEmbeddedBytes(Row1PatchResourceName));
                    runspace.SessionStateProxy.SetVariable("AOTR8P_ROW2_PATCH", ReadEmbeddedBytes(Row2PatchResourceName));
                    runspace.SessionStateProxy.SetVariable("AOTR8P_ROW3_PATCH", ReadEmbeddedBytes(Row3PatchResourceName));
                    runspace.SessionStateProxy.SetVariable("AOTR8P_READY_PATCH", ReadEmbeddedBytes(ReadyPatchResourceName));

                    using (PowerShell ps = PowerShell.Create())
                    {
                        ps.Runspace = runspace;
                        ps.AddScript(guiScript);
                        ps.Invoke();

                        if (ps.HadErrors)
                        {
                            StringBuilder sb = new StringBuilder();
                            foreach (var err in ps.Streams.Error)
                            {
                                if (sb.Length > 0) sb.AppendLine();
                                sb.Append(err.ToString());
                            }
                            if (sb.Length > 0)
                            {
                                MessageBox.Show(
                                    "Launcher error:\r\n\r\n" + sb.ToString(),
                                    "AotR 8P War of the Ring",
                                    MessageBoxButtons.OK,
                                    MessageBoxIcon.Error);
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "Could not start the embedded launcher.\r\n\r\n" + FormatException(ex),
                    "AotR 8P War of the Ring",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
        }
    }

    private static string FormatException(Exception ex)
    {
        StringBuilder sb = new StringBuilder();
        int depth = 0;
        while (ex != null && depth < 8)
        {
            if (depth > 0) sb.AppendLine().AppendLine("Inner exception:");
            sb.Append(ex.GetType().FullName).Append(": ").Append(ex.Message);
            ex = ex.InnerException;
            depth++;
        }
        return sb.ToString();
    }

    private sealed class UpdateManifest
    {
        public int schema { get; set; }
        public string launcher_version { get; set; }
        public string launcher_url { get; set; }
        public string launcher_sha256 { get; set; }
        public bool mandatory { get; set; }
    }

    private static bool TrySelfUpdate(string exePath, string root)
    {
        if (String.IsNullOrWhiteSpace(UpdateManifestUrl) ||
            UpdateManifestUrl.StartsWith("__", StringComparison.Ordinal))
            return false;

        LogUpdate("Checking " + UpdateManifestUrl + " from launcher " + LauncherVersion);
        string json = DownloadUtf8String(UpdateManifestUrl);
        JavaScriptSerializer ser = new JavaScriptSerializer();
        UpdateManifest manifest = ser.Deserialize<UpdateManifest>(json);
        if (manifest == null || manifest.schema != 1)
            return false;

        Version current;
        Version remote;
        if (!TryVersion(LauncherVersion, out current) ||
            !TryVersion(manifest.launcher_version, out remote))
            return false;

        if (remote.CompareTo(current) <= 0)
        {
            LogUpdate("Launcher is current. Remote=" + manifest.launcher_version);
            return false;
        }

        LogUpdate("Update available: " + LauncherVersion + " -> " + manifest.launcher_version);
        if (String.IsNullOrWhiteSpace(manifest.launcher_url) ||
            String.IsNullOrWhiteSpace(manifest.launcher_sha256))
            return false;

        string updateDir = Path.Combine(root, ".launcher_update");
        Directory.CreateDirectory(updateDir);

        string packagePath = Path.Combine(updateDir, "launcher.download");
        string helperPath = Path.Combine(updateDir, "AotR 8P WotR Mod Update.exe");
        TryDelete(packagePath);
        TryDelete(helperPath);

        DownloadToFile(manifest.launcher_url, packagePath);
        string actual = Sha256(packagePath);
        if (!String.Equals(actual, manifest.launcher_sha256.Trim(), StringComparison.OrdinalIgnoreCase))
        {
            TryDelete(packagePath);
            throw new InvalidDataException("Launcher update SHA256 verification failed.");
        }
        LogUpdate("Downloaded update package verified: " + actual);

        File.Copy(packagePath, helperPath, true);
        string helperHash = Sha256(helperPath);
        if (!String.Equals(helperHash, actual, StringComparison.OrdinalIgnoreCase))
        {
            TryDelete(helperPath);
            TryDelete(packagePath);
            throw new InvalidDataException("Materialized update helper SHA256 mismatch.");
        }

        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = helperPath;
        psi.Arguments =
            "--apply-update " +
            QuoteArgument(exePath) + " " +
            Process.GetCurrentProcess().Id.ToString(System.Globalization.CultureInfo.InvariantCulture) + " " +
            actual;
        psi.WorkingDirectory = updateDir;
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WindowStyle = ProcessWindowStyle.Hidden;
        Process.Start(psi);
        LogUpdate("Verified install-staged update helper started; launcher will exit for replacement.");
        return true;
    }

    internal static string ManualUpdateCheck()
    {
        string exePath = Process.GetCurrentProcess().MainModule.FileName;
        string root = Path.GetDirectoryName(exePath);
        try
        {
            if (TrySelfUpdate(exePath, root))
                return "UPDATE_STARTED";
            return "UP_TO_DATE|" + LauncherVersion;
        }
        catch (Exception ex)
        {
            LogUpdate("Manual update check failed: " + FormatException(ex));
            return "ERROR|" + FormatException(ex);
        }
    }

    private static void RunUpdateHelper(string[] args)
    {
        string stagedExe = null;
        string backupExe = null;
        try
        {
            if (args.Length < 4)
                throw new ArgumentException("Invalid update-helper arguments.");

            string targetExe = Path.GetFullPath(args[1]);
            int parentPid;
            if (!Int32.TryParse(args[2], out parentPid) || parentPid <= 0)
                throw new ArgumentException("Invalid launcher PID.");

            string expectedHash = (args[3] ?? String.Empty).Trim();
            if (expectedHash.Length != 64)
                throw new ArgumentException("Invalid expected SHA256.");

            string helperExe = Process.GetCurrentProcess().MainModule.FileName;
            string helperHash = Sha256(helperExe);
            if (!String.Equals(helperHash, expectedHash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Update helper SHA256 does not match the verified download.");

            LogUpdate("Update helper " + LauncherVersion + " started for PID " +
                parentPid.ToString(System.Globalization.CultureInfo.InvariantCulture) + ".");

            try
            {
                Process parent = Process.GetProcessById(parentPid);
                parent.WaitForExit(30000);
            }
            catch (ArgumentException) { }
            catch (Exception ex) { LogUpdate("Parent wait warning: " + ex.Message); }

            string targetDir = Path.GetDirectoryName(targetExe);
            stagedExe = Path.Combine(targetDir, "AotR 8P WotR Mod.update-staged.exe");
            backupExe = Path.Combine(targetDir, "AotR 8P WotR Mod.rollback.exe");
            TryDelete(stagedExe);
            TryDelete(backupExe);

            File.Copy(helperExe, stagedExe, true);
            if (!String.Equals(Sha256(stagedExe), expectedHash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Staged launcher SHA256 mismatch.");

            bool targetExisted = File.Exists(targetExe);
            if (targetExisted)
                File.Copy(targetExe, backupExe, true);

            ReplaceFileWithRetries(stagedExe, targetExe);
            if (!String.Equals(Sha256(targetExe), expectedHash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Installed launcher SHA256 mismatch after replacement.");

            TryDelete(backupExe);
            TryDelete(Path.Combine(Path.GetDirectoryName(helperExe), "launcher.download"));
            LogUpdate("Update installed successfully: " + expectedHash);

            ProcessStartInfo relaunch = new ProcessStartInfo();
            relaunch.FileName = targetExe;
            relaunch.WorkingDirectory = targetDir;
            relaunch.UseShellExecute = true;
            Process.Start(relaunch);
        }
        catch (Exception ex)
        {
            LogUpdate("Update helper failed: " + FormatException(ex));
            try
            {
                if (!String.IsNullOrWhiteSpace(backupExe) && File.Exists(backupExe))
                {
                    if (!String.IsNullOrWhiteSpace(stagedExe)) TryDelete(stagedExe);
                    ReplaceFileWithRetries(backupExe, args != null && args.Length > 1 ? Path.GetFullPath(args[1]) : backupExe + ".restored");
                    LogUpdate("Rollback completed after update failure.");
                }
            }
            catch (Exception rollbackEx)
            {
                LogUpdate("Rollback failed: " + FormatException(rollbackEx));
            }

            MessageBox.Show(
                "Launcher update failed. The previous launcher was preserved when possible.\r\n\r\n" + FormatException(ex),
                "AotR 8P War of the Ring",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
        finally
        {
            TryDelete(stagedExe);
            if (!String.IsNullOrWhiteSpace(backupExe) && File.Exists(backupExe))
            {
                try { File.Delete(backupExe); } catch { }
            }
        }
    }

    private static void ReplaceFileWithRetries(string source, string destination)
    {
        Exception last = null;
        for (int attempt = 0; attempt < 80; attempt++)
        {
            try
            {
                if (File.Exists(destination))
                    File.Delete(destination);
                File.Move(source, destination);
                return;
            }
            catch (IOException ex)
            {
                last = ex;
                Thread.Sleep(250);
            }
            catch (UnauthorizedAccessException ex)
            {
                last = ex;
                Thread.Sleep(250);
            }
        }
        throw new IOException("Could not replace launcher executable after repeated retries.", last);
    }

    private static bool IsProcessRunningFromPath(string fullPath)
    {
        string expected = Path.GetFullPath(fullPath);
        foreach (Process process in Process.GetProcesses())
        {
            try
            {
                string candidate = process.MainModule == null ? null : process.MainModule.FileName;
                if (!String.IsNullOrWhiteSpace(candidate) &&
                    String.Equals(Path.GetFullPath(candidate), expected, StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            catch { }
            finally { process.Dispose(); }
        }
        return false;
    }

    private static void CleanupStaleUpdateFiles()
    {
        try
        {
            string currentExe = Process.GetCurrentProcess().MainModule.FileName;
            string root = Path.GetDirectoryName(currentExe);
            string updateDir = Path.Combine(root, ".launcher_update");
            if (Directory.Exists(updateDir))
            {
                foreach (string file in Directory.GetFiles(updateDir))
                {
                    if (String.Equals(Path.GetFullPath(file), Path.GetFullPath(currentExe), StringComparison.OrdinalIgnoreCase))
                        continue;
                    try
                    {
                        DateTime ageReference = File.GetLastWriteTimeUtc(file);
                        if ((DateTime.UtcNow - ageReference).TotalSeconds >= 3)
                            File.Delete(file);
                    }
                    catch { }
                }
                try
                {
                    if (Directory.Exists(updateDir) && Directory.GetFileSystemEntries(updateDir).Length == 0)
                        Directory.Delete(updateDir);
                }
                catch { }
            }
        }
        catch { }
    }

    private static string QuoteArgument(string value)
    {
        if (value == null) return "\"\"";
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static void LogUpdate(string message)
    {
        try
        {
            string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AotR 8P WotR Mod");
            Directory.CreateDirectory(dir);
            string path = Path.Combine(dir, "updater.log");
            File.AppendAllText(path, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + message + Environment.NewLine, Encoding.UTF8);
        }
        catch { }
    }

    private static HttpWebRequest CreateHttpRequest(string url)
    {
        ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
        HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
        request.Method = "GET";
        request.UserAgent = "AotR-8P-WotR-Launcher/" + LauncherVersion;
        request.CachePolicy = new System.Net.Cache.RequestCachePolicy(System.Net.Cache.RequestCacheLevel.NoCacheNoStore);
        request.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;
        request.Timeout = 15000;
        request.ReadWriteTimeout = 30000;
        return request;
    }

    private static string DownloadUtf8String(string url)
    {
        HttpWebRequest request = CreateHttpRequest(url);
        using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
        using (Stream input = response.GetResponseStream())
        using (StreamReader reader = new StreamReader(input, Encoding.UTF8, true))
            return reader.ReadToEnd();
    }

    private static void DownloadToFile(string url, string path)
    {
        HttpWebRequest request = CreateHttpRequest(url);
        using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
        using (Stream input = response.GetResponseStream())
        using (FileStream output = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            input.CopyTo(output);
            output.Flush(true);
        }
    }

    private static bool TryVersion(string text, out Version version)
    {
        version = null;
        if (String.IsNullOrWhiteSpace(text)) return false;
        string clean = text.Trim();
        int dash = clean.IndexOf('-');
        if (dash >= 0) clean = clean.Substring(0, dash);
        return Version.TryParse(clean, out version);
    }

    private static string Sha256(string path)
    {
        using (SHA256 sha = SHA256.Create())
        using (FileStream fs = File.OpenRead(path))
            return BitConverter.ToString(sha.ComputeHash(fs)).Replace("-", "");
    }

    private static void TryDelete(string path)
    {
        if (String.IsNullOrWhiteSpace(path)) return;
        try { if (File.Exists(path)) File.Delete(path); } catch { }
    }

    private static void TryCreateDesktopShortcut(string exePath, string root)
    {
        try
        {
            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            string shortcutPath = Path.Combine(desktop, "AotR 8P WotR Mod.lnk");
            try { if (File.Exists(shortcutPath)) File.Delete(shortcutPath); } catch { }

            Type shellType = Type.GetTypeFromProgID("WScript.Shell");
            if (shellType == null) return;
            object shell = Activator.CreateInstance(shellType);
            object shortcut = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { shortcutPath });
            Type shortcutType = shortcut.GetType();
            shortcutType.InvokeMember("TargetPath", BindingFlags.SetProperty, null, shortcut, new object[] { exePath });
            shortcutType.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, shortcut, new object[] { root });
            shortcutType.InvokeMember("Description", BindingFlags.SetProperty, null, shortcut, new object[] { "AotR 8P War of the Ring" });
            shortcutType.InvokeMember("IconLocation", BindingFlags.SetProperty, null, shortcut, new object[] { exePath + ",0" });
            shortcutType.InvokeMember("Save", BindingFlags.InvokeMethod, null, shortcut, null);
            if (shortcut is System.Runtime.InteropServices.ComTypes.IStream) { }
            System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shortcut);
            System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shell);
        }
        catch { }
    }
}

public static class AotR8PUpdateBridge
{
    public static string CheckNow()
    {
        return Program.ManualUpdateCheck();
    }
}
