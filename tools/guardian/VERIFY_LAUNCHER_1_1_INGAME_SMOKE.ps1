#requires -version 5.1
[CmdletBinding()]
param(
    [string]$PackageRoot = "",
    [int]$GameStartTimeoutSeconds = 180,
    [int]$GameStableSeconds = 10,
    [int]$LauncherExitTimeoutSeconds = 30
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedLauncherVersion = "1.1"
$ExpectedLauncherSha256 = "9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4"
$ExpectedUiSha256 = "827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376"
$ExpectedPaperSha256 = "3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43"

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToUpperInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Add-Result(
    [System.Collections.Generic.List[string]]$Lines,
    [string]$Name,
    [bool]$Pass,
    [string]$Detail
) {
    $status = if ($Pass) { "PASS" } else { "FAIL" }
    $Lines.Add(("- **{0}:** {1} - {2}" -f $Name, $status, $Detail))
}

function Write-Report(
    [System.Collections.Generic.List[string]]$Lines,
    [string]$Path
) {
    $Lines | Set-Content -LiteralPath $Path -Encoding UTF8
}

if ($GameStartTimeoutSeconds -lt 1) { throw "GameStartTimeoutSeconds must be at least 1." }
if ($GameStableSeconds -lt 1) { throw "GameStableSeconds must be at least 1." }
if ($LauncherExitTimeoutSeconds -lt 1) { throw "LauncherExitTimeoutSeconds must be at least 1." }

if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
}
else {
    $PackageRoot = [IO.Path]::GetFullPath($PackageRoot)
}

$LauncherPath = Join-Path $PackageRoot "AotR 8P WotR Mod.exe"
$ManifestPath = Join-Path $PackageRoot "manifest.json"
$RepairManifestPath = Join-Path $PackageRoot "repair-manifest.json"
$UiPath = Join-Path $PackageRoot "payload_ui.big"
$PaperPath = Join-Path $PackageRoot "payload_paper.inc"

foreach ($required in @($LauncherPath, $ManifestPath, $RepairManifestPath, $UiPath, $PaperPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required release file missing: $required"
    }
}

$Manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$RepairManifest = Get-Content -LiteralPath $RepairManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

$LauncherHash = Get-Sha256 $LauncherPath
$UiHash = Get-Sha256 $UiPath
$PaperHash = Get-Sha256 $PaperPath

if ([string]$Manifest.launcher_version -ne $ExpectedLauncherVersion) {
    throw "manifest.json launcher_version is '$($Manifest.launcher_version)', expected '$ExpectedLauncherVersion'."
}
if ([string]$RepairManifest.generated_for_launcher -ne $ExpectedLauncherVersion) {
    throw "repair-manifest.json generated_for_launcher is '$($RepairManifest.generated_for_launcher)', expected '$ExpectedLauncherVersion'."
}
if ($LauncherHash -ne $ExpectedLauncherSha256) {
    throw "Launcher SHA256 mismatch. Expected $ExpectedLauncherSha256, got $LauncherHash."
}
if ($UiHash -ne $ExpectedUiSha256) {
    throw "UI SHA256 mismatch. Expected $ExpectedUiSha256, got $UiHash."
}
if ($PaperHash -ne $ExpectedPaperSha256) {
    throw "Paper SHA256 mismatch. Expected $ExpectedPaperSha256, got $PaperHash."
}
if ([string]$Manifest.launcher_sha256 -ne $LauncherHash) {
    throw "manifest.json launcher_sha256 does not match the tested EXE."
}
if ([string]$Manifest.ui_sha256 -ne $UiHash) {
    throw "manifest.json ui_sha256 does not match payload_ui.big."
}
if ([string]$Manifest.paper_sha256 -ne $PaperHash) {
    throw "manifest.json paper_sha256 does not match payload_paper.inc."
}

$ExistingGame = @(Get-Process -Name "lotrbfme2ep1" -ErrorAction SilentlyContinue)
if ($ExistingGame.Count -gt 0) {
    $ids = ($ExistingGame | ForEach-Object { $_.Id }) -join ", "
    throw "A lotrbfme2ep1.exe process is already running (PID(s): $ids). Close it before this smoke test so a stale process cannot create a false PASS."
}

$StartUtc = [DateTime]::UtcNow
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ReportRoot = Join-Path $env:TEMP "AotR8P_Guardian"
New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null
$ReportPath = Join-Path $ReportRoot ("LAUNCHER_1_1_INGAME_SMOKE_{0}.md" -f $Stamp)

$Lines = New-Object 'System.Collections.Generic.List[string]'
$Lines.Add("# Launcher 1.1 exact-final in-game smoke")
$Lines.Add("")
$Lines.Add(("- Timestamp: {0}" -f (Get-Date -Format o)))
$Lines.Add(("- Package root: {0}" -f $PackageRoot))
$Lines.Add(("- Launcher SHA256: {0}" -f $LauncherHash))
$Lines.Add(("- Expected release SHA256: {0}" -f $ExpectedLauncherSha256))
$Lines.Add("")
$Lines.Add("## Results")
$Lines.Add("")

