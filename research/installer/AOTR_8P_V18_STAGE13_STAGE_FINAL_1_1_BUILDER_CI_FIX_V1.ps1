#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$ProductionWorkRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE8_1_1_RC2_20260827_033705'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoUrl = 'https://github.com/eliaauditore/AotR-8P-WotR.git'
$FixBranch = 'release/launcher-1.1-ci-builder-fix'
$ExpectedBase = 'bbd7eff483d2cdbf3e799f764433b49195dc55b6'
$GeneratedBuilderName = 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_RC2_TOPBAR_POLISH_NONRELEASE.ps1'
$FinalBuilderName = 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1.ps1'
$Stage8ReportName = 'V18_STAGE8_1_1_RC2_TOPBAR_POLISH_REPORT.txt'
$ExpectedGuiSha = '23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C'
$ExpectedEngineSha = '94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA'

function Get-Sha256File([string]$Path) {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Invoke-Git([string]$WorkingDirectory,[string[]]$Arguments,[switch]$ReturnText) {
    $all = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) { [void]$all.Add('-C'); [void]$all.Add($WorkingDirectory) }
    foreach ($arg in $Arguments) { [void]$all.Add($arg) }
    $out = & git @all 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0) { throw ('git ' + ($Arguments -join ' ') + ' failed (' + $exit + ')' + [Environment]::NewLine + (($out | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)) }
    if ($ReturnText) { return (($out | ForEach-Object { [string]$_ }) -join "`n").Trim() }
    foreach ($line in $out) { Write-Host ([string]$line) }
}

