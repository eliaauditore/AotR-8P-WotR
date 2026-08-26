#requires -version 5.1
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE1_20260827_003823\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_NONRELEASE.ps1',
    [string]$LauncherVersion = '1.0.10-autodetect-v2-test'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = '6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386'
$DeadManifestUrl = 'https://invalid.invalid/aotr8p-autodetect-v2-test/manifest.json'
$DeadBinaryUrl = 'https://invalid.invalid/aotr8p-autodetect-v2-test/AotR%208P%20WotR%20Mod.exe'

function Assert-Leaf([string]$Path,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label missing: $Path" }
}

function Assert-Container([string]$Path,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "$Label missing: $Path" }
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

$BuilderPath = [IO.Path]::GetFullPath($BuilderPath)
Assert-Leaf $BuilderPath 'Stage-1 non-release builder'
$builderHash = Get-Sha256 $BuilderPath
if ($builderHash -ne $ExpectedBuilderSha256) {
    throw "Builder checkpoint mismatch. Expected $ExpectedBuilderSha256, got $builderHash. Build refused."
}

$requiredInputs = @(
    @{ Relative = 'assets'; Label = 'assets' },
    @{ Relative = 'internal\assets'; Label = 'internal assets' },
    @{ Relative = 'payload'; Label = 'payload' }
)
foreach ($item in $requiredInputs) {
    Assert-Container (Join-Path $Base $item.Relative) $item.Label
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$buildRoot = Join-Path $Base ("AUTODETECT_V2_BUILD_" + $stamp)
if (Test-Path -LiteralPath $buildRoot) {
    throw "Refusing to reuse build root: $buildRoot"
}
New-Item -ItemType Directory -Path $buildRoot | Out-Null

try {
    foreach ($item in $requiredInputs) {
        $source = Join-Path $Base $item.Relative
        $destination = Join-Path $buildRoot $item.Relative
        $parent = Split-Path $destination -Parent
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
    }

    $rootLauncher = Join-Path $buildRoot 'AotR 8P WotR Mod.exe'
    if (Test-Path -LiteralPath $rootLauncher) {
        throw 'Isolation precondition failed: a root launcher already exists in the new build root.'
    }

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' AOTR 8P ROBUST AUTODETECT V2 - STAGE 2 NON-RELEASE BUILD' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host "Builder      : $BuilderPath"
    Write-Host "Builder SHA  : $builderHash" -ForegroundColor Green
    Write-Host "Build root   : $buildRoot"
    Write-Host "Version      : $LauncherVersion"
    Write-Host 'BundleOnly   : TRUE'
    Write-Host 'GitHub bundle: TRUE (LOCAL ISOLATED FOLDER ONLY)'
    Write-Host 'Update URLs  : intentionally invalid for test safety'
    Write-Host ''

    & $BuilderPath `
        -PackageRoot $buildRoot `
        -LauncherVersion $LauncherVersion `
        -UpdateManifestUrl $DeadManifestUrl `
        -UpdateBinaryUrl $DeadBinaryUrl `
        -BundleOnly `
        -EmitGitHubBundle

    $bundleRoot = Join-Path $buildRoot '_GITHUB_UPDATE'
    $exe = Join-Path $bundleRoot 'AotR 8P WotR Mod.exe'
    $manifest = Join-Path $bundleRoot 'manifest.json'
    $repairManifest = Join-Path $bundleRoot 'repair-manifest.json'

    Assert-Leaf $exe 'Built non-release EXE'
    Assert-Leaf $manifest 'Generated manifest'
    Assert-Leaf $repairManifest 'Generated repair manifest'

    $bytes = [IO.File]::ReadAllBytes($exe)
    if ($bytes.Length -lt 4096 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        throw 'Built bundle EXE is not a valid Windows PE/MZ file.'
    }

    if (Test-Path -LiteralPath $rootLauncher) {
        throw 'SAFETY FAILURE: BundleOnly build unexpectedly created/replaced a launcher in the PackageRoot root.'
    }

    $manifestObject = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ([string]$manifestObject.launcher_version -ne $LauncherVersion) {
        throw "Manifest launcher_version mismatch: $($manifestObject.launcher_version)"
    }
    if ([string]$manifestObject.launcher_url -ne $DeadBinaryUrl) {
        throw 'Manifest launcher_url is not the intentionally invalid test URL.'
    }

    $exeHash = Get-Sha256 $exe
    if ([string]$manifestObject.launcher_sha256 -ne $exeHash) {
        throw "Manifest launcher SHA mismatch. Manifest=$($manifestObject.launcher_sha256) Actual=$exeHash"
    }

    $reportPath = Join-Path $buildRoot 'STAGE2_BUILD_REPORT.txt'
    $report = @(
        'AOTR 8P ROBUST AUTODETECT V2 - STAGE 2 BUILD REPORT',
        ('Timestamp: ' + (Get-Date -Format o)),
        ('Builder: ' + $BuilderPath),
        ('Builder SHA256: ' + $builderHash),
        ('LauncherVersion: ' + $LauncherVersion),
        ('BuildRoot: ' + $buildRoot),
        ('Bundle EXE: ' + $exe),
        ('Bundle EXE SHA256: ' + $exeHash),
        ('Bundle EXE bytes: ' + $bytes.Length),
        ('Manifest: ' + $manifest),
        ('Repair manifest: ' + $repairManifest),
        ('Root launcher replaced: NO'),
        ('Original builder modified: NO'),
        ('Update manifest URL: ' + $DeadManifestUrl),
        ('Update binary URL: ' + $DeadBinaryUrl)
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText($reportPath,$report + [Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' STAGE 2 BUILD COMPLETE' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host "Build root : $buildRoot"
    Write-Host "EXE        : $exe"
    Write-Host "EXE SHA256 : $exeHash" -ForegroundColor Green
    Write-Host "EXE bytes  : $($bytes.Length)"
    Write-Host "Report     : $reportPath"
    Write-Host ''
    Write-Host 'Current launcher replaced: NO' -ForegroundColor Green
    Write-Host 'Public release modified: NO' -ForegroundColor Green
    Write-Host 'Test EXE auto-update target: INVALID / SAFE' -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host '[STAGE 2 BUILD FAILED]' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Partial isolated build root retained for inspection: $buildRoot" -ForegroundColor Yellow
    throw
}
