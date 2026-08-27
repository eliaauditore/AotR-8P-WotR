#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$FrozenDonorRoot,
    [string]$OutputRoot = "",
    [string]$LauncherVersion = "1.1.2"
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

function Assert-Hash([string]$Path,[string]$Expected,[string]$Role) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Role missing: $Path" }
    $actual = Get-Sha256 $Path
    if ($actual -ne $Expected) { throw "$Role SHA256 mismatch. Expected $Expected, got $actual" }
    Write-Host "$Role OK: $actual" -ForegroundColor Green
}

function Inflate-Base64Gzip([string]$Value,[string]$OutPath) {
    $packed = [Convert]::FromBase64String($Value)
    $input = New-Object IO.MemoryStream(,$packed)
    try {
        $gzip = New-Object IO.Compression.GZipStream($input,[IO.Compression.CompressionMode]::Decompress)
        try {
            $output = [IO.File]::Create($OutPath)
            try { $gzip.CopyTo($output) } finally { $output.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally { $input.Dispose() }
}

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$FrozenDonorRoot = [IO.Path]::GetFullPath($FrozenDonorRoot)
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $RepoRoot "_V19_1_1_2_BUILD" }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$Work = Join-Path $OutputRoot "work"
$Resources = Join-Path $Work "resources"
$Frozen = Join-Path $Work "frozen"
$Package = Join-Path $OutputRoot "package"

if (Test-Path -LiteralPath $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Resources,$Frozen,$Package | Out-Null

$DonorExe = Join-Path $FrozenDonorRoot "AotR 8P WotR Mod.exe"
$DonorUi = Join-Path $FrozenDonorRoot "payload_ui.big"
$DonorPaper = Join-Path $FrozenDonorRoot "payload_paper.inc"

Assert-Hash $DonorExe "2141EA9690708EA7A61B7298AD90E0C76CC417FED996AC0CF3685276BA2A4024" "Frozen 1.1.1 EXE"
Assert-Hash $DonorUi "827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376" "UI payload"
Assert-Hash $DonorPaper "3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43" "Paper payload"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.Drawing
$asm = [Reflection.Assembly]::LoadFile($DonorExe)
$type = $asm.GetType("Program",$true)
$flags = [Reflection.BindingFlags]"NonPublic,Public,Static"
function Get-ConstString([string]$Name) {
    $field = $type.GetField($Name,$flags)
    if (-not $field) { throw "Frozen donor field missing: $Name" }
    $value = $field.GetRawConstantValue()
    if (-not ($value -is [string])) { throw "Frozen donor field is not string: $Name" }
    return [string]$value
}

$FrozenGui = Join-Path $Frozen "launcher_gui.ps1"
$FrozenEngine = Join-Path $Frozen "launcher_engine.ps1"
$Skin = Join-Path $Resources "launcher_skin.png"
Inflate-Base64Gzip (Get-ConstString "Issue33SkinGzipBase64") $Skin
Inflate-Base64Gzip (Get-ConstString "GuiGzipBase64") $FrozenGui
Inflate-Base64Gzip (Get-ConstString "EngineGzipBase64") $FrozenEngine
Assert-Hash $Skin "BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6" "Launcher skin"
Assert-Hash $FrozenGui "23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C" "Frozen GUI"
Assert-Hash $FrozenEngine "94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA" "Frozen engine"

$Icon = Join-Path $Resources "launcher.ico"
$iconObject = [Drawing.Icon]::ExtractAssociatedIcon($DonorExe)
if (-not $iconObject) { throw "Could not extract frozen launcher icon" }
$iconStream = [IO.File]::Create($Icon)
try { $iconObject.Save($iconStream) } finally { $iconStream.Dispose(); $iconObject.Dispose() }

$guiText = Get-Content -LiteralPath $FrozenGui -Raw -Encoding UTF8
foreach ($pair in @(
    @("Row1CleanPatchBase64","row1cleanpatch.png","D4DC9A47F0E2FD9715D92F8DD4C3831B9AB95F8CA34E98937F019B7574294177"),
    @("Row2CleanPatchBase64","row2cleanpatch.png","58B9A7173CE1C9C30C85EE76D15D54E3D40B3E7E14E25D0C1FE5D8EFD89E6D8E"),
    @("Row3CleanPatchBase64","row3cleanpatch.png","7F86C02BC02D2E57D66202AF9C526D6FAE13CFC9B7CB1EFF1BB61C165B25278C"),
    @("ReadyCleanPatchBase64","readycleanpatch.png","35DCBCBE6E625C5C06EC36BAB3CA51A6F4EE29DA3DFF4CAEEDD69BC87D873DF3")
)) {
    $name = $pair[0]; $file = $pair[1]; $expected = $pair[2]
    $pattern = "(?m)^\$" + [regex]::Escape($name) + "\s*=\s*`"([^`"]+)`"\s*$"
    $match = [regex]::Match($guiText,$pattern)
    if (-not $match.Success) { throw "Could not extract frozen GUI resource $name" }
    $path = Join-Path $Resources $file
    [IO.File]::WriteAllBytes($path,[Convert]::FromBase64String($match.Groups[1].Value))
    Assert-Hash $path $expected $file
}

$FrozenFinal = Join-Path $Frozen "final_stable_v7.ps1"
$engineText = Get-Content -LiteralPath $FrozenEngine -Raw -Encoding UTF8
$finalPattern = '(?s)\$FinalStableV7Base64\s*=\s*@''\s*(.*?)\s*''@'
$finalMatch = [regex]::Match($engineText,$finalPattern)
if (-not $finalMatch.Success) { throw "Could not extract frozen FINAL_STABLE_V7" }
[IO.File]::WriteAllBytes($FrozenFinal,[Convert]::FromBase64String(($finalMatch.Groups[1].Value -replace "\s","")))
Assert-Hash $FrozenFinal "FEAF40B3B231646CD8F7C7099D1E8544090D5010F1C6DB06E5B2F3EF8C0C5F44" "Frozen FINAL_STABLE_V7"

$Python = (Get-Command python -ErrorAction Stop).Source
& $Python (Join-Path $PSScriptRoot "prepare_clean_resources.py") $FrozenGui $FrozenEngine $Resources
if ($LASTEXITCODE -ne 0) { throw "GUI/engine clean resource transform failed" }
& $Python (Join-Path $PSScriptRoot "apply_issue43_recheck_flow.py") (Join-Path $Resources "launcher_gui.ps1") --expected-output "135B1FDD64B84B0DE84BC7526F04157A790228DFC49FF5DD6253C89023D71EBD"
if ($LASTEXITCODE -ne 0) { throw "Issue43 post-repair health re-check transform failed" }
& $Python (Join-Path $PSScriptRoot "prepare_final_stable_resource.py") $FrozenFinal (Join-Path $Resources "final_stable_v7.ps1") (Join-Path $Resources "v7_shellcode.bin")
if ($LASTEXITCODE -ne 0) { throw "FINAL_STABLE_V7 clean resource transform failed" }

Assert-Hash (Join-Path $Resources "launcher_gui.ps1") "135B1FDD64B84B0DE84BC7526F04157A790228DFC49FF5DD6253C89023D71EBD" "Clean GUI Issue43"
Assert-Hash (Join-Path $Resources "launcher_engine.ps1") "5DB2F749F10E84322BC471FFF04E25326EFF194FA440175FE9841ED13367F938" "Clean engine"
Assert-Hash (Join-Path $Resources "final_stable_v7.ps1") "72D00490538BE2222F5BAAF3D8A1648A86071D3A098946A7B8751E7D337300E2" "Clean FINAL_STABLE_V7"
Assert-Hash (Join-Path $Resources "v7_shellcode.bin") "60EECE4660C3BA0AD183EB82B82DCDACF3ECA6DC892C8FAFCD629A92170ED45A" "V7 shellcode resource"

& (Join-Path $PSScriptRoot "VERIFY_V7_RESOURCE_CHAIN.ps1") -ResourcesRoot $Resources

foreach ($path in @(
    (Join-Path $Resources "launcher_gui.ps1"),
    (Join-Path $Resources "launcher_engine.ps1"),
    (Join-Path $Resources "final_stable_v7.ps1")
)) {
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) { throw "PowerShell 5.1 parse failed: $path :: $($errors[0].Message)" }
    Write-Host "PS5 PARSE OK: $path" -ForegroundColor Green
}

$SourceTemplate = Join-Path $PSScriptRoot "launcher.cs"
$source = Get-Content -LiteralPath $SourceTemplate -Raw -Encoding UTF8
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
    ("/win32icon:"+$Icon),("/win32manifest:"+$NativeManifest),
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
Write-Host "CANDIDATE_SHA256=$LauncherHash" -ForegroundColor Cyan
Write-Host "CANDIDATE_SIZE=$((Get-Item -LiteralPath $Exe).Length)" -ForegroundColor Cyan

$candidateAsm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($Exe))
$names = @($candidateAsm.GetManifestResourceNames() | Sort-Object)
$expectedNames = @(
    "AotR8P.EngineScript","AotR8P.FinalStableV7","AotR8P.GuiScript","AotR8P.LauncherSkin",
    "AotR8P.ReadyPatch","AotR8P.Row1Patch","AotR8P.Row2Patch","AotR8P.Row3Patch","AotR8P.V7Shellcode"
) | Sort-Object
if (($names -join "|") -ne ($expectedNames -join "|")) { throw "Embedded resource inventory mismatch: $($names -join ', ')" }
$ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Exe))
foreach ($forbidden in @("Issue33SkinGzipBase64","GuiGzipBase64","EngineGzipBase64","FromBase64String","GZipStream","WebClient","DownloadString")) {
    if ($ascii.Contains($forbidden)) { throw "Forbidden legacy token remains in compiled candidate: $forbidden" }
}
Write-Host "STATIC CLEANUP PASS" -ForegroundColor Green

& (Join-Path $PSScriptRoot "VERIFY_V7_RESOURCE_CHAIN.ps1") -ResourcesRoot $Resources -ExePath $Exe

Copy-Item -LiteralPath $DonorUi -Destination (Join-Path $Package "payload_ui.big") -Force
Copy-Item -LiteralPath $DonorPaper -Destination (Join-Path $Package "payload_paper.inc") -Force
$manifestObject = [ordered]@{
    schema=1; launcher_version=$LauncherVersion
    launcher_url="https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/AotR%208P%20WotR%20Mod.exe"
    launcher_sha256=$LauncherHash; mandatory=$false
    repair_manifest_url="https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/repair-manifest.json"
    ui_url="https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/payload_ui.big"
    ui_sha256="827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376"
    paper_url="https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/payload_paper.inc"
    paper_sha256="3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43"
}
[IO.File]::WriteAllText((Join-Path $Package "manifest.json"),(($manifestObject|ConvertTo-Json -Depth 6)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
$repair = Get-Content -LiteralPath (Join-Path $RepoRoot "repair-manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$repair.generated_for_launcher = $LauncherVersion
[IO.File]::WriteAllText((Join-Path $Package "repair-manifest.json"),(($repair|ConvertTo-Json -Depth 8)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))

$PublicFiles = @("AotR 8P WotR Mod.exe","manifest.json","repair-manifest.json","payload_ui.big","payload_paper.inc")
$actualNames = @(Get-ChildItem -LiteralPath $Package -File | Select-Object -ExpandProperty Name | Sort-Object)
if (($actualNames -join "|") -ne (($PublicFiles|Sort-Object) -join "|")) { throw "Package root is not exact five-file contract: $($actualNames -join ', ')" }
$records = foreach ($name in $PublicFiles) {
    $path = Join-Path $Package $name
    [PSCustomObject]@{ file=$name; sha256=Get-Sha256 $path; size=(Get-Item -LiteralPath $path).Length }
}
[IO.File]::WriteAllText((Join-Path $OutputRoot "SHA256SUMS.json"),(($records|ConvertTo-Json -Depth 4)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))

$Zip = Join-Path $OutputRoot "AotR_8P_War_of_the_Ring_1.1.2_Clean_Candidate.zip"
Compress-Archive -LiteralPath ($PublicFiles | ForEach-Object { Join-Path $Package $_ }) -DestinationPath $Zip -CompressionLevel Optimal
$ZipHash = Get-Sha256 $Zip
[IO.File]::WriteAllText(($Zip+".sha256.txt"),"$ZipHash  $([IO.Path]::GetFileName($Zip))`r`n",[Text.Encoding]::ASCII)
Write-Host "ZIP_SHA256=$ZipHash" -ForegroundColor Cyan

$status = "UNAVAILABLE"
$mp = @(
    "$env:ProgramFiles\Windows Defender\MpCmdRun.exe",
    "$env:ProgramData\Microsoft\Windows Defender\Platform\*\MpCmdRun.exe"
) | ForEach-Object { Get-Item $_ -ErrorAction SilentlyContinue } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($mp) {
    & $mp.FullName -Scan -ScanType 3 -File $Exe -DisableRemediation
    $code = $LASTEXITCODE
    $detections = @()
    try { $detections = @(Get-MpThreatDetection -ErrorAction Stop | Where-Object { $_.Resources -match "AotR 8P WotR Mod.exe" }) } catch {}
    if ($code -eq 0 -and $detections.Count -eq 0) { $status="SCANNED_CLEAN" }
    else { $status="SCAN_ALERT_OR_ERROR|exit=$code|detections=$($detections.Count)" }
}
[IO.File]::WriteAllText((Join-Path $OutputRoot "DEFENDER_SCAN.txt"),$status+"`r`n",[Text.Encoding]::ASCII)
Write-Host "DEFENDER_STATUS=$status" -ForegroundColor Cyan
if ($status -ne "SCANNED_CLEAN") { throw "Defender gate not clean: $status" }

Write-Host "V19 CLEAN CANDIDATE PASS" -ForegroundColor Green
