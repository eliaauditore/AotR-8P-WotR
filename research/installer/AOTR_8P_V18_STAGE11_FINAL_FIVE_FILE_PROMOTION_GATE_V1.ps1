#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$ProductionWorkRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE8_1_1_RC2_20260827_033705',
    [string]$ExpectedAotRRoot = 'D:\Games\AotR\AgeoftheRing'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$LauncherName = 'AotR 8P WotR Mod.exe'
$ExpectedExeSha256   = '9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4'
$ExpectedSkinSha256  = 'BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6'
$ExpectedIconSha256  = '3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A'
$ExpectedUiSha256    = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha256 = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
$ExpectedLiveExeSha256 = '6A80E0F7B862ABE3E0F19C3DF5ED9EE9EE730F246CF603ED00A39D1EE7DFF2F8'
$ExpectedValidation = 'aotr-standalone-v2'

$RootBase = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main'
$ExpectedLauncherUrl = $RootBase + '/AotR%208P%20WotR%20Mod.exe'
$ExpectedManifestUrl = $RootBase + '/manifest.json'
$ExpectedRepairUrl = $RootBase + '/repair-manifest.json'
$ExpectedUiUrl = $RootBase + '/payload_ui.big'
$ExpectedPaperUrl = $RootBase + '/payload_paper.inc'

$ExpectedBundleFiles = @(
    'AotR 8P WotR Mod.exe',
    'manifest.json',
    'repair-manifest.json',
    'payload_ui.big',
    'payload_paper.inc'
)

$ExpectedPlans = [ordered]@{
    'A8P-INSTALL-001'       = @('reset_install','retry_launch')
    'A8P-PAYLOAD-UI-001'    = @('repair_payloads','reset_runtime','retry_launch')
    'A8P-PAYLOAD-PAPER-001' = @('repair_payloads','reset_runtime','retry_launch')
    'A8P-LEGACY-001'        = @('stop_old_dev_launchers','stop_legacy_runtime','retry_launch')
    'A8P-PROCESS-001'       = @('stop_legacy_runtime','stop_failed_game','retry_launch')
    'A8P-RUNTIME-001'       = @('stop_legacy_runtime','stop_failed_game','reset_runtime','repair_payloads','retry_launch')
    'A8P-GAMEPROC-001'      = @('stop_legacy_runtime','stop_failed_game','reset_runtime','retry_launch')
    'A8P-PERMISSION-001'    = @('stop_failed_game','retry_launch')
    'A8P-COMPAT-001'        = @('check_launcher_update')
    'A8P-ENGINE-001'        = @('stop_legacy_runtime','stop_failed_game','reset_runtime','clear_compat_cache','retry_launch')
}

function Get-Sha256File([string]$Path) {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Assert-Hash([string]$Path,[string]$Expected,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ($Label + ' missing: ' + $Path) }
    $actual = Get-Sha256File $Path
    if ($actual -ne $Expected) { throw ($Label + ' hash mismatch. Expected ' + $Expected + ', got ' + $actual) }
    Write-Host (('{0,-28}: {1}' -f $Label,$actual)) -ForegroundColor Green
    return $actual
}

function Copy-Verified([string]$Source,[string]$Destination,[string]$Expected,[string]$Label) {
    [void](Assert-Hash $Source $Expected ('Source ' + $Label))
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    [void](Assert-Hash $Destination $Expected ('Runtime ' + $Label))
}

function Assert-ExactActions($Plan,[string[]]$Expected,[string]$Code) {
    $actual = @($Plan.actions | ForEach-Object { [string]$_ })
    if ($actual.Count -ne $Expected.Count) { throw ($Code + ' action count mismatch.') }
    for ($i=0; $i -lt $Expected.Count; $i++) {
        if ($actual[$i] -ne $Expected[$i]) { throw ($Code + ' action mismatch at index ' + $i + ': expected ' + $Expected[$i] + ', got ' + $actual[$i]) }
    }
}

