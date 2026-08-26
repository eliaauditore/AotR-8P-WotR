#requires -version 7.0
[CmdletBinding()]
param(
    [string]$BuildRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE2_V4_BUILD_20260827_010245',
    [string]$ExpectedAotRRoot = 'D:\Games\AotR\AgeoftheRing'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedExeSha256 = '0EE6D45F01270F6C81DF2D5A828FE373C66202806EC742FDF7B9C64F6FBA7F0B'
$ExpectedIconSha256 = '3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A'
$ExpectedSkinSha256 = '2158FD8BB4E9195E27667F517FF81C745983BEE200394FB64107FFF902666473'
$ExpectedUiSha256 = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha256 = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
$ExpectedValidation = 'aotr-standalone-v2'
$ExeName = 'AotR 8P WotR Mod.exe'

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Canon([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
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
        throw "$Label checkpoint mismatch. Expected $Expected, got $actual. Path=$Path"
    }
    return $actual
}

$BuildRoot = Canon $BuildRoot
$ExpectedAotRRoot = Canon $ExpectedAotRRoot
Assert-Container $BuildRoot 'Stage-2 V4 build root'

$bundleRoot = Join-Path $BuildRoot '_GITHUB_UPDATE'
$builtExe = Join-Path $bundleRoot $ExeName
$sourceIcon = Join-Path $BuildRoot 'assets\launcher.ico'
$sourceSkin = Join-Path $BuildRoot 'internal\assets\launcher_skin.png'
$sourceUi = Join-Path $BuildRoot 'payload\!!!WOTR_8P_UI_TEST.big'
$sourcePaper = Join-Path $BuildRoot 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc'
$sourceManifest = Join-Path $bundleRoot 'manifest.json'
$sourceRepairManifest = Join-Path $bundleRoot 'repair-manifest.json'

$exeHash = Assert-Hash $builtExe $ExpectedExeSha256 'Robust Autodetect V2 test EXE'
[void](Assert-Hash $sourceIcon $ExpectedIconSha256 'launcher.ico')
[void](Assert-Hash $sourceSkin $ExpectedSkinSha256 'launcher_skin.png')
[void](Assert-Hash $sourceUi $ExpectedUiSha256 'UI payload')
[void](Assert-Hash $sourcePaper $ExpectedPaperSha256 'PaperScenario payload')
Assert-Leaf $sourceManifest 'Generated manifest'
Assert-Leaf $sourceRepairManifest 'Generated repair manifest'

$expectedRuntime = Join-Path $ExpectedAotRRoot 'rotwk'
$expectedSourceMod = Join-Path $ExpectedAotRRoot 'aotr'
$expectedExe = Join-Path $expectedRuntime 'lotrbfme2ep1.exe'
$gameDatDirect = Join-Path $expectedRuntime 'game.dat'
$gameDatZG = Join-Path $expectedRuntime 'zGameDats\game.dat'

Assert-Container $ExpectedAotRRoot 'Expected AotR root'
Assert-Container $expectedRuntime 'Expected rotwk runtime'
Assert-Container $expectedSourceMod 'Expected aotr source mod'
Assert-Leaf $expectedExe 'Expected RotWK executable'
if (Test-Path -LiteralPath $gameDatDirect -PathType Leaf) {
    $expectedGameDat = Canon $gameDatDirect
}
elseif (Test-Path -LiteralPath $gameDatZG -PathType Leaf) {
    $expectedGameDat = Canon $gameDatZG
}
else {
    throw "Expected AotR root has no game.dat in rotwk or rotwk\zGameDats: $ExpectedAotRRoot"
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$isolationRoot = Join-Path $env:TEMP ("AOTR8P_STAGE3_FRESH_DISCOVERY_V2_" + $stamp)
$packageRoot = Join-Path $isolationRoot 'PACKAGE'
$isolatedLocalAppData = Join-Path $isolationRoot 'LOCALAPPDATA'
New-Item -ItemType Directory -Force -Path $packageRoot,$isolatedLocalAppData | Out-Null

# Build a complete disposable runtime package. Nothing in BuildRoot is modified.
Copy-Item -LiteralPath (Join-Path $BuildRoot 'assets') -Destination (Join-Path $packageRoot 'assets') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $BuildRoot 'internal') -Destination (Join-Path $packageRoot 'internal') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $BuildRoot 'payload') -Destination (Join-Path $packageRoot 'payload') -Recurse -Force
Copy-Item -LiteralPath $sourceManifest -Destination (Join-Path $packageRoot 'manifest.json') -Force
Copy-Item -LiteralPath $sourceRepairManifest -Destination (Join-Path $packageRoot 'repair-manifest.json') -Force
Copy-Item -LiteralPath $builtExe -Destination (Join-Path $packageRoot $ExeName) -Force

