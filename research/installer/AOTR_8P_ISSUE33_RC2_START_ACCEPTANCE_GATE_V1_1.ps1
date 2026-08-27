#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Bundle = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_051102\PACKAGE\_GITHUB_UPDATE',
    [int]$StabilitySeconds = 15,
    [int]$StartTimeoutSeconds = 180,
    [int]$HandoffTimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedVersion = '1.1.1-issue33-rc2'
$ExpectedExeSha = '59865672D5E4F53579E61D9CE37FECD7C5E5BC77E81C6CB05D028A9554FD4E44'
$ExpectedSkinSha = 'BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6'
$ExpectedUiSha = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
$ExpectedRootFiles = @('AotR 8P WotR Mod.exe','manifest.json','repair-manifest.json','payload_ui.big','payload_paper.inc')

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
    Write-Host (('{0,-31}: {1}' -f $Label,$actual)) -ForegroundColor Green
    return $actual
}

function Get-CandidateLauncherProcesses([string]$ExactExe) {
    $result = @()
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        try {
            if ($p.Path -and [string]::Equals([IO.Path]::GetFullPath($p.Path),$ExactExe,[StringComparison]::OrdinalIgnoreCase)) {
                $result += $p
            }
        } catch {}
    }
    return @($result)
}

function Get-GameProcesses {
    return @(Get-Process -Name 'lotrbfme2ep1' -ErrorAction SilentlyContinue)
}

if (-not (Test-Path -LiteralPath $Bundle -PathType Container)) { throw ('Candidate bundle missing: ' + $Bundle) }
$Bundle = [IO.Path]::GetFullPath($Bundle)

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' ISSUE #33 RC2 - START ACCEPTANCE GATE V1.1' -ForegroundColor Cyan
Write-Host ' FRESH FIVE-FILE RUN -> REPAIR IF NEEDED -> START -> GAME' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('Source bundle : ' + $Bundle)

$preExistingGame = @(Get-GameProcesses)
if ($preExistingGame.Count -gt 0) {
    throw ('lotrbfme2ep1.exe is already running. Close it before this gate. PID(s): ' + (($preExistingGame | Select-Object -ExpandProperty Id) -join ', '))
}
Write-Host '[PASS] no pre-existing lotrbfme2ep1.exe process' -ForegroundColor Green

foreach ($name in $ExpectedRootFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $Bundle $name) -PathType Leaf)) { throw ('Source bundle missing public artifact: ' + $name) }
}
[void](Assert-Hash (Join-Path $Bundle 'AotR 8P WotR Mod.exe') $ExpectedExeSha 'Source candidate EXE')
[void](Assert-Hash (Join-Path $Bundle 'payload_ui.big') $ExpectedUiSha 'Source UI')
[void](Assert-Hash (Join-Path $Bundle 'payload_paper.inc') $ExpectedPaperSha 'Source paper')

$manifest = Get-Content -LiteralPath (Join-Path $Bundle 'manifest.json') -Raw | ConvertFrom-Json
$repair = Get-Content -LiteralPath (Join-Path $Bundle 'repair-manifest.json') -Raw | ConvertFrom-Json
if ([string]$manifest.launcher_version -ne $ExpectedVersion) { throw ('Source manifest version mismatch: ' + [string]$manifest.launcher_version) }
if ([string]$manifest.launcher_sha256 -ne $ExpectedExeSha) { throw 'Source manifest EXE SHA mismatch.' }
if ([string]$repair.generated_for_launcher -ne $ExpectedVersion) { throw ('Source repair-manifest version mismatch: ' + [string]$repair.generated_for_launcher) }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$testRoot = Join-Path ([IO.Path]::GetDirectoryName($Bundle)) ('_ISSUE33_RC2_START_ACCEPTANCE_' + $stamp)
$runRoot = Join-Path $testRoot 'RUN'
$isolatedLocalAppData = Join-Path $testRoot 'LOCALAPPDATA'
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
New-Item -ItemType Directory -Path $isolatedLocalAppData -Force | Out-Null

foreach ($name in $ExpectedRootFiles) {
    Copy-Item -LiteralPath (Join-Path $Bundle $name) -Destination (Join-Path $runRoot $name) -Force
}

