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
    private const string LauncherSkinSha256 = "BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6";

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

    private static string Sha256Bytes(byte[] bytes)
    {
        using (SHA256 sha = SHA256.Create())
            return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "");
    }

    private static void EnsureLauncherSkin()
    {
        byte[] expectedBytes = ReadEmbeddedBytes(SkinResourceName);
        string embeddedHash = Sha256Bytes(expectedBytes);
        if (!String.Equals(embeddedHash, LauncherSkinSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Embedded launcher skin SHA256 mismatch: " + embeddedHash);

        string skinPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "internal", "assets", "launcher_skin.png");
        if (File.Exists(skinPath))
        {
            string existingHash = Sha256(skinPath);
            if (String.Equals(existingHash, LauncherSkinSha256, StringComparison.OrdinalIgnoreCase))
                return;
        }

        string directory = Path.GetDirectoryName(skinPath);
        if (!Directory.Exists(directory))
            Directory.CreateDirectory(directory);

        using (FileStream output = new FileStream(skinPath, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            output.Write(expectedBytes, 0, expectedBytes.Length);
            output.Flush(true);
        }

        string writtenHash = Sha256(skinPath);
        if (!String.Equals(writtenHash, LauncherSkinSha256, StringComparison.OrdinalIgnoreCase))
            throw new IOException("Materialized launcher skin SHA256 mismatch: " + writtenHash);
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
                // Network/update failure must never block the known-good local launcher.
                LogUpdate("Update check failed: " + FormatException(updateEx));
            }

            // Only the launcher version that actually survives the update check may own
            // the desktop shortcut. Rebuild it from scratch so Windows cannot keep stale
            // Shell Link tracking metadata for a replaced self-updating executable.
            TryCreateDesktopShortcut(exePath, root);

            EnsureLauncherSkin();
            string guiScript = ReadEmbeddedUtf8(GuiResourceName);
            string engineScript = ReadEmbeddedUtf8(EngineResourceName);

            try
            {
                using (Runspace runspace = RunspaceFactory.CreateRunspace())
                {
                    // WPF must be created on an STA thread. A fresh PowerShell runspace
                    // otherwise defaults to a worker thread that can be MTA, causing
                    // XamlReader.Load() / Window construction to fail. Keep the GUI
                    // runspace on this [STAThread] Main thread.
                    runspace.ApartmentState = ApartmentState.STA;
                    runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                    runspace.Open();
                    runspace.SessionStateProxy.SetVariable("AOTR8P_PACKAGE_ROOT", root);
                    runspace.SessionStateProxy.SetVariable("AOTR8P_ENGINE_SCRIPT", engineScript);
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

    internal static string ManualUpdateCheck()
    {
        try
        {
            string exePath = Process.GetCurrentProcess().MainModule.FileName;
            string root = Path.GetDirectoryName(exePath);
            bool updatedCopie = TrySelfUpdate(exePath, root, false);
            if (updatedCopy) return "UPDATED";
            return "UP-TO-DATE";
        }
        catch (Exception ex)
        {
            LogUpdate("Manual update check failed: " + FormatException(ex));
            return "ERROR: " + ex.Message;
        }
    }

    private static bool TrySelfUpdate(string exePath, string root)
    {
        return TrySelfUpdate(exePath, root, true);
    }

    private static bool TrySelfUpdate(string exePath, string root, bool startNewCopy)
    {
        if (String.IsNullOrWhiteSpace(UpdateManifestUrl)) return false;

        string json = DownloadUtf8String(UpdateManifestUrl);
        JavaScriptSerializer js = new JavaScriptSerializer();
        UpdateManifest manifest = js.Deserialize<UpdateManifest>(json);
        if (manifest == null)
            throw new InvalidDataException("Update manifest could not be parsed.");

        Version current;

        if (!TryVersion(LauncherVersion, out current))
            throw new InvalidOperationException("Local launcher version is invalid: " + LauncherVersion);

        string remoteText = manifest.launcher_version;
        string coreRemote = String.IsNullOrWhiteSpace(remoteText) ? String.Empty : remoteText.Split(new char[] { '-' }, 2)[0];
        Version remote;

        if (!Version.TryParse(coreRemote, out remote))
            throw new InvalidDataException("Remote launcher version is invalid: " + remoteText);

        if (remote <= current)
            return false;

        if (String.IsNullOrWhiteSpace(manifest.launcher_url)) ||
            String.IsNullOrWhiteSpace(manifest.launcher_sha256))
            throw new InvalidDataException("Remote manifest is missing launcher_url or launcher_sha256.");

        string updateDir = Path.Combine(root, ".launcher_update");
        Directory.CreateDirectory(updateDir);

        string newExe = Path.Combine(updateDir, "AotR 8P WotR Mod.new.exe");
        string updateExe = Path.Combine(updateDir, "AotR8P_WotR_Update_" + Guid.NewGuid().ToString("N") + ".exe");

        TryDelete(newExe);
        TryDelete(updateExe);

        DownloadToFile(manifest.launcher_url, newExe);

        string downloadedHash = Sha256(newExe);
        if (!String.Equals(downloadedHash, manifest.launcher_sha256, StringComparison.OrdinalIgnoreCase))
        {
            TryDelete(newExe);
            throw new InvalidDataException("Update SHA256 mismatch. Expected " + manifest.launcher_sha256 + " but got " + downloadedHash + ".");
        }

        File.Copy(exePath, updateExe, true);

        string arguments =
            "--apply-update " +
            QuoteArgument(proot) + " " +
            QuoteArgument(exePath) + " " +
            QuoteArgument(newExe) + " " +
            QuoteArgument(UpdateManifestUrl) + " " +
            QuoteArgument(UpdateManifestUrl) + " " +
            QuoteArgument(LauncherVersion) + " " +
            (startNewCopy ? "1" : "0");

        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = updateExe;
        psi.Arguments = arguments;
        psi.WorkingDirectory = updateDir;
        psi.UseShellExecute = true;
        psi.Verb = "runas";

        Process.Start(psi);

        LogUpdate("Launcher update staged to " + manifest.launcher_version + " with sha256 " + downloadedHash + " via " + updateDir);
        return true;
    }

    private static void RunUpdateHelper(string[] args)
    {
        if (args.Length < 7)
        {
            MessageBox.Show("Launcher update helper received invalid arguments.", "AotR 8P War of the Ring", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        string root = Path.GetFullPath(args[1]);
        string targetExe = Path.GetFullPath(args[2]);
        string newExe = Path.GetFullPath(args[3]);
        string manifestUrl = args[4];
        string updateManifestUrl = args[5];
        string fromVersion = args[6];
        bool startNewCopy = (args.Length < 8 || args[7] != "0");

        if (!String.Equals(Path.GetDirectoryName(targetExe).TrimEnd(Path.DirectorySeparatorChar), root.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Update helper target is outside the expected package root.");

        string updateDir = Path.GetDirectoryName(Process.GetCurrentProcess().MainModule.FileName);

        LogUpdate("Update helper started. root=" + root + " target=" + targetExe + " new=" + newExe + " from=" + fromVersion + " startNew=" + startNewCopy);

        try
        {
            for (int i = 0; i < 120; i++)
            {
                if (!IsProcessRunningFromPath(targetExe)) break;
                Thread.Sleep(250);
            }

            if (IsProcessRunningFromPath(targetExe))
                throw new IOException("Target launcher process did not exit within the update wait window.");

            for (int i = 0; i < 20; i++)
            {
                try
                {
                    File.Copy(newExe, targetExe, true);
                    break;
                }
                catch (IOException)
                {
                    Thread.Sleep(250);
                    if (i == 19) throw;
                }
            }

            string installedHash = Sha256(targetExe);
            string sourceHash = Sha256(newExe);
            if (!String.Equals(installedHash, sourceHash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Installed launcher SHA256 mismatch after replacement.");

            TryDelete(newExe);

            if (startNewCopy)
            {
                ProcessStartInfo next = new ProcessStartInfo();
                next.FileName = targetExe;
                next.WorkingDirectory = root;
                next.UseShellExecute = true;
                Process.Start(next);
            }

            LogUpdate("Update helper installed new launcher sha256 " + installedHash);
        }
        catch (Exception ex)
        {
            LogUpdate("Update helper failed: " + FormatException(ex));
            MessageBox.Show(
                "Launcher update failed.\r\n\r\n" + FormatException(ex),
                "AotR 8P War of the Ring",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private static void CleanupStaleUpdateFiles()
    {
        // Clean both the V15 install-owned staging directory and legacy V6/V14
        // %TEMP% helpers. Failures are intentionally non-fatal because an update helper
        // may still be exiting while the newly installed launcher starts.
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
                        Directory.Delete(updateDir, false);
                }
                catch { }
            }
        }
        catch { }

        try
        {
            string tempDir = Path.GetTempPath();
            string currentExe = Process.GetCurrentProcess().MainModule.FileName;
            foreach (string file in Directory.GetFiles(tempDir, "AotR8P_WotR_Update_*.exe"))
            {
                if (String.Equals(Path.GetFullPath(file), Path.GetFullPath(currentExe), StringComparison.OrdinalIgnoreCase))
                    continue;
                try
                {
                    DateTime ageReference = File.GetLastWriteTimeUtc(file);
                    if ((DateTime.UtcNow - ageReference).TotalSeconds >= 5)
                        File.Delete(file);
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
        ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; // TLS 1.2
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
      {
            return reader.ReadToEnd();
        }
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
        {
            return BitConverter.ToString(sha.ComputeHash(fs)).Replace("-", "");
        }
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { }
    }

    private static void TryCreateDesktopShortcut(string exePath, string root)
    {
        try
        {
            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            string shortcutPath = Path.Combine(desktop, "AotR 8P WotR Mod.lnk");

            // Do not edit an existing .lnk in place. Windows Shell Links can retain
            // distributed-link-tracking data for the old executable object even when
            // TargetPath text is unchanged. A fresh .lnk always resolves the current
            // executable at exePath.
            if (File.Exists(shortcutPath))
                File.Delete(shortcutPath);

            Type shellType = Type.GetTypeFromProgID("WScript.Shell");
            if (shellType == null) return;

            object shell = Activator.CreateInstance(shellType);
            object shortcut = shellType.InvokeMember(
                "CreateShortcut", BindingFlags.InvokeMethod, null, shell,
                new object[] { shortcutPath });

            Type shortcutType = shortcut.GetType();
            shortcutType.InvokeMember("TargetPath", BindingFlags.SetProperty, null, shortcut, new object[] { exePath });
            shortcutType.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, shortcut, new object[] { root });
            shortcutType.InvokeMember("IconLocation", BindingFlags.SetProperty, null, shortcut, new object[] { exePath + ",0" });
            shortcutType.InvokeMember("Description", BindingFlags.SetProperty, null, shortcut,
                new object[] { "Age of the Ring - 8 Player War of the Ring" });
            shortcutType.InvokeMember("Save", BindingFlags.InvokeMethod, null, shortcut, null);
            LogUpdate("Desktop shortcut rebuilt for launcher " + LauncherVersion + ": " + shortcutPath);
        }
        catch (Exception ex)
        {
            LogUpdate("Desktop shortcut rebuild failed: " + ex.Message);
        }
    }
}

// Public bridge used by the embedded WPF PowerShell GUI. It deliberately exposes
// only one narrow operation: ask the already-tested native updater to check now.
public static class AotR8PUpdateBridge
{
    public static string CheckNow()
    {
        return Program.ManualUpdateCheck();
    }
}