$testExe = Join-Path $packageRoot $ExeName
$testIcon = Join-Path $packageRoot 'assets\launcher.ico'
$testSkin = Join-Path $packageRoot 'internal\assets\launcher_skin.png'
$testUi = Join-Path $packageRoot 'payload\!!!WOTR_8P_UI_TEST.big'
$testPaper = Join-Path $packageRoot 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc'

[void](Assert-Hash $testExe $ExpectedExeSha256 'Disposable test EXE')
[void](Assert-Hash $testIcon $ExpectedIconSha256 'Disposable launcher.ico')
[void](Assert-Hash $testSkin $ExpectedSkinSha256 'Disposable launcher_skin.png')
[void](Assert-Hash $testUi $ExpectedUiSha256 'Disposable UI payload')
[void](Assert-Hash $testPaper $ExpectedPaperSha256 'Disposable PaperScenario payload')

$oldLocalAppData = $env:LOCALAPPDATA
$oldAotrHomeExists = Test-Path Env:AOTR_HOME
$oldAotrHome = if ($oldAotrHomeExists) { $env:AOTR_HOME } else { $null }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P ROBUST AUTODETECT V2 - STAGE 3 FRESH DISCOVERY V2' -ForegroundColor Cyan
Write-Host ' COMPLETE DISPOSABLE RUNTIME / ISOLATED LOCALAPPDATA' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Source build root : $BuildRoot"
Write-Host "Runtime package   : $packageRoot"
Write-Host "Test EXE          : $testExe"
Write-Host "EXE SHA256        : $exeHash" -ForegroundColor Green
Write-Host "Expected root     : $ExpectedAotRRoot"
Write-Host "Expected runtime  : $expectedRuntime"
Write-Host "Expected mod      : $expectedSourceMod"
Write-Host "Expected game.dat : $expectedGameDat"
Write-Host "Isolated state    : $isolatedLocalAppData"
Write-Host ''
Write-Host 'When the launcher window appears:' -ForegroundColor Yellow
Write-Host '  1. Let it finish opening.' -ForegroundColor Yellow
Write-Host '  2. Do NOT manually browse to the AotR folder.' -ForegroundColor Yellow
Write-Host '  3. Do NOT click START yet.' -ForegroundColor Yellow
Write-Host '  4. If it opens normally without asking for a folder, close the launcher.' -ForegroundColor Yellow
Write-Host '  5. If it asks for a folder or shows an A8P-INSTALL error, note the exact message, then close it.' -ForegroundColor Yellow
Write-Host ''

try {
    $env:LOCALAPPDATA = $isolatedLocalAppData
    Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue

    $p = Start-Process -FilePath $testExe -WorkingDirectory $packageRoot -PassThru
    Write-Host ("Launcher PID: " + $p.Id)
    $p.WaitForExit()
    Write-Host ("Launcher exit code: " + $p.ExitCode)
}
finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if ($oldAotrHomeExists) {
        $env:AOTR_HOME = $oldAotrHome
    }
    else {
        Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue
    }
}

