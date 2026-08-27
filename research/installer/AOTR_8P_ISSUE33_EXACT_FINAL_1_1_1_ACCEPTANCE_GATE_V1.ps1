#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Bundle = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_054456\PACKAGE\_GITHUB_UPDATE',
    [int]$StabilitySeconds = 15,
    [int]$StartTimeoutSeconds = 180,
    [int]$CleanupTimeoutSeconds = 120,
    [int]$HandoffTimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedVersion = '1.1.1'
$ExpectedExeSha = '2141EA9690708EA7A61B7298AD90E0C76CC417FED996AC0CF3685276BA2A4024'
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
    Write-Host (('{0,-36}: {1}' -f $Label,$actual)) -ForegroundColor Green
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

function Start-IsolatedCandidate([string]$Exe,[string]$WorkingDir,[string]$IsolatedLocalAppData) {
    $oldLocalAppData = $env:LOCALAPPDATA
    $hadAotrHome = Test-Path Env:AOTR_HOME
    $oldAotrHome = if ($hadAotrHome) { $env:AOTR_HOME } else { $null }
    try {
        $env:LOCALAPPDATA = $IsolatedLocalAppData
        Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue
        return Start-Process -FilePath $Exe -WorkingDirectory $WorkingDir -PassThru
    }
    finally {
        $env:LOCALAPPDATA = $oldLocalAppData
        if ($hadAotrHome) { $env:AOTR_HOME = $oldAotrHome } else { Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue }
    }
}

function Wait-ForNoGame([int]$TimeoutSeconds,[string]$Reason) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (@(Get-GameProcesses).Count -gt 0) {
        if ([DateTime]::UtcNow -ge $deadline) {
            $pids = @((Get-GameProcesses) | Select-Object -ExpandProperty Id)
            throw ($Reason + ' Timed out waiting for lotrbfme2ep1.exe to exit. PID(s): ' + ($pids -join ', '))
        }
        Start-Sleep -Milliseconds 250
    }
}

function Wait-ForNoCandidateLauncher([string]$ExactExe,[int]$TimeoutSeconds,[string]$Reason) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (@(Get-CandidateLauncherProcesses $ExactExe).Count -gt 0) {
        if ([DateTime]::UtcNow -ge $deadline) {
            $pids = @((Get-CandidateLauncherProcesses $ExactExe) | Select-Object -ExpandProperty Id)
            throw ($Reason + ' Timed out waiting for candidate launcher to exit. PID(s): ' + ($pids -join ', '))
        }
        Start-Sleep -Milliseconds 250
    }
}

if (-not (Test-Path -LiteralPath $Bundle -PathType Container)) { throw ('Final bundle missing: ' + $Bundle) }
$Bundle = [IO.Path]::GetFullPath($Bundle)

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' ISSUE #33 EXACT FINAL 1.1.1 ACCEPTANCE GATE' -ForegroundColor Cyan
Write-Host ' FRESH FIVE FILES -> PROVISION -> CLEAN MANUAL START' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('Source bundle : ' + $Bundle)
Write-Host ''

$preExistingGame = @(Get-GameProcesses)
if ($preExistingGame.Count -gt 0) {
    throw ('lotrbfme2ep1.exe is already running before the gate. Close it first. PID(s): ' + (($preExistingGame | Select-Object -ExpandProperty Id) -join ', '))
}
Write-Host '[PASS] no pre-existing lotrbfme2ep1.exe process' -ForegroundColor Green

$sourceFiles = @(Get-ChildItem -LiteralPath $Bundle -File | Select-Object -ExpandProperty Name | Sort-Object)
$expectedSorted = @($ExpectedRootFiles | Sort-Object)
if ($sourceFiles.Count -ne 5 -or (($sourceFiles -join "`n") -cne ($expectedSorted -join "`n"))) {
    throw ('Source final bundle is not exactly the five public files. Found: ' + ($sourceFiles -join ', '))
}
if (Test-Path -LiteralPath (Join-Path $Bundle 'internal')) { throw 'Source final bundle unexpectedly contains internal\.' }
Write-Host '[PASS] source final bundle contains exactly five public files and no internal\' -ForegroundColor Green

[void](Assert-Hash (Join-Path $Bundle 'AotR 8P WotR Mod.exe') $ExpectedExeSha 'Source final EXE')
[void](Assert-Hash (Join-Path $Bundle 'payload_ui.big') $ExpectedUiSha 'Source final UI')
[void](Assert-Hash (Join-Path $Bundle 'payload_paper.inc') $ExpectedPaperSha 'Source final paper')

