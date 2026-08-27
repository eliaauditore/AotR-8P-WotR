#requires -version 7.0
[CmdletBinding()]
param(
    [string]$WorkRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_054456'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$AcceptedBuilderName = 'BUILD_ISSUE33_STANDALONE_SKIN_RC2.ps1'
$CanonicalBuilderName = 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_1.ps1'
$ExpectedAcceptedBuilderSha = 'B30EAFB0ABCE94DC22E5121FB7F9B3B9AF31A6D2FCDB5E5B14CB4056AF392560'
$ExpectedExeSha = '2141EA9690708EA7A61B7298AD90E0C76CC417FED996AC0CF3685276BA2A4024'
$ExpectedUiSha = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
$ExpectedSkinSha = 'BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6'
$ExpectedFiles = @('AotR 8P WotR Mod.exe','manifest.json','repair-manifest.json','payload_ui.big','payload_paper.inc')

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
    Write-Host (('{0,-38}: {1}' -f $Label,$actual)) -ForegroundColor Green
    return $actual
}

function Assert-PowerShellText([string]$Text,[string]$Label) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        $messages = @($errors | ForEach-Object { $_.Message })
        throw ($Label + ' parser errors: ' + ($messages -join '; '))
    }
}

function Replace-ExactOnce([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $count = 0
    $index = 0
    while (($found = $Text.IndexOf($Old,$index,[StringComparison]::Ordinal)) -ge 0) {
        $count++
        $index = $found + $Old.Length
    }
    if ($count -ne 1) { throw ('Expected exactly one target for ' + $Label + ', found ' + $count) }
    return $Text.Replace($Old,$New)
}

if (-not (Test-Path -LiteralPath $WorkRoot -PathType Container)) { throw ('Work root missing: ' + $WorkRoot) }
$acceptedBuilder = Join-Path $WorkRoot $AcceptedBuilderName
$canonicalBuilder = Join-Path $WorkRoot $CanonicalBuilderName
$acceptedPackage = Join-Path $WorkRoot 'PACKAGE'
$acceptedBundle = Join-Path $acceptedPackage '_GITHUB_UPDATE'
$acceptedSkin = Join-Path $acceptedPackage 'internal\assets\launcher_skin.png'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' ISSUE #33 - FINALIZE CANONICAL FINAL_1_1_1 BUILDER' -ForegroundColor Cyan
Write-Host ' EXACT ONE-LINE DEFAULT CHANGE + DEFAULT-VERSION REPRODUCTION' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('Work root        : ' + $WorkRoot)
Write-Host ('Accepted builder : ' + $acceptedBuilder)
Write-Host ('Canonical output : ' + $canonicalBuilder)
Write-Host ''

[void](Assert-Hash $acceptedBuilder $ExpectedAcceptedBuilderSha 'Accepted final-build builder')
[void](Assert-Hash (Join-Path $acceptedBundle 'AotR 8P WotR Mod.exe') $ExpectedExeSha 'Accepted final EXE')
[void](Assert-Hash (Join-Path $acceptedBundle 'payload_ui.big') $ExpectedUiSha 'Accepted UI')
[void](Assert-Hash (Join-Path $acceptedBundle 'payload_paper.inc') $ExpectedPaperSha 'Accepted paper')
[void](Assert-Hash $acceptedSkin $ExpectedSkinSha 'Accepted source skin')

$acceptedManifest = Get-Content -LiteralPath (Join-Path $acceptedBundle 'manifest.json') -Raw | ConvertFrom-Json
$acceptedRepair = Get-Content -LiteralPath (Join-Path $acceptedBundle 'repair-manifest.json') -Raw | ConvertFrom-Json
if ([string]$acceptedManifest.launcher_version -ne '1.1.1') { throw ('Accepted manifest version is not 1.1.1: ' + [string]$acceptedManifest.launcher_version) }
if ([string]$acceptedManifest.launcher_sha256 -ne $ExpectedExeSha) { throw 'Accepted manifest EXE hash mismatch.' }
if ([string]$acceptedRepair.generated_for_launcher -ne '1.1.1') { throw ('Accepted repair-manifest version is not 1.1.1: ' + [string]$acceptedRepair.generated_for_launcher) }

$bytes = [IO.File]::ReadAllBytes($acceptedBuilder)
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$offset = if ($hasBom) { 3 } else { 0 }
$text = [Text.UTF8Encoding]::new($false,$true).GetString($bytes,$offset,$bytes.Length-$offset)
Assert-PowerShellText $text 'Accepted builder'

$oldDefault = '[string]$LauncherVersion = "1.1",'
$newDefault = '[string]$LauncherVersion = "1.1.1",'
$oldCount = 0
$scan = 0
while (($found = $text.IndexOf($oldDefault,$scan,[StringComparison]::Ordinal)) -ge 0) { $oldCount++; $scan = $found + $oldDefault.Length }
$newCountBefore = 0
$scan = 0
while (($found = $text.IndexOf($newDefault,$scan,[StringComparison]::Ordinal)) -ge 0) { $newCountBefore++; $scan = $found + $newDefault.Length }
if ($oldCount -ne 1) { throw ('Accepted builder must contain exactly one LauncherVersion default 1.1; found ' + $oldCount) }
if ($newCountBefore -ne 0) { throw ('Accepted builder unexpectedly already contains LauncherVersion default 1.1.1; found ' + $newCountBefore) }
Write-Host '[PASS] root cause confirmed: accepted builder default is exactly 1.1 while final build passed 1.1.1 explicitly' -ForegroundColor Green

$patched = Replace-ExactOnce $text $oldDefault $newDefault 'LauncherVersion default 1.1 -> 1.1.1'
$reverted = Replace-ExactOnce $patched $newDefault $oldDefault 'round-trip LauncherVersion default'
if ($reverted -cne $text) { throw 'Round-trip verification failed: more than the LauncherVersion default would change.' }
Assert-PowerShellText $patched 'Canonical FINAL_1_1_1 builder'

$utf8 = [Text.UTF8Encoding]::new($false)
$patchedBytes = $utf8.GetBytes($patched)
if ($hasBom) {
    $preamble = [Text.UTF8Encoding]::new($true).GetPreamble()
    $outBytes = New-Object byte[] ($preamble.Length + $patchedBytes.Length)
    [Array]::Copy($preamble,0,$outBytes,0,$preamble.Length)
    [Array]::Copy($patchedBytes,0,$outBytes,$preamble.Length,$patchedBytes.Length)
    [IO.File]::WriteAllBytes($canonicalBuilder,$outBytes)
} else {
    [IO.File]::WriteAllBytes($canonicalBuilder,$patchedBytes)
}

$canonicalSha = Get-Sha256File $canonicalBuilder
$canonicalText = Get-Content -LiteralPath $canonicalBuilder -Raw
Assert-PowerShellText $canonicalText 'Written canonical FINAL_1_1_1 builder'
if (($canonicalText.Split($newDefault,[StringSplitOptions]::None).Count - 1) -ne 1) { throw 'Written canonical builder does not contain exactly one 1.1.1 default.' }
if (($canonicalText.Split($oldDefault,[StringSplitOptions]::None).Count - 1) -ne 0) { throw 'Written canonical builder still contains the old 1.1 default.' }
Write-Host ('Canonical FINAL_1_1_1 SHA256       : ' + $canonicalSha) -ForegroundColor Green
Write-Host '[PASS] canonical builder differs from accepted builder only by the default LauncherVersion value' -ForegroundColor Green

# Reproduce from the canonical builder WITHOUT passing -LauncherVersion.
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$reproRoot = Join-Path $WorkRoot ('CANONICAL_FINAL_1_1_1_REPRO_' + $stamp)
$reproPackage = Join-Path $reproRoot 'PACKAGE'
New-Item -ItemType Directory -Path $reproRoot -Force | Out-Null
Copy-Item -LiteralPath $acceptedPackage -Destination $reproPackage -Recurse -Force
Remove-Item -LiteralPath (Join-Path $reproPackage '_GITHUB_UPDATE') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $reproPackage 'AotR 8P WotR Mod.exe') -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host 'Rebuilding with canonical FINAL_1_1_1 and NO -LauncherVersion override...' -ForegroundColor Cyan
& $canonicalBuilder -PackageRoot $reproPackage -EmitGitHubBundle
if ($LASTEXITCODE) { throw ('Canonical FINAL_1_1_1 builder returned exit code ' + $LASTEXITCODE) }

