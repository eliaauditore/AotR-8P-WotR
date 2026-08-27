#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE1_20260827_022948\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10_ROBUST_AUTODETECT_V2_NONRELEASE.ps1',
    [string]$SupportDonor = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\V18_RC1_TEST_20260827_004234'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ReleaseCommit = '1303e0a6b268b082e9352ded1461fa8d794f16d3'
$ExpectedBuilderSha256 = 'D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0'
$ExpectedReleaseExeSha256 = '6A80E0F7B862ABE3E0F19C3DF5ED9EE9EE730F246CF603ED00A39D1EE7DFF2F8'
$ExpectedUiSha256 = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha256 = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
$ExpectedIconSha256 = '3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A'
$ExpectedSkinSha256 = '2158FD8BB4E9195E27667F517FF81C745983BEE200394FB64107FFF902666473'
$TestVersion = '1.0.10-autodetect-v2-v18-test'
$InvalidManifestUrl = 'https://invalid.invalid/aotr8p-autodetect-v2-test/manifest.json'
$InvalidBinaryUrl = 'https://invalid.invalid/aotr8p-autodetect-v2-test/AotR%208P%20WotR%20Mod.exe'

function Get-Sha256File([string]$Path) {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Assert-FileHash([string]$Path,[string]$Expected,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label missing: $Path" }
    $actual = Get-Sha256File $Path
    if ($actual -ne $Expected) { throw "$Label hash mismatch. Expected $Expected, got $actual" }
    Write-Host ("{0,-24}: {1}" -f $Label,$actual) -ForegroundColor Green
    return $actual
}

if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw "Base missing: $Base" }
Assert-FileHash $BuilderPath $ExpectedBuilderSha256 'Autodetect V18 builder' | Out-Null
if (-not (Test-Path -LiteralPath $SupportDonor -PathType Container)) { throw "Support donor missing: $SupportDonor" }

$donorIcon = Join-Path $SupportDonor 'assets\launcher.ico'
$donorSkin = Join-Path $SupportDonor 'internal\assets\launcher_skin.png'
Assert-FileHash $donorIcon $ExpectedIconSha256 'Support icon' | Out-Null
Assert-FileHash $donorSkin $ExpectedSkinSha256 'Support skin' | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ("AUTODETECT_V2_V18_STAGE2_BUILD_" + $stamp)
$packageRoot = Join-Path $workRoot 'PACKAGE'
if (Test-Path -LiteralPath $workRoot) { throw "Refusing existing work root: $workRoot" }

