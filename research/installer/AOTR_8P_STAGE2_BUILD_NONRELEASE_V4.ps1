#requires -version 5.1
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE1_20260827_003823\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_NONRELEASE.ps1',
    [string]$SeedPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\RELEASE_1_0_9_UI_POLISH_20260822_183040\github_repo\AotR 8P WotR Mod.exe',
    [string]$SupportDonorRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\V18_RC1_TEST_20260827_004234',
    [string]$LauncherVersion = '1.0.10-autodetect-v2-test'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = '6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386'
$ExpectedSeedSha256    = '97A8163CA72BDFB5C6C24931E06B2BFCE1D0E33C382FEA2462F73BC80BD3EA9F'
$ExpectedIconSha256    = '3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A'
$ExpectedSkinSha256    = '2158FD8BB4E9195E27667F517FF81C745983BEE200394FB64107FFF902666473'
$ExpectedUiSha256      = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha256   = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'

$DeadManifestUrl = 'https://invalid.invalid/aotr8p-autodetect-v2-test/manifest.json'
$DeadBinaryUrl   = 'https://invalid.invalid/aotr8p-autodetect-v2-test/AotR%208P%20WotR%20Mod.exe'
$LauncherName = 'AotR 8P WotR Mod.exe'

function Assert-Leaf([string]$Path,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label missing: $Path" }
}

function Assert-Container([string]$Path,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "$Label missing: $Path" }
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-Hash([string]$Path,[string]$Expected,[string]$Label) {
    Assert-Leaf $Path $Label
    $actual = Get-Sha256 $Path
    if ($actual -ne $Expected) {
        throw "$Label checkpoint mismatch. Expected $Expected, got $actual. Path: $Path"
    }
    return $actual
}

function Copy-VerifiedFile([string]$Source,[string]$Destination,[string]$Expected,[string]$Label) {
    [void](Assert-Hash $Source $Expected ("Source " + $Label))
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    [void](Assert-Hash $Destination $Expected ("Copied " + $Label))
}

$BuilderPath = [IO.Path]::GetFullPath($BuilderPath)
$SeedPath = [IO.Path]::GetFullPath($SeedPath)
$SupportDonorRoot = [IO.Path]::GetFullPath($SupportDonorRoot)
$Base = [IO.Path]::GetFullPath($Base)

Assert-Container $Base 'Base work root'
Assert-Container $SupportDonorRoot 'Support donor root'
$builderHashBefore = Assert-Hash $BuilderPath $ExpectedBuilderSha256 'Stage-1 patched builder'
$seedSourceHashBefore = Assert-Hash $SeedPath $ExpectedSeedSha256 'Public 1.0.9 seed'

$iconSource  = Join-Path $SupportDonorRoot 'assets\launcher.ico'
$skinSource  = Join-Path $SupportDonorRoot 'internal\assets\launcher_skin.png'
$uiSource    = Join-Path $SupportDonorRoot 'payload\!!!WOTR_8P_UI_TEST.big'
$paperSource = Join-Path $SupportDonorRoot 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc'

$iconHashBefore  = Assert-Hash $iconSource  $ExpectedIconSha256  'Donor launcher.ico'
$skinHashBefore  = Assert-Hash $skinSource  $ExpectedSkinSha256  'Donor launcher_skin.png'
$uiHashBefore    = Assert-Hash $uiSource    $ExpectedUiSha256    'Donor UI BIG'
$paperHashBefore = Assert-Hash $paperSource $ExpectedPaperSha256 'Donor PaperScenario001.inc'

$winPS = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
Assert-Leaf $winPS 'Windows PowerShell 5.1 executable'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$buildRoot = Join-Path $Base ("AUTODETECT_V2_STAGE2_V4_BUILD_" + $stamp)
if (Test-Path -LiteralPath $buildRoot) {
    throw "Refusing to reuse build root: $buildRoot"
}
New-Item -ItemType Directory -Path $buildRoot | Out-Null

$rootSeed = Join-Path $buildRoot $LauncherName
$iconDest = Join-Path $buildRoot 'assets\launcher.ico'
$skinDest = Join-Path $buildRoot 'internal\assets\launcher_skin.png'
$uiDest = Join-Path $buildRoot 'payload\!!!WOTR_8P_UI_TEST.big'
$paperDest = Join-Path $buildRoot 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc'
$buildLog = Join-Path $buildRoot 'STAGE2_V4_BUILDER_OUTPUT.log'
$reportPath = Join-Path $buildRoot 'STAGE2_V4_BUILD_REPORT.txt'

