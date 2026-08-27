from pathlib import Path
import hashlib
import sys

GUI_IN = Path(sys.argv[1])
ENGINE_IN = Path(sys.argv[2])
OUT_DIR = Path(sys.argv[3])
OUT_DIR.mkdir(parents=True, exist_ok=True)

EXPECTED_GUI_IN = "23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C"
EXPECTED_ENGINE_IN = "94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA"
EXPECTED_GUI_OUT = "5733ABD62210214EDB64B2A0A3324E43FFF7CCAD109791E4E69CC42220360AB9"
EXPECTED_ENGINE_OUT = "0CD7F235467F67736FE8A4C1279AA1681CD446628A6ED35BC5E639DCE9600A12"

GUI_OPS = [{'i1': 21,
  'i2': 21,
  'new': ['Add-Type -AssemblyName System.Net.Http',
          '',
          '$script:HttpClient = New-Object System.Net.Http.HttpClient',
          '$script:HttpClient.Timeout = [TimeSpan]::FromSeconds(30)',
          '$script:HttpClient.DefaultRequestHeaders.UserAgent.ParseAdd(',
          '    "AotR-8P-WotR-Launcher/$([string]$global:AOTR8P_LAUNCHER_VERSION)"',
          ')',
          '$script:HttpClient.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json")',
          '',
          'function Get-HttpText([string]$Url) {',
          '    if ([string]::IsNullOrWhiteSpace($Url)) { throw "HTTP URL is empty." }',
          '    $response = $script:HttpClient.GetAsync($Url).GetAwaiter().GetResult()',
          '    try {',
          '        $response.EnsureSuccessStatusCode()',
          '        return $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()',
          '    }',
          '    finally {',
          '        $response.Dispose()',
          '    }',
          '}',
          '',
          'function Save-HttpFile([string]$Url,[string]$Destination) {',
          '    if ([string]::IsNullOrWhiteSpace($Url)) { throw "HTTP URL is empty." }',
          '    $response = $script:HttpClient.GetAsync($Url).GetAwaiter().GetResult()',
          '    try {',
          '        $response.EnsureSuccessStatusCode()',
          '        $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()',
          '        [IO.File]::WriteAllBytes($Destination,$bytes)',
          '    }',
          '    finally {',
          '        $response.Dispose()',
          '    }',
          '}',
          '']},
 {'i1': 27, 'i2': 28, 'new': []},
 {'i1': 718, 'i2': 724, 'new': []},
 {'i1': 1316,
  'i2': 1328,
  'new': ['function Set-EmbeddedPngSource($ImageControl, [byte[]]$Bytes) {',
          '    if ($null -eq $ImageControl -or $null -eq $Bytes -or $Bytes.Length -eq 0) { return }',
          '    $ms = New-Object IO.MemoryStream(,$Bytes)']},
 {'i1': 1342,
  'i2': 1346,
  'new': ['Set-EmbeddedPngSource $SkinImage ([byte[]]$global:AOTR8P_SKIN_BYTES)',
          'Set-EmbeddedPngSource $Row1CleanPatch ([byte[]]$global:AOTR8P_ROW1_PATCH)',
          'Set-EmbeddedPngSource $Row2CleanPatch ([byte[]]$global:AOTR8P_ROW2_PATCH)',
          'Set-EmbeddedPngSource $Row3CleanPatch ([byte[]]$global:AOTR8P_ROW3_PATCH)',
          'Set-EmbeddedPngSource $ReadyCleanPatch ([byte[]]$global:AOTR8P_READY_PATCH)']},
 {'i1': 1517, 'i2': 1522, 'new': ['        $json = Get-HttpText $RepairManifestUrl']},
 {'i1': 1798, 'i2': 1807, 'new': []},
 {'i1': 1816, 'i2': 1817, 'new': []},
 {'i1': 1818,
  'i2': 1819,
  'new': ['        $result = Get-HttpText ("https://api.github.com/search/issues?q=$query&per_page=10") | ConvertFrom-Json']},
 {'i1': 1835,
  'i2': 1837,
  'new': ['        $comments = @(Get-HttpText ("$GitHubApiRoot/issues/$MasterIssue/comments?per_page=100") | ConvertFrom-Json)']},
 {'i1': 2130, 'i2': 2134, 'new': ['        Save-HttpFile $Url $temp']},
 {'i1': 2146, 'i2': 2151, 'new': ['    $manifest = ((Get-HttpText $ModManifestUrl) | ConvertFrom-Json)']},
 {'i1': 2651,
  'i2': 2651,
  'new': ['        $script:EngineRunspace.SessionStateProxy.SetVariable("AOTR8P_FINAL_STABLE_V7_BYTES", [byte[]]$global:AOTR8P_FINAL_STABLE_V7_BYTES)']}]
ENGINE_OPS = [{'i1': 6, 'i2': 7, 'new': ['#   - installs byte-identical FINAL_STABLE_V7 from a verified launcher resource']},
 {'i1': 422, 'i2': 796, 'new': []},
 {'i1': 872,
  'i2': 873,
  'new': ['    $bytes = [byte[]]$global:AOTR8P_FINAL_STABLE_V7_BYTES',
          '    if ($null -eq $bytes -or $bytes.Length -eq 0) {',
          '        throw "FINAL_STABLE_V7 resource is missing."',
          '    }',
          '']}]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def apply(path, ops, out):
    text = path.read_text(encoding="utf-8-sig")
    lines = text.splitlines()
    for op in sorted(ops, key=lambda x: x["i1"], reverse=True):
        lines[op["i1"]:op["i2"]] = op["new"]
    result = "\n".join(lines) + "\n"
    out.write_text(result, encoding="utf-8", newline="\n")
    return result

if sha(GUI_IN) != EXPECTED_GUI_IN:
    raise SystemExit("Frozen GUI input hash mismatch")
if sha(ENGINE_IN) != EXPECTED_ENGINE_IN:
    raise SystemExit("Frozen engine input hash mismatch")

gui = apply(GUI_IN, GUI_OPS, OUT_DIR / "launcher_gui.ps1")
engine = apply(ENGINE_IN, ENGINE_OPS, OUT_DIR / "launcher_engine.ps1")

if sha(OUT_DIR / "launcher_gui.ps1") != EXPECTED_GUI_OUT:
    raise SystemExit("Clean GUI output hash mismatch")
if sha(OUT_DIR / "launcher_engine.ps1") != EXPECTED_ENGINE_OUT:
    raise SystemExit("Clean engine output hash mismatch")

required_gui = [
    "System.Net.Http.HttpClient",
    "AOTR8P_SKIN_BYTES",
    "AOTR8P_ROW1_PATCH",
    "AOTR8P_FINAL_STABLE_V7_BYTES",
    "Get-HttpText",
    "Save-HttpFile",
]
forbidden_gui = [
    "Net.WebClient",
    "DownloadString(",
    "DownloadFile(",
    "FromBase64String",
    "Row1CleanPatchBase64",
    "ReadyCleanPatchBase64",
    "internal\\assets\\launcher_skin.png",
    "$Skin =",
]
required_engine = ["AOTR8P_FINAL_STABLE_V7_BYTES"]
forbidden_engine = ["FinalStableV7Base64", "FromBase64String"]

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

print("CLEAN_GUI_SHA256=" + sha(OUT_DIR / "launcher_gui.ps1"))
print("CLEAN_ENGINE_SHA256=" + sha(OUT_DIR / "launcher_engine.ps1"))