function Canon([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

if (-not (Test-Path -LiteralPath $ProductionWorkRoot -PathType Container)) { throw ('Production work root missing: ' + $ProductionWorkRoot) }
$packageRoot = Join-Path $ProductionWorkRoot 'PACKAGE'
$bundleRoot = Join-Path $packageRoot '_GITHUB_UPDATE'
if (-not (Test-Path -LiteralPath $bundleRoot -PathType Container)) { throw ('Production bundle missing: ' + $bundleRoot) }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P V18 STAGE 11 - FINAL FIVE-FILE PROMOTION GATE' -ForegroundColor Cyan
Write-Host ' PRODUCTION 1.1 / ROLLBACK SNAPSHOT / FINAL ISOLATED SMOKE' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('Production root : ' + $ProductionWorkRoot)
Write-Host ('Bundle root     : ' + $bundleRoot)
Write-Host ''

# 1) Exact five-file bundle surface.
$actualFiles = @(Get-ChildItem -LiteralPath $bundleRoot -File | Select-Object -ExpandProperty Name | Sort-Object)
$expectedFilesSorted = @($ExpectedBundleFiles | Sort-Object)
if ($actualFiles.Count -ne 5) { throw ('Bundle must contain exactly five files; found ' + $actualFiles.Count + ': ' + ($actualFiles -join ', ')) }
for ($i=0; $i -lt 5; $i++) {
    if ($actualFiles[$i] -ne $expectedFilesSorted[$i]) { throw ('Unexpected bundle file surface. Expected [' + ($expectedFilesSorted -join ', ') + '], got [' + ($actualFiles -join ', ') + ']') }
}
Write-Host '[PASS] bundle contains exactly the five release-root files' -ForegroundColor Green

$exe = Join-Path $bundleRoot $LauncherName
$manifestPath = Join-Path $bundleRoot 'manifest.json'
$repairPath = Join-Path $bundleRoot 'repair-manifest.json'
$uiPath = Join-Path $bundleRoot 'payload_ui.big'
$paperPath = Join-Path $bundleRoot 'payload_paper.inc'
$skinPath = Join-Path $packageRoot 'internal\assets\launcher_skin.png'
$iconPath = Join-Path $packageRoot 'assets\launcher.ico'
$runtimeUiSource = Join-Path $packageRoot 'payload\!!!WOTR_8P_UI_TEST.big'
$runtimePaperSource = Join-Path $packageRoot 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc'

$exeSha = Assert-Hash $exe $ExpectedExeSha256 'Production EXE'
$uiSha = Assert-Hash $uiPath $ExpectedUiSha256 'Bundle UI'
$paperSha = Assert-Hash $paperPath $ExpectedPaperSha256 'Bundle Paper'
[void](Assert-Hash $skinPath $ExpectedSkinSha256 'Production skin')
[void](Assert-Hash $iconPath $ExpectedIconSha256 'Production icon')
[void](Assert-Hash $runtimeUiSource $ExpectedUiSha256 'Package UI source')
[void](Assert-Hash $runtimePaperSource $ExpectedPaperSha256 'Package Paper source')

$manifestRaw = Get-Content -LiteralPath $manifestPath -Raw
$repairRaw = Get-Content -LiteralPath $repairPath -Raw
if ($manifestRaw -match '(?i)invalid\.invalid' -or $repairRaw -match '(?i)invalid\.invalid') { throw 'Production JSON still contains invalid.invalid.' }
$manifestSha = Get-Sha256File $manifestPath
$repairSha = Get-Sha256File $repairPath
$manifest = $manifestRaw | ConvertFrom-Json
$repair = $repairRaw | ConvertFrom-Json

if ([int]$manifest.schema -ne 1) { throw 'manifest.schema must be 1.' }
if ([string]$manifest.launcher_version -ne '1.1') { throw 'manifest.launcher_version must be 1.1.' }
if ([string]$manifest.launcher_url -ne $ExpectedLauncherUrl) { throw 'manifest.launcher_url mismatch.' }
if ([string]$manifest.launcher_sha256 -ne $ExpectedExeSha256) { throw 'manifest.launcher_sha256 mismatch.' }
if ([bool]$manifest.mandatory) { throw 'manifest.mandatory unexpectedly true.' }
if ([string]$manifest.repair_manifest_url -ne $ExpectedRepairUrl) { throw 'manifest.repair_manifest_url mismatch.' }
if ([string]$manifest.ui_url -ne $ExpectedUiUrl -or [string]$manifest.ui_sha256 -ne $ExpectedUiSha256) { throw 'manifest UI URL/hash mismatch.' }
if ([string]$manifest.paper_url -ne $ExpectedPaperUrl -or [string]$manifest.paper_sha256 -ne $ExpectedPaperSha256) { throw 'manifest Paper URL/hash mismatch.' }
Write-Host '[PASS] production manifest cross-links all five root files correctly' -ForegroundColor Green

if ([int]$repair.schema -ne 1) { throw 'repair-manifest.schema must be 1.' }
if ([string]$repair.generated_for_launcher -ne '1.1') { throw 'repair-manifest.generated_for_launcher must be 1.1.' }
$planNames = @($repair.plans.PSObject.Properties.Name | Sort-Object)
$expectedPlanNames = @($ExpectedPlans.Keys | Sort-Object)
if ($planNames.Count -ne $expectedPlanNames.Count) { throw 'Repair plan count mismatch.' }
for ($i=0; $i -lt $expectedPlanNames.Count; $i++) {
    if ($planNames[$i] -ne $expectedPlanNames[$i]) { throw ('Repair plan set mismatch. Expected ' + ($expectedPlanNames -join ', ') + '; got ' + ($planNames -join ', ')) }
}
foreach ($code in $ExpectedPlans.Keys) {
    $plan = $repair.plans.$code
    if ($null -eq $plan) { throw ('Missing repair plan ' + $code) }
    Assert-ExactActions $plan $ExpectedPlans[$code] $code
    if ($code -eq 'A8P-COMPAT-001') {
        if (-not [bool]$plan.protected) { throw 'A8P-COMPAT-001 must remain protected=true.' }
    } elseif ($plan.PSObject.Properties.Name -contains 'protected' -and [bool]$plan.protected) {
        throw ($code + ' unexpectedly gained protected=true.')
    }
}
Write-Host '[PASS] repair-manifest plan set/actions exactly match proven production dispatcher' -ForegroundColor Green

# 2) Verify current live release before promotion and keep rollback bytes locally.
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$gateRoot = Join-Path $Base ('AUTODETECT_V2_V18_STAGE11_PROMOTION_GATE_' + $stamp)
$rollbackRoot = Join-Path $gateRoot 'ROLLBACK_1_0_10'
$runtimeRoot = Join-Path $gateRoot 'RUNTIME_PACKAGE'
$isolatedLocalAppData = Join-Path $gateRoot 'LOCALAPPDATA'
New-Item -ItemType Directory -Path $rollbackRoot,$runtimeRoot,$isolatedLocalAppData -Force | Out-Null

Write-Host ''
Write-Host 'Downloading current live five-file root as rollback snapshot...' -ForegroundColor Cyan
foreach ($name in $ExpectedBundleFiles) {
    $encoded = if ($name -eq $LauncherName) { 'AotR%208P%20WotR%20Mod.exe' } else { $name }
    Invoke-WebRequest -Uri ($RootBase + '/' + $encoded) -OutFile (Join-Path $rollbackRoot $name)
}
$liveExe = Join-Path $rollbackRoot $LauncherName
[void](Assert-Hash $liveExe $ExpectedLiveExeSha256 'Live 1.0.10 EXE')
$liveManifestRaw = Get-Content -LiteralPath (Join-Path $rollbackRoot 'manifest.json') -Raw
$liveManifest = $liveManifestRaw | ConvertFrom-Json
if ([string]$liveManifest.launcher_version -ne '1.0.10') { throw ('Live baseline is no longer 1.0.10; found ' + [string]$liveManifest.launcher_version + '. Stop promotion and reassess.') }
if ([string]$liveManifest.launcher_sha256 -ne $ExpectedLiveExeSha256) { throw 'Live 1.0.10 manifest/EXE relationship changed.' }
[void](Assert-Hash (Join-Path $rollbackRoot 'payload_ui.big') $ExpectedUiSha256 'Live UI')
[void](Assert-Hash (Join-Path $rollbackRoot 'payload_paper.inc') $ExpectedPaperSha256 'Live Paper')
Write-Host '[PASS] live 1.0.10 baseline still matches expected release; rollback snapshot saved' -ForegroundColor Green

# 3) Create full isolated runtime from the FINAL production candidate.
Copy-Verified $exe (Join-Path $runtimeRoot $LauncherName) $ExpectedExeSha256 'EXE'
Copy-Verified $skinPath (Join-Path $runtimeRoot 'internal\assets\launcher_skin.png') $ExpectedSkinSha256 'skin'
Copy-Verified $iconPath (Join-Path $runtimeRoot 'assets\launcher.ico') $ExpectedIconSha256 'icon'
Copy-Verified $runtimeUiSource (Join-Path $runtimeRoot 'payload\!!!WOTR_8P_UI_TEST.big') $ExpectedUiSha256 'UI'
Copy-Verified $runtimePaperSource (Join-Path $runtimeRoot 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc') $ExpectedPaperSha256 'paper'
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $runtimeRoot 'manifest.json') -Force
Copy-Item -LiteralPath $repairPath -Destination (Join-Path $runtimeRoot 'repair-manifest.json') -Force

$realLocalAppData = $env:LOCALAPPDATA
$realConfig = Join-Path $realLocalAppData 'AotR 8P WotR Mod\launcher_config.json'
$realConfigExistedBefore = Test-Path -LiteralPath $realConfig -PathType Leaf
$realConfigHashBefore = if ($realConfigExistedBefore) { Get-Sha256File $realConfig } else { '' }
$oldAotrHomeExists = Test-Path Env:AOTR_HOME
$oldAotrHome = if ($oldAotrHomeExists) { [string]$env:AOTR_HOME } else { $null }

Write-Host ''
Write-Host 'FINAL PRODUCTION SMOKE:' -ForegroundColor Yellow
Write-Host '  - This is the exact 9F2D... production EXE, not RC2.' -ForegroundColor Yellow
Write-Host '  - Confirm topbar [ - ][ X ], Launcher v1.1, status panel, MESSAGES.' -ForegroundColor Yellow
Write-Host '  - Test Minimize and Close. Do NOT press LAUNCH.' -ForegroundColor Yellow
Write-Host ''

try {
    $env:LOCALAPPDATA = $isolatedLocalAppData
    Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue
    $runtimeExe = Join-Path $runtimeRoot $LauncherName
    $proc = Start-Process -FilePath $runtimeExe -WorkingDirectory $runtimeRoot -PassThru
    Write-Host ('Production launcher PID: ' + $proc.Id)
    $proc.WaitForExit()
    Write-Host ('Production launcher exit code: ' + $proc.ExitCode)
}
finally {
    $env:LOCALAPPDATA = $realLocalAppData
    if ($oldAotrHomeExists) { $env:AOTR_HOME = $oldAotrHome } else { Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue }
}

$realConfigExistedAfter = Test-Path -LiteralPath $realConfig -PathType Leaf
$realConfigHashAfter = if ($realConfigExistedAfter) { Get-Sha256File $realConfig } else { '' }
if ($realConfigExistedAfter -ne $realConfigExistedBefore) { throw 'Real launcher config existence changed during final production smoke.' }
if ($realConfigExistedBefore -and $realConfigHashAfter -ne $realConfigHashBefore) { throw 'Real launcher config changed during final production smoke.' }
[void](Assert-Hash $exe $ExpectedExeSha256 'Production EXE after smoke')
[void](Assert-Hash $manifestPath $manifestSha 'Manifest after smoke')
[void](Assert-Hash $repairPath $repairSha 'Repair manifest after smoke')
[void](Assert-Hash $uiPath $ExpectedUiSha256 'Bundle UI after smoke')
[void](Assert-Hash $paperPath $ExpectedPaperSha256 'Bundle Paper after smoke')

$configs = @(Get-ChildItem -LiteralPath $isolatedLocalAppData -Recurse -File -Filter 'launcher_config.json' -ErrorAction SilentlyContinue)
if ($configs.Count -ne 1) { throw ('Expected exactly one isolated launcher_config.json after final smoke; found ' + $configs.Count) }
$config = Get-Content -LiteralPath $configs[0].FullName -Raw | ConvertFrom-Json
if ([int]$config.schema -ne 2 -or [string]$config.validation -ne $ExpectedValidation) { throw 'Final production smoke did not create valid Config V2.' }
if ((Canon ([string]$config.aotr_root)) -ne (Canon $ExpectedAotRRoot)) { throw ('Final production smoke resolved unexpected AotR root: ' + [string]$config.aotr_root) }
Write-Host '[PASS] exact production EXE launched with isolated Config V2 and real config remained unchanged' -ForegroundColor Green

$report = Join-Path $gateRoot 'V18_STAGE11_FINAL_FIVE_FILE_PROMOTION_GATE_REPORT.txt'
$rollbackHashes = foreach ($name in $ExpectedBundleFiles) {
    $p = Join-Path $rollbackRoot $name
    $name + ' = ' + (Get-Sha256File $p)
}
$reportLines = @(
    'AOTR 8P V18 STAGE11 FINAL FIVE-FILE PROMOTION GATE',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Production bundle: ' + $bundleRoot),
    ('Production EXE SHA256: ' + $ExpectedExeSha256),
    ('Production manifest SHA256: ' + $manifestSha),
    ('Production repair-manifest SHA256: ' + $repairSha),
    ('Production UI SHA256: ' + $ExpectedUiSha256),
    ('Production Paper SHA256: ' + $ExpectedPaperSha256),
    ('Production skin SHA256: ' + $ExpectedSkinSha256),
    '',
    'GATE ASSERTIONS',
    '- exact five-file bundle surface: PASS',
    '- manifest cross-links/version/production URLs: PASS',
    '- mandatory=false: PASS',
    '- exact repair plan set/actions/protected flag: PASS',
    '- no invalid.invalid in production JSON: PASS',
    '- live 1.0.10 baseline verified before promotion: PASS',
    '- rollback snapshot captured: PASS',
    '- exact production EXE final isolated smoke: PASS',
    '- Config V2 created and validated: PASS',
    '- real launcher config unchanged: PASS',
    '',
    'ROLLBACK SNAPSHOT',
    ('Path: ' + $rollbackRoot)
) + @($rollbackHashes) + @(
    '',
    'STATUS: READY TO PROMOTE LAUNCHER 1.1'
)
[IO.File]::WriteAllLines($report,$reportLines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' STAGE 11 FINAL FIVE-FILE PROMOTION GATE: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('Production EXE : ' + $ExpectedExeSha256) -ForegroundColor Green
Write-Host ('Manifest SHA   : ' + $manifestSha) -ForegroundColor Green
Write-Host ('Repair SHA     : ' + $repairSha) -ForegroundColor Green
Write-Host ('Rollback       : ' + $rollbackRoot) -ForegroundColor Green
Write-Host ('Report         : ' + $report)
Write-Host ''
Write-Host 'READY TO PROMOTE LAUNCHER 1.1' -ForegroundColor Green
Write-Host 'No repository root file was modified by this gate.' -ForegroundColor Green
