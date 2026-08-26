#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE3_HASHFIX_V2_20260827_012753\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_HASHFIX_V2_NONRELEASE.ps1',
    [string]$SeedPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\RELEASE_1_0_9_UI_POLISH_20260822_183040\github_repo\AotR 8P WotR Mod.exe',
    [string]$SupportDonorRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\V18_RC1_TEST_20260827_004234',
    [string]$ExpectedAotRRoot = 'D:\Games\AotR\AgeoftheRing',
    [string]$LauncherVersion = '1.0.10-autodetect-v2-hashfix-test'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = 'B244D987A99533DD3A79978032F64C261FF7EBBDDA1AAFA6BB0142FFA9BC2572'
$ExpectedSeedSha256    = '97A8163CA72BDFB5C6C24931E06B2BFCE1D0E33C382FEA2462F73BC80BD3EA9F'
$ExpectedIconSha256    = '3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A'
$ExpectedSkinSha256    = '2158FD8BB4E9195E27667F517FF81C745983BEE200394FB64107FFF902666473'
$ExpectedUiSha256      = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha256   = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
$ExpectedValidation    = 'aotr-standalone-v2'
$DeadManifestUrl = 'https://invalid.invalid/aotr8p-autodetect-v2-hashfix-test/manifest.json'
$DeadBinaryUrl   = 'https://invalid.invalid/aotr8p-autodetect-v2-hashfix-test/AotR%208P%20WotR%20Mod.exe'
$LauncherName = 'AotR 8P WotR Mod.exe'

