#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = "",
    [string]$LauncherVersion = "1.1.3-signingclean-visualproof3"
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

function Replace-ExactOnce([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $first = $Text.IndexOf($Old,[StringComparison]::Ordinal)
    $last = $Text.LastIndexOf($Old,[StringComparison]::Ordinal)
    if ($first -lt 0 -or $first -ne $last) {
        throw "Expected exactly one patch target for $Label. First=$first Last=$last"
    }
    return $Text.Substring(0,$first) + $New + $Text.Substring($first + $Old.Length)
}

function Write-SolidPng([string]$Path,[int]$Width,[int]$Height,[System.Drawing.Color]$Color) {
    $bitmap = New-Object System.Drawing.Bitmap($Width,$Height,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try { $graphics.Clear($Color) }
        finally { $graphics.Dispose() }
        $bitmap.Save($Path,[System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $bitmap.Dispose() }
}

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$Resources = Join-Path $PSScriptRoot "resources"
$SourceTemplate = Join-Path $PSScriptRoot "..\v19\launcher.cs"
$V7Verifier = Join-Path $PSScriptRoot "..\v19\VERIFY_V7_RESOURCE_CHAIN.ps1"

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $env:TEMP "AOTR8P_SIGNING_CLEAN_VISUAL_PROOF_V3"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$Work = Join-Path $OutputRoot "work"
$GeneratedVisuals = Join-Path $Work "generated-visuals"
if (Test-Path -LiteralPath $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Work,$GeneratedVisuals | Out-Null

$ExpectedSourceHashes = [ordered]@{
    "launcher_gui.ps1"     = "135B1FDD64B84B0DE84BC7526F04157A790228DFC49FF5DD6253C89023D71EBD"
    "launcher_engine.ps1"  = "5DB2F749F10E84322BC471FFF04E25326EFF194FA440175FE9841ED13367F938"
    "final_stable_v7.ps1"  = "72D00490538BE2222F5BAAF3D8A1648A86071D3A098946A7B8751E7D337300E2"
    "v7_shellcode.bin"     = "60EECE4660C3BA0AD183EB82B82DCDACF3ECA6DC892C8FAFCD629A92170ED45A"
}
foreach ($name in $ExpectedSourceHashes.Keys) {
    Assert-Hash (Join-Path $Resources $name) $ExpectedSourceHashes[$name] "Signing-clean source $name"
}

# Historical visual resources are retained only as provenance on this research branch.
# This proof does not read their bytes as build inputs; their known hashes are used only
# as forbidden identities against the generated neutral assets and embedded output.
$HistoricalVisualHashes = [ordered]@{
    "launcher_skin.png"   = "BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6"
    "launcher.ico"        = "3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A"
    "row1cleanpatch.png"  = "D4DC9A47F0E2FD9715D92F8DD4C3831B9AB95F8CA34E98937F019B7574294177"
    "row2cleanpatch.png"  = "58B9A7173CE1C9C30C85EE76D15D54E3D40B3E7E14E25D0C1FE5D8EFD89E6D8E"
    "row3cleanpatch.png"  = "7F86C02BC02D2E57D66202AF9C526D6FAE13CFC9B7CB1EFF1BB61C165B25278C"
    "readycleanpatch.png" = "35DCBCBE6E625C5C06EC36BAB3CA51A6F4EE29DA3DFF4CAEEDD69BC87D873DF3"
}
$ForbiddenHistoricalHashes = @($HistoricalVisualHashes.Values | ForEach-Object { ([string]$_).ToUpperInvariant() })

if (-not (Test-Path -LiteralPath $V7Verifier -PathType Leaf)) { throw "V7 verifier missing: $V7Verifier" }
& $V7Verifier -ResourcesRoot $Resources

# Preserve the maintained GUI/Engine scripts byte-for-byte. Only visual resource bytes change.
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

Add-Type -AssemblyName System.Drawing
$GeneratedSkin = Join-Path $GeneratedVisuals "launcher_skin.generated.png"
$GeneratedRow1 = Join-Path $GeneratedVisuals "row1.generated.png"
$GeneratedRow2 = Join-Path $GeneratedVisuals "row2.generated.png"
$GeneratedRow3 = Join-Path $GeneratedVisuals "row3.generated.png"
$GeneratedReady = Join-Path $GeneratedVisuals "ready.generated.png"

# Project-owned neutral visual resources: solid dark launcher canvas plus transparent overlays.
Write-SolidPng $GeneratedSkin 900 675 ([System.Drawing.Color]::FromArgb(255,24,29,33))
Write-SolidPng $GeneratedRow1 1 1 ([System.Drawing.Color]::Transparent)
Write-SolidPng $GeneratedRow2 1 1 ([System.Drawing.Color]::Transparent)
Write-SolidPng $GeneratedRow3 1 1 ([System.Drawing.Color]::Transparent)
Write-SolidPng $GeneratedReady 1 1 ([System.Drawing.Color]::Transparent)

$GeneratedVisualMap = [ordered]@{
    "AotR8P.LauncherSkin" = $GeneratedSkin
    "AotR8P.Row1Patch" = $GeneratedRow1
    "AotR8P.Row2Patch" = $GeneratedRow2
    "AotR8P.Row3Patch" = $GeneratedRow3
    "AotR8P.ReadyPatch" = $GeneratedReady
}
$GeneratedVisualHashes = [ordered]@{}
foreach ($resourceName in $GeneratedVisualMap.Keys) {
    $path = [string]$GeneratedVisualMap[$resourceName]
    $hash = Get-Sha256 $path
    if ($ForbiddenHistoricalHashes -contains $hash) {
        throw "Generated neutral resource unexpectedly equals a historical blocked visual hash: $resourceName $hash"
    }
    $GeneratedVisualHashes[$resourceName] = $hash
    Write-Host "GENERATED PROJECT VISUAL: $resourceName $hash" -ForegroundColor Green
}

# Prepare the donor-free C# source exactly as before except no custom PE icon is supplied.
if (-not (Test-Path -LiteralPath $SourceTemplate -PathType Leaf)) { throw "C# source template missing: $SourceTemplate" }
$source = [IO.File]::ReadAllText($SourceTemplate).Replace("`r`n","`n")
if ($source.Contains("FrozenDonorRoot")) { throw "Donor token unexpectedly present in C# source" }

$finalNameLine = '    private const string FinalStableV7ResourceName = "AotR8P.FinalStableV7";'
$source = Replace-ExactOnce $source $finalNameLine ($finalNameLine + "`n" + '    private const string V7ShellcodeResourceName = "AotR8P.V7Shellcode";') "insert V7 shellcode resource name"
$finalVariableLine = '                    runspace.SessionStateProxy.SetVariable("AOTR8P_FINAL_STABLE_V7_BYTES", ReadEmbeddedBytes(FinalStableV7ResourceName));'
$source = Replace-ExactOnce $source $finalVariableLine ($finalVariableLine + "`n" + '                    runspace.SessionStateProxy.SetVariable("AOTR8P_V7_SHELLCODE_BYTES", ReadEmbeddedBytes(V7ShellcodeResourceName));') "insert V7 shellcode runspace variable"

$versionCore = ($LauncherVersion -split '-',2)[0]
$parsed = $null
if (-not [Version]::TryParse($versionCore,[ref]$parsed)) { throw "Invalid launcher version: $LauncherVersion" }
$fileVersion = ('{0}.{1}.{2}.{3}' -f $parsed.Major,[Math]::Max(0,$parsed.Minor),[Math]::Max(0,$parsed.Build),[Math]::Max(0,$parsed.Revision))
$source = $source.Replace("__LAUNCHER_VERSION__",$LauncherVersion).Replace("__FILE_VERSION__",$fileVersion).Replace("__UPDATE_URL__","")
if ($source -match '__[A-Z0-9_]+__') { throw "Unresolved C# placeholder remains" }
if ($source.Contains("FrozenDonorRoot")) { throw "Donor token remains after C# preparation" }
$CsPath = Join-Path $Work "launcher_signing_clean_visualproof3.cs"
[IO.File]::WriteAllText($CsPath,$source,(New-Object Text.UTF8Encoding($false)))

$NativeManifest = Join-Path $Work "launcher.manifest"
$manifestText = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0"><assemblyIdentity version="1.0.0.0" name="eliaauditore.AotR8PWotRMod.SigningCleanVisualProof3"/><trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges><requestedExecutionLevel level="requireAdministrator" uiAccess="false"/></requestedPrivileges></security></trustInfo><application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings><dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware></windowsSettings></application></assembly>'
[IO.File]::WriteAllText($NativeManifest,$manifestText,(New-Object Text.UTF8Encoding($false)))

$windowsPS = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
$automation = (& $windowsPS -NoLogo -NoProfile -NonInteractive -Command "[System.Management.Automation.PSObject].Assembly.Location" | Select-Object -First 1).Trim()
if (-not (Test-Path -LiteralPath $automation -PathType Leaf)) { throw "Windows PowerShell automation DLL missing" }
$csc = @(
    (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $csc) { throw "csc.exe missing" }

$Exe = Join-Path $OutputRoot "AotR 8P WotR Mod SIGNING CLEAN VISUAL PROOF.exe"
$compileArgs = @(
    "/nologo","/target:winexe","/optimize+","/platform:anycpu",
    "/reference:System.Windows.Forms.dll","/reference:System.Web.Extensions.dll",("/reference:"+$automation),
    ("/win32manifest:"+$NativeManifest),
    ("/resource:"+$GeneratedSkin+",AotR8P.LauncherSkin"),
    ("/resource:"+(Join-Path $Resources "launcher_gui.ps1")+",AotR8P.GuiScript"),
    ("/resource:"+(Join-Path $Resources "launcher_engine.ps1")+",AotR8P.EngineScript"),
    ("/resource:"+(Join-Path $Resources "final_stable_v7.ps1")+",AotR8P.FinalStableV7"),
    ("/resource:"+(Join-Path $Resources "v7_shellcode.bin")+",AotR8P.V7Shellcode"),
    ("/resource:"+$GeneratedRow1+",AotR8P.Row1Patch"),
    ("/resource:"+$GeneratedRow2+",AotR8P.Row2Patch"),
    ("/resource:"+$GeneratedRow3+",AotR8P.Row3Patch"),
    ("/resource:"+$GeneratedReady+",AotR8P.ReadyPatch"),
    ("/out:"+$Exe),$CsPath
)

# There is deliberately no /win32icon argument. The default compiler icon is used.
if (($compileArgs -join "|") -match '(?i)/win32icon:') { throw "Custom PE icon unexpectedly present in compile arguments" }
& $csc @compileArgs
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw "Signing-clean visual proof compilation failed" }

$fvi = [Diagnostics.FileVersionInfo]::GetVersionInfo($Exe)
if ($fvi.ProductVersion -ne $LauncherVersion) { throw "Compiled ProductVersion mismatch: $($fvi.ProductVersion)" }

$candidateAsm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($Exe))
$names = @($candidateAsm.GetManifestResourceNames() | Sort-Object)
$expectedNames = @(
    "AotR8P.EngineScript",
    "AotR8P.FinalStableV7",
    "AotR8P.GuiScript",
    "AotR8P.LauncherSkin",
    "AotR8P.ReadyPatch",
    "AotR8P.Row1Patch",
    "AotR8P.Row2Patch",
    "AotR8P.Row3Patch",
    "AotR8P.V7Shellcode"
) | Sort-Object
if (($names -join "|") -ne ($expectedNames -join "|")) {
    throw "Signing-clean resource inventory mismatch: $($names -join ', ')"
}

$expectedEmbedded = [ordered]@{
    "AotR8P.LauncherSkin" = $GeneratedVisualHashes["AotR8P.LauncherSkin"]
    "AotR8P.GuiScript" = $ExpectedSourceHashes["launcher_gui.ps1"]
    "AotR8P.EngineScript" = $ExpectedSourceHashes["launcher_engine.ps1"]
    "AotR8P.FinalStableV7" = $ExpectedSourceHashes["final_stable_v7.ps1"]
    "AotR8P.V7Shellcode" = $ExpectedSourceHashes["v7_shellcode.bin"]
    "AotR8P.Row1Patch" = $GeneratedVisualHashes["AotR8P.Row1Patch"]
    "AotR8P.Row2Patch" = $GeneratedVisualHashes["AotR8P.Row2Patch"]
    "AotR8P.Row3Patch" = $GeneratedVisualHashes["AotR8P.Row3Patch"]
    "AotR8P.ReadyPatch" = $GeneratedVisualHashes["AotR8P.ReadyPatch"]
}
foreach ($resourceName in $expectedEmbedded.Keys) {
    $stream = $candidateAsm.GetManifestResourceStream($resourceName)
    if ($null -eq $stream) { throw "Compiled resource missing: $resourceName" }
    try {
        $memory = New-Object IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            $actual = Get-BytesSha256 $memory.ToArray()
        }
        finally { $memory.Dispose() }
    }
    finally { $stream.Dispose() }
    if ($actual -ne $expectedEmbedded[$resourceName]) {
        throw "Compiled resource hash mismatch: $resourceName expected $($expectedEmbedded[$resourceName]) got $actual"
    }
    if ($resourceName -in @("AotR8P.LauncherSkin","AotR8P.Row1Patch","AotR8P.Row2Patch","AotR8P.Row3Patch","AotR8P.ReadyPatch") -and ($ForbiddenHistoricalHashes -contains $actual)) {
        throw "Historical blocked visual bytes leaked into compiled proof: $resourceName $actual"
    }
    Write-Host "SIGNING-CLEAN EMBEDDED RESOURCE OK: $resourceName $actual" -ForegroundColor Green
}

& $V7Verifier -ResourcesRoot $Resources -ExePath $Exe

$ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Exe))
foreach ($forbidden in @("Issue33SkinGzipBase64","GuiGzipBase64","EngineGzipBase64","FrozenDonorRoot","GZipStream")) {
    if ($ascii.Contains($forbidden)) { throw "Forbidden donor/legacy token remains in compiled proof: $forbidden" }
}

