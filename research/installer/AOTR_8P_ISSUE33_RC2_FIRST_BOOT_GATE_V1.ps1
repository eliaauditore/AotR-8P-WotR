#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Bundle = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_051102\PACKAGE\_GITHUB_UPDATE'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedVersion = '1.1.1-issue33-rc2'
$ExpectedExeSha = '59865672D5E4F53579E61D9CE37FECD7C5E5BC77E81C6CB05D028A9554FD4E44'
$ExpectedSkinSha = 'BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6'
$ExpectedUiSha = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
$ExpectedRootFiles = @(
    'AotR 8P WotR Mod.exe',
    'manifest.json',
    'repair-manifest.json',
    'payload_ui.big',
    'payload_paper.inc'
)

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
    if ($actual -ne $Expected) { throw ($Label + ' SHA256 mismatch. Expected ' + $Expected + ', got ' + $actual) }
    Write-Host (('{0,-30}: {1}' -f $Label,$actual)) -ForegroundColor Green
    return $actual
}

if (-not (Test-Path -LiteralPath $Bundle -PathType Container)) { throw ('Bundle missing: ' + $Bundle) }
$Bundle = [IO.Path]::GetFullPath($Bundle)
$exe = Join-Path $Bundle 'AotR 8P WotR Mod.exe'
$manifestPath = Join-Path $Bundle 'manifest.json'
$repairPath = Join-Path $Bundle 'repair-manifest.json'
$uiPath = Join-Path $Bundle 'payload_ui.big'
$paperPath = Join-Path $Bundle 'payload_paper.inc'
$internalRoot = Join-Path $Bundle 'internal'
$skinPath = Join-Path $Bundle 'internal\assets\launcher_skin.png'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' ISSUE #33 RC2 - ISOLATED FIRST-BOOT GATE' -ForegroundColor Cyan
Write-Host ' EXACT FIVE-FILE ROOT -> SELF-MATERIALIZED SKIN -> GUI' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('Bundle : ' + $Bundle)
Write-Host ''

$rootFiles = @(Get-ChildItem -LiteralPath $Bundle -File | Select-Object -ExpandProperty Name | Sort-Object)
$expectedSorted = @($ExpectedRootFiles | Sort-Object)
if ($rootFiles.Count -ne 5) { throw ('Pre-launch root must contain exactly five files; found ' + $rootFiles.Count + ': ' + ($rootFiles -join ', ')) }
if (($rootFiles -join "`n") -cne ($expectedSorted -join "`n")) { throw ('Pre-launch root file set mismatch. Found: ' + ($rootFiles -join ', ')) }
Write-Host '[PASS] pre-launch root contains exactly the intended five public files' -ForegroundColor Green

if (Test-Path -LiteralPath $internalRoot) {
    throw ('Pre-launch internal\ already exists. First-boot proof would be invalid. Path: ' + $internalRoot)
}
Write-Host '[PASS] pre-launch internal\ does not exist' -ForegroundColor Green

[void](Assert-Hash $exe $ExpectedExeSha 'Candidate EXE')
[void](Assert-Hash $uiPath $ExpectedUiSha 'Candidate UI')
[void](Assert-Hash $paperPath $ExpectedPaperSha 'Candidate paper')

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$repair = Get-Content -LiteralPath $repairPath -Raw | ConvertFrom-Json
if ([int]$manifest.schema -ne 1) { throw ('manifest schema mismatch: ' + [string]$manifest.schema) }
if ([string]$manifest.launcher_version -ne $ExpectedVersion) { throw ('manifest launcher_version mismatch: ' + [string]$manifest.launcher_version) }
if ([string]$manifest.launcher_sha256 -ne $ExpectedExeSha) { throw ('manifest launcher_sha256 mismatch: ' + [string]$manifest.launcher_sha256) }
if ([int]$repair.schema -ne 1) { throw ('repair-manifest schema mismatch: ' + [string]$repair.schema) }
if ([string]$repair.generated_for_launcher -ne $ExpectedVersion) { throw ('repair-manifest generated_for_launcher mismatch: ' + [string]$repair.generated_for_launcher) }
Write-Host '[PASS] candidate manifests identify the exact RC2 candidate' -ForegroundColor Green

$testRoot = Join-Path ([IO.Path]::GetDirectoryName($Bundle)) '_ISSUE33_FIRST_BOOT_ISOLATION'
$isolatedLocalAppData = Join-Path $testRoot 'LOCALAPPDATA'
New-Item -ItemType Directory -Path $isolatedLocalAppData -Force | Out-Null

