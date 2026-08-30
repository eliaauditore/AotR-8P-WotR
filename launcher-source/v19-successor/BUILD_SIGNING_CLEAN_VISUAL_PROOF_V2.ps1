#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = "",
    [string]$LauncherVersion = "1.1.3-signingclean-visualproof2"
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

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$Resources = Join-Path $PSScriptRoot "resources"
$SourceTemplate = Join-Path $PSScriptRoot "..\v19\launcher.cs"
$V7Verifier = Join-Path $PSScriptRoot "..\v19\VERIFY_V7_RESOURCE_CHAIN.ps1"

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $env:TEMP "AOTR8P_SIGNING_CLEAN_VISUAL_PROOF_V2"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$Work = Join-Path $OutputRoot "work"
if (Test-Path -LiteralPath $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Work | Out-Null

# Only resources that remain inside the proof EXE are admitted here.
$ExpectedSourceHashes = [ordered]@{
    "launcher_gui.ps1"     = "135B1FDD64B84B0DE84BC7526F04157A790228DFC49FF5DD6253C89023D71EBD"
    "launcher_engine.ps1"  = "5DB2F749F10E84322BC471FFF04E25326EFF194FA440175FE9841ED13367F938"
    "final_stable_v7.ps1"  = "72D00490538BE2222F5BAAF3D8A1648A86071D3A098946A7B8751E7D337300E2"
    "v7_shellcode.bin"     = "60EECE4660C3BA0AD183EB82B82DCDACF3ECA6DC892C8FAFCD629A92170ED45A"
}
foreach ($name in $ExpectedSourceHashes.Keys) {
    Assert-Hash (Join-Path $Resources $name) $ExpectedSourceHashes[$name] "Signing-clean source $name"
}

# Require historical visual inputs to exist so exclusion is explicit and auditable.
$ExcludedVisuals = @(
    "launcher_skin.png",
    "launcher.ico",
    "row1cleanpatch.png",
    "row2cleanpatch.png",
    "row3cleanpatch.png",
    "readycleanpatch.png"
)
foreach ($name in $ExcludedVisuals) {
    if (-not (Test-Path -LiteralPath (Join-Path $Resources $name) -PathType Leaf)) {
        throw "Historical excluded visual resource missing: $name"
    }
}

if (-not (Test-Path -LiteralPath $V7Verifier -PathType Leaf)) { throw "V7 verifier missing: $V7Verifier" }
& $V7Verifier -ResourcesRoot $Resources

# Build a neutral WPF presentation from the maintained GUI source. No new artwork is introduced.
$guiSourcePath = Join-Path $Resources "launcher_gui.ps1"
$guiText = [IO.File]::ReadAllText($guiSourcePath).Replace("`r`n","`n")
$windowAnchor = @(
    '        AllowsTransparency="True"',
    '        Background="Transparent"',
    '        ShowInTaskbar="True">'
) -join "`n"
$windowReplacement = @(
    '        AllowsTransparency="True"',
    '        Background="#181D21"',
    '        ShowInTaskbar="True">'
) -join "`n"
$guiText = Replace-ExactOnce $guiText $windowAnchor $windowReplacement "neutral main window background"

$visualBindings = @(
    'Set-EmbeddedPngSource $SkinImage ([byte[]]$global:AOTR8P_SKIN_BYTES)',
    'Set-EmbeddedPngSource $Row1CleanPatch ([byte[]]$global:AOTR8P_ROW1_PATCH)',
    'Set-EmbeddedPngSource $Row2CleanPatch ([byte[]]$global:AOTR8P_ROW2_PATCH)',
    'Set-EmbeddedPngSource $Row3CleanPatch ([byte[]]$global:AOTR8P_ROW3_PATCH)',
    'Set-EmbeddedPngSource $ReadyCleanPatch ([byte[]]$global:AOTR8P_READY_PATCH)'
)
foreach ($line in $visualBindings) {
    $guiText = Replace-ExactOnce $guiText $line '# signing-clean visual proof: embedded visual omitted' ("remove visual binding: " + $line)
}

foreach ($forbidden in @(
    'AOTR8P_SKIN_BYTES',
    'AOTR8P_ROW1_PATCH',
    'AOTR8P_ROW2_PATCH',
    'AOTR8P_ROW3_PATCH',
    'AOTR8P_READY_PATCH'
)) {
    if ($guiText.Contains($forbidden)) { throw "Excluded visual global remains in generated GUI: $forbidden" }
}

$CleanGui = Join-Path $Work "launcher_gui_signing_clean.ps1"
[IO.File]::WriteAllText($CleanGui,$guiText,(New-Object Text.UTF8Encoding($false)))

foreach ($path in @(
    $CleanGui,
    (Join-Path $Resources "launcher_engine.ps1"),
    (Join-Path $Resources "final_stable_v7.ps1")
)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) { throw "PowerShell 5.1 parse failed: $path :: $($errors[0].Message)" }
    Write-Host "PS5 PARSE OK: $path" -ForegroundColor Green
}

# Prepare C# host with only GUI, Engine, FINAL_STABLE_V7 and V7 shellcode embedded.
if (-not (Test-Path -LiteralPath $SourceTemplate -PathType Leaf)) { throw "C# source template missing: $SourceTemplate" }
$source = [IO.File]::ReadAllText($SourceTemplate).Replace("`r`n","`n")