function Canon([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-Leaf([string]$Path,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label missing: $Path" }
}

function Assert-Container([string]$Path,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "$Label missing: $Path" }
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

$Base = Canon $Base
$BuilderPath = Canon $BuilderPath
$SeedPath = Canon $SeedPath
$SupportDonorRoot = Canon $SupportDonorRoot
$ExpectedAotRRoot = Canon $ExpectedAotRRoot

Assert-Container $Base 'Base work root'
Assert-Container $SupportDonorRoot 'Support donor root'
$builderHashBefore = Assert-Hash $BuilderPath $ExpectedBuilderSha256 'Hash-host-fixed builder'
$seedHashBefore = Assert-Hash $SeedPath $ExpectedSeedSha256 'Public 1.0.9 seed'

$iconSource  = Join-Path $SupportDonorRoot 'assets\launcher.ico'
$skinSource  = Join-Path $SupportDonorRoot 'internal\assets\launcher_skin.png'
$uiSource    = Join-Path $SupportDonorRoot 'payload\!!!WOTR_8P_UI_TEST.big'
$paperSource = Join-Path $SupportDonorRoot 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc'

$iconHashBefore  = Assert-Hash $iconSource  $ExpectedIconSha256  'Donor launcher.ico'
$skinHashBefore  = Assert-Hash $skinSource  $ExpectedSkinSha256  'Donor launcher_skin.png'
$uiHashBefore    = Assert-Hash $uiSource    $ExpectedUiSha256    'Donor UI BIG'
$paperHashBefore = Assert-Hash $paperSource $ExpectedPaperSha256 'Donor PaperScenario001.inc'

$expectedRuntime = Join-Path $ExpectedAotRRoot 'rotwk'
$expectedSourceMod = Join-Path $ExpectedAotRRoot 'aotr'
$expectedRotwkExe = Join-Path $expectedRuntime 'lotrbfme2ep1.exe'
$gameDatDirect = Join-Path $expectedRuntime 'game.dat'
$gameDatZG = Join-Path $expectedRuntime 'zGameDats\game.dat'
Assert-Container $ExpectedAotRRoot 'Expected AotR root'
Assert-Container $expectedRuntime 'Expected rotwk runtime'
Assert-Container $expectedSourceMod 'Expected aotr source mod'
Assert-Leaf $expectedRotwkExe 'Expected RotWK executable'
if (Test-Path -LiteralPath $gameDatDirect -PathType Leaf) { $expectedGameDat = Canon $gameDatDirect }
elseif (Test-Path -LiteralPath $gameDatZG -PathType Leaf) { $expectedGameDat = Canon $gameDatZG }
else { throw "Expected AotR root has no game.dat: $ExpectedAotRRoot" }

$winPS = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
Assert-Leaf $winPS 'Windows PowerShell 5.1 executable'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ("AUTODETECT_V2_STAGE3_V3_" + $stamp)
$buildRoot = Join-Path $workRoot 'BUILD'
$runtimePackage = Join-Path $workRoot 'RUNTIME_PACKAGE'
$isolatedLocalAppData = Join-Path $workRoot 'LOCALAPPDATA'
$buildLog = Join-Path $workRoot 'BUILDER_OUTPUT.log'
$reportPath = Join-Path $workRoot 'STAGE3_V3_REPORT.txt'
New-Item -ItemType Directory -Path $buildRoot,$runtimePackage,$isolatedLocalAppData -Force | Out-Null

$rootSeed = Join-Path $buildRoot $LauncherName
$iconDest = Join-Path $buildRoot 'assets\launcher.ico'
$skinDest = Join-Path $buildRoot 'internal\assets\launcher_skin.png'
$uiDest = Join-Path $buildRoot 'payload\!!!WOTR_8P_UI_TEST.big'
$paperDest = Join-Path $buildRoot 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc'

Copy-VerifiedFile $SeedPath $rootSeed $ExpectedSeedSha256 'isolated RC4 seed'
Copy-VerifiedFile $iconSource $iconDest $ExpectedIconSha256 'launcher.ico'
Copy-VerifiedFile $skinSource $skinDest $ExpectedSkinSha256 'launcher_skin.png'
Copy-VerifiedFile $uiSource $uiDest $ExpectedUiSha256 'UI BIG'
Copy-VerifiedFile $paperSource $paperDest $ExpectedPaperSha256 'PaperScenario001.inc'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P STAGE 3 V3 - HASHFIX BUILD + FRESH SMOKE' -ForegroundColor Cyan
Write-Host ' NON-RELEASE / ISOLATED / NO REAL CONFIG' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Builder       : $BuilderPath"
Write-Host "Builder SHA   : $builderHashBefore" -ForegroundColor Green
Write-Host "Expected AotR : $ExpectedAotRRoot"
Write-Host "Build root    : $buildRoot"
Write-Host "State root    : $isolatedLocalAppData"
Write-Host ''

$builderArgs = @(
    '-NoProfile','-ExecutionPolicy','Bypass','-File',$BuilderPath,
    '-PackageRoot',$buildRoot,
    '-LauncherVersion',$LauncherVersion,
    '-UpdateManifestUrl',$DeadManifestUrl,
    '-UpdateBinaryUrl',$DeadBinaryUrl,
    '-BundleOnly','-EmitGitHubBundle'
)

& $winPS @builderArgs 2>&1 | Tee-Object -FilePath $buildLog
$buildExitCode = $LASTEXITCODE
if ($buildExitCode -ne 0) { throw "Builder failed with exit code $buildExitCode. See $buildLog" }

# Inputs and sources must remain unchanged.
[void](Assert-Hash $rootSeed $ExpectedSeedSha256 'Isolated seed after build')
[void](Assert-Hash $BuilderPath $ExpectedBuilderSha256 'Hash-host-fixed builder after build')
[void](Assert-Hash $SeedPath $ExpectedSeedSha256 'Public 1.0.9 seed after build')
[void](Assert-Hash $iconSource $ExpectedIconSha256 'Donor icon after build')
[void](Assert-Hash $skinSource $ExpectedSkinSha256 'Donor skin after build')
[void](Assert-Hash $uiSource $ExpectedUiSha256 'Donor UI after build')
[void](Assert-Hash $paperSource $ExpectedPaperSha256 'Donor Paper after build')

$bundleRoot = Join-Path $buildRoot '_GITHUB_UPDATE'
$builtExe = Join-Path $bundleRoot $LauncherName
$manifestPath = Join-Path $bundleRoot 'manifest.json'
$repairManifestPath = Join-Path $bundleRoot 'repair-manifest.json'
$bundleUi = Join-Path $bundleRoot 'payload_ui.big'
$bundlePaper = Join-Path $bundleRoot 'payload_paper.inc'
Assert-Leaf $builtExe 'Built hashfix EXE'
Assert-Leaf $manifestPath 'Generated manifest'
Assert-Leaf $repairManifestPath 'Generated repair manifest'
[void](Assert-Hash $bundleUi $ExpectedUiSha256 'Bundled UI')
[void](Assert-Hash $bundlePaper $ExpectedPaperSha256 'Bundled Paper')

$bytes = [IO.File]::ReadAllBytes($builtExe)
if ($bytes.Length -lt 4096 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { throw 'Built EXE is not a valid MZ executable.' }
$peOffset = [BitConverter]::ToInt32($bytes,0x3C)
if ($peOffset -lt 64 -or ($peOffset + 3) -ge $bytes.Length) { throw "Invalid PE offset: $peOffset" }
if ($bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset+1] -ne 0x45 -or $bytes[$peOffset+2] -ne 0 -or $bytes[$peOffset+3] -ne 0) { throw 'Built EXE missing PE signature.' }
$builtHash = Get-Sha256 $builtExe
if ($builtHash -eq $ExpectedSeedSha256) { throw 'Built EXE equals seed hash.' }

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ([string]$manifest.launcher_version -ne $LauncherVersion) { throw "Manifest version mismatch: $($manifest.launcher_version)" }
if ([string]$manifest.launcher_url -ne $DeadBinaryUrl) { throw "Manifest launcher URL is not safe/dead: $($manifest.launcher_url)" }
if ([string]$manifest.launcher_sha256 -ne $builtHash) { throw 'Manifest EXE hash does not match built EXE.' }
if ([string]$manifest.ui_sha256 -ne $ExpectedUiSha256) { throw 'Manifest UI hash mismatch.' }
if ([string]$manifest.paper_sha256 -ne $ExpectedPaperSha256) { throw 'Manifest Paper hash mismatch.' }

Write-Host ''
Write-Host '=== BUILD VERIFIED ===' -ForegroundColor Green
Write-Host "Built EXE     : $builtExe"
Write-Host "Built SHA256  : $builtHash" -ForegroundColor Green
Write-Host "Built bytes   : $($bytes.Length)"
Write-Host ''

# Construct the exact package layout expected by the embedded GUI.
$runtimeExe = Join-Path $runtimePackage $LauncherName
Copy-Item -LiteralPath $builtExe -Destination $runtimeExe -Force
[void](Assert-Hash $runtimeExe $builtHash 'Runtime test EXE')
Copy-VerifiedFile $iconSource (Join-Path $runtimePackage 'assets\launcher.ico') $ExpectedIconSha256 'runtime launcher.ico'
Copy-VerifiedFile $skinSource (Join-Path $runtimePackage 'internal\assets\launcher_skin.png') $ExpectedSkinSha256 'runtime launcher_skin.png'
Copy-VerifiedFile $uiSource (Join-Path $runtimePackage 'payload\!!!WOTR_8P_UI_TEST.big') $ExpectedUiSha256 'runtime UI BIG'
Copy-VerifiedFile $paperSource (Join-Path $runtimePackage 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc') $ExpectedPaperSha256 'runtime PaperScenario'
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $runtimePackage 'manifest.json') -Force
Copy-Item -LiteralPath $repairManifestPath -Destination (Join-Path $runtimePackage 'repair-manifest.json') -Force

$oldLocalAppData = $env:LOCALAPPDATA
$oldAotrHomeExists = Test-Path Env:AOTR_HOME
$oldAotrHome = if ($oldAotrHomeExists) { $env:AOTR_HOME } else { $null }

Write-Host '============================================================' -ForegroundColor Yellow
Write-Host ' FRESH GUI SMOKE TEST STARTING' -ForegroundColor Yellow
Write-Host '============================================================' -ForegroundColor Yellow
Write-Host 'When the launcher appears:' -ForegroundColor Yellow
Write-Host '  - Do NOT browse to AotR manually.' -ForegroundColor Yellow
Write-Host '  - Do NOT click START.' -ForegroundColor Yellow
Write-Host '  - Check whether the previous game.dat not found / A8P-INSTALL-001 error is gone.' -ForegroundColor Yellow
Write-Host '  - Then close the launcher with X.' -ForegroundColor Yellow
Write-Host ''

try {
    $env:LOCALAPPDATA = $isolatedLocalAppData
    Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue
    $p = Start-Process -FilePath $runtimeExe -WorkingDirectory $runtimePackage -PassThru
    Write-Host ("Launcher PID: " + $p.Id)
    $p.WaitForExit()
    Write-Host ("Launcher exit code: " + $p.ExitCode)
}
finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if ($oldAotrHomeExists) { $env:AOTR_HOME = $oldAotrHome }
    else { Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue }
}

$configs = @(Get-ChildItem -LiteralPath $isolatedLocalAppData -Recurse -File -Filter 'launcher_config.json' -ErrorAction SilentlyContinue)
if ($configs.Count -ne 1) { throw "Expected exactly one isolated launcher_config.json; found $($configs.Count). Work root: $workRoot" }
$configPath = $configs[0].FullName
$configRaw = Get-Content -LiteralPath $configPath -Raw
$config = $configRaw | ConvertFrom-Json

$failures = New-Object System.Collections.Generic.List[string]
if ([int]$config.schema -ne 2) { [void]$failures.Add("schema expected 2, got '$($config.schema)'") }
if ([string]$config.validation -ne $ExpectedValidation) { [void]$failures.Add("validation mismatch: '$($config.validation)'") }
if ((Canon ([string]$config.aotr_root)) -ne $ExpectedAotRRoot) { [void]$failures.Add("aotr_root mismatch: '$($config.aotr_root)'") }
if ((Canon ([string]$config.runtime)) -ne (Canon $expectedRuntime)) { [void]$failures.Add("runtime mismatch: '$($config.runtime)'") }
if ((Canon ([string]$config.source_mod)) -ne (Canon $expectedSourceMod)) { [void]$failures.Add("source_mod mismatch: '$($config.source_mod)'") }
if ((Canon ([string]$config.game_dat)) -ne $expectedGameDat) { [void]$failures.Add("game_dat mismatch: '$($config.game_dat)'") }
if ([string]::IsNullOrWhiteSpace([string]$config.last_verified_utc)) { [void]$failures.Add('last_verified_utc empty') }

$launcherLog = Join-Path $isolatedLocalAppData 'AotR 8P WotR Mod\launcher_current.log'
$logText = ''
if (Test-Path -LiteralPath $launcherLog -PathType Leaf) { $logText = Get-Content -LiteralPath $launcherLog -Raw -ErrorAction SilentlyContinue }
$hasGetFileHashFailure = $logText -match '(?i)Get-FileHash.*not recognized|Benennung\s+"?Get-FileHash'
if ($hasGetFileHashFailure) { [void]$failures.Add('launcher log still contains Get-FileHash command-not-found evidence') }

$report = @(
    'AOTR 8P STAGE 3 V3 - HASHFIX BUILD + FRESH SMOKE',
    ('Timestamp: ' + (Get-Date -Format o)),
    ('Builder: ' + $BuilderPath),
    ('Builder SHA256: ' + $builderHashBefore),
    ('Built EXE: ' + $builtExe),
    ('Built EXE SHA256: ' + $builtHash),
    ('Built EXE bytes: ' + $bytes.Length),
    ('Expected AotR root: ' + $ExpectedAotRRoot),
    ('Config: ' + $configPath),
    ('Config aotr_root: ' + [string]$config.aotr_root),
    ('Config runtime: ' + [string]$config.runtime),
    ('Config source_mod: ' + [string]$config.source_mod),
    ('Config game_dat: ' + [string]$config.game_dat),
    ('Config score: ' + [string]$config.score),
    ('Get-FileHash command-not-found in isolated log: ' + $hasGetFileHashFailure),
    ('Failure count: ' + $failures.Count),
    ('Public release modified: NO'),
    ('Real launcher config modified: NO'),
    ('AOTR_HOME used: NO'),
    ('Update URL: ' + $DeadBinaryUrl)
) -join [Environment]::NewLine
[IO.File]::WriteAllText($reportPath,$report+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))

