#requires -version 5.1
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$ResearchRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING',
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE1_20260827_003823\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_NONRELEASE.ps1',
    [string]$SeedLauncherPath = '',
    [string]$LauncherVersion = '1.0.10-autodetect-v2-test'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = '6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386'
$ExpectedSeedSha256 = '97A8163CA72BDFB5C6C24931E06B2BFCE1D0E33C382FEA2462F73BC80BD3EA9F'
$SeedName = 'AotR 8P WotR Mod.exe'
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

function Resolve-VerifiedSeed {
    param(
        [string]$ExplicitPath,
        [string]$BoundedRoot
    )

    $rows = New-Object System.Collections.Generic.List[object]

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $p = [IO.Path]::GetFullPath($ExplicitPath)
        Assert-Leaf $p 'Explicit seed launcher'
        $h = Get-Sha256 $p
        [void]$rows.Add([PSCustomObject]@{ Path=$p; SHA256=$h; Match=($h -eq $ExpectedSeedSha256) })
    }
    else {
        Assert-Container $BoundedRoot 'Bounded research root'
        foreach ($f in @(Get-ChildItem -LiteralPath $BoundedRoot -Recurse -File -Filter $SeedName -ErrorAction SilentlyContinue)) {
            try {
                $h = Get-Sha256 $f.FullName
                [void]$rows.Add([PSCustomObject]@{
                    Path = $f.FullName
                    SHA256 = $h
                    Match = ($h -eq $ExpectedSeedSha256)
                })
            } catch {}
        }
    }

    $matches = @($rows | Where-Object Match | Sort-Object @{Expression={$_.Path.Length};Ascending=$true}, Path)
    if ($matches.Count -lt 1) {
        Write-Host ''
        Write-Host '=== SEED DISCOVERY RESULTS ===' -ForegroundColor Yellow
        if ($rows.Count -gt 0) {
            $rows | Sort-Object Path | Format-Table -AutoSize
        } else {
            Write-Host "No files named '$SeedName' were found below $BoundedRoot" -ForegroundColor Yellow
        }
        throw "No verified 1.0.9 seed launcher found. Required SHA256: $ExpectedSeedSha256"
    }

    Write-Host ''
    Write-Host '=== VERIFIED SEED DISCOVERY ===' -ForegroundColor Cyan
    $rows | Sort-Object @{Expression={$_.Match};Descending=$true}, Path | Format-Table -AutoSize
    return [string]$matches[0].Path
}

$BuilderPath = [IO.Path]::GetFullPath($BuilderPath)
Assert-Leaf $BuilderPath 'Stage-1 non-release builder'
$builderHash = Get-Sha256 $BuilderPath
if ($builderHash -ne $ExpectedBuilderSha256) {
    throw "Builder checkpoint mismatch. Expected $ExpectedBuilderSha256, got $builderHash. Build refused."
}

$seedSource = Resolve-VerifiedSeed -ExplicitPath $SeedLauncherPath -BoundedRoot $ResearchRoot
$seedSourceHash = Get-Sha256 $seedSource
if ($seedSourceHash -ne $ExpectedSeedSha256) {
    throw "Internal seed-selection failure. Expected $ExpectedSeedSha256, got $seedSourceHash."
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

    $rootLauncher = Join-Path $buildRoot $SeedName
    Copy-Item -LiteralPath $seedSource -Destination $rootLauncher -Force
    $seedBefore = Get-Sha256 $rootLauncher
    if ($seedBefore -ne $ExpectedSeedSha256) {
        throw "Isolated seed copy hash mismatch before build. Expected $ExpectedSeedSha256, got $seedBefore."
    }

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' AOTR 8P ROBUST AUTODETECT V2 - STAGE 2 NON-RELEASE BUILD V3' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host "Builder      : $BuilderPath"
    Write-Host "Builder SHA  : $builderHash" -ForegroundColor Green
    Write-Host "Seed source  : $seedSource"
    Write-Host "Seed SHA256  : $seedSourceHash" -ForegroundColor Green
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

    $seedAfter = Get-Sha256 $rootLauncher
    if ($seedAfter -ne $seedBefore) {
        throw "SAFETY FAILURE: isolated RC4 seed was modified/replaced. Before=$seedBefore After=$seedAfter"
    }

    $bundleRoot = Join-Path $buildRoot '_GITHUB_UPDATE'
    $exe = Join-Path $bundleRoot $SeedName
    $manifest = Join-Path $bundleRoot 'manifest.json'
    $repairManifest = Join-Path $bundleRoot 'repair-manifest.json'

    Assert-Leaf $exe 'Built non-release EXE'
    Assert-Leaf $manifest 'Generated manifest'
    Assert-Leaf $repairManifest 'Generated repair manifest'

    $bytes = [IO.File]::ReadAllBytes($exe)
    if ($bytes.Length -lt 4096 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        throw 'Built bundle EXE is not a valid Windows PE/MZ file.'
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

    if ($exeHash -eq $ExpectedSeedSha256) {
        throw 'Built EXE hash equals the 1.0.9 seed hash; patched build did not produce a distinct executable.'
    }

    $reportPath = Join-Path $buildRoot 'STAGE2_BUILD_REPORT.txt'
    $report = @(
        'AOTR 8P ROBUST AUTODETECT V2 - STAGE 2 BUILD REPORT V3',
        ('Timestamp: ' + (Get-Date -Format o)),
        ('Builder: ' + $BuilderPath),
        ('Builder SHA256: ' + $builderHash),
        ('Seed source: ' + $seedSource),
        ('Seed SHA256 before: ' + $seedBefore),
        ('Seed SHA256 after: ' + $seedAfter),
        ('LauncherVersion: ' + $LauncherVersion),
        ('BuildRoot: ' + $buildRoot),
        ('Bundle EXE: ' + $exe),
        ('Bundle EXE SHA256: ' + $exeHash),
        ('Bundle EXE bytes: ' + $bytes.Length),
        ('Manifest: ' + $manifest),
        ('Repair manifest: ' + $repairManifest),
        ('Isolated seed modified/replaced: NO'),
        ('Real/public launcher modified: NO'),
        ('Original builder modified: NO'),
        ('Update manifest URL: ' + $DeadManifestUrl),
        ('Update binary URL: ' + $DeadBinaryUrl)
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText($reportPath,$report + [Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' STAGE 2 BUILD COMPLETE' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host "Build root  : $buildRoot"
    Write-Host "Seed source : $seedSource"
    Write-Host "Seed SHA256 : $seedBefore" -ForegroundColor Green
    Write-Host "EXE         : $exe"
    Write-Host "EXE SHA256  : $exeHash" -ForegroundColor Green
    Write-Host "EXE bytes   : $($bytes.Length)"
    Write-Host "Report      : $reportPath"
    Write-Host ''
    Write-Host 'Isolated seed modified/replaced: NO' -ForegroundColor Green
    Write-Host 'Real/public launcher modified: NO' -ForegroundColor Green
    Write-Host 'Public release modified: NO' -ForegroundColor Green
    Write-Host 'Test EXE auto-update target: INVALID / SAFE' -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host '[STAGE 2 BUILD FAILED]' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($buildRoot) {
        Write-Host "Partial isolated build root retained for inspection: $buildRoot" -ForegroundColor Yellow
    }
    throw
}
