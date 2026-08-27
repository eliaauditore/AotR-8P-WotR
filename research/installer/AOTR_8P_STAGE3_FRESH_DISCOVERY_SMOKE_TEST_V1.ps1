#requires -version 7.0
[CmdletBinding()]
param(
    [string]$TestExe = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE2_V4_BUILD_20260827_010245\_GITHUB_UPDATE\AotR 8P WotR Mod.exe',
    [string]$ExpectedAotRRoot = 'D:\Games\AotR\AgeoftheRing'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedExeSha256 = '0EE6D45F01270F6C81DF2D5A828FE373C66202806EC742FDF7B9C64F6FBA7F0B'
$ExpectedValidation = 'aotr-standalone-v2'

function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Canon([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Assert-Leaf([string]$Path,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label missing: $Path" }
}

function Assert-Container([string]$Path,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "$Label missing: $Path" }
}

$TestExe = Canon $TestExe
$ExpectedAotRRoot = Canon $ExpectedAotRRoot
Assert-Leaf $TestExe 'Robust Autodetect V2 test EXE'
$exeHash = Get-Sha256 $TestExe
if ($exeHash -ne $ExpectedExeSha256) {
    throw "Test EXE checkpoint mismatch. Expected $ExpectedExeSha256, got $exeHash."
}

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
$isolationRoot = Join-Path $env:TEMP ("AOTR8P_STAGE3_FRESH_DISCOVERY_" + $stamp)
$isolatedLocalAppData = Join-Path $isolationRoot 'LOCALAPPDATA'
New-Item -ItemType Directory -Force -Path $isolatedLocalAppData | Out-Null

$oldLocalAppData = $env:LOCALAPPDATA
$oldAotrHomeExists = Test-Path Env:AOTR_HOME
$oldAotrHome = if ($oldAotrHomeExists) { $env:AOTR_HOME } else { $null }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P ROBUST AUTODETECT V2 - STAGE 3 FRESH DISCOVERY' -ForegroundColor Cyan
Write-Host ' ISOLATED LOCALAPPDATA / REAL CONFIG UNTOUCHED' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Test EXE        : $TestExe"
Write-Host "EXE SHA256      : $exeHash" -ForegroundColor Green
Write-Host "Expected root   : $ExpectedAotRRoot"
Write-Host "Expected runtime: $expectedRuntime"
Write-Host "Expected mod    : $expectedSourceMod"
Write-Host "Expected game.dat: $expectedGameDat"
Write-Host "Isolated state  : $isolatedLocalAppData"
Write-Host ''
Write-Host 'When the launcher window appears:' -ForegroundColor Yellow
Write-Host '  1. Let it finish opening.' -ForegroundColor Yellow
Write-Host '  2. Do NOT manually browse to the AotR folder.' -ForegroundColor Yellow
Write-Host '  3. Do NOT click START yet.' -ForegroundColor Yellow
Write-Host '  4. If it opens normally without asking for a folder, close the launcher.' -ForegroundColor Yellow
Write-Host '  5. If it asks for a folder or shows an A8P-INSTALL error, leave it visible, note the exact message, then close it.' -ForegroundColor Yellow
Write-Host ''

try {
    $env:LOCALAPPDATA = $isolatedLocalAppData
    Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue

    $p = Start-Process -FilePath $TestExe -WorkingDirectory (Split-Path $TestExe -Parent) -PassThru
    Write-Host ("Launcher PID: " + $p.Id)
    $p.WaitForExit()
    Write-Host ("Launcher exit code: " + $p.ExitCode)
}
finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if ($oldAotrHomeExists) {
        $env:AOTR_HOME = $oldAotrHome
    } else {
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
} catch {
    Write-Host 'Config is not valid JSON.' -ForegroundColor Red
    Write-Host $configRaw
    Write-Host "Isolation root retained: $isolationRoot" -ForegroundColor Yellow
    exit 4
}

Write-Host ''
Write-Host '=== CONFIG V2 VALIDATION ===' -ForegroundColor Cyan
Write-Host $configRaw

$failures = New-Object System.Collections.Generic.List[string]
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
    foreach ($f in $failures) { Write-Host ("  - " + $f) -ForegroundColor Red }
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
Write-Host "Isolation root : $isolationRoot"
Write-Host ''
Write-Host 'Real launcher config modified: NO' -ForegroundColor Green
Write-Host 'AOTR_HOME used: NO' -ForegroundColor Green
Write-Host 'Manual folder selection used: NO' -ForegroundColor Green
Write-Host 'Fresh standalone discovery: PASS' -ForegroundColor Green
