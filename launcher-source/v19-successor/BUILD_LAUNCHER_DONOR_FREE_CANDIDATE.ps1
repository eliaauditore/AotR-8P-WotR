#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = "",
    [string]$LauncherVersion = "1.1.3-donorfree-dev1"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-","").ToUpperInvariant() }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace("-","").ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Assert-Hash([string]$Path,[string]$Expected,[string]$Role) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Role missing: $Path" }
    $actual = Get-Sha256 $Path
    if ($actual -ne $Expected) { throw "$Role SHA256 mismatch. Expected $Expected, got $actual" }
    Write-Host "$Role OK: $actual" -ForegroundColor Green
}

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$Resources = Join-Path $PSScriptRoot "resources"
$SourceTemplate = Join-Path $PSScriptRoot "..\v19\launcher.cs"
$Verifier = Join-Path $PSScriptRoot "..\v19\VERIFY_V7_RESOURCE_CHAIN.ps1"

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $RepoRoot "_V19_DONOR_FREE_SUCCESSOR_BUILD"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$Work = Join-Path $OutputRoot "work"
$Package = Join-Path $OutputRoot "package"

if (Test-Path -LiteralPath $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Work,$Package | Out-Null

# These are maintained repository resources. No previous launcher EXE, donor package,
# FrozenDonorRoot, reflection extraction or hidden local research path is accepted here.
$ExpectedResourceHashes = [ordered]@{
    "launcher_gui.ps1"     = "135B1FDD64B84B0DE84BC7526F04157A790228DFC49FF5DD6253C89023D71EBD"
    "launcher_engine.ps1"  = "5DB2F749F10E84322BC471FFF04E25326EFF194FA440175FE9841ED13367F938"
    "launcher_skin.png"    = "BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6"
    "launcher.ico"         = "3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A"
    "final_stable_v7.ps1" = "72D00490538BE2222F5BAAF3D8A1648A86071D3A098946A7B8751E7D337300E2"
    "v7_shellcode.bin"     = "60EECE4660C3BA0AD183EB82B82DCDACF3ECA6DC892C8FAFCD629A92170ED45A"
    "row1cleanpatch.png"   = "D4DC9A47F0E2FD9715D92F8DD4C3831B9AB95F8CA34E98937F019B7574294177"
    "row2cleanpatch.png"   = "58B9A7173CE1C9C30C85EE76D15D54E3D40B3E7E14E25D0C1FE5D8EFD89E6D8E"
    "row3cleanpatch.png"   = "7F86C02BC02D2E57D66202AF9C526D6FAE13CFC9B7CB1EFF1BB61C165B25278C"
    "readycleanpatch.png"  = "35DCBCBE6E625C5C06EC36BAB3CA51A6F4EE29DA3DFF4CAEEDD69BC87D873DF3"
}

if (-not (Test-Path -LiteralPath $Resources -PathType Container)) {
    throw "Maintained successor resources are missing: $Resources"
}
foreach ($name in $ExpectedResourceHashes.Keys) {
    Assert-Hash (Join-Path $Resources $name) $ExpectedResourceHashes[$name] "Repo resource $name"
}

foreach ($path in @(
    (Join-Path $Resources "launcher_gui.ps1"),
    (Join-Path $Resources "launcher_engine.ps1"),
    (Join-Path $Resources "final_stable_v7.ps1")
)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) { throw "PowerShell 5.1 parse failed: $path :: $($errors[0].Message)" }
    Write-Host "PS5 PARSE OK: $path" -ForegroundColor Green
}

if (-not (Test-Path -LiteralPath $Verifier -PathType Leaf)) { throw "V7 verifier missing: $Verifier" }
& $Verifier -ResourcesRoot $Resources

if (-not (Test-Path -LiteralPath $SourceTemplate -PathType Leaf)) { throw "Launcher C# template missing: $SourceTemplate" }
$source = Get-Content -LiteralPath $SourceTemplate -Raw -Encoding UTF8
if ($source.Contains("FrozenDonorRoot")) { throw "Donor token unexpectedly present in launcher C# source" }

