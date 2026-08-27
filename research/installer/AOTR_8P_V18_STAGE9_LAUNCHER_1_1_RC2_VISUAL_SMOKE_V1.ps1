#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$RcBundle = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE8_1_1_RC2_20260827_033129\PACKAGE\_GITHUB_UPDATE'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedExeSha256   = 'A3A20BD540E429330F6A97FD30DE6B416EB70426AEF8FD9223C03856B4EBBBF8'
$ExpectedSkinSha256  = 'BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6'
$ExpectedIconSha256  = '3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A'
$ExpectedUiSha256    = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha256 = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
$LauncherName = 'AotR 8P WotR Mod.exe'

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
    Write-Host (('{0,-22}: {1}' -f $Label,$actual)) -ForegroundColor Green
    return $actual
}

function Copy-Verified([string]$Source,[string]$Destination,[string]$Expected,[string]$Label) {
    [void](Assert-Hash $Source $Expected ('Source ' + $Label))
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    [void](Assert-Hash $Destination $Expected ('Runtime ' + $Label))
}

if (-not (Test-Path -LiteralPath $RcBundle -PathType Container)) { throw ('RC2 bundle missing: ' + $RcBundle) }
$packageRoot = Split-Path -Parent $RcBundle
if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) { throw ('RC2 package root missing: ' + $packageRoot) }

$bundleExe = Join-Path $RcBundle $LauncherName
$skinSource = Join-Path $packageRoot 'internal\assets\launcher_skin.png'
$iconSource = Join-Path $packageRoot 'assets\launcher.ico'
$uiSource = Join-Path $packageRoot 'payload\!!!WOTR_8P_UI_TEST.big'
$paperSource = Join-Path $packageRoot 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc'
$manifestSource = Join-Path $RcBundle 'manifest.json'
$repairManifestSource = Join-Path $RcBundle 'repair-manifest.json'

Write-Host '=== RC2 INPUT VERIFICATION ===' -ForegroundColor Cyan
[void](Assert-Hash $bundleExe $ExpectedExeSha256 'RC2 EXE')
[void](Assert-Hash $skinSource $ExpectedSkinSha256 'RC2 skin')
[void](Assert-Hash $iconSource $ExpectedIconSha256 'Icon')
[void](Assert-Hash $uiSource $ExpectedUiSha256 'UI payload')
[void](Assert-Hash $paperSource $ExpectedPaperSha256 'Paper payload')
if (-not (Test-Path -LiteralPath $manifestSource -PathType Leaf)) { throw ('Manifest missing: ' + $manifestSource) }
if (-not (Test-Path -LiteralPath $repairManifestSource -PathType Leaf)) { throw ('Repair manifest missing: ' + $repairManifestSource) }

$manifest = Get-Content -LiteralPath $manifestSource -Raw | ConvertFrom-Json
if ([string]$manifest.launcher_sha256 -ne $ExpectedExeSha256) { throw 'RC2 manifest launcher_sha256 does not match the pinned RC2 EXE.' }
if ([string]$manifest.launcher_url -notmatch '^https://invalid\.invalid/') { throw 'RC2 manifest launcher URL is not the safe invalid test target.' }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ('AUTODETECT_V2_V18_STAGE9_1_1_RC2_VISUAL_' + $stamp)
$runtimePackage = Join-Path $workRoot 'RUNTIME_PACKAGE'
$isolatedLocalAppData = Join-Path $workRoot 'LOCALAPPDATA'
New-Item -ItemType Directory -Force -Path $runtimePackage,$isolatedLocalAppData | Out-Null

