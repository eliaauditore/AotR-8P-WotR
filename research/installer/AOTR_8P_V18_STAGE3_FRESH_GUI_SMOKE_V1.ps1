#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$Stage2Package = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE2_BUILD_20260827_023209\PACKAGE',
    [string]$ExpectedAotRRoot = 'D:\Games\AotR\AgeoftheRing'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$LauncherName = 'AotR 8P WotR Mod.exe'
$ExpectedBuiltExeSha256 = 'B85818E9349A76DB62DF288C23879BC2345A463D399A21105A2F75114557A944'
$ExpectedSeedExeSha256  = '6A80E0F7B862ABE3E0F19C3DF5ED9EE9EE730F246CF603ED00A39D1EE7DFF2F8'
$ExpectedUiSha256       = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha256    = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
$ExpectedIconSha256     = '3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A'
$ExpectedSkinSha256     = '2158FD8BB4E9195E27667F517FF81C745983BEE200394FB64107FFF902666473'
$ExpectedValidation     = 'aotr-standalone-v2'

function Canon([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
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

function Assert-Leaf([string]$Path,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label missing: $Path" }
}

function Assert-Container([string]$Path,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "$Label missing: $Path" }
}

function Assert-Hash([string]$Path,[string]$Expected,[string]$Label) {
    Assert-Leaf $Path $Label
    $actual = Get-Sha256File $Path
    if ($actual -ne $Expected) { throw "$Label hash mismatch. Expected $Expected, got $actual" }
    return $actual
}

function Copy-Verified([string]$Source,[string]$Destination,[string]$Expected,[string]$Label) {
    [void](Assert-Hash $Source $Expected ("Source " + $Label))
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    [void](Assert-Hash $Destination $Expected ("Copied " + $Label))
}

$Base = Canon $Base
$Stage2Package = Canon $Stage2Package
$ExpectedAotRRoot = Canon $ExpectedAotRRoot
Assert-Container $Base 'Base'
Assert-Container $Stage2Package 'Stage2 package'
Assert-Container $ExpectedAotRRoot 'Expected AotR root'

$expectedRuntime = Canon (Join-Path $ExpectedAotRRoot 'rotwk')
$expectedSourceMod = Canon (Join-Path $ExpectedAotRRoot 'aotr')
$expectedExe = Join-Path $expectedRuntime 'lotrbfme2ep1.exe'
$gameDatDirect = Join-Path $expectedRuntime 'game.dat'
$gameDatZG = Join-Path $expectedRuntime 'zGameDats\game.dat'
Assert-Container $expectedRuntime 'Expected rotwk runtime'
Assert-Container $expectedSourceMod 'Expected aotr source mod'
Assert-Leaf $expectedExe 'Expected lotrbfme2ep1.exe'
if (Test-Path -LiteralPath $gameDatDirect -PathType Leaf) { $expectedGameDat = Canon $gameDatDirect }
elseif (Test-Path -LiteralPath $gameDatZG -PathType Leaf) { $expectedGameDat = Canon $gameDatZG }
else { throw "Expected AotR root has no game.dat: $ExpectedAotRRoot" }

$bundleRoot = Join-Path $Stage2Package '_GITHUB_UPDATE'
$builtExe = Join-Path $bundleRoot $LauncherName
$seedExe = Join-Path $Stage2Package $LauncherName
$iconSource = Join-Path $Stage2Package 'assets\launcher.ico'
$skinSource = Join-Path $Stage2Package 'internal\assets\launcher_skin.png'
$uiSource = Join-Path $Stage2Package 'payload\!!!WOTR_8P_UI_TEST.big'
$paperSource = Join-Path $Stage2Package 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc'
$manifestSource = Join-Path $bundleRoot 'manifest.json'
$repairManifestSource = Join-Path $bundleRoot 'repair-manifest.json'

Write-Host '=== STAGE 2 INPUT VERIFICATION ===' -ForegroundColor Cyan
Write-Host ("Built EXE : " + (Assert-Hash $builtExe $ExpectedBuiltExeSha256 'Built V18 autodetect EXE')) -ForegroundColor Green
Write-Host ("Seed EXE  : " + (Assert-Hash $seedExe $ExpectedSeedExeSha256 'Released 1.0.10 seed')) -ForegroundColor Green
Write-Host ("UI        : " + (Assert-Hash $uiSource $ExpectedUiSha256 'UI payload')) -ForegroundColor Green
Write-Host ("Paper     : " + (Assert-Hash $paperSource $ExpectedPaperSha256 'Paper payload')) -ForegroundColor Green
Write-Host ("Icon      : " + (Assert-Hash $iconSource $ExpectedIconSha256 'Icon')) -ForegroundColor Green
Write-Host ("Skin      : " + (Assert-Hash $skinSource $ExpectedSkinSha256 'Skin')) -ForegroundColor Green
Assert-Leaf $manifestSource 'Generated manifest'
Assert-Leaf $repairManifestSource 'Generated repair manifest'

$manifest = Get-Content -LiteralPath $manifestSource -Raw | ConvertFrom-Json
if ([string]$manifest.launcher_sha256 -ne $ExpectedBuiltExeSha256) { throw 'Generated manifest does not point to the pinned Stage2 EXE hash.' }
if ([string]$manifest.launcher_url -notmatch '^https://invalid\.invalid/') { throw 'Generated manifest launcher URL is not the safe invalid test target.' }

$bytes = [IO.File]::ReadAllBytes($builtExe)
if ($bytes.Length -ne 691712) { throw "Pinned EXE size changed. Expected 691712, got $($bytes.Length)" }
if ($bytes.Length -lt 4096 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { throw 'Pinned Stage2 EXE is not an MZ executable.' }
$peOffset = [BitConverter]::ToInt32($bytes,0x3C)
if ($peOffset -lt 64 -or ($peOffset + 3) -ge $bytes.Length) { throw "Invalid PE offset: $peOffset" }
if ($bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset+1] -ne 0x45 -or $bytes[$peOffset+2] -ne 0 -or $bytes[$peOffset+3] -ne 0) { throw 'Pinned Stage2 EXE has no PE signature.' }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ("AUTODETECT_V2_V18_STAGE3_SMOKE_" + $stamp)
$runtimePackage = Join-Path $workRoot 'RUNTIME_PACKAGE'
$isolatedLocalAppData = Join-Path $workRoot 'LOCALAPPDATA'
$reportPath = Join-Path $workRoot 'V18_STAGE3_FRESH_GUI_SMOKE_REPORT.txt'
New-Item -ItemType Directory -Path $runtimePackage,$isolatedLocalAppData -Force | Out-Null

$runtimeExe = Join-Path $runtimePackage $LauncherName
Copy-Verified $builtExe $runtimeExe $ExpectedBuiltExeSha256 'runtime EXE'
Copy-Verified $iconSource (Join-Path $runtimePackage 'assets\launcher.ico') $ExpectedIconSha256 'runtime icon'
Copy-Verified $skinSource (Join-Path $runtimePackage 'internal\assets\launcher_skin.png') $ExpectedSkinSha256 'runtime skin'
Copy-Verified $uiSource (Join-Path $runtimePackage 'payload\!!!WOTR_8P_UI_TEST.big') $ExpectedUiSha256 'runtime UI'
Copy-Verified $paperSource (Join-Path $runtimePackage 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc') $ExpectedPaperSha256 'runtime paper'
Copy-Item -LiteralPath $manifestSource -Destination (Join-Path $runtimePackage 'manifest.json') -Force
Copy-Item -LiteralPath $repairManifestSource -Destination (Join-Path $runtimePackage 'repair-manifest.json') -Force

$realLocalAppData = $env:LOCALAPPDATA
$realConfig = Join-Path $realLocalAppData 'AotR 8P WotR Mod\launcher_config.json'
$realConfigExistedBefore = Test-Path -LiteralPath $realConfig -PathType Leaf
$realConfigHashBefore = if ($realConfigExistedBefore) { Get-Sha256File $realConfig } else { '' }
$oldAotrHomeExists = Test-Path Env:AOTR_HOME
$oldAotrHome = if ($oldAotrHomeExists) { [string]$env:AOTR_HOME } else { $null }

Write-Host ''
Write-Host '============================================================' -ForegroundColor Yellow
Write-Host ' V18 STAGE 3 - FRESH GUI SMOKE' -ForegroundColor Yellow
Write-Host '============================================================' -ForegroundColor Yellow
Write-Host "Pinned EXE        : $ExpectedBuiltExeSha256"
Write-Host "Runtime package   : $runtimePackage"
Write-Host "Isolated state    : $isolatedLocalAppData"
Write-Host "Expected AotR     : $ExpectedAotRRoot"
Write-Host ''
Write-Host 'When the launcher opens, do NOT browse and do NOT launch the game.' -ForegroundColor Yellow
Write-Host 'Visually check the center status panel:' -ForegroundColor Yellow
Write-Host '  AOTR INSTALLATION  -> OK' -ForegroundColor Yellow
Write-Host '  8P WOTR CAMPAIGN   -> OK' -ForegroundColor Yellow
Write-Host '  8-PLAYER WOTR UI   -> OK' -ForegroundColor Yellow
Write-Host '  Overall            -> READY / COMPAT CHECK ON LAUNCH' -ForegroundColor Yellow
Write-Host 'Also confirm MESSAGES is visible and no A8P-INSTALL-001/game.dat-not-found panel appears.' -ForegroundColor Yellow
Write-Host 'Then close the launcher with X.' -ForegroundColor Yellow
Write-Host ''

try {
    $env:LOCALAPPDATA = $isolatedLocalAppData
    Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue
    $proc = Start-Process -FilePath $runtimeExe -WorkingDirectory $runtimePackage -PassThru
    Write-Host ("Launcher PID       : " + $proc.Id)
    $proc.WaitForExit()
    Write-Host ("Launcher exit code : " + $proc.ExitCode)
}
finally {
    $env:LOCALAPPDATA = $realLocalAppData
    if ($oldAotrHomeExists) { $env:AOTR_HOME = $oldAotrHome }
    else { Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue }
}

$failures = New-Object System.Collections.Generic.List[string]
$configs = @(Get-ChildItem -LiteralPath $isolatedLocalAppData -Recurse -File -Filter 'launcher_config.json' -ErrorAction SilentlyContinue)
if ($configs.Count -ne 1) {
    [void]$failures.Add("Expected exactly one isolated launcher_config.json; found $($configs.Count)")
    $configPath = ''
    $configRaw = ''
    $config = $null
} else {
    $configPath = $configs[0].FullName
    $configRaw = Get-Content -LiteralPath $configPath -Raw
    $config = $configRaw | ConvertFrom-Json

    if ([int]$config.schema -ne 2) { [void]$failures.Add("schema expected 2, got '$($config.schema)'") }
    if ([string]$config.validation -ne $ExpectedValidation) { [void]$failures.Add("validation mismatch: '$($config.validation)'") }
    if ((Canon ([string]$config.aotr_root)) -ne $ExpectedAotRRoot) { [void]$failures.Add("aotr_root mismatch: '$($config.aotr_root)'") }
    if ((Canon ([string]$config.runtime)) -ne $expectedRuntime) { [void]$failures.Add("runtime mismatch: '$($config.runtime)'") }
    if ((Canon ([string]$config.source_mod)) -ne $expectedSourceMod) { [void]$failures.Add("source_mod mismatch: '$($config.source_mod)'") }
    if ((Canon ([string]$config.game_dat)) -ne $expectedGameDat) { [void]$failures.Add("game_dat mismatch: '$($config.game_dat)'") }
    if ([string]::IsNullOrWhiteSpace([string]$config.last_verified_utc)) { [void]$failures.Add('last_verified_utc is empty') }
}

$realConfigExistedAfter = Test-Path -LiteralPath $realConfig -PathType Leaf
$realConfigHashAfter = if ($realConfigExistedAfter) { Get-Sha256File $realConfig } else { '' }
if ($realConfigExistedAfter -ne $realConfigExistedBefore) { [void]$failures.Add('Real launcher config existence changed during isolated smoke.') }
if ($realConfigExistedBefore -and $realConfigHashAfter -ne $realConfigHashBefore) { [void]$failures.Add('Real launcher config hash changed during isolated smoke.') }

if ((Get-Sha256File $builtExe) -ne $ExpectedBuiltExeSha256) { [void]$failures.Add('Stage2 built EXE changed during smoke.') }
if ((Get-Sha256File $runtimeExe) -ne $ExpectedBuiltExeSha256) { [void]$failures.Add('Runtime copy EXE changed during smoke.') }
if ((Get-Sha256File $seedExe) -ne $ExpectedSeedExeSha256) { [void]$failures.Add('Released seed EXE changed during smoke.') }

$launcherLog = Join-Path $isolatedLocalAppData 'AotR 8P WotR Mod\launcher_current.log'
$logText = ''
if (Test-Path -LiteralPath $launcherLog -PathType Leaf) { $logText = Get-Content -LiteralPath $launcherLog -Raw -ErrorAction SilentlyContinue }
$hasGetFileHashFailure = $logText -match '(?i)Get-FileHash.*not recognized|Benennung\s+"?Get-FileHash'
if ($hasGetFileHashFailure) { [void]$failures.Add('Isolated launcher log contains Get-FileHash command-not-found evidence.') }

$reportLines = @(
    'AOTR 8P V18 STAGE3 FRESH GUI SMOKE',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Pinned EXE SHA256: ' + $ExpectedBuiltExeSha256),
    ('Runtime EXE: ' + $runtimeExe),
    ('Expected AotR root: ' + $ExpectedAotRRoot),
    ('Config path: ' + $configPath),
    ('Real config existed before: ' + $realConfigExistedBefore),
    ('Real config hash before: ' + $realConfigHashBefore),
    ('Real config existed after: ' + $realConfigExistedAfter),
    ('Real config hash after: ' + $realConfigHashAfter),
    ('Get-FileHash failure in isolated log: ' + $hasGetFileHashFailure),
    ('Failure count: ' + $failures.Count),
    '',
    'VISUAL CHECK REQUIRES USER OBSERVATION',
    '- AOTR INSTALLATION = OK',
    '- 8P WOTR CAMPAIGN = OK',
    '- 8-PLAYER WOTR UI = OK',
    '- Overall = READY / COMPAT CHECK ON LAUNCH',
    '- MESSAGES visible',
    '- No A8P-INSTALL-001 / game.dat not found overlay'
)
[IO.File]::WriteAllLines($reportPath,$reportLines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '=== ISOLATED CONFIG V2 ===' -ForegroundColor Cyan
if ($configRaw) { Write-Host $configRaw }
Write-Host ''

if ($failures.Count -gt 0) {
    Write-Host 'V18 Stage3 fresh GUI smoke: FAIL' -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host ("  - " + $failure) -ForegroundColor Red }
    Write-Host "Work root retained: $workRoot" -ForegroundColor Yellow
    exit 5
}

Write-Host '============================================================' -ForegroundColor Green
Write-Host ' V18 STAGE 3 FRESH DISCOVERY / CONFIG V2 PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host "Pinned EXE        : $ExpectedBuiltExeSha256" -ForegroundColor Green
Write-Host "Canonical root    : $($config.aotr_root)" -ForegroundColor Green
Write-Host "Runtime           : $($config.runtime)"
Write-Host "Source mod        : $($config.source_mod)"
Write-Host "Game dat          : $($config.game_dat)"
Write-Host "Score             : $($config.score)"
Write-Host "Config            : $configPath"
Write-Host "Launcher log      : $launcherLog"
Write-Host "Report            : $reportPath"
Write-Host "Work root         : $workRoot"
Write-Host ''
Write-Host 'Fresh standalone discovery : PASS' -ForegroundColor Green
Write-Host 'Config V2                  : PASS' -ForegroundColor Green
Write-Host 'Real launcher config       : UNCHANGED' -ForegroundColor Green
Write-Host 'Stage2 EXE                  : UNCHANGED' -ForegroundColor Green
Write-Host 'AOTR_HOME                   : NOT USED' -ForegroundColor Green
Write-Host 'Get-FileHash host failure   : NO' -ForegroundColor Green
Write-Host ''
Write-Host 'Visual status-panel result still requires your screenshot/observation.' -ForegroundColor Yellow