$manifest = Get-Content -LiteralPath (Join-Path $Bundle 'manifest.json') -Raw | ConvertFrom-Json
$repair = Get-Content -LiteralPath (Join-Path $Bundle 'repair-manifest.json') -Raw | ConvertFrom-Json
if ([int]$manifest.schema -ne 1) { throw ('manifest schema mismatch: ' + [string]$manifest.schema) }
if ([string]$manifest.launcher_version -ne $ExpectedVersion) { throw ('manifest launcher_version mismatch: ' + [string]$manifest.launcher_version) }
if ([string]$manifest.launcher_sha256 -ne $ExpectedExeSha) { throw ('manifest launcher_sha256 mismatch: ' + [string]$manifest.launcher_sha256) }
if ([int]$repair.schema -ne 1) { throw ('repair-manifest schema mismatch: ' + [string]$repair.schema) }
if ([string]$repair.generated_for_launcher -ne $ExpectedVersion) { throw ('repair-manifest generated_for_launcher mismatch: ' + [string]$repair.generated_for_launcher) }
foreach ($planName in @('A8P-PAYLOAD-UI-001','A8P-PAYLOAD-PAPER-001')) {
    $plan = $repair.plans.$planName
    if ($null -eq $plan) { throw ('Required repair plan missing: ' + $planName) }
    if (@($plan.actions) -notcontains 'retry_launch') { throw ($planName + ' no longer contains retry_launch; gate assumptions changed.') }
}
Write-Host '[PASS] exact final manifests and repair retry behavior verified' -ForegroundColor Green

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$testRoot = Join-Path ([IO.Path]::GetDirectoryName($Bundle)) ('_ISSUE33_EXACT_FINAL_1_1_1_ACCEPTANCE_' + $stamp)
$runRoot = Join-Path $testRoot 'RUN'
$isolatedLocalAppData = Join-Path $testRoot 'LOCALAPPDATA'
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
New-Item -ItemType Directory -Path $isolatedLocalAppData -Force | Out-Null
foreach ($name in $ExpectedRootFiles) { Copy-Item -LiteralPath (Join-Path $Bundle $name) -Destination (Join-Path $runRoot $name) -Force }

$runFiles = @(Get-ChildItem -LiteralPath $runRoot -File | Select-Object -ExpandProperty Name | Sort-Object)
if ($runFiles.Count -ne 5 -or (($runFiles -join "`n") -cne ($expectedSorted -join "`n"))) {
    throw ('Fresh run root is not exactly the five public files. Found: ' + ($runFiles -join ', '))
}
if (Test-Path -LiteralPath (Join-Path $runRoot 'internal')) { throw 'Fresh run root unexpectedly contains internal\ before launch.' }
Write-Host '[PASS] fresh exact-final run contains five files and no internal\' -ForegroundColor Green

$runExe = [IO.Path]::GetFullPath((Join-Path $runRoot 'AotR 8P WotR Mod.exe'))
$skinPath = Join-Path $runRoot 'internal\assets\launcher_skin.png'
$beforeHashes = @{}
foreach ($name in $ExpectedRootFiles) { $beforeHashes[$name] = Get-Sha256File (Join-Path $runRoot $name) }
[void](Assert-Hash $runExe $ExpectedExeSha 'Run final EXE')

Write-Host ''
Write-Host '==================== PHASE A - PROVISION ====================' -ForegroundColor Cyan
$phaseALauncher = Start-IsolatedCandidate $runExe $runRoot $isolatedLocalAppData
Write-Host ('Phase A launcher PID              : ' + $phaseALauncher.Id)
$skinDeadline = [DateTime]::UtcNow.AddSeconds(20)
while (-not (Test-Path -LiteralPath $skinPath -PathType Leaf)) {
    $phaseALauncher.Refresh()
    if ($phaseALauncher.HasExited) { throw ('Phase A launcher exited before materializing skin. Exit code: ' + $phaseALauncher.ExitCode) }
    if ([DateTime]::UtcNow -ge $skinDeadline) { throw ('Timed out waiting for embedded skin: ' + $skinPath) }
    Start-Sleep -Milliseconds 100
}
[void](Assert-Hash $skinPath $ExpectedSkinSha 'Phase A materialized skin')
Write-Host '[PASS] exact final EXE self-materialized the frozen skin' -ForegroundColor Green

