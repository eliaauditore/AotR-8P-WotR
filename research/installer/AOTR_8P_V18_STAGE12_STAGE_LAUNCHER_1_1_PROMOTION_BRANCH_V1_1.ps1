#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceCommit = '485b2a4f3aac28b0f51b24f8e453e29d038f6d23'
$SourcePath = 'research/installer/AOTR_8P_V18_STAGE12_STAGE_LAUNCHER_1_1_PROMOTION_BRANCH_V1.ps1'
$ExpectedGitBlobSha1 = '41e84d81da6e8cafd76bbf06067539f46e91813b'
$SourceUrl = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $SourceCommit + '/' + $SourcePath
$SourceTemp = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE12_PROMOTION_V1_SOURCE.ps1'
$Runtime = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE12_PROMOTION_V1_1_RUNTIME.ps1'
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
if ($blob -ne $ExpectedGitBlobSha1) { throw ('Pinned Stage12 V1 blob mismatch. Expected ' + $ExpectedGitBlobSha1 + ', got ' + $blob) }

$text = [Text.UTF8Encoding]::new($false,$true).GetString($sourceBytes)
$text = Replace-ExactOnce $text `
    "Invoke-Git `$cloneRoot @('fetch','origin','main')" `
    "Invoke-Git `$cloneRoot @('fetch','origin','+refs/heads/main:refs/remotes/origin/main')" `
    'explicit origin/main tracking ref'

[IO.File]::WriteAllText($Runtime,$text,[Text.UTF8Encoding]::new($false))
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) {
    $errors | Format-List *
    throw 'STOP: Stage12 V1.1 runtime has parser errors.'
}

Write-Host 'Stage12 V1.1 parser validation: PASS' -ForegroundColor Green
Write-Host ('Pinned source blob : ' + $ExpectedGitBlobSha1)
Write-Host ('Runtime            : ' + $Runtime)
Write-Host 'Fix                : explicit refs/heads/main -> refs/remotes/origin/main fetch' -ForegroundColor Green
Write-Host ''

& $Runtime -Base $Base
