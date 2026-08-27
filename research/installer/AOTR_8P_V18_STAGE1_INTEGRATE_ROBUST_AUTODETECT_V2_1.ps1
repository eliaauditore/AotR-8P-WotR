#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceCommit = '0e3a4812e053dc78731f3a3a9877b4428ead7f2a'
$SourceUrl = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/research/installer/AOTR_8P_V18_STAGE1_INTEGRATE_ROBUST_AUTODETECT_V2.ps1"
$ExpectedSourceSha256 = '60C73235C1E043488A4FB5D0AB9A85E228DAAA965A89DFC7E614F0C7CAF93338'

function Get-Sha256File([string]$Path) {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

$sourcePath = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE1_INTEGRATE_ROBUST_AUTODETECT_V2_SOURCE.ps1'
$runtimePath = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE1_INTEGRATE_ROBUST_AUTODETECT_V2_1_RUNTIME.ps1'
Remove-Item $sourcePath,$runtimePath -Force -ErrorAction SilentlyContinue

Invoke-WebRequest -Uri $SourceUrl -OutFile $sourcePath
$sourceSha = Get-Sha256File $sourcePath
if ($sourceSha -ne $ExpectedSourceSha256) {
    throw "Pinned V18 integrator source hash mismatch. Expected $ExpectedSourceSha256, got $sourceSha"
}

$text = [IO.File]::ReadAllText($sourcePath)
$old = 'throw "Protected 1.0.10 GUI marker count changed for $key: $($guiCountsBefore[$key]) -> $after"'
$new = 'throw "Protected 1.0.10 GUI marker count changed for ${key}: $($guiCountsBefore[$key]) -> $after"'

$count = ([regex]::Matches($text,[regex]::Escape($old))).Count
if ($count -ne 1) {
    throw "Expected exactly one parser-interpolation defect, found $count."
}
$text = $text.Replace($old,$new)

if (([regex]::Matches($text,'\$key:')).Count -ne 0) {
    throw 'The known $key: interpolation defect is still present after hotfix.'
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) {
    $errors | Format-List * | Out-Host
    throw 'V18 autodetect integrator V2.1 still has parser errors.'
}

[IO.File]::WriteAllText($runtimePath,$text,[Text.UTF8Encoding]::new($false))
Write-Host 'V18 autodetect integrator V2.1 parser validation: PASS' -ForegroundColor Green
Write-Host "Pinned source SHA : $sourceSha" -ForegroundColor Green
Write-Host "Runtime path      : $runtimePath"

& $runtimePath -Base $Base