$runFiles = @(Get-ChildItem -LiteralPath $runRoot -File | Select-Object -ExpandProperty Name | Sort-Object)
$expectedSorted = @($ExpectedRootFiles | Sort-Object)
if ($runFiles.Count -ne 5 -or (($runFiles -join "`n") -cne ($expectedSorted -join "`n"))) {
    throw ('Fresh run root is not exactly the five public files. Found: ' + ($runFiles -join ', '))
}
if (Test-Path -LiteralPath (Join-Path $runRoot 'internal')) { throw 'Fresh run root unexpectedly contains internal\ before launch.' }
Write-Host '[PASS] fresh acceptance run contains exactly five public files and no internal\' -ForegroundColor Green

$runExe = [IO.Path]::GetFullPath((Join-Path $runRoot 'AotR 8P WotR Mod.exe'))
$skinPath = Join-Path $runRoot 'internal\assets\launcher_skin.png'
$beforeHashes = @{}
foreach ($name in $ExpectedRootFiles) { $beforeHashes[$name] = Get-Sha256File (Join-Path $runRoot $name) }
[void](Assert-Hash $runExe $ExpectedExeSha 'Run candidate EXE')

$oldLocalAppData = $env:LOCALAPPDATA
$hadAotrHome = Test-Path Env:AOTR_HOME
$oldAotrHome = if ($hadAotrHome) { $env:AOTR_HOME } else { $null }
$launcher = $null
try {
    $env:LOCALAPPDATA = $isolatedLocalAppData
    Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host 'Launching exact RC2 candidate with fresh isolated LOCALAPPDATA...' -ForegroundColor Cyan
    $launcher = Start-Process -FilePath $runExe -WorkingDirectory $runRoot -PassThru
    Write-Host ('Initial launcher PID           : ' + $launcher.Id)
}
finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if ($hadAotrHome) { $env:AOTR_HOME = $oldAotrHome } else { Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue }
}

$skinDeadline = [DateTime]::UtcNow.AddSeconds(20)
while (-not (Test-Path -LiteralPath $skinPath -PathType Leaf)) {
    $launcher.Refresh()
    if ($launcher.HasExited) { throw ('Launcher exited before self-materializing skin. Exit code: ' + $launcher.ExitCode) }
    if ([DateTime]::UtcNow -ge $skinDeadline) { throw ('Timed out waiting for embedded skin: ' + $skinPath) }
    Start-Sleep -Milliseconds 100
}
[void](Assert-Hash $skinPath $ExpectedSkinSha 'Self-materialized skin')
Write-Host '[PASS] standalone skin bootstrap still works in fresh START acceptance run' -ForegroundColor Green

Write-Host ''
Write-Host 'USER ACTION - DO NOT CLICK START YET:' -ForegroundColor Yellow
Write-Host '  1. Wait until the launcher is fully visible.'
Write-Host '  2. Fresh LOCALAPPDATA may show BP WOTR CAMPAIGN / 8-PLAYER WOTR UI as missing.'
Write-Host '  3. If so, click AUTO REPAIR and wait until the required status rows are OK.'
Write-Host '  4. Confirm the AOTR INSTALLATION row is OK.'
Write-Host '  5. Return to this PowerShell window and type READY.'
Write-Host ''
$ready = Read-Host 'Type READY when the launcher is ready for START'
if ($ready.Trim().ToUpperInvariant() -ne 'READY') { throw 'START gate aborted because READY was not confirmed.' }

if (@(Get-GameProcesses).Count -gt 0) { throw 'A game process appeared before START monitoring began. Gate is ambiguous; rerun from clean state.' }
Write-Host ''
Write-Host ('CLICK START NOW. Waiting up to ' + $StartTimeoutSeconds + ' seconds for a fresh lotrbfme2ep1.exe...') -ForegroundColor Yellow

$game = $null
$startDeadline = [DateTime]::UtcNow.AddSeconds($StartTimeoutSeconds)
while (-not $game) {
    $games = @(Get-GameProcesses)
    if ($games.Count -gt 0) {
        $game = @($games | Sort-Object StartTime -Descending | Select-Object -First 1)[0]
        break
    }
    if ([DateTime]::UtcNow -ge $startDeadline) { throw 'Timed out waiting for a fresh lotrbfme2ep1.exe after START.' }
    Start-Sleep -Milliseconds 200
}