function Replace-ExactOnce([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $count = 0; $index = 0
    while (($found = $Text.IndexOf($Old,$index,[StringComparison]::Ordinal)) -ge 0) { $count++; $index = $found + $Old.Length }
    if ($count -ne 1) { throw ('Expected exactly one target for ' + $Label + ', found ' + $count) }
    return $Text.Replace($Old,$New)
}

function Test-PowerShellText([string]$Text,[string]$Label) {
    if ($Text.Length -gt 0 -and [int][char]$Text[0] -eq 0xFEFF) { $Text = $Text.Substring(1) }
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) { throw ($Label + ' parser errors: ' + (($errors | ForEach-Object { $_.Message }) -join '; ')) }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git.exe not found in PATH.' }
if (-not (Test-Path -LiteralPath $ProductionWorkRoot -PathType Container)) { throw ('Production work root missing: ' + $ProductionWorkRoot) }

$generatedBuilder = Join-Path $ProductionWorkRoot $GeneratedBuilderName
$stage8Report = Join-Path $ProductionWorkRoot $Stage8ReportName
if (-not (Test-Path -LiteralPath $generatedBuilder -PathType Leaf)) { throw ('Generated production builder missing: ' + $generatedBuilder) }
if (-not (Test-Path -LiteralPath $stage8Report -PathType Leaf)) { throw ('Stage8 report missing: ' + $stage8Report) }

$reportRaw = Get-Content -LiteralPath $stage8Report -Raw
$mBuilder = [regex]::Match($reportRaw,'(?mi)^Output builder SHA256:\s*([A-F0-9]{64})\s*$')
$mGui = [regex]::Match($reportRaw,'(?mi)^Output GUI SHA256:\s*([A-F0-9]{64})\s*$')
$mEngine = [regex]::Match($reportRaw,'(?mi)^ENGINE SHA256 unchanged:\s*([A-F0-9]{64})\s*$')
if (-not $mBuilder.Success -or -not $mGui.Success -or -not $mEngine.Success) { throw 'Could not parse builder/GUI/ENGINE hashes from Stage8 report.' }
$reportedBuilderSha = $mBuilder.Groups[1].Value.ToUpperInvariant()
$reportedGuiSha = $mGui.Groups[1].Value.ToUpperInvariant()
$reportedEngineSha = $mEngine.Groups[1].Value.ToUpperInvariant()
$actualGeneratedSha = Get-Sha256File $generatedBuilder
if ($actualGeneratedSha -ne $reportedBuilderSha) { throw ('Generated builder hash mismatch. Report=' + $reportedBuilderSha + ', actual=' + $actualGeneratedSha) }
if ($reportedGuiSha -ne $ExpectedGuiSha) { throw ('Stage8 report GUI hash mismatch: ' + $reportedGuiSha) }
if ($reportedEngineSha -ne $ExpectedEngineSha) { throw ('Stage8 report ENGINE hash mismatch: ' + $reportedEngineSha) }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P V18 STAGE 13 - STAGE FINAL 1.1 BUILDER CI FIX' -ForegroundColor Cyan
Write-Host ' RELEASE ROOT BYTES UNTOUCHED' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('Generated builder SHA : ' + $actualGeneratedSha) -ForegroundColor Green
Write-Host ('GUI SHA               : ' + $reportedGuiSha) -ForegroundColor Green
Write-Host ('ENGINE SHA            : ' + $reportedEngineSha) -ForegroundColor Green

$bytes = [IO.File]::ReadAllBytes($generatedBuilder)
$hadBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$offset = if ($hadBom) { 3 } else { 0 }
$text = [Text.UTF8Encoding]::new($false,$true).GetString($bytes,$offset,$bytes.Length-$offset)
Test-PowerShellText $text 'generated builder'
if ($text -match '(?i)invalid\.invalid') { throw 'Generated builder unexpectedly contains invalid.invalid.' }
if ($text -notmatch 'aotr-standalone-v2') { throw 'Robust autodetect Config V2 marker missing from generated builder.' }

# Canonical FINAL_1_1 builder defaults to 1.1 when invoked without an explicit version.
$patchedText = $text
if ($patchedText.Contains("[string]`$LauncherVersion = '1.0.10'")) {
    $patchedText = Replace-ExactOnce $patchedText "[string]`$LauncherVersion = '1.0.10'" "[string]`$LauncherVersion = '1.1'" 'LauncherVersion default'
} elseif ($patchedText.Contains("[string]`$LauncherVersion = '1.1'")) {
    Write-Host 'Builder already defaults to LauncherVersion 1.1.' -ForegroundColor DarkGray
} else {
    throw 'Could not identify canonical LauncherVersion default in generated builder.'
}
Test-PowerShellText $patchedText 'canonical FINAL_1_1 builder'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ('AUTODETECT_V2_V18_STAGE13_FINAL_BUILDER_CI_FIX_' + $stamp)
$cloneRoot = Join-Path $workRoot 'repo'
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
Invoke-Git '' @('clone','--no-tags','--single-branch','--branch',$FixBranch,$RepoUrl,$cloneRoot)
Invoke-Git $cloneRoot @('config','core.autocrlf','false')
Invoke-Git $cloneRoot @('config','core.safecrlf','false')
Invoke-Git $cloneRoot @('config','user.name','eliaauditore')
Invoke-Git $cloneRoot @('config','user.email','eliaauditore@users.noreply.github.com')
$head = Invoke-Git $cloneRoot @('rev-parse','HEAD') -ReturnText
if ($head -ne $ExpectedBase) { throw ('CI-fix branch moved. Expected ' + $ExpectedBase + ', got ' + $head) }

$dest = Join-Path $cloneRoot ('launcher-source\' + $FinalBuilderName)
$parent = Split-Path -Parent $dest
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$enc = [Text.UTF8Encoding]::new($false)
if ($hadBom) {
    $body = $enc.GetBytes($patchedText)
    $finalBytes = New-Object byte[] ($body.Length + 3)
    $finalBytes[0]=0xEF; $finalBytes[1]=0xBB; $finalBytes[2]=0xBF; [Array]::Copy($body,0,$finalBytes,3,$body.Length)
    [IO.File]::WriteAllBytes($dest,$finalBytes)
} else {
    [IO.File]::WriteAllText($dest,$patchedText,$enc)
}
$finalBuilderSha = Get-Sha256File $dest
Test-PowerShellText (Get-Content -LiteralPath $dest -Raw) 'committed FINAL_1_1 builder'
Write-Host ('Canonical FINAL_1_1 SHA: ' + $finalBuilderSha) -ForegroundColor Green

Invoke-Git $cloneRoot @('add','--','launcher-source/' + $FinalBuilderName)
$changed = Invoke-Git $cloneRoot @('diff','--cached','--name-only') -ReturnText
if ($changed.Trim() -ne ('launcher-source/' + $FinalBuilderName)) { throw ('Unexpected staged paths: ' + $changed) }
Invoke-Git $cloneRoot @('commit','-m','Add canonical launcher 1.1 final builder')
$commit = Invoke-Git $cloneRoot @('rev-parse','HEAD') -ReturnText
$parentCommit = Invoke-Git $cloneRoot @('rev-parse','HEAD^') -ReturnText
if ($parentCommit -ne $ExpectedBase) { throw ('CI-fix commit parent mismatch: ' + $parentCommit) }
Invoke-Git $cloneRoot @('push','origin',('HEAD:refs/heads/' + $FixBranch))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' STAGE 13 FINAL 1.1 BUILDER CI FIX STAGING: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('Staged commit        : ' + $commit) -ForegroundColor Green
Write-Host ('Final builder SHA256 : ' + $finalBuilderSha) -ForegroundColor Green
Write-Host ('Branch               : ' + $FixBranch) -ForegroundColor Green
Write-Host ''
Write-Host 'Release-root EXE/manifest/repair/UI/Paper files were not modified.' -ForegroundColor Yellow