try {
    Copy-VerifiedFile $SeedPath $rootSeed $ExpectedSeedSha256 'isolated RC4 seed'
    Copy-VerifiedFile $iconSource $iconDest $ExpectedIconSha256 'launcher.ico'
    Copy-VerifiedFile $skinSource $skinDest $ExpectedSkinSha256 'launcher_skin.png'
    Copy-VerifiedFile $uiSource $uiDest $ExpectedUiSha256 'UI BIG'
    Copy-VerifiedFile $paperSource $paperDest $ExpectedPaperSha256 'PaperScenario001.inc'

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' AOTR 8P ROBUST AUTODETECT V2 - STAGE 2 BUILD V4' -ForegroundColor Cyan
    Write-Host ' HASH-PINNED / ISOLATED / NON-RELEASE' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ('Builder      : ' + $BuilderPath)
    Write-Host ('Builder SHA  : ' + $builderHashBefore) -ForegroundColor Green
    Write-Host ('Seed         : ' + $SeedPath)
    Write-Host ('Seed SHA     : ' + $seedSourceHashBefore) -ForegroundColor Green
    Write-Host ('Support donor: ' + $SupportDonorRoot)
    Write-Host ('Icon SHA     : ' + $iconHashBefore) -ForegroundColor Green
    Write-Host ('Skin SHA     : ' + $skinHashBefore) -ForegroundColor Green
    Write-Host ('UI SHA       : ' + $uiHashBefore) -ForegroundColor Green
    Write-Host ('Paper SHA    : ' + $paperHashBefore) -ForegroundColor Green
    Write-Host ('Build root   : ' + $buildRoot)
    Write-Host ('PowerShell   : ' + $winPS)
    Write-Host ('Version      : ' + $LauncherVersion)
    Write-Host 'BundleOnly   : TRUE'
    Write-Host 'Emit bundle  : TRUE (isolated local build root only)'
    Write-Host 'Update URLs  : intentionally invalid for test safety'
    Write-Host ''

    $builderArgs = @(
        '-NoProfile',
        '-ExecutionPolicy','Bypass',
        '-File',$BuilderPath,
        '-PackageRoot',$buildRoot,
        '-LauncherVersion',$LauncherVersion,
        '-UpdateManifestUrl',$DeadManifestUrl,
        '-UpdateBinaryUrl',$DeadBinaryUrl,
        '-BundleOnly',
        '-EmitGitHubBundle'
    )

    & $winPS @builderArgs 2>&1 | Tee-Object -FilePath $buildLog
    $buildExitCode = $LASTEXITCODE
    if ($buildExitCode -ne 0) {
        throw "Windows PowerShell builder exited with code $buildExitCode. See $buildLog"
    }

    # The isolated seed is a required input only. BundleOnly must not replace it.
    $seedCopyHashAfter = Assert-Hash $rootSeed $ExpectedSeedSha256 'Isolated RC4 seed after build'

    # Source checkpoints must remain byte-identical.
    $builderHashAfter = Assert-Hash $BuilderPath $ExpectedBuilderSha256 'Stage-1 patched builder after build'
    $seedSourceHashAfter = Assert-Hash $SeedPath $ExpectedSeedSha256 'Public 1.0.9 seed after build'
    $iconHashAfter  = Assert-Hash $iconSource  $ExpectedIconSha256  'Donor launcher.ico after build'
    $skinHashAfter  = Assert-Hash $skinSource  $ExpectedSkinSha256  'Donor launcher_skin.png after build'
    $uiHashAfter    = Assert-Hash $uiSource    $ExpectedUiSha256    'Donor UI BIG after build'
    $paperHashAfter = Assert-Hash $paperSource $ExpectedPaperSha256 'Donor PaperScenario001.inc after build'

    $bundleRoot = Join-Path $buildRoot '_GITHUB_UPDATE'
    $builtExe = Join-Path $bundleRoot $LauncherName
    $manifestPath = Join-Path $bundleRoot 'manifest.json'
    $repairManifestPath = Join-Path $bundleRoot 'repair-manifest.json'
    $bundleUi = Join-Path $bundleRoot 'payload_ui.big'
    $bundlePaper = Join-Path $bundleRoot 'payload_paper.inc'

    Assert-Leaf $builtExe 'Built non-release EXE'
    Assert-Leaf $manifestPath 'Generated manifest'
    Assert-Leaf $repairManifestPath 'Generated repair manifest'
    [void](Assert-Hash $bundleUi $ExpectedUiSha256 'Bundled UI payload')
    [void](Assert-Hash $bundlePaper $ExpectedPaperSha256 'Bundled Paper payload')

    $bytes = [IO.File]::ReadAllBytes($builtExe)
    if ($bytes.Length -lt 4096 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        throw 'Built EXE is not a valid MZ executable.'
    }
    $peOffset = [BitConverter]::ToInt32($bytes,0x3C)
    if ($peOffset -lt 64 -or ($peOffset + 3) -ge $bytes.Length) {
        throw "Built EXE has invalid PE header offset: $peOffset"
    }
    if ($bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset+1] -ne 0x45 -or $bytes[$peOffset+2] -ne 0x00 -or $bytes[$peOffset+3] -ne 0x00) {
        throw 'Built EXE is missing PE signature.'
    }

    $builtHash = Get-Sha256 $builtExe
    if ($builtHash -eq $ExpectedSeedSha256) {
        throw 'Built EXE equals the 1.0.9 seed hash; patched build did not produce a distinct executable.'
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ([string]$manifest.launcher_version -ne $LauncherVersion) {
        throw "Manifest launcher_version mismatch. Expected $LauncherVersion, got $($manifest.launcher_version)"
    }
    if ([string]$manifest.launcher_url -ne $DeadBinaryUrl) {
        throw "Manifest launcher_url is not the intentionally invalid test URL: $($manifest.launcher_url)"
    }
    if ([string]$manifest.launcher_sha256 -ne $builtHash) {
        throw "Manifest launcher SHA mismatch. Manifest=$($manifest.launcher_sha256) Actual=$builtHash"
    }
    if ([string]$manifest.ui_sha256 -ne $ExpectedUiSha256) {
        throw "Manifest UI SHA mismatch: $($manifest.ui_sha256)"
    }
    if ([string]$manifest.paper_sha256 -ne $ExpectedPaperSha256) {
        throw "Manifest Paper SHA mismatch: $($manifest.paper_sha256)"
    }

    $report = @(
        'AOTR 8P ROBUST AUTODETECT V2 - STAGE 2 V4 BUILD REPORT',
        ('Timestamp: ' + (Get-Date -Format o)),
        ('Builder: ' + $BuilderPath),
        ('Builder SHA256 before: ' + $builderHashBefore),
        ('Builder SHA256 after: ' + $builderHashAfter),
        ('Seed source: ' + $SeedPath),
        ('Seed SHA256 before: ' + $seedSourceHashBefore),
        ('Seed SHA256 after: ' + $seedSourceHashAfter),
        ('Support donor: ' + $SupportDonorRoot),
        ('Icon SHA256 before/after: ' + $iconHashBefore + ' / ' + $iconHashAfter),
        ('Skin SHA256 before/after: ' + $skinHashBefore + ' / ' + $skinHashAfter),
        ('UI SHA256 before/after: ' + $uiHashBefore + ' / ' + $uiHashAfter),
        ('Paper SHA256 before/after: ' + $paperHashBefore + ' / ' + $paperHashAfter),
        ('LauncherVersion: ' + $LauncherVersion),
        ('Build root: ' + $buildRoot),
        ('Builder log: ' + $buildLog),
        ('Isolated seed SHA256 after: ' + $seedCopyHashAfter),
        ('Bundle EXE: ' + $builtExe),
        ('Bundle EXE SHA256: ' + $builtHash),
        ('Bundle EXE bytes: ' + $bytes.Length),
        ('Manifest: ' + $manifestPath),
        ('Repair manifest: ' + $repairManifestPath),
        ('Windows PowerShell exit code: ' + $buildExitCode),
        ('BundleOnly: TRUE'),
        ('EmitGitHubBundle: TRUE'),
        ('Real/public launcher modified: NO'),
        ('Original builder modified: NO'),
        ('Support donor modified: NO'),
        ('Update manifest URL: ' + $DeadManifestUrl),
        ('Update binary URL: ' + $DeadBinaryUrl)
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText($reportPath,$report + [Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' STAGE 2 V4 BUILD COMPLETE' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ('Build root  : ' + $buildRoot)
    Write-Host ('EXE         : ' + $builtExe)
    Write-Host ('EXE SHA256  : ' + $builtHash) -ForegroundColor Green
    Write-Host ('EXE bytes   : ' + $bytes.Length)
    Write-Host ('Builder log : ' + $buildLog)
    Write-Host ('Report      : ' + $reportPath)
    Write-Host ''
    Write-Host 'Isolated seed modified/replaced: NO' -ForegroundColor Green
    Write-Host 'Real/public launcher modified: NO' -ForegroundColor Green
    Write-Host 'Support donor modified: NO' -ForegroundColor Green
    Write-Host 'Public release modified: NO' -ForegroundColor Green
    Write-Host 'Test EXE auto-update target: INVALID / SAFE' -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host '[STAGE 2 V4 BUILD FAILED]' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ('Partial isolated build root retained for inspection: ' + $buildRoot) -ForegroundColor Yellow
    throw
}