# V19 1.1.2 inserted the explicit shellcode resource at build time. Preserve the exact
# behavior while keeping the source input repo-controlled and the transformation deterministic.
$needle1 = '    private const string FinalStableV7ResourceName = "AotR8P.FinalStableV7";'
$replace1 = $needle1 + [Environment]::NewLine + '    private const string V7ShellcodeResourceName = "AotR8P.V7Shellcode";'
$first1 = $source.IndexOf($needle1,[StringComparison]::Ordinal)
$last1 = $source.LastIndexOf($needle1,[StringComparison]::Ordinal)
if ($first1 -lt 0 -or $first1 -ne $last1) { throw "V7 shellcode resource-name insertion anchor is not unique" }
$source = $source.Replace($needle1,$replace1)

$needle2 = '                    runspace.SessionStateProxy.SetVariable("AOTR8P_FINAL_STABLE_V7_BYTES", ReadEmbeddedBytes(FinalStableV7ResourceName));'
$replace2 = $needle2 + [Environment]::NewLine + '                    runspace.SessionStateProxy.SetVariable("AOTR8P_V7_SHELLCODE_BYTES", ReadEmbeddedBytes(V7ShellcodeResourceName));'
$first2 = $source.IndexOf($needle2,[StringComparison]::Ordinal)
$last2 = $source.LastIndexOf($needle2,[StringComparison]::Ordinal)
if ($first2 -lt 0 -or $first2 -ne $last2) { throw "V7 shellcode runspace insertion anchor is not unique" }
$source = $source.Replace($needle2,$replace2)

$versionCore = ($LauncherVersion -split '-',2)[0]
$parsed = $null
if (-not [Version]::TryParse($versionCore,[ref]$parsed)) { throw "Invalid launcher version: $LauncherVersion" }
$fileVersion = ('{0}.{1}.{2}.{3}' -f $parsed.Major,[Math]::Max(0,$parsed.Minor),[Math]::Max(0,$parsed.Build),[Math]::Max(0,$parsed.Revision))
$source = $source.Replace("__LAUNCHER_VERSION__",$LauncherVersion).Replace("__FILE_VERSION__",$fileVersion).Replace("__UPDATE_URL__","https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/manifest.json")
if ($source -match '__[A-Z0-9_]+__') { throw "Unresolved C# source placeholder" }
if ($source.Contains("FrozenDonorRoot")) { throw "Donor token remains after C# preparation" }
$CsPath = Join-Path $Work "launcher.cs"
[IO.File]::WriteAllText($CsPath,$source,(New-Object Text.UTF8Encoding($false)))

$NativeManifest = Join-Path $Work "launcher.manifest"
$manifestText = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0"><assemblyIdentity version="1.0.0.0" name="eliaauditore.AotR8PWotRMod.SingleExe"/><trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges><requestedExecutionLevel level="requireAdministrator" uiAccess="false"/></requestedPrivileges></security></trustInfo><application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings><dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware></windowsSettings></application></assembly>'
[IO.File]::WriteAllText($NativeManifest,$manifestText,(New-Object Text.UTF8Encoding($false)))

$windowsPS = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
$automation = (& $windowsPS -NoLogo -NoProfile -NonInteractive -Command "[System.Management.Automation.PSObject].Assembly.Location" | Select-Object -First 1).Trim()
if (-not (Test-Path -LiteralPath $automation -PathType Leaf)) { throw "Windows PowerShell automation DLL missing" }
$csc = @(
    (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $csc) { throw "csc.exe missing" }

$Exe = Join-Path $Package "AotR 8P WotR Mod.exe"
$compileArgs = @(
    "/nologo","/target:winexe","/optimize+","/platform:anycpu",
    "/reference:System.Windows.Forms.dll","/reference:System.Web.Extensions.dll",("/reference:"+$automation),
    ("/win32icon:"+(Join-Path $Resources "launcher.ico")),("/win32manifest:"+$NativeManifest),
    ("/resource:"+(Join-Path $Resources "launcher_skin.png")+",AotR8P.LauncherSkin"),
    ("/resource:"+(Join-Path $Resources "launcher_gui.ps1")+",AotR8P.GuiScript"),
    ("/resource:"+(Join-Path $Resources "launcher_engine.ps1")+",AotR8P.EngineScript"),
    ("/resource:"+(Join-Path $Resources "final_stable_v7.ps1")+",AotR8P.FinalStableV7"),
    ("/resource:"+(Join-Path $Resources "v7_shellcode.bin")+",AotR8P.V7Shellcode"),
    ("/resource:"+(Join-Path $Resources "row1cleanpatch.png")+",AotR8P.Row1Patch"),
    ("/resource:"+(Join-Path $Resources "row2cleanpatch.png")+",AotR8P.Row2Patch"),
    ("/resource:"+(Join-Path $Resources "row3cleanpatch.png")+",AotR8P.Row3Patch"),
    ("/resource:"+(Join-Path $Resources "readycleanpatch.png")+",AotR8P.ReadyPatch"),
    ("/out:"+$Exe),$CsPath
)
& $csc @compileArgs
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw "Launcher C# compilation failed" }

