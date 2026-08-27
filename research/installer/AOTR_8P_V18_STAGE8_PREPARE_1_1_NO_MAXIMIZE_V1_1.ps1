#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE1_20260827_022948\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10_ROBUST_AUTODETECT_V2_NONRELEASE.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceCommit = '2f52871905edb2a504145d522e793a527ff8c984'
$SourcePath = 'research/installer/AOTR_8P_V18_STAGE8_PREPARE_1_1_NO_MAXIMIZE_V1.ps1'
$SourceUrl = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/$SourcePath"
$ExpectedGitBlobSha1 = '1d5314797aef87caa1dcd69a38850cd69447d37a'

function Get-GitBlobSha1([string]$Path) {
    $body = [IO.File]::ReadAllBytes($Path)
    $header = [Text.Encoding]::UTF8.GetBytes(('blob ' + $body.Length + [char]0))
    $all = New-Object byte[] ($header.Length + $body.Length)
    [Array]::Copy($header,0,$all,0,$header.Length)
    [Array]::Copy($body,0,$all,$header.Length,$body.Length)
    $sha1 = [Security.Cryptography.SHA1]::Create()
    try { return ([BitConverter]::ToString($sha1.ComputeHash($all))).Replace('-','').ToLowerInvariant() }
    finally { $sha1.Dispose() }
}

$source = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE8_PREPARE_1_1_NO_MAXIMIZE_V1_SOURCE.ps1'
$runtime = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE8_PREPARE_1_1_NO_MAXIMIZE_V1_1_RUNTIME.ps1'
Remove-Item $source,$runtime -Force -ErrorAction SilentlyContinue

Invoke-WebRequest -Uri $SourceUrl -OutFile $source
$blob = Get-GitBlobSha1 $source
if ($blob -ne $ExpectedGitBlobSha1) {
    throw ('Pinned Stage8 source blob mismatch. Expected ' + $ExpectedGitBlobSha1 + ', got ' + $blob)
}

$text = [IO.File]::ReadAllText($source)
$count = @([regex]::Matches($text,'(?m)^elif\s*\(')).Count
if ($count -ne 1) { throw ('Expected exactly one Stage8 elif typo, found ' + $count) }
$text = [regex]::Replace($text,'(?m)^elif\s*\(','elseif (',1)

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) {
    $errors | Format-List * | Out-Host
    throw 'Stage8 V1.1 runtime still has parser errors.'
}

[IO.File]::WriteAllText($runtime,$text,[Text.UTF8Encoding]::new($false))
Write-Host 'Stage8 V1.1 parser validation: PASS' -ForegroundColor Green
Write-Host ('Pinned source blob : ' + $blob) -ForegroundColor Green
Write-Host ('Runtime            : ' + $runtime)
Write-Host ''

& $runtime -Base $Base -BuilderPath $BuilderPath