$assetsDir = Join-Path $packageRoot 'assets'
$skinDir = Join-Path $packageRoot 'internal\assets'
$payloadDir = Join-Path $packageRoot 'payload'
$paperDir = Join-Path $packageRoot 'payload\data\ini\campaigns\scenarios'
foreach ($dir in @($workRoot,$packageRoot,$assetsDir,$skinDir,$payloadDir,$paperDir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

$seedExe = Join-Path $packageRoot 'AotR 8P WotR Mod.exe'
$uiPath = Join-Path $payloadDir '!!!WOTR_8P_UI_TEST.big'
$paperPath = Join-Path $paperDir 'PaperScenario001.inc'
$iconPath = Join-Path $assetsDir 'launcher.ico'
$skinPath = Join-Path $skinDir 'launcher_skin.png'
$builderCopy = Join-Path $packageRoot 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10_ROBUST_AUTODETECT_V2_NONRELEASE.ps1'

$releaseBase = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$ReleaseCommit"
Write-Host ''
Write-Host 'Downloading immutable 1.0.10 release inputs...' -ForegroundColor Cyan
Invoke-WebRequest -Uri ($releaseBase + '/AotR%208P%20WotR%20Mod.exe') -OutFile $seedExe
Invoke-WebRequest -Uri ($releaseBase + '/payload_ui.big') -OutFile $uiPath
Invoke-WebRequest -Uri ($releaseBase + '/payload_paper.inc') -OutFile $paperPath
Copy-Item -LiteralPath $donorIcon -Destination $iconPath
Copy-Item -LiteralPath $donorSkin -Destination $skinPath
Copy-Item -LiteralPath $BuilderPath -Destination $builderCopy

Write-Host ''
Write-Host '=== INPUT HASHES ===' -ForegroundColor Cyan
Assert-FileHash $builderCopy $ExpectedBuilderSha256 'Builder copy' | Out-Null
Assert-FileHash $seedExe $ExpectedReleaseExeSha256 'Released 1.0.10 EXE' | Out-Null
Assert-FileHash $uiPath $ExpectedUiSha256 'UI payload' | Out-Null
Assert-FileHash $paperPath $ExpectedPaperSha256 'Paper payload' | Out-Null
Assert-FileHash $iconPath $ExpectedIconSha256 'Icon copy' | Out-Null
Assert-FileHash $skinPath $ExpectedSkinSha256 'Skin copy' | Out-Null

$seedHashBefore = Get-Sha256File $seedExe
$builderHashBefore = Get-Sha256File $builderCopy

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P V18 STAGE 2 - NON-RELEASE BUILD' -ForegroundColor Cyan
Write-Host ' BUNDLE ONLY / INVALID TEST UPDATE URLS' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Work root       : $workRoot"
Write-Host "Package root    : $packageRoot"
Write-Host "Launcher version: $TestVersion"
Write-Host "Manifest URL    : $InvalidManifestUrl"
Write-Host "Binary URL      : $InvalidBinaryUrl"
Write-Host ''

& $builderCopy `
    -PackageRoot $packageRoot `
    -LauncherVersion $TestVersion `
    -UpdateManifestUrl $InvalidManifestUrl `
    -UpdateBinaryUrl $InvalidBinaryUrl `
    -EmitGitHubBundle `
    -BundleOnly

$bundleRoot = Join-Path $packageRoot '_GITHUB_UPDATE'
$builtExe = Join-Path $bundleRoot 'AotR 8P WotR Mod.exe'
if (-not (Test-Path -LiteralPath $builtExe -PathType Leaf)) { throw "BundleOnly build did not produce expected EXE: $builtExe" }

$builtSha = Get-Sha256File $builtExe
$builtInfo = Get-Item -LiteralPath $builtExe

if ((Get-Sha256File $seedExe) -ne $seedHashBefore) { throw 'BundleOnly unexpectedly modified the package seed launcher.' }
if ((Get-Sha256File $builderCopy) -ne $builderHashBefore) { throw 'Builder copy changed during build.' }
if ((Get-Sha256File $BuilderPath) -ne $ExpectedBuilderSha256) { throw 'Original Stage 1 builder changed during build.' }

$bundleUi = Join-Path $bundleRoot 'payload_ui.big'
$bundlePaper = Join-Path $bundleRoot 'payload_paper.inc'
if (Test-Path -LiteralPath $bundleUi -PathType Leaf) { Assert-FileHash $bundleUi $ExpectedUiSha256 'Bundle UI' | Out-Null }
if (Test-Path -LiteralPath $bundlePaper -PathType Leaf) { Assert-FileHash $bundlePaper $ExpectedPaperSha256 'Bundle Paper' | Out-Null }

$report = Join-Path $workRoot 'V18_STAGE2_NONRELEASE_BUILD_REPORT.txt'
$reportLines = @(
    'AOTR 8P V18 STAGE2 NON-RELEASE BUILD',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Release commit: ' + $ReleaseCommit),
    ('Input builder SHA256: ' + $ExpectedBuilderSha256),
    ('Seed 1.0.10 EXE SHA256: ' + $ExpectedReleaseExeSha256),
    ('Version: ' + $TestVersion),
    ('Manifest URL: ' + $InvalidManifestUrl),
    ('Binary URL: ' + $InvalidBinaryUrl),
    ('Built EXE: ' + $builtExe),
    ('Built EXE SHA256: ' + $builtSha),
    ('Built EXE bytes: ' + $builtInfo.Length),
    '',
    'SAFETY',
    '- Build mode BundleOnly + EmitGitHubBundle: PASS',
    '- Package seed EXE unchanged: PASS',
    '- Original Stage1 builder unchanged: PASS',
    '- Invalid test update URLs embedded via builder parameters: PASS',
    '- Public repository/release files not written by this runner: PASS',
    '- Game files not modified by this runner: PASS'
)
[IO.File]::WriteAllLines($report,$reportLines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '=== V18 STAGE 2 RESULT ===' -ForegroundColor Cyan
Write-Host "Built EXE    : $builtExe" -ForegroundColor Green
Write-Host "Built SHA256 : $builtSha" -ForegroundColor Green
Write-Host "Built bytes  : $($builtInfo.Length)" -ForegroundColor Green
Write-Host "Report       : $report"
Write-Host ''
Write-Host 'V18 non-release BundleOnly build: PASS' -ForegroundColor Green
Write-Host 'No installed launcher, public release, manifest, config, cache, or game file was modified.' -ForegroundColor Green