$fvi = [Diagnostics.FileVersionInfo]::GetVersionInfo($Exe)
if ($fvi.ProductVersion -ne $LauncherVersion) { throw "Compiled ProductVersion mismatch: $($fvi.ProductVersion)" }
$LauncherHash = Get-Sha256 $Exe
$LauncherSize = (Get-Item -LiteralPath $Exe).Length
Write-Host "CANDIDATE_SHA256=$LauncherHash" -ForegroundColor Cyan
Write-Host "CANDIDATE_SIZE=$LauncherSize" -ForegroundColor Cyan

$candidateAsm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($Exe))
$embeddedMap = [ordered]@{
    "AotR8P.LauncherSkin"  = "launcher_skin.png"
    "AotR8P.GuiScript"     = "launcher_gui.ps1"
    "AotR8P.EngineScript"  = "launcher_engine.ps1"
    "AotR8P.FinalStableV7" = "final_stable_v7.ps1"
    "AotR8P.V7Shellcode"   = "v7_shellcode.bin"
    "AotR8P.Row1Patch"     = "row1cleanpatch.png"
    "AotR8P.Row2Patch"     = "row2cleanpatch.png"
    "AotR8P.Row3Patch"     = "row3cleanpatch.png"
    "AotR8P.ReadyPatch"    = "readycleanpatch.png"
}
$names = @($candidateAsm.GetManifestResourceNames() | Sort-Object)
$expectedNames = @($embeddedMap.Keys | Sort-Object)
if (($names -join "|") -ne ($expectedNames -join "|")) { throw "Embedded resource inventory mismatch: $($names -join ', ')" }
foreach ($resourceName in $embeddedMap.Keys) {
    $stream = $candidateAsm.GetManifestResourceStream($resourceName)
    if ($null -eq $stream) { throw "Compiled resource missing: $resourceName" }
    try {
        $memory = New-Object IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            $actualEmbedded = Get-BytesSha256 $memory.ToArray()
        }
        finally { $memory.Dispose() }
    }
    finally { $stream.Dispose() }
    $expectedEmbedded = $ExpectedResourceHashes[$embeddedMap[$resourceName]]
    if ($actualEmbedded -ne $expectedEmbedded) {
        throw "Compiled resource hash mismatch: $resourceName expected $expectedEmbedded got $actualEmbedded"
    }
    Write-Host "EMBEDDED RESOURCE OK: $resourceName $actualEmbedded" -ForegroundColor Green
}

$ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Exe))
foreach ($forbidden in @("Issue33SkinGzipBase64","GuiGzipBase64","EngineGzipBase64","FrozenDonorRoot","GZipStream","Net.WebClient","DownloadString(")) {
    if ($ascii.Contains($forbidden)) { throw "Forbidden donor/legacy token remains in compiled candidate: $forbidden" }
}
Write-Host "STATIC DONOR-FREE CLEANUP PASS" -ForegroundColor Green

& $Verifier -ResourcesRoot $Resources -ExePath $Exe

# Public AotR/BFME payloads remain OUTSIDE the signed-launcher resource boundary.
# They are copied from the current repository only to make a complete non-release five-file test package.
$RepoUi = Join-Path $RepoRoot "payload_ui.big"
$RepoPaper = Join-Path $RepoRoot "payload_paper.inc"
Assert-Hash $RepoUi "827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376" "Repository UI payload"
Assert-Hash $RepoPaper "3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43" "Repository Paper payload"
Copy-Item -LiteralPath $RepoUi -Destination (Join-Path $Package "payload_ui.big") -Force
Copy-Item -LiteralPath $RepoPaper -Destination (Join-Path $Package "payload_paper.inc") -Force