$game.Refresh()
$gamePath = $null
$gameStart = $null
try { $gamePath = $game.Path } catch {}
try { $gameStart = $game.StartTime.ToString('o') } catch {}
Write-Host ('Fresh game PID                 : ' + $game.Id) -ForegroundColor Green
if ($gamePath) { Write-Host ('Fresh game path                : ' + $gamePath) -ForegroundColor Green }
if ($gameStart) { Write-Host ('Fresh game start               : ' + $gameStart) }
Write-Host '[PASS] START created a fresh lotrbfme2ep1.exe' -ForegroundColor Green

Write-Host ('Stability window               : ' + $StabilitySeconds + ' seconds')
$stableDeadline = [DateTime]::UtcNow.AddSeconds($StabilitySeconds)
while ([DateTime]::UtcNow -lt $stableDeadline) {
    try {
        $game.Refresh()
        if ($game.HasExited) { throw ('lotrbfme2ep1.exe exited during stability window. Exit code: ' + $game.ExitCode) }
    } catch {
        throw ('lotrbfme2ep1.exe did not survive stability window: ' + $_.Exception.Message)
    }
    Start-Sleep -Milliseconds 500
}
Write-Host '[PASS] lotrbfme2ep1.exe survived the stability window' -ForegroundColor Green

Write-Host ('Waiting up to ' + $HandoffTimeoutSeconds + ' seconds for launcher handoff/exit...')
$handoffDeadline = [DateTime]::UtcNow.AddSeconds($HandoffTimeoutSeconds)
while (@(Get-CandidateLauncherProcesses $runExe).Count -gt 0 -and [DateTime]::UtcNow -lt $handoffDeadline) {
    Start-Sleep -Milliseconds 250
}
$remainingLaunchers = @(Get-CandidateLauncherProcesses $runExe)
if ($remainingLaunchers.Count -gt 0) {
    throw ('Candidate launcher did not exit after START handoff. Remaining PID(s): ' + (($remainingLaunchers | Select-Object -ExpandProperty Id) -join ', '))
}
Write-Host '[PASS] launcher handed off and exited after successful START' -ForegroundColor Green

[void](Assert-Hash $runExe $ExpectedExeSha 'Candidate EXE after START')
[void](Assert-Hash $skinPath $ExpectedSkinSha 'Skin after START')
foreach ($name in $ExpectedRootFiles) {
    $after = Get-Sha256File (Join-Path $runRoot $name)
    if ($after -ne $beforeHashes[$name]) { throw ('Public release artifact changed during START gate: ' + $name) }
}
Write-Host '[PASS] all five public release artifacts remained byte-identical' -ForegroundColor Green

$report = Join-Path $testRoot 'ISSUE33_RC2_START_ACCEPTANCE_REPORT.txt'
$lines = @(
    'AOTR 8P WOTR ISSUE #33 RC2 START ACCEPTANCE: PASS',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Source bundle: ' + $Bundle),
    ('Fresh run root: ' + $runRoot),
    ('Candidate version: ' + $ExpectedVersion),
    ('Candidate EXE SHA256: ' + $ExpectedExeSha),
    ('Skin SHA256: ' + $ExpectedSkinSha),
    ('UI SHA256: ' + $ExpectedUiSha),
    ('Paper SHA256: ' + $ExpectedPaperSha),
    ('Fresh game PID: ' + $game.Id),
    ('Fresh game path: ' + [string]$gamePath),
    ('Fresh game start: ' + [string]$gameStart),
    ('Stability seconds: ' + $StabilitySeconds),
    'Fresh five-file root before launch: PASS',
    'Embedded skin bootstrap: PASS',
    'Fresh lotrbfme2ep1.exe after START: PASS',
    'Game stability window: PASS',
    'Launcher handoff/exit: PASS',
    'Public release artifacts unchanged: PASS',
    ('Isolated LOCALAPPDATA: ' + $isolatedLocalAppData)
)
[IO.File]::WriteAllLines($report,$lines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' ISSUE #33 RC2 START ACCEPTANCE: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('Candidate EXE : ' + $ExpectedExeSha) -ForegroundColor Green
Write-Host ('Game PID      : ' + $game.Id) -ForegroundColor Green
Write-Host ('Stability     : ' + $StabilitySeconds + ' s') -ForegroundColor Green
Write-Host ('Report        : ' + $report)
Write-Host ''
Write-Host 'You can now close the game normally. NEXT: regression/CI gates and guarded PR.' -ForegroundColor Cyan