Add-Result $Lines "Release identity" $true "launcher 1.1 EXE, manifest, repair manifest, UI and PaperScenario hashes match the frozen release values."

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " AotR 8P WotR - Launcher 1.1 exact-final smoke" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Launcher SHA256 verified:" -ForegroundColor Green
Write-Host "  $LauncherHash"
Write-Host ""
Write-Host "The exact frozen 1.1 EXE will open now." -ForegroundColor Yellow
Write-Host "In the launcher, press START once. This script will detect the new AotR game process automatically." -ForegroundColor Yellow
Write-Host "Do not manually start AotR outside the launcher during this test." -ForegroundColor Yellow
Write-Host ""

$LauncherProcess = Start-Process -FilePath $LauncherPath -WorkingDirectory $PackageRoot -PassThru
$Lines.Add(("- Launcher PID: {0}" -f $LauncherProcess.Id))

$GameProcess = $null
$LauncherExitedBeforeGame = $false
$Deadline = [DateTime]::UtcNow.AddSeconds($GameStartTimeoutSeconds)

while ([DateTime]::UtcNow -lt $Deadline) {
    $candidates = @(Get-Process -Name "lotrbfme2ep1" -ErrorAction SilentlyContinue)
    foreach ($candidate in $candidates) {
        try {
            if ($candidate.StartTime.ToUniversalTime() -ge $StartUtc.AddSeconds(-2)) {
                $GameProcess = $candidate
                break
            }
        }
        catch {
            # Ignore a process that disappears while being inspected.
        }
    }

    if ($GameProcess) { break }

    if (-not (Get-Process -Id $LauncherProcess.Id -ErrorAction SilentlyContinue)) {
        $LauncherExitedBeforeGame = $true
        break
    }

    Start-Sleep -Milliseconds 500
}

if (-not $GameProcess) {
    if ($LauncherExitedBeforeGame) {
        $gameStartDetail = "launcher exited before a new lotrbfme2ep1.exe process appeared."
    }
    else {
        $gameStartDetail = "no new lotrbfme2ep1.exe process appeared within $GameStartTimeoutSeconds seconds."
    }

    Add-Result $Lines "START -> AotR process" $false $gameStartDetail
    $Lines.Add("")
    $Lines.Add("Overall: **FAIL**")
    Write-Report $Lines $ReportPath
    Write-Host "FAIL: no new lotrbfme2ep1.exe process detected." -ForegroundColor Red
    Write-Host "Report: $ReportPath"
    exit 1
}

Add-Result $Lines "START -> AotR process" $true ("new lotrbfme2ep1.exe detected as PID {0}." -f $GameProcess.Id)
Write-Host ("Detected AotR game process PID {0}." -f $GameProcess.Id) -ForegroundColor Green

$GameStable = $true
for ($i = 0; $i -lt $GameStableSeconds; $i++) {
    Start-Sleep -Seconds 1
    if (-not (Get-Process -Id $GameProcess.Id -ErrorAction SilentlyContinue)) {
        $GameStable = $false
        break
    }
}

if ($GameStable) {
    $GameStableDetail = "game process remained alive for at least $GameStableSeconds seconds."
}
else {
    $GameStableDetail = "game process exited before the $GameStableSeconds-second stability window completed."
}
Add-Result $Lines "Game process stability" $GameStable $GameStableDetail

$LauncherExited = $false
$LauncherDeadline = [DateTime]::UtcNow.AddSeconds($LauncherExitTimeoutSeconds)
while ([DateTime]::UtcNow -lt $LauncherDeadline) {
    if (-not (Get-Process -Id $LauncherProcess.Id -ErrorAction SilentlyContinue)) {
        $LauncherExited = $true
        break
    }
    Start-Sleep -Milliseconds 500
}

if ($LauncherExited) {
    $LauncherExitDetail = "launcher process exited after handing off to AotR."
}
else {
    $LauncherExitDetail = "launcher process was still present after $LauncherExitTimeoutSeconds seconds."
}
Add-Result $Lines "Launcher exits after game start" $LauncherExited $LauncherExitDetail

$OverallPass = $GameStable -and $LauncherExited
$OverallText = if ($OverallPass) { "PASS" } else { "FAIL" }

$Lines.Add("")
$Lines.Add("## Evidence boundary")
$Lines.Add("")
$Lines.Add("This automated smoke proves that the exact frozen launcher 1.1 artifact accepted START, created a fresh AotR lotrbfme2ep1.exe process, and, when PASS, that the game process remained alive through the configured stability window while the launcher exited after handoff.")
$Lines.Add("")
$Lines.Add("It does not by itself prove multiplayer/OOS behavior, strategic-turn correctness, or every internal RAM patch. Those remain covered by their own reverse-engineering/runtime checkpoints.")
$Lines.Add("")
$Lines.Add(("Overall: **{0}**" -f $OverallText))

Write-Report $Lines $ReportPath

if ($OverallPass) {
    Write-Host "PASS: exact launcher 1.1 START -> AotR smoke succeeded." -ForegroundColor Green
    Write-Host "Report: $ReportPath"
    exit 0
}

Write-Host "FAIL: AotR started, but one or more handoff/stability checks failed." -ForegroundColor Red
Write-Host "Report: $ReportPath"
exit 2