Write-Host ''
Write-Host 'PHASE A USER ACTION:' -ForegroundColor Yellow
Write-Host '  1. Wait for the launcher UI.'
Write-Host '  2. If BP WOTR CAMPAIGN / 8-PLAYER WOTR UI are missing, click AUTO REPAIR.'
Write-Host '  3. Let AUTO REPAIR finish completely.'
Write-Host '  4. Its retry_launch may start the game automatically; that is expected here.'
Write-Host '  5. Return here and type PREPARED.'
$prepared = Read-Host 'Type PREPARED when provisioning is finished'
if ($prepared.Trim().ToUpperInvariant() -ne 'PREPARED') { throw 'Phase A aborted because PREPARED was not confirmed.' }

Start-Sleep -Seconds 3
$phaseAGames = @(Get-GameProcesses)
$phaseARetryLaunchObserved = ($phaseAGames.Count -gt 0)
if ($phaseARetryLaunchObserved) {
    Write-Host ('[INFO] Phase A retry_launch produced game PID(s): ' + (($phaseAGames | Select-Object -ExpandProperty Id) -join ', ')) -ForegroundColor Yellow
    Write-Host 'Close the Phase A game normally now; it does not count as manual START evidence.' -ForegroundColor Yellow
    Wait-ForNoGame $CleanupTimeoutSeconds 'Phase A cleanup.'
    Write-Host '[PASS] Phase A auto-launched game closed' -ForegroundColor Green
}
$phaseALaunchers = @(Get-CandidateLauncherProcesses $runExe)
if ($phaseALaunchers.Count -gt 0) {
    Write-Host ('Close the remaining Phase A launcher with X now. PID(s): ' + (($phaseALaunchers | Select-Object -ExpandProperty Id) -join ', ')) -ForegroundColor Yellow
    Wait-ForNoCandidateLauncher $runExe $CleanupTimeoutSeconds 'Phase A cleanup.'
}
Write-Host '[PASS] Phase A launcher is no longer running' -ForegroundColor Green

$quiescentUntil = [DateTime]::UtcNow.AddSeconds(3)
while ([DateTime]::UtcNow -lt $quiescentUntil) {
    if (@(Get-GameProcesses).Count -gt 0) { throw 'Late Phase A game appeared during clean-baseline check.' }
    if (@(Get-CandidateLauncherProcesses $runExe).Count -gt 0) { throw 'Late Phase A launcher appeared during clean-baseline check.' }
    Start-Sleep -Milliseconds 250
}
Write-Host '[PASS] clean process baseline established for Phase B' -ForegroundColor Green

[void](Assert-Hash $runExe $ExpectedExeSha 'EXE after Phase A')
[void](Assert-Hash $skinPath $ExpectedSkinSha 'Skin after Phase A')
foreach ($name in $ExpectedRootFiles) {
    $afterPhaseA = Get-Sha256File (Join-Path $runRoot $name)
    if ($afterPhaseA -ne $beforeHashes[$name]) { throw ('Public release artifact changed during Phase A: ' + $name) }
}
Write-Host '[PASS] five public release artifacts stayed byte-identical through provisioning' -ForegroundColor Green

Write-Host ''
Write-Host '================== PHASE B - MANUAL START ==================' -ForegroundColor Cyan
$phaseBLauncher = Start-IsolatedCandidate $runExe $runRoot $isolatedLocalAppData
Write-Host ('Phase B launcher PID              : ' + $phaseBLauncher.Id)
Start-Sleep -Seconds 2
$phaseBLauncher.Refresh()
if ($phaseBLauncher.HasExited) { throw ('Phase B launcher exited before READY. Exit code: ' + $phaseBLauncher.ExitCode) }
[void](Assert-Hash $skinPath $ExpectedSkinSha 'Phase B skin')

Write-Host ''
Write-Host 'PHASE B USER ACTION - DO NOT CLICK AUTO REPAIR OR START YET:' -ForegroundColor Yellow
Write-Host '  1. Confirm AOTR INSTALLATION is OK.'
Write-Host '  2. Confirm BP WOTR CAMPAIGN is OK.'
Write-Host '  3. Confirm 8-PLAYER WOTR UI is OK.'
Write-Host '  4. Return here and type READY.'
$ready = Read-Host 'Type READY when all three required rows are OK'
if ($ready.Trim().ToUpperInvariant() -ne 'READY') { throw 'Phase B aborted because READY was not confirmed.' }
if (@(Get-GameProcesses).Count -gt 0) { throw 'Game process exists before the manual START monitoring point.' }

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
    if ([DateTime]::UtcNow -ge $startDeadline) { throw 'Timed out waiting for fresh lotrbfme2ep1.exe after manual START.' }
    Start-Sleep -Milliseconds 200
}