$runtimeExe = Join-Path $runtimePackage $LauncherName
Copy-Verified $bundleExe $runtimeExe $ExpectedExeSha256 'EXE'
Copy-Verified $skinSource (Join-Path $runtimePackage 'internal\assets\launcher_skin.png') $ExpectedSkinSha256 'skin'
Copy-Verified $iconSource (Join-Path $runtimePackage 'assets\launcher.ico') $ExpectedIconSha256 'icon'
Copy-Verified $uiSource (Join-Path $runtimePackage 'payload\!!!WOTR_8P_UI_TEST.big') $ExpectedUiSha256 'UI'
Copy-Verified $paperSource (Join-Path $runtimePackage 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc') $ExpectedPaperSha256 'paper'
Copy-Item -LiteralPath $manifestSource -Destination (Join-Path $runtimePackage 'manifest.json') -Force
Copy-Item -LiteralPath $repairManifestSource -Destination (Join-Path $runtimePackage 'repair-manifest.json') -Force

$realLocalAppData = $env:LOCALAPPDATA
$realConfig = Join-Path $realLocalAppData 'AotR 8P WotR Mod\launcher_config.json'
$realConfigExistedBefore = Test-Path -LiteralPath $realConfig -PathType Leaf
$realConfigHashBefore = if ($realConfigExistedBefore) { Get-Sha256File $realConfig } else { '' }
$oldAotrHomeExists = Test-Path Env:AOTR_HOME
$oldAotrHome = if ($oldAotrHomeExists) { [string]$env:AOTR_HOME } else { $null }

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P V18 STAGE 9 - LAUNCHER 1.1 RC2 VISUAL SMOKE' -ForegroundColor Cyan
Write-Host ' COMPLETE ISOLATED RUNTIME PACKAGE / NO GAME START' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('RC2 EXE SHA : ' + $ExpectedExeSha256) -ForegroundColor Green
Write-Host ('Runtime      : ' + $runtimePackage)
Write-Host ('State        : ' + $isolatedLocalAppData)
Write-Host ''
Write-Host 'VISUAL CHECK:' -ForegroundColor Yellow
Write-Host '  1. Topbar should now look intentional: Minimize immediately left of X.' -ForegroundColor Yellow
Write-Host '  2. No fake maximize icon and no large dead gap.' -ForegroundColor Yellow
Write-Host '  3. Click MINIMIZE at its new position; it must minimize normally.' -ForegroundColor Yellow
Write-Host '  4. Restore from taskbar.' -ForegroundColor Yellow
Write-Host '  5. Confirm Launcher v1.1 + status panel + MESSAGES still look normal.' -ForegroundColor Yellow
Write-Host '  6. Do NOT click LAUNCH.' -ForegroundColor Yellow
Write-Host '  7. Close with X; X must still work.' -ForegroundColor Yellow
Write-Host ''

try {
    $env:LOCALAPPDATA = $isolatedLocalAppData
    Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue
    $proc = Start-Process -FilePath $runtimeExe -WorkingDirectory $runtimePackage -PassThru
    Write-Host ('Launcher PID : ' + $proc.Id)
    $proc.WaitForExit()
    Write-Host ('Exit code    : ' + $proc.ExitCode)
}
finally {
    $env:LOCALAPPDATA = $realLocalAppData
    if ($oldAotrHomeExists) { $env:AOTR_HOME = $oldAotrHome }
    else { Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue }
}

$realConfigExistedAfter = Test-Path -LiteralPath $realConfig -PathType Leaf
$realConfigHashAfter = if ($realConfigExistedAfter) { Get-Sha256File $realConfig } else { '' }
if ($realConfigExistedAfter -ne $realConfigExistedBefore) { throw 'Real launcher config existence changed during RC2 visual smoke.' }
if ($realConfigExistedBefore -and $realConfigHashAfter -ne $realConfigHashBefore) { throw 'Real launcher config hash changed during RC2 visual smoke.' }
if ((Get-Sha256File $bundleExe) -ne $ExpectedExeSha256) { throw 'RC2 bundle EXE changed during visual smoke.' }
if ((Get-Sha256File $runtimeExe) -ne $ExpectedExeSha256) { throw 'Runtime RC2 EXE changed during visual smoke.' }
if ((Get-Sha256File $skinSource) -ne $ExpectedSkinSha256) { throw 'RC2 source skin changed during visual smoke.' }

Write-Host ''
Write-Host '[PASS] RC2 EXE unchanged' -ForegroundColor Green
Write-Host '[PASS] RC2 skin unchanged' -ForegroundColor Green
Write-Host '[PASS] real launcher config unchanged' -ForegroundColor Green
Write-Host ''
Write-Host 'STAGE 9 RC2 FUNCTIONAL SAFETY: PASS' -ForegroundColor Green
Write-Host 'Visual result must still be confirmed by the user.' -ForegroundColor Yellow