Write-Host ''
Write-Host '=== CONFIG V2 ===' -ForegroundColor Cyan
Write-Host $configRaw
Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host 'STAGE 3 V3 RESULT: FAIL' -ForegroundColor Red
    foreach ($f in $failures) { Write-Host ("  - " + $f) -ForegroundColor Red }
    Write-Host "Work root retained: $workRoot" -ForegroundColor Yellow
    exit 5
}

Write-Host '============================================================' -ForegroundColor Green
Write-Host ' STAGE 3 V3 HASHFIX + FRESH DISCOVERY PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host "Built EXE SHA256 : $builtHash" -ForegroundColor Green
Write-Host "Canonical root   : $($config.aotr_root)" -ForegroundColor Green
Write-Host "Runtime          : $($config.runtime)"
Write-Host "Source mod       : $($config.source_mod)"
Write-Host "Game dat         : $($config.game_dat)"
Write-Host "Score            : $($config.score)"
Write-Host "Config path      : $configPath"
Write-Host "Launcher log     : $launcherLog"
Write-Host "Report           : $reportPath"
Write-Host "Work root        : $workRoot"
Write-Host ''
Write-Host 'Get-FileHash host failure in log: NO' -ForegroundColor Green
Write-Host 'Fresh standalone discovery       : PASS' -ForegroundColor Green
Write-Host 'Real launcher config modified    : NO' -ForegroundColor Green
Write-Host 'Public/release EXE modified      : NO' -ForegroundColor Green
Write-Host 'AOTR_HOME used                   : NO' -ForegroundColor Green
Write-Host 'Test auto-update target          : INVALID / SAFE' -ForegroundColor Green