$game.Refresh()
$gamePath = $null
$gameStart = $null
try { $gamePath = $game.Path } catch {}
try { $gameStart = $game.StartTime.ToString('o') } catch {}
Write-Host ('Fresh game PID                   : ' + $game.Id) -ForegroundColor Green
if ($gamePath) { Write-Host ('Fresh game path                  : ' + $gamePath) -ForegroundColor Green }
if ($gameStart) { Write-Host ('Fresh game start                 : ' + $gameStart) }
Write-Host '[PASS] manual START created a fresh lotrbfme2ep1.exe' -ForegroundColor Green

Write-Host ('Stability window                 : ' + $StabilitySeconds + ' seconds')
$stableDeadline = [DateTime]::UtcNow.AddSeconds($StabilitySeconds)
while ([DateTime]::UtcNow -lt $stableDeadline) {
    $game.Refresh()
    if ($game.HasExited) { throw ('lotrbfme2ep1.exe exited during stability window. Exit code: ' + $game.ExitCode) }
    Start-Sleep -Milliseconds 500
}
Write-Host '[PASS] lotrbfme2ep1.exe survived the stability window' -ForegroundColor Green

$handoffDeadline = [DateTime]::UtcNow.AddSeconds($HandoffTimeoutSeconds)
while (@(Get-CandidateLauncherProcesses $runExe).Count -gt 0 -and [DateTime]::UtcNow -lt $handoffDeadline) {
    Start-Sleep -Milliseconds 250
}
$remainingLaunchers = @(Get-CandidateLauncherProcesses $runExe)
if ($remainingLaunchers.Count -gt 0) {
    throw ('Final candidate launcher did not exit after START handoff. Remaining PID(s): ' + (($remainingLaunchers | Select-Object -ExpandProperty Id) -join ', '))
}
Write-Host '[PASS] launcher handed off and exited after successful START' -ForegroundColor Green

[void](Assert-Hash $runExe $ExpectedExeSha 'Final EXE after START')
[void](Assert-Hash $skinPath $ExpectedSkinSha 'Skin after START')
foreach ($name in $ExpectedRootFiles) {
    $after = Get-Sha256File (Join-Path $runRoot $name)
    if ($after -ne $beforeHashes[$name]) { throw ('Public release artifact changed during exact-final gate: ' + $name) }
}
Write-Host '[PASS] all five public release artifacts remained byte-identical' -ForegroundColor Green

$report = Join-Path $testRoot 'ISSUE33_EXACT_FINAL_1_1_1_ACCEPTANCE_REPORT.txt'
$lines = @(
    'AOTR 8P WOTR ISSUE #33 EXACT FINAL 1.1.1 ACCEPTANCE: PASS',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Source bundle: ' + $Bundle),
    ('Fresh run root: ' + $runRoot),
    ('Final version: ' + $ExpectedVersion),
    ('Final EXE SHA256: ' + $ExpectedExeSha),
    ('Skin SHA256: ' + $ExpectedSkinSha),
    ('UI SHA256: ' + $ExpectedUiSha),
    ('Paper SHA256: ' + $ExpectedPaperSha),
    ('Fresh game PID: ' + $game.Id),
    ('Fresh game path: ' + [string]$gamePath),
    ('Fresh game start: ' + [string]$gameStart),
    ('Stability seconds: ' + $StabilitySeconds),
    ('Phase A retry_launch observed: ' + $phaseARetryLaunchObserved),
    'Fresh five-file root: PASS',
    'Embedded skin bootstrap: PASS',
    'Provisioning isolation: PASS',
    'Manual START fresh game: PASS',
    'Game stability: PASS',
    'Launcher handoff: PASS',
    'Public release artifacts unchanged: PASS',
    ('Isolated LOCALAPPDATA: ' + $isolatedLocalAppData)
)
[IO.File]::WriteAllLines($report,$lines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' ISSUE #33 EXACT FINAL 1.1.1 ACCEPTANCE: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('Final EXE    : ' + $ExpectedExeSha) -ForegroundColor Green
Write-Host ('Game PID     : ' + $game.Id) -ForegroundColor Green
Write-Host ('Stability    : ' + $StabilitySeconds + ' s') -ForegroundColor Green
Write-Host ('Repair retry : ' + $phaseARetryLaunchObserved) -ForegroundColor Green
Write-Host ('Report       : ' + $report)
Write-Host ''
Write-Host 'You can now close the game normally. NEXT: stage exact release files + FINAL_1_1_1 builder for guarded PR.' -ForegroundColor Cyan
