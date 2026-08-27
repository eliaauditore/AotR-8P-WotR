#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$RcBundle = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE8_1_1_RC_20260827_032114\PACKAGE\_GITHUB_UPDATE'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedExeSha256 = '08C9298600B59FD4EA629F88014AD152880858998E0C522BF8DAA9DEDAEEAC77'
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

if (-not (Test-Path -LiteralPath $RcBundle -PathType Container)) { throw ('RC bundle missing: ' + $RcBundle) }
$exe = Join-Path $RcBundle $LauncherName
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw ('RC EXE missing: ' + $exe) }
$exeSha = Get-Sha256File $exe
if ($exeSha -ne $ExpectedExeSha256) { throw ('RC EXE hash mismatch. Expected ' + $ExpectedExeSha256 + ', got ' + $exeSha) }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ('AUTODETECT_V2_V18_STAGE9_1_1_VISUAL_' + $stamp)
$isolatedLocalAppData = Join-Path $workRoot 'LOCALAPPDATA'
New-Item -ItemType Directory -Force -Path $isolatedLocalAppData | Out-Null

$realLocalAppData = $env:LOCALAPPDATA
$realConfig = Join-Path $realLocalAppData 'AotR 8P WotR Mod\launcher_config.json'
$realConfigExistedBefore = Test-Path -LiteralPath $realConfig -PathType Leaf
$realConfigHashBefore = if ($realConfigExistedBefore) { Get-Sha256File $realConfig } else { '' }
$oldAotrHomeExists = Test-Path Env:AOTR_HOME
$oldAotrHome = if ($oldAotrHomeExists) { [string]$env:AOTR_HOME } else { $null }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P V18 STAGE 9 - LAUNCHER 1.1 RC VISUAL SMOKE' -ForegroundColor Cyan
Write-Host ' ISOLATED LOCALAPPDATA / NO GAME START' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('RC EXE SHA : ' + $exeSha) -ForegroundColor Green
Write-Host ('RC EXE     : ' + $exe)
Write-Host ('State      : ' + $isolatedLocalAppData)
Write-Host ''
Write-Host 'VISUAL CHECK:' -ForegroundColor Yellow
Write-Host '  1. Fake maximize icon must be GONE.' -ForegroundColor Yellow
Write-Host '  2. Click MINIMIZE. It must minimize normally.' -ForegroundColor Yellow
Write-Host '  3. Restore it from the taskbar.' -ForegroundColor Yellow
Write-Host '  4. Confirm status panel + MESSAGES + Launcher v1.1 still look normal.' -ForegroundColor Yellow
Write-Host '  5. Do NOT click LAUNCH.' -ForegroundColor Yellow
Write-Host '  6. Close with X. X must still work.' -ForegroundColor Yellow
Write-Host ''

try {
    $env:LOCALAPPDATA = $isolatedLocalAppData
    Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue
    $proc = Start-Process -FilePath $exe -WorkingDirectory $RcBundle -PassThru
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
if ($realConfigExistedAfter -ne $realConfigExistedBefore) { throw 'Real launcher config existence changed during visual smoke.' }
if ($realConfigExistedBefore -and $realConfigHashAfter -ne $realConfigHashBefore) { throw 'Real launcher config hash changed during visual smoke.' }
if ((Get-Sha256File $exe) -ne $ExpectedExeSha256) { throw 'RC EXE changed during visual smoke.' }

Write-Host ''
Write-Host '[PASS] RC EXE unchanged' -ForegroundColor Green
Write-Host '[PASS] real launcher config unchanged' -ForegroundColor Green
Write-Host ''
Write-Host 'STAGE 9 FUNCTIONAL SAFETY: PASS' -ForegroundColor Green
Write-Host 'Visual result must still be confirmed by the user.' -ForegroundColor Yellow