$oldLocalAppData = $env:LOCALAPPDATA
$oldAotrHome = $env:AOTR_HOME
$proc = $null
try {
    $env:LOCALAPPDATA = $isolatedLocalAppData
    $env:AOTR_HOME = Join-Path $testRoot 'INVALID_AOTR_HOME_DECOY'

    Write-Host ''
    Write-Host 'Launching exact RC2 candidate from the five-file root...' -ForegroundColor Cyan
    $proc = Start-Process -FilePath $exe -WorkingDirectory $Bundle -PassThru
    Write-Host ('Candidate launcher PID        : ' + $proc.Id)
}
finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:AOTR_HOME = $oldAotrHome
}

$deadline = [DateTime]::UtcNow.AddSeconds(20)
while (-not (Test-Path -LiteralPath $skinPath -PathType Leaf)) {
    $proc.Refresh()
    if ($proc.HasExited) {
        throw ('Candidate exited before materializing launcher_skin.png. Exit code: ' + $proc.ExitCode)
    }
    if ([DateTime]::UtcNow -ge $deadline) {
        throw ('Timed out waiting for self-materialized skin: ' + $skinPath)
    }
    Start-Sleep -Milliseconds 100
}

$skinSha = Get-Sha256File $skinPath
if ($skinSha -ne $ExpectedSkinSha) { throw ('Self-materialized skin SHA mismatch. Expected ' + $ExpectedSkinSha + ', got ' + $skinSha) }
Write-Host ('Self-materialized skin      : ' + $skinSha) -ForegroundColor Green
Write-Host '[PASS] exact skin was created by the candidate from an initially five-file-only release root' -ForegroundColor Green

Start-Sleep -Seconds 2
$proc.Refresh()
if ($proc.HasExited) { throw ('Candidate exited immediately after bootstrap. Exit code: ' + $proc.ExitCode) }
Write-Host '[PASS] launcher process remains alive after bootstrap' -ForegroundColor Green

Write-Host ''
Write-Host 'VISUAL CHECK - DO NOT PRESS START:' -ForegroundColor Yellow
Write-Host '  1. Launcher window is visible and rendered normally.'
Write-Host '  2. Topbar shows [ - ][ X ].'
Write-Host '  3. Launcher version shows 1.1.1-issue33-rc2.'
Write-Host '  4. Status panel and MESSAGES are present.'
Write-Host '  5. Do NOT press START in this gate.'
Write-Host ''
$answer = Read-Host 'Type PASS if all five visual checks are true'
if ($answer.Trim().ToUpperInvariant() -ne 'PASS') { throw 'Visual first-boot confirmation was not PASS.' }

Write-Host 'Close the launcher with its X button now. Do NOT press START.' -ForegroundColor Yellow
$proc.WaitForExit()
if ($proc.ExitCode -ne 0) { throw ('Launcher closed with non-zero exit code: ' + $proc.ExitCode) }

[void](Assert-Hash $exe $ExpectedExeSha 'Candidate EXE after smoke')
$skinShaAfter = Get-Sha256File $skinPath
if ($skinShaAfter -ne $ExpectedSkinSha) { throw ('Skin changed during first-boot smoke: ' + $skinShaAfter) }

$report = Join-Path $testRoot 'ISSUE33_RC2_FIRST_BOOT_GATE_REPORT.txt'
$lines = @(
    'AOTR 8P WOTR ISSUE #33 RC2 FIRST-BOOT GATE: PASS',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Bundle: ' + $Bundle),
    ('Candidate version: ' + $ExpectedVersion),
    ('Candidate EXE SHA256: ' + $ExpectedExeSha),
    ('Materialized skin SHA256: ' + $ExpectedSkinSha),
    ('UI SHA256: ' + $ExpectedUiSha),
    ('Paper SHA256: ' + $ExpectedPaperSha),
    'Pre-launch root file count: 5',
    'Pre-launch internal/: absent',
    'Self-materialized internal/assets/launcher_skin.png: PASS',
    'Launcher remained alive after bootstrap: PASS',
    'Visual GUI confirmation: PASS',
    'START was not pressed in this gate.'
)
[IO.File]::WriteAllLines($report,$lines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' ISSUE #33 RC2 FIRST-BOOT GATE: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('Candidate EXE : ' + $ExpectedExeSha) -ForegroundColor Green
Write-Host ('Skin SHA      : ' + $ExpectedSkinSha) -ForegroundColor Green
Write-Host ('Report        : ' + $report)
Write-Host ''
Write-Host 'NEXT: exact START -> fresh lotrbfme2ep1.exe -> stability window -> launcher handoff gate.' -ForegroundColor Cyan