$reproBundle = Join-Path $reproPackage '_GITHUB_UPDATE'
$reproFiles = @(Get-ChildItem -LiteralPath $reproBundle -File | Select-Object -ExpandProperty Name | Sort-Object)
$expectedSorted = @($ExpectedFiles | Sort-Object)
if ($reproFiles.Count -ne 5 -or (($reproFiles -join "`n") -cne ($expectedSorted -join "`n"))) {
    throw ('Reproduction bundle is not exactly the five public files. Found: ' + ($reproFiles -join ', '))
}
if (Test-Path -LiteralPath (Join-Path $reproBundle 'internal')) { throw 'Reproduction five-file bundle unexpectedly contains internal\.' }

$reproExeSha = Assert-Hash (Join-Path $reproBundle 'AotR 8P WotR Mod.exe') $ExpectedExeSha 'Reproduced default-version EXE'
[void](Assert-Hash (Join-Path $reproBundle 'payload_ui.big') $ExpectedUiSha 'Reproduced UI')
[void](Assert-Hash (Join-Path $reproBundle 'payload_paper.inc') $ExpectedPaperSha 'Reproduced paper')
$reproManifestPath = Join-Path $reproBundle 'manifest.json'
$reproRepairPath = Join-Path $reproBundle 'repair-manifest.json'
$reproManifest = Get-Content -LiteralPath $reproManifestPath -Raw | ConvertFrom-Json
$reproRepair = Get-Content -LiteralPath $reproRepairPath -Raw | ConvertFrom-Json
if ([string]$reproManifest.launcher_version -ne '1.1.1') { throw ('Canonical builder default did not produce launcher 1.1.1: ' + [string]$reproManifest.launcher_version) }
if ([string]$reproManifest.launcher_sha256 -ne $ExpectedExeSha) { throw 'Reproduction manifest EXE SHA mismatch.' }
if ([string]$reproRepair.generated_for_launcher -ne '1.1.1') { throw ('Reproduction repair-manifest version mismatch: ' + [string]$reproRepair.generated_for_launcher) }
if ((Get-Sha256File $reproManifestPath) -ne (Get-Sha256File (Join-Path $acceptedBundle 'manifest.json'))) { throw 'Reproduction manifest bytes differ from the accepted final manifest.' }
if ((Get-Sha256File $reproRepairPath) -ne (Get-Sha256File (Join-Path $acceptedBundle 'repair-manifest.json'))) { throw 'Reproduction repair-manifest bytes differ from the accepted final repair-manifest.' }
Write-Host '[PASS] canonical FINAL_1_1_1 default rebuild reproduces the exact accepted 2141EA... release EXE and manifests' -ForegroundColor Green