$visualCSharpLines = @(
    '    private const string SkinResourceName = "AotR8P.LauncherSkin";',
    '    private const string Row1PatchResourceName = "AotR8P.Row1Patch";',
    '    private const string Row2PatchResourceName = "AotR8P.Row2Patch";',
    '    private const string Row3PatchResourceName = "AotR8P.Row3Patch";',
    '    private const string ReadyPatchResourceName = "AotR8P.ReadyPatch";',
    '                    runspace.SessionStateProxy.SetVariable("AOTR8P_SKIN_BYTES", ReadEmbeddedBytes(SkinResourceName));',
    '                    runspace.SessionStateProxy.SetVariable("AOTR8P_ROW1_PATCH", ReadEmbeddedBytes(Row1PatchResourceName));',
    '                    runspace.SessionStateProxy.SetVariable("AOTR8P_ROW2_PATCH", ReadEmbeddedBytes(Row2PatchResourceName));',
    '                    runspace.SessionStateProxy.SetVariable("AOTR8P_ROW3_PATCH", ReadEmbeddedBytes(Row3PatchResourceName));',
    '                    runspace.SessionStateProxy.SetVariable("AOTR8P_READY_PATCH", ReadEmbeddedBytes(ReadyPatchResourceName));'
)
foreach ($line in $visualCSharpLines) {
    $source = Replace-ExactOnce $source ($line + "`n") "" ("remove C# visual dependency: " + $line.Trim())
}

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
foreach ($forbidden in @(
    'AotR8P.LauncherSkin','AotR8P.Row1Patch','AotR8P.Row2Patch','AotR8P.Row3Patch','AotR8P.ReadyPatch',
    'AOTR8P_SKIN_BYTES','AOTR8P_ROW1_PATCH','AOTR8P_ROW2_PATCH','AOTR8P_ROW3_PATCH','AOTR8P_READY_PATCH'
)) {
    if ($source.Contains($forbidden)) { throw "Excluded visual dependency remains in generated C#: $forbidden" }
}
$CsPath = Join-Path $Work "launcher_signing_clean.cs"
[IO.File]::WriteAllText($CsPath,$source,(New-Object Text.UTF8Encoding($false)))

$NativeManifest = Join-Path $Work "launcher.manifest"
$manifestText = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0"><assemblyIdentity version="1.0.0.0" name="eliaauditore.AotR8PWotRMod.SigningCleanVisualProof"/><trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges><requestedExecutionLevel level="requireAdministrator" uiAccess="false"/></requestedPrivileges></security></trustInfo><application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings><dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware></windowsSettings></application></assembly>'
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
    ("/resource:"+$CleanGui+",AotR8P.GuiScript"),
    ("/resource:"+(Join-Path $Resources "launcher_engine.ps1")+",AotR8P.EngineScript"),
    ("/resource:"+(Join-Path $Resources "final_stable_v7.ps1")+",AotR8P.FinalStableV7"),
    ("/resource:"+(Join-Path $Resources "v7_shellcode.bin")+",AotR8P.V7Shellcode"),
    ("/out:"+$Exe),$CsPath
)
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
    "AotR8P.V7Shellcode"
) | Sort-Object
if (($names -join "|") -ne ($expectedNames -join "|")) {
    throw "Signing-clean resource inventory mismatch: $($names -join ', ')"
}

$expectedEmbedded = [ordered]@{
    "AotR8P.GuiScript" = Get-Sha256 $CleanGui
    "AotR8P.EngineScript" = $ExpectedSourceHashes["launcher_engine.ps1"]
    "AotR8P.FinalStableV7" = $ExpectedSourceHashes["final_stable_v7.ps1"]
    "AotR8P.V7Shellcode" = $ExpectedSourceHashes["v7_shellcode.bin"]
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
    Write-Host "SIGNING-CLEAN EMBEDDED RESOURCE OK: $resourceName $actual" -ForegroundColor Green
}

# Re-run V7 embedded-resource and cross-resource verification on the compiled proof.
& $V7Verifier -ResourcesRoot $Resources -ExePath $Exe

$ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Exe))
foreach ($forbidden in @(
    "AotR8P.LauncherSkin","AotR8P.Row1Patch","AotR8P.Row2Patch","AotR8P.Row3Patch","AotR8P.ReadyPatch",
    "Issue33SkinGzipBase64","GuiGzipBase64","EngineGzipBase64","FrozenDonorRoot","GZipStream"
)) {
    if ($ascii.Contains($forbidden)) { throw "Excluded/legacy token remains in compiled proof: $forbidden" }
}

$report = [ordered]@{
    schema = 1
    state = "NON_RELEASE_SIGNING_CLEAN_VISUAL_PROOF"
    launcher_version = $LauncherVersion
    candidate_exe_sha256 = Get-Sha256 $Exe
    candidate_exe_size = (Get-Item -LiteralPath $Exe).Length
    embedded_resources = @($names)
    excluded_visual_resources = @($ExcludedVisuals)
    custom_pe_icon_embedded = $false
    original_gui_sha256 = $ExpectedSourceHashes["launcher_gui.ps1"]
    neutral_gui_sha256 = Get-Sha256 $CleanGui
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
    note = "Research proof only. Binary is intentionally not a field candidate and is not uploaded for local execution."
}
$ReportPath = Join-Path $OutputRoot "SIGNING_CLEAN_VISUAL_PROOF_REPORT.json"
[IO.File]::WriteAllText($ReportPath,($report | ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))

Write-Host "SIGNING_CLEAN_VISUAL_PROOF=PASS" -ForegroundColor Green
Write-Host ("PROOF_EXE_SHA256=" + $report.candidate_exe_sha256)
Write-Host ("PROOF_EXE_SIZE=" + $report.candidate_exe_size)
Write-Host ("NEUTRAL_GUI_SHA256=" + $report.neutral_gui_sha256)
Write-Host ("REPORT=" + $ReportPath)