$manifestObject = [ordered]@{
    schema = 1
    launcher_version = $LauncherVersion
    launcher_url = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/AotR%208P%20WotR%20Mod.exe"
    launcher_sha256 = $LauncherHash
    mandatory = $false
    repair_manifest_url = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/repair-manifest.json"
    ui_url = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/payload_ui.big"
    ui_sha256 = "827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376"
    paper_url = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/payload_paper.inc"
    paper_sha256 = "3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43"
}
[IO.File]::WriteAllText((Join-Path $Package "manifest.json"),(($manifestObject | ConvertTo-Json -Depth 6)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))

$repair = Get-Content -LiteralPath (Join-Path $RepoRoot "repair-manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$repair.generated_for_launcher = $LauncherVersion
[IO.File]::WriteAllText((Join-Path $Package "repair-manifest.json"),(($repair | ConvertTo-Json -Depth 8)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))

$PublicFiles = @("AotR 8P WotR Mod.exe","manifest.json","repair-manifest.json","payload_ui.big","payload_paper.inc")
$actualNames = @(Get-ChildItem -LiteralPath $Package -File | Select-Object -ExpandProperty Name | Sort-Object)
if (($actualNames -join "|") -ne (($PublicFiles | Sort-Object) -join "|")) { throw "Package root is not exact five-file contract: $($actualNames -join ', ')" }

$records = foreach ($name in $PublicFiles) {
    $path = Join-Path $Package $name
    [ordered]@{ file=$name; sha256=(Get-Sha256 $path); size=[int64](Get-Item -LiteralPath $path).Length }
}
[IO.File]::WriteAllText((Join-Path $OutputRoot "SHA256SUMS.json"),(($records | ConvertTo-Json -Depth 4)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))

$report = [ordered]@{
    schema = 1
    state = "NON_RELEASE_DONOR_FREE_CANDIDATE"
    launcher_version = $LauncherVersion
    candidate_exe_sha256 = $LauncherHash
    candidate_exe_size = [int64]$LauncherSize
    frozen_production_version = "1.1.2"
    frozen_production_exe_sha256 = "5B4D12B7BF43D72860E27C51A3D8AC7AC00CA53DB58499E41AC735F7B7ECED0E"
    frozen_release_immutable = $true
    frozen_donor_root_used = $false
    resource_root = "launcher-source/v19-successor/resources"
    source_template = "launcher-source/v19/launcher.cs"
    resource_hashes = $ExpectedResourceHashes
    payload_scope = "outside signed-launcher boundary; copied from repository only for five-file runtime test package"
    byte_identity_note = "Candidate EXE is not expected to match frozen 1.1.2 because version identity changed and the legacy csc pipeline is byte-nondeterministic. Behavioral regression is the acceptance criterion."
    signpath_note = "Donor-free build provenance alone does not grant ownership or OSS licensing. See RESOURCE_OWNERSHIP.json."
}
[IO.File]::WriteAllText((Join-Path $OutputRoot "DONOR_FREE_BUILD_REPORT.json"),(($report | ConvertTo-Json -Depth 8)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))

$Zip = Join-Path $OutputRoot ("AotR_8P_War_of_the_Ring_" + $LauncherVersion + "_NON_RELEASE.zip")
Compress-Archive -LiteralPath ($PublicFiles | ForEach-Object { Join-Path $Package $_ }) -DestinationPath $Zip -CompressionLevel Optimal
$ZipHash = Get-Sha256 $Zip
[IO.File]::WriteAllText(($Zip+".sha256.txt"),"$ZipHash  $([IO.Path]::GetFileName($Zip))`r`n",[Text.Encoding]::ASCII)
Write-Host "ZIP_SHA256=$ZipHash" -ForegroundColor Cyan
Write-Host "V19 DONOR-FREE NON-RELEASE CANDIDATE BUILD PASS" -ForegroundColor Green
