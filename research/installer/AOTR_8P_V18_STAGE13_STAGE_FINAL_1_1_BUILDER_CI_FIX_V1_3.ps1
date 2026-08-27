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
$Runtime = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE13_V1_3_RUNTIME.ps1'
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

Invoke-WebRequest -Uri $SourceUrl -OutFile $SourceTemp
$sourceBytes = [IO.File]::ReadAllBytes($SourceTemp)
$blob = Get-GitBlobSha1 $sourceBytes
if ($blob -ne $ExpectedSourceBlobSha1) { throw ('Pinned Stage13 V1.1 blob mismatch. Expected ' + $ExpectedSourceBlobSha1 + ', got ' + $blob) }

$text = [Text.UTF8Encoding]::new($false,$true).GetString($sourceBytes)

# Patch only the canonical LauncherVersion-default handling block in V1.
$pattern = '(?s)# Canonical FINAL_1_1 builder defaults to 1\.1 when invoked without an explicit version\.[\r\n]+\$patchedText = \$text[\r\n]+if \(\$patchedText\.Contains\("\[string\]`\$LauncherVersion = ''1\.0\.10''"\)\) \{.*?\}[\r\n]+Test-PowerShellText \$patchedText ''canonical FINAL_1_1 builder'''
$replacement = @'
# Canonical FINAL_1_1 builder defaults to 1.1 when invoked without an explicit version.
$patchedText = $text
$launcherVersionPattern = '(?m)^\s*\[string\]\$LauncherVersion\s*=\s*"1\.0\.0",\s*$'
$matches = [regex]::Matches($patchedText,$launcherVersionPattern)
if ($matches.Count -ne 1) { throw ('Expected exactly one actual V18 LauncherVersion default declaration, found ' + $matches.Count) }
$patchedText = [regex]::Replace($patchedText,$launcherVersionPattern,'    [string]$LauncherVersion = "1.1",',1)
Write-Host 'Canonical LauncherVersion default: 1.0.0 -> 1.1' -ForegroundColor Green
Test-PowerShellText $patchedText 'canonical FINAL_1_1 builder'
'@
$newText = [regex]::Replace($text,$pattern,$replacement,1)
if ($newText -eq $text) { throw 'Stage13 V1.3 could not patch the canonical LauncherVersion handling block.' }

[IO.File]::WriteAllText($Runtime,$newText,[Text.UTF8Encoding]::new($false))
$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseInput($newText,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) { $errors | Format-List *; throw 'STOP: Stage13 V1.3 runtime has parser errors.' }

Write-Host 'Stage13 V1.3 parser validation: PASS' -ForegroundColor Green
Write-Host ('Pinned V1.1 blob : ' + $ExpectedSourceBlobSha1)
Write-Host ('Runtime          : ' + $Runtime)
Write-Host ''
& $Runtime -Base $Base -ProductionWorkRoot $ProductionWorkRoot
