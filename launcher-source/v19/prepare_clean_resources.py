from pathlib import Path
import hashlib
import re
import sys

GUI_IN = Path(sys.argv[1])
ENGINE_IN = Path(sys.argv[2])
OUT_DIR = Path(sys.argv[3])
OUT_DIR.mkdir(parents=True, exist_ok=True)

EXPECTED_GUI_IN = "23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C"
EXPECTED_ENGINE_IN = "94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA"
EXPECTED_GUI_OUT = "201B90D474AE39EE7776159A79AC025C80C6E95BB263D1CBF53152B3784895EF"
EXPECTED_ENGINE_OUT = "5DB2F749F10E84322BC471FFF04E25326EFF194FA440175FE9841ED13367F938"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source block, found {count}")
    return text.replace(old, new, 1)


def regex_once(text: str, pattern: str, repl: str, label: str, flags: int = 0) -> str:
    result, count = re.subn(pattern, repl, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {count}")
    return result


if sha(GUI_IN) != EXPECTED_GUI_IN:
    raise SystemExit("Frozen GUI input hash mismatch")
if sha(ENGINE_IN) != EXPECTED_ENGINE_IN:
    raise SystemExit("Frozen engine input hash mismatch")

gui = GUI_IN.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
engine = ENGINE_IN.read_text(encoding="utf-8-sig").replace("\r\n", "\n")

http_helpers = '''Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Net.Http

$script:HttpClient = New-Object System.Net.Http.HttpClient
$script:HttpClient.Timeout = [TimeSpan]::FromSeconds(30)
$script:HttpClient.DefaultRequestHeaders.UserAgent.ParseAdd(
    "AotR-8P-WotR-Launcher/$([string]$global:AOTR8P_LAUNCHER_VERSION)"
)
$script:HttpClient.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json")

function Get-HttpText([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) { throw "HTTP URL is empty." }
    $response = $script:HttpClient.GetAsync($Url).GetAwaiter().GetResult()
    try {
        [void]$response.EnsureSuccessStatusCode()
        return $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    }
    finally { $response.Dispose() }
}

function Save-HttpFile([string]$Url,[string]$Destination) {
    if ([string]::IsNullOrWhiteSpace($Url)) { throw "HTTP URL is empty." }
    $response = $script:HttpClient.GetAsync($Url).GetAwaiter().GetResult()
    try {
        [void]$response.EnsureSuccessStatusCode()
        $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        [IO.File]::WriteAllBytes($Destination,$bytes)
    }
    finally { $response.Dispose() }
}
'''

gui = replace_once(gui, "Add-Type -AssemblyName System.Windows.Forms\n", http_helpers, "HTTP helper insertion")
gui = replace_once(gui, '$Skin = Join-Path $packageRoot "internal\\assets\\launcher_skin.png"\n', "", "legacy skin path removal")

for variable in ("Row1CleanPatchBase64", "Row2CleanPatchBase64", "Row3CleanPatchBase64", "ReadyCleanPatchBase64"):
    gui = regex_once(gui, rf'^\${variable}\s*=\s*"[^"]*"\n', "", f"remove {variable}", re.M)

legacy_image_block = '''$bitmap = New-Object Windows.Media.Imaging.BitmapImage
$bitmap.BeginInit()
$bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
$bitmap.UriSource = New-Object Uri($Skin, [UriKind]::Absolute)
$bitmap.EndInit()
$bitmap.Freeze()
$SkinImage.Source = $bitmap

function Set-EmbeddedPngSource($ImageControl, [string]$Base64) {
    if ($null -eq $ImageControl -or [string]::IsNullOrWhiteSpace($Base64)) { return }
    $bytes = [Convert]::FromBase64String($Base64)
    $ms = New-Object IO.MemoryStream(,$bytes)
    try {
        $bi = New-Object Windows.Media.Imaging.BitmapImage
        $bi.BeginInit()
        $bi.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bi.StreamSource = $ms
        $bi.EndInit()
        $bi.Freeze()
        $ImageControl.Source = $bi
    }
    finally {
        $ms.Dispose()
    }
}

Set-EmbeddedPngSource $Row1CleanPatch $Row1CleanPatchBase64
Set-EmbeddedPngSource $Row2CleanPatch $Row2CleanPatchBase64
Set-EmbeddedPngSource $Row3CleanPatch $Row3CleanPatchBase64
Set-EmbeddedPngSource $ReadyCleanPatch $ReadyCleanPatchBase64
'''
managed_image_block = '''function Set-EmbeddedPngSource($ImageControl, [byte[]]$Bytes) {
    if ($null -eq $ImageControl -or $null -eq $Bytes -or $Bytes.Length -eq 0) { return }
    $ms = New-Object IO.MemoryStream(,$Bytes)
    try {
        $bi = New-Object Windows.Media.Imaging.BitmapImage
        $bi.BeginInit()
        $bi.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bi.StreamSource = $ms
        $bi.EndInit()
        $bi.Freeze()
        $ImageControl.Source = $bi
    }
    finally { $ms.Dispose() }
}

Set-EmbeddedPngSource $SkinImage ([byte[]]$global:AOTR8P_SKIN_BYTES)
Set-EmbeddedPngSource $Row1CleanPatch ([byte[]]$global:AOTR8P_ROW1_PATCH)
Set-EmbeddedPngSource $Row2CleanPatch ([byte[]]$global:AOTR8P_ROW2_PATCH)
Set-EmbeddedPngSource $Row3CleanPatch ([byte[]]$global:AOTR8P_ROW3_PATCH)
Set-EmbeddedPngSource $ReadyCleanPatch ([byte[]]$global:AOTR8P_READY_PATCH)
'''
gui = replace_once(gui, legacy_image_block, managed_image_block, "managed image resources")

gui = replace_once(gui, '''    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object Net.WebClient
        $wc.Headers["User-Agent"] = "AotR-8P-WotR-Launcher/$($global:AOTR8P_LAUNCHER_VERSION)"
        $wc.CachePolicy = New-Object System.Net.Cache.RequestCachePolicy([System.Net.Cache.RequestCacheLevel]::NoCacheNoStore)
        $json = $wc.DownloadString($RepairManifestUrl)
''', '''    try {
        $json = Get-HttpText $RepairManifestUrl
''', "remote repair HTTP")

gui = replace_once(gui, '''function New-GitHubWebClient {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object Net.WebClient
    $wc.Headers["User-Agent"] = "AotR-8P-WotR-Launcher/$($global:AOTR8P_LAUNCHER_VERSION)"
    $wc.Headers["Accept"] = "application/vnd.github+json"
    $wc.CachePolicy = New-Object System.Net.Cache.RequestCachePolicy([System.Net.Cache.RequestCacheLevel]::NoCacheNoStore)
    return $wc
}

''', "", "legacy GitHub WebClient helper")

gui = replace_once(gui, '''        $wc = New-GitHubWebClient
        $query = [Uri]::EscapeDataString('repo:eliaauditore/AotR-8P-WotR label:master-ticket "' + $Fingerprint + '"')
        $result = $wc.DownloadString("https://api.github.com/search/issues?q=$query&per_page=10") | ConvertFrom-Json
''', '''        $query = [Uri]::EscapeDataString('repo:eliaauditore/AotR-8P-WotR label:master-ticket "' + $Fingerprint + '"')
        $result = Get-HttpText ("https://api.github.com/search/issues?q=$query&per_page=10") | ConvertFrom-Json
''', "master ticket lookup HTTP")

gui = replace_once(gui, '''        $wc = New-GitHubWebClient
        $comments = @($wc.DownloadString("$GitHubApiRoot/issues/$MasterIssue/comments?per_page=100") | ConvertFrom-Json)
''', '''        $comments = @(Get-HttpText ("$GitHubApiRoot/issues/$MasterIssue/comments?per_page=100") | ConvertFrom-Json)
''', "maintainer comments HTTP")

gui = replace_once(gui, '''    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $parent = Split-Path $Destination -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $temp = Join-Path $parent (".repair_" + [Guid]::NewGuid().ToString("N") + ".tmp")
    try {
        $wc = New-Object Net.WebClient
        $wc.Headers["User-Agent"] = "AotR-8P-WotR-Launcher/$($global:AOTR8P_LAUNCHER_VERSION)"
        $wc.CachePolicy = New-Object System.Net.Cache.RequestCachePolicy([System.Net.Cache.RequestCacheLevel]::NoCacheNoStore)
        $wc.DownloadFile($Url,$temp)
''', '''    $parent = Split-Path $Destination -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $temp = Join-Path $parent (".repair_" + [Guid]::NewGuid().ToString("N") + ".tmp")
    try {
        Save-HttpFile $Url $temp
''', "verified download HTTP")

gui = replace_once(gui, '''function Repair-ModPayloads {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object Net.WebClient
    $wc.Headers["User-Agent"] = "AotR-8P-WotR-Launcher/$($global:AOTR8P_LAUNCHER_VERSION)"
    $wc.CachePolicy = New-Object System.Net.Cache.RequestCachePolicy([System.Net.Cache.RequestCacheLevel]::NoCacheNoStore)
    $manifest = ($wc.DownloadString($ModManifestUrl) | ConvertFrom-Json)
''', '''function Repair-ModPayloads {
    $manifest = (Get-HttpText $ModManifestUrl | ConvertFrom-Json)
''', "mod manifest HTTP")

gui = replace_once(gui, '        $script:EngineRunspace.SessionStateProxy.SetVariable("AOTR8P_LAUNCHER_VERSION", [string]$global:AOTR8P_LAUNCHER_VERSION)\n', '''        $script:EngineRunspace.SessionStateProxy.SetVariable("AOTR8P_LAUNCHER_VERSION", [string]$global:AOTR8P_LAUNCHER_VERSION)
        $script:EngineRunspace.SessionStateProxy.SetVariable("AOTR8P_FINAL_STABLE_V7_BYTES", [byte[]]$global:AOTR8P_FINAL_STABLE_V7_BYTES)
        $script:EngineRunspace.SessionStateProxy.SetVariable("AOTR8P_V7_SHELLCODE_BYTES", [byte[]]$global:AOTR8P_V7_SHELLCODE_BYTES)
''', "engine resource handoff")

engine = replace_once(engine, "#   - installs byte-identical FINAL_STABLE_V7 via a real temporary PowerShell script\n", "#   - installs byte-identical FINAL_STABLE_V7 from a verified launcher resource\n", "engine source comment")
engine = regex_once(engine, r"(?ms)^\$FinalStableV7Base64\s*=\s*@'\n.*?^'@\n", "", "FINAL_STABLE_V7 Base64 removal")
engine = replace_once(engine, '$FinalStableV7Sha256 = "FEAF40B3B231646CD8F7C7099D1E8544090D5010F1C6DB06E5B2F3EF8C0C5F44"\n', '$FinalStableV7Sha256 = "72D00490538BE2222F5BAAF3D8A1648A86071D3A098946A7B8751E7D337300E2"\n', "clean FINAL_STABLE_V7 resource integrity hash")
engine = replace_once(engine, '''    $bytes = [Convert]::FromBase64String(($FinalStableV7Base64 -replace '\\s',''))
    $embeddedHash = [BitConverter]::ToString(
        [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    ).Replace("-","")

    if ($embeddedHash -ne $FinalStableV7Sha256) {
        throw "Eingebettetes FINAL_STABLE_V7 ist beschaedigt."
    }

''', '''    $bytes = [byte[]]$global:AOTR8P_FINAL_STABLE_V7_BYTES
    if ($null -eq $bytes -or $bytes.Length -eq 0) {
        throw "FINAL_STABLE_V7 resource is missing."
    }
    $embeddedHash = [BitConverter]::ToString(
        [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    ).Replace("-","")
    if ($embeddedHash -ne $FinalStableV7Sha256) {
        throw "FINAL_STABLE_V7 resource hash mismatch."
    }

''', "FINAL_STABLE_V7 resource consumption")

engine = replace_once(engine, '        [void]$v7.AddParameter("DragSpeed", [single]-16.0)\n', '''        [void]$v7.AddParameter("DragSpeed", [single]-16.0)
        [void]$v7.AddParameter("V7Shellcode", [byte[]]$global:AOTR8P_V7_SHELLCODE_BYTES)
''', "V7 child shellcode parameter")

required_gui = ("System.Net.Http.HttpClient", "AOTR8P_SKIN_BYTES", "AOTR8P_ROW1_PATCH", "AOTR8P_FINAL_STABLE_V7_BYTES", "Get-HttpText", "Save-HttpFile")
forbidden_gui = ("Net.WebClient", "DownloadString(", "DownloadFile(", "FromBase64String", "Row1CleanPatchBase64", "ReadyCleanPatchBase64", "internal\\assets\\launcher_skin.png", "$Skin =")
required_engine = ("AOTR8P_FINAL_STABLE_V7_BYTES", "AOTR8P_V7_SHELLCODE_BYTES", "V7Shellcode")
forbidden_engine = ("FinalStableV7Base64", "FromBase64String")

for token in required_gui:
    if token not in gui:
        raise SystemExit("Missing GUI token: " + token)
for token in forbidden_gui:
    if token in gui:
        raise SystemExit("Forbidden GUI token remains: " + token)
for token in required_engine:
    if token not in engine:
        raise SystemExit("Missing engine token: " + token)
for token in forbidden_engine:
    if token in engine:
        raise SystemExit("Forbidden engine token remains: " + token)

# Windows PowerShell 5.1 interprets BOM-less UTF-8 files as ANSI. Some UTF-8 punctuation
# (notably em dashes) then decodes into smart-quote characters that the PS parser treats
# as string delimiters. Emit a BOM so file-based CI parsing sees the same Unicode text that
# the launcher supplies to AddScript(). ReadEmbeddedUtf8() strips the BOM before execution.
(OUT_DIR / "launcher_gui.ps1").write_text(gui, encoding="utf-8-sig", newline="\n")
(OUT_DIR / "launcher_engine.ps1").write_text(engine, encoding="utf-8-sig", newline="\n")

if sha(OUT_DIR / "launcher_gui.ps1") != EXPECTED_GUI_OUT:
    raise SystemExit("Clean GUI output hash mismatch")
if sha(OUT_DIR / "launcher_engine.ps1") != EXPECTED_ENGINE_OUT:
    raise SystemExit("Clean engine output hash mismatch")

print("CLEAN_GUI_SHA256=" + sha(OUT_DIR / "launcher_gui.ps1"))
print("CLEAN_ENGINE_SHA256=" + sha(OUT_DIR / "launcher_engine.ps1"))
