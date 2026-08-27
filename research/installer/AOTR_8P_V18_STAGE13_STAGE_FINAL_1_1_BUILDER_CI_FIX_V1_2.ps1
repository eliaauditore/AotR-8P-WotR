#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$ProductionWorkRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE8_1_1_RC2_20260827_033705'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceCommit = '5a549fcd6c7d9d4557ab2d8c2bc1bae0f6d98d8a'
$SourcePath = 'research/installer/AOTR_8P_V18_STAGE13_STAGE_FINAL_1_1_BUILDER_CI_FIX_V1_1.ps1'
$ExpectedSourceBlobSha1 = '621c4fd1b25e187d79e8e65d0213bdcddf15380b'
$SourceUrl = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $SourceCommit + '/' + $SourcePath
$SourceTemp = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE13_V1_1_SOURCE.ps1'
$Runtime = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE13_V1_2_RUNTIME.ps1'
Remove-Item $SourceTemp,$Runtime -Force -ErrorAction SilentlyContinue

function Get-GitBlobSha1([byte[]]$Bytes) {
    $header = [Text.Encoding]::ASCII.GetBytes(('blob ' + $Bytes.Length + [char]0))
    $all = New-Object byte[] ($header.Length + $Bytes.Length)
    [Array]::Copy($header,0,$all,0,$header.Length)
    [Array]::Copy($Bytes,0,$all,$header.Length,$Bytes.Length)
    $sha = [Security.Cryptography.SHA1]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($all))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Replace-ExactOnce([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $count = 0
    $index = 0
    while (($found = $Text.IndexOf($Old,$index,[StringComparison]::Ordinal)) -ge 0) {
        $count++
        $index = $found + $Old.Length
    }
    if ($count -ne 1) { throw ('Expected exactly one patch target for ' + $Label + ', found ' + $count) }
    return $Text.Replace($Old,$New)
}

Invoke-WebRequest -Uri $SourceUrl -OutFile $SourceTemp
$sourceBytes = [IO.File]::ReadAllBytes($SourceTemp)
$blob = Get-GitBlobSha1 $sourceBytes
if ($blob -ne $ExpectedSourceBlobSha1) { throw ('Pinned Stage13 V1.1 blob mismatch. Expected ' + $ExpectedSourceBlobSha1 + ', got ' + $blob) }

$text = [Text.UTF8Encoding]::new($false,$true).GetString($sourceBytes)
$old = @'
$patchedText = $text
if ($patchedText.Contains("[string]`$LauncherVersion = '1.0.10'")) {
    $patchedText = Replace-ExactOnce $patchedText "[string]`$LauncherVersion = '1.0.10'" "[string]`$LauncherVersion = '1.1'" 'LauncherVersion default'
} elseif ($patchedText.Contains("[string]`$LauncherVersion = '1.1'")) {
    Write-Host 'Builder already defaults to LauncherVersion 1.1.' -ForegroundColor DarkGray
} else {
    throw 'Could not identify canonical LauncherVersion default in generated builder.'
}
'@
$new = @'
$patchedText = $text
$versionPattern = '(?m)(\[string\]\$LauncherVersion\s*=\s*)(["''])(?<value>[^"'']+)\2'
$versionMatches = [regex]::Matches($patchedText,$versionPattern)
if ($versionMatches.Count -ne 1) {
    throw ('Expected exactly one LauncherVersion parameter declaration in generated builder, found ' + $versionMatches.Count)
}
$currentDefault = $versionMatches[0].Groups['value'].Value
if ($currentDefault -eq '1.1') {
    Write-Host 'Builder already defaults to LauncherVersion 1.1.' -ForegroundColor DarkGray
} elseif ($currentDefault -eq '1.0.0') {
    $oldDecl = $versionMatches[0].Value
    $prefix = $versionMatches[0].Groups[1].Value
    $quote = $versionMatches[0].Groups[2].Value
    $newDecl = $prefix + $quote + '1.1' + $quote
    $patchedText = Replace-ExactOnce $patchedText $oldDecl $newDecl 'LauncherVersion default 1.0.0 -> 1.1'
    Write-Host 'Canonical LauncherVersion default: 1.0.0 -> 1.1' -ForegroundColor Green
} else {
    throw ('Unexpected LauncherVersion default in generated builder: ' + $currentDefault)
}
'@
$text = Replace-ExactOnce $text $old $new 'actual V18 LauncherVersion default detection'

[IO.File]::WriteAllText($Runtime,$text,[Text.UTF8Encoding]::new($false))
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) {
    $errors | Format-List *
    throw 'STOP: Stage13 V1.2 runtime has parser errors.'
}

Write-Host 'Stage13 V1.2 parser validation: PASS' -ForegroundColor Green
Write-Host ('Pinned V1.1 blob : ' + $ExpectedSourceBlobSha1)
Write-Host ('Runtime          : ' + $Runtime)
Write-Host ''

& $Runtime -Base $Base -ProductionWorkRoot $ProductionWorkRoot
