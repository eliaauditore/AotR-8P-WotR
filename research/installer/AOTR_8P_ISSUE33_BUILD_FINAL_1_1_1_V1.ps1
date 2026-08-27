#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$FinalVersion = '1.1.1'
$PinnedRc2Commit = '371e4d898b08377769fe8ba023385f69624828cc'
$Rc2Path = 'research/installer/AOTR_8P_ISSUE33_BUILD_STANDALONE_SKIN_RC2_V1.ps1'
$Rc2Url = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $PinnedRc2Commit + '/' + $Rc2Path
$ExpectedSkinSha = 'BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6'
$ExpectedUiSha = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
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

function Test-PowerShellFile([string]$Path,[string]$Label) {
    $text = Get-Content -LiteralPath $Path -Raw
    if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0xFEFF) { $text = $text.Substring(1) }
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) {
        $errors | Format-List *
        throw ($Label + ' has parser errors.')
    }
}

if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw ('Base missing: ' + $Base) }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' ISSUE #33 - BUILD EXACT FINAL LAUNCHER 1.1.1' -ForegroundColor Cyan
Write-Host ' SAME ACCEPTED RC2 FIX / FINAL VERSION ONLY / NO PUBLISH' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('Pinned RC2 implementation : ' + $PinnedRc2Commit)
Write-Host ('Final version             : ' + $FinalVersion)
Write-Host ''

$before = @{}
foreach ($d in @(Get-ChildItem -LiteralPath $Base -Directory -Filter 'ISSUE33_STANDALONE_SKIN_RC2_*' -ErrorAction SilentlyContinue)) { $before[$d.FullName] = $true }

$runner = Join-Path $env:TEMP 'AOTR_8P_ISSUE33_PINNED_RC2_BUILDER.ps1'
Remove-Item -LiteralPath $runner -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -Uri $Rc2Url -OutFile $runner
Test-PowerShellFile $runner 'Pinned RC2 builder'
Write-Host 'Pinned RC2 builder parser : PASS' -ForegroundColor Green

& $runner -Base $Base -CandidateVersion $FinalVersion
if ($LASTEXITCODE) { throw ('Pinned RC2 builder returned exit code ' + $LASTEXITCODE) }

$newRoots = @(Get-ChildItem -LiteralPath $Base -Directory -Filter 'ISSUE33_STANDALONE_SKIN_RC2_*' | Where-Object { -not $before.ContainsKey($_.FullName) } | Sort-Object LastWriteTime -Descending)
if ($newRoots.Count -ne 1) { throw ('Expected exactly one new Issue33 build root, found ' + $newRoots.Count) }
$workRoot = $newRoots[0].FullName
$packageRoot = Join-Path $workRoot 'PACKAGE'
$bundle = Join-Path $packageRoot '_GITHUB_UPDATE'
$exe = Join-Path $bundle 'AotR 8P WotR Mod.exe'
$manifestPath = Join-Path $bundle 'manifest.json'
$repairPath = Join-Path $bundle 'repair-manifest.json'
$uiPath = Join-Path $bundle 'payload_ui.big'
$paperPath = Join-Path $bundle 'payload_paper.inc'
$skinSource = Join-Path $packageRoot 'internal\assets\launcher_skin.png'
$finalBuilder = Join-Path $workRoot 'BUILD_ISSUE33_STANDALONE_SKIN_RC2.ps1'

if (-not (Test-Path -LiteralPath $bundle -PathType Container)) { throw ('Final five-file bundle missing: ' + $bundle) }
$actualFiles = @(Get-ChildItem -LiteralPath $bundle -File | Select-Object -ExpandProperty Name | Sort-Object)
$expectedSorted = @($ExpectedFiles | Sort-Object)
if ($actualFiles.Count -ne 5 -or (($actualFiles -join "`n") -cne ($expectedSorted -join "`n"))) {
    throw ('Final bundle is not exactly the five public files. Found: ' + ($actualFiles -join ', '))
}
if (Test-Path -LiteralPath (Join-Path $bundle 'internal')) { throw 'Final five-file bundle unexpectedly contains internal\.' }
Write-Host '[PASS] final bundle contains exactly five public files and no internal\' -ForegroundColor Green

foreach ($required in @($exe,$manifestPath,$repairPath,$uiPath,$paperPath,$skinSource,$finalBuilder)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw ('Required final artifact missing: ' + $required) }
}

$exeSha = Get-Sha256File $exe
$uiSha = Get-Sha256File $uiPath
$paperSha = Get-Sha256File $paperPath
$skinSha = Get-Sha256File $skinSource
if ($uiSha -ne $ExpectedUiSha) { throw ('Final UI hash mismatch: ' + $uiSha) }
if ($paperSha -ne $ExpectedPaperSha) { throw ('Final paper hash mismatch: ' + $paperSha) }
if ($skinSha -ne $ExpectedSkinSha) { throw ('Final skin source hash mismatch: ' + $skinSha) }

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$repair = Get-Content -LiteralPath $repairPath -Raw | ConvertFrom-Json
if ([int]$manifest.schema -ne 1) { throw ('Manifest schema mismatch: ' + [string]$manifest.schema) }
if ([string]$manifest.launcher_version -ne $FinalVersion) { throw ('Manifest version mismatch: ' + [string]$manifest.launcher_version) }
if ([string]$manifest.launcher_sha256 -ne $exeSha) { throw ('Manifest EXE hash mismatch. Manifest=' + [string]$manifest.launcher_sha256 + ' actual=' + $exeSha) }
if ([int]$repair.schema -ne 1) { throw ('Repair schema mismatch: ' + [string]$repair.schema) }
if ([string]$repair.generated_for_launcher -ne $FinalVersion) { throw ('Repair version mismatch: ' + [string]$repair.generated_for_launcher) }
if ([bool]$manifest.mandatory) { throw 'Final manifest unexpectedly marks update mandatory.' }

Test-PowerShellFile $finalBuilder 'Final generated 1.1.1 builder'
$builderSha = Get-Sha256File $finalBuilder

$report = Join-Path $workRoot 'ISSUE33_FINAL_1_1_1_BUILD_REPORT.txt'
$lines = @(
    'AOTR 8P WOTR ISSUE #33 EXACT FINAL 1.1.1 BUILD: PASS',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Pinned RC2 implementation commit: ' + $PinnedRc2Commit),
    ('Version: ' + $FinalVersion),
    ('Work root: ' + $workRoot),
    ('Five-file bundle: ' + $bundle),
    ('EXE SHA256: ' + $exeSha),
    ('UI SHA256: ' + $uiSha),
    ('Paper SHA256: ' + $paperSha),
    ('Skin SHA256: ' + $skinSha),
    ('Generated final builder: ' + $finalBuilder),
    ('Generated final builder SHA256: ' + $builderSha),
    'Published v1.1 was not modified by this build.'
)
[IO.File]::WriteAllLines($report,$lines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' ISSUE #33 EXACT FINAL 1.1.1 BUILD: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('Final EXE SHA     : ' + $exeSha) -ForegroundColor Green
Write-Host ('Final builder SHA : ' + $builderSha) -ForegroundColor Green
Write-Host ('Bundle            : ' + $bundle)
Write-Host ('Builder           : ' + $finalBuilder)
Write-Host ('Report            : ' + $report)
Write-Host ''
Write-Host 'DO NOT PUBLISH YET. Send this complete output back for the exact-final first-boot + START gate.' -ForegroundColor Yellow