$configs = @(
    Get-ChildItem -LiteralPath $isolatedLocalAppData -Recurse -File -Filter 'launcher_config.json' -ErrorAction SilentlyContinue
)

Write-Host ''
Write-Host '=== ISOLATED CONFIG DISCOVERY ===' -ForegroundColor Cyan
if ($configs.Count -eq 0) {
    Write-Host 'No launcher_config.json was written below isolated LOCALAPPDATA.' -ForegroundColor Red
    Write-Host "Isolation root retained: $isolationRoot" -ForegroundColor Yellow
    Write-Host 'RESULT: FAIL / NEED RUNTIME DIAGNOSIS' -ForegroundColor Red
    exit 2
}

foreach ($cfg in $configs) {
    Write-Host ("Config: " + $cfg.FullName)
}

if ($configs.Count -ne 1) {
    Write-Host "Expected exactly one launcher_config.json, found $($configs.Count)." -ForegroundColor Red
    Write-Host "Isolation root retained: $isolationRoot" -ForegroundColor Yellow
    exit 3
}

$configPath = $configs[0].FullName
$configRaw = Get-Content -LiteralPath $configPath -Raw
try {
    $config = $configRaw | ConvertFrom-Json
}
catch {
    Write-Host 'Config is not valid JSON.' -ForegroundColor Red
    Write-Host $configRaw
    Write-Host "Isolation root retained: $isolationRoot" -ForegroundColor Yellow
    exit 4
}

Write-Host ''
Write-Host '=== CONFIG V2 VALIDATION ===' -ForegroundColor Cyan
Write-Host $configRaw

$failures = [System.Collections.Generic.List[string]]::new()
if ([int]$config.schema -ne 2) { [void]$failures.Add("schema expected 2, got '$($config.schema)'") }
if ([string]$config.validation -ne $ExpectedValidation) { [void]$failures.Add("validation expected '$ExpectedValidation', got '$($config.validation)'") }
if ((Canon ([string]$config.aotr_root)) -ne $ExpectedAotRRoot) { [void]$failures.Add("aotr_root mismatch: '$($config.aotr_root)'") }
if ((Canon ([string]$config.runtime)) -ne (Canon $expectedRuntime)) { [void]$failures.Add("runtime mismatch: '$($config.runtime)'") }
if ((Canon ([string]$config.source_mod)) -ne (Canon $expectedSourceMod)) { [void]$failures.Add("source_mod mismatch: '$($config.source_mod)'") }
if ((Canon ([string]$config.game_dat)) -ne $expectedGameDat) { [void]$failures.Add("game_dat mismatch: '$($config.game_dat)'") }
if ([string]::IsNullOrWhiteSpace([string]$config.last_verified_utc)) { [void]$failures.Add('last_verified_utc is empty') }

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host 'RESULT: FAIL' -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host ("  - " + $failure) -ForegroundColor Red
    }
    Write-Host "Isolation root retained: $isolationRoot" -ForegroundColor Yellow
    exit 5
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' STAGE 3 FRESH DISCOVERY SMOKE TEST PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host "Canonical root : $($config.aotr_root)" -ForegroundColor Green
Write-Host "Runtime        : $($config.runtime)"
Write-Host "Source mod     : $($config.source_mod)"
Write-Host "Game dat       : $($config.game_dat)"
Write-Host "Score          : $($config.score)"
Write-Host "Verified UTC   : $($config.last_verified_utc)"
Write-Host "Config path    : $configPath"
Write-Host "Runtime package: $packageRoot"
Write-Host "Isolation root : $isolationRoot"
Write-Host ''
Write-Host 'Stage-2 build modified: NO' -ForegroundColor Green
Write-Host 'Real launcher config modified: NO' -ForegroundColor Green
Write-Host 'AOTR_HOME used: NO' -ForegroundColor Green
Write-Host 'Manual folder selection used: NO' -ForegroundColor Green
Write-Host 'Fresh standalone discovery: PASS' -ForegroundColor Green