$report = [ordered]@{
    schema = 1
    state = "NON_RELEASE_SIGNING_CLEAN_VISUAL_PROOF"
    strategy = "GENERATED_PROJECT_NEUTRAL_VISUALS"
    launcher_version = $LauncherVersion
    candidate_exe_sha256 = Get-Sha256 $Exe
    candidate_exe_size = (Get-Item -LiteralPath $Exe).Length
    embedded_resources = @($names)
    generated_visual_hashes = $GeneratedVisualHashes
    historical_visual_hashes_forbidden = $HistoricalVisualHashes
    historical_visual_files_used_as_build_inputs = $false
    custom_pe_icon_embedded = $false
    gui_sha256 = $ExpectedSourceHashes["launcher_gui.ps1"]
    engine_sha256 = $ExpectedSourceHashes["launcher_engine.ps1"]
    final_stable_v7_sha256 = $ExpectedSourceHashes["final_stable_v7.ps1"]
    v7_shellcode_sha256 = $ExpectedSourceHashes["v7_shellcode.bin"]
    public_release_modified = $false
    field_execution_allowed = $false
    remaining_signpath_review = @(
        "launcher_gui.ps1 authorship/license scope",
        "launcher_engine.ps1 rights/policy review",
        "final_stable_v7.ps1 provenance/policy review",
        "v7_shellcode.bin authored-generation/provenance review"
    )
    note = "Research proof only. Unsigned binary is not uploaded and is not a Windows field candidate."
}
$ReportPath = Join-Path $OutputRoot "SIGNING_CLEAN_VISUAL_PROOF_REPORT.json"
[IO.File]::WriteAllText($ReportPath,($report | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))

Write-Host "SIGNING_CLEAN_VISUAL_PROOF=PASS" -ForegroundColor Green
Write-Host ("PROOF_EXE_SHA256=" + $report.candidate_exe_sha256)
Write-Host ("PROOF_EXE_SIZE=" + $report.candidate_exe_size)
Write-Host ("GENERATED_SKIN_SHA256=" + $GeneratedVisualHashes["AotR8P.LauncherSkin"])
Write-Host ("GENERATED_OVERLAY_SHA256=" + $GeneratedVisualHashes["AotR8P.Row1Patch"])
Write-Host ("REPORT=" + $ReportPath)
