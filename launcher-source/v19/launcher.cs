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
                LogUpdate("Update check failed: " + FormatException(updateEx));
            }

            TryCreateDesktopShortcut(exePath, root);

            EnsureLauncherSkin();
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

    private static HttpWebRequest CreateHttpRequest(string url)
    {
        HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
        request.Method = "GET";
        request.UserAgent = "AotR8PWotRLauncher/" + LauncherVersion;
        request.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;
        request.Timeout = 15000;
        request.ReadWriteTimeout = 30000;
        return request;
    }

    private static string DownloadUtf8String(string url)
    {
        HttpWebRequest request = CreateHttpRequest(url);
        using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
        using (Stream stream = response.GetResponseStream())
        using (StreamReader reader = new StreamReader(stream, Encoding.UTF8, true))
            return reader.ReadToEnd();
    }

    private static void DownloadToFile(string url, string destination)
    {
        HttpWebRequest request = CreateHttpRequest(url);
        using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
        using (Stream input = response.GetResponseStream())
        using (FileStream output = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.None))
            input.CopyTo(output);
    }

    private static bool TrySelfUpdate(string exePath, string root)
    {
        if (String.IsNullOrWhiteSpace(UpdateManifestUrl)) return false;

        string json = DownloadUtf8String(UpdateManifestUrl);
        JavaScriptSerializer serializer = new JavaScriptSerializer();
        UpdateManifest manifest = serializer.Deserialize<UpdateManifest>(json);
        if (manifest == null || String.IsNullOrWhiteSpace(manifest.launcher_version)) return false;

        Version current;
        Version remote;
        if (!TryParseComparableVersion(LauncherVersion, out current) ||
            !TryParseComparableVersion(manifest.launcher_version, out remote))
            return false;
        if (remote <= current) return false;
        if (String.IsNullOrWhiteSpace(manifest.launcher_url) || String.IsNullOrWhiteSpace(manifest.launcher_sha256))
            return false;

        string newPath = exePath + ".new";
        string helperPath = exePath + ".update.exe";
        TryDelete(newPath);
        TryDelete(helperPath);

        DownloadToFile(manifest.launcher_url, newPath);
        string actualHash = Sha256(newPath);
        if (!String.Equals(actualHash, manifest.launcher_sha256, StringComparison.OrdinalIgnoreCase))
        {
            TryDelete(newPath);
            throw new InvalidDataException("Launcher update SHA256 mismatch.");
        }

        File.Copy(exePath, helperPath, true);
        ProcessStartInfo psi = new ProcessStartInfo
        {
            FileName = helperPath,
            WorkingDirectory = root,
            UseShellExecute = false,
            CreateNoWindow = true,
            Arguments = "--apply-update " + Quote(exePath) + " " + Quote(newPath) + " " + Process.GetCurrentProcess().Id.ToString()
        };
        Process.Start(psi);
        return true;
    }

    private static void RunUpdateHelper(string[] args)
    {
        if (args == null || args.Length < 4) return;
        string target = args[1];
        string source = args[2];
        int parentPid;
        Int32.TryParse(args[3], out parentPid);

        if (parentPid > 0)
        {
            try
            {
                Process parent = Process.GetProcessById(parentPid);
                parent.WaitForExit(30000);
            }
            catch { }
        }

        Exception last = null;
        for (int i = 0; i < 20; i++)
        {
            try
            {
                File.Copy(source, target, true);
                TryDelete(source);
                Process.Start(new ProcessStartInfo
                {
                    FileName = target,
                    WorkingDirectory = Path.GetDirectoryName(target),
                    UseShellExecute = true
                });
                return;
            }
            catch (Exception ex)
            {
                last = ex;
                Thread.Sleep(500);
            }
        }

        if (last != null)
            MessageBox.Show("Launcher update failed.\r\n\r\n" + last.Message, "AotR 8P War of the Ring", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }

    private static bool TryParseComparableVersion(string value, out Version version)
    {
        version = null;
        if (String.IsNullOrWhiteSpace(value)) return false;
        string core = value.Split(new[] { '-' }, 2)[0];
        return Version.TryParse(core, out version);
    }

    private static string Sha256(string path)
    {
        using (FileStream stream = File.OpenRead(path))
        using (SHA256 sha = SHA256.Create())
            return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
    }

    private static string Quote(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static void CleanupStaleUpdateFiles()
    {
        try
        {
            string exePath = Process.GetCurrentProcess().MainModule.FileName;
            TryDelete(exePath + ".new");
        }
        catch { }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch { }
    }

    private static string UpdateLogPath()
    {
        string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AotR8P_WotR");
        Directory.CreateDirectory(dir);
        return Path.Combine(dir, "launcher-update.log");
    }

    private static void LogUpdate(string message)
    {
        try
        {
            File.AppendAllText(UpdateLogPath(), DateTime.Now.ToString("s") + " " + message + Environment.NewLine);
        }
        catch { }
    }

    private static void TryCreateDesktopShortcut(string exePath, string root)
    {
        try
        {
            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            if (String.IsNullOrWhiteSpace(desktop) || !Directory.Exists(desktop)) return;

            string shortcut = Path.Combine(desktop, "AotR 8P War of the Ring.lnk");
            string ps = "$ws=New-Object -ComObject WScript.Shell;" +
                        "$s=$ws.CreateShortcut('" + PsQuote(shortcut) + "');" +
                        "$s.TargetPath='" + PsQuote(exePath) + "';" +
                        "$s.WorkingDirectory='" + PsQuote(root) + "';" +
                        "$s.IconLocation='" + PsQuote(exePath) + ",0';" +
                        "$s.Description='AotR 8P War of the Ring';" +
                        "$s.Save()";

            using (PowerShell shell = PowerShell.Create())
            {
                shell.AddScript(ps);
                shell.Invoke();
            }
        }
        catch (Exception ex)
        {
            LogUpdate("Shortcut creation failed: " + ex.Message);
        }
    }

    private static string PsQuote(string value)
    {
        return (value ?? String.Empty).Replace("'", "''");
    }
}