$report = Join-Path $reproRoot 'ISSUE33_CANONICAL_FINAL_1_1_1_BUILDER_REPRO_REPORT.txt'
$lines = @(
    'AOTR 8P WOTR ISSUE #33 CANONICAL FINAL_1_1_1 BUILDER REPRODUCTION: PASS',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Accepted builder SHA256: ' + $ExpectedAcceptedBuilderSha),
    ('Canonical FINAL_1_1_1 builder: ' + $canonicalBuilder),
    ('Canonical FINAL_1_1_1 builder SHA256: ' + $canonicalSha),
    'Only semantic source change: LauncherVersion default 1.1 -> 1.1.1',
    ('Reproduced EXE SHA256: ' + [string]$reproExeSha),
    ('Expected/accepted EXE SHA256: ' + $ExpectedExeSha),
    ('UI SHA256: ' + $ExpectedUiSha),
    ('Paper SHA256: ' + $ExpectedPaperSha),
    ('Skin SHA256: ' + $ExpectedSkinSha),
    ('Reproduction bundle: ' + $reproBundle),
    'No GitHub branch was modified by this gate.'
)
[IO.File]::WriteAllLines($report,$lines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' ISSUE #33 CANONICAL FINAL_1_1_1 BUILDER: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('Canonical builder     : ' + $canonicalBuilder) -ForegroundColor Green
Write-Host ('Canonical builder SHA : ' + $canonicalSha) -ForegroundColor Green
Write-Host ('Reproduced EXE SHA    : ' + $ExpectedExeSha) -ForegroundColor Green
Write-Host ('Report                : ' + $report)
Write-Host ''
Write-Host 'NEXT: pin this canonical builder SHA into the PR #34 stager. Do not publish manually.' -ForegroundColor Cyan
