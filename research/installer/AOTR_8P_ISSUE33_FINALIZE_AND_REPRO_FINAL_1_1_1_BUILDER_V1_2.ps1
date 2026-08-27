#requires -version 7.0
[CmdletBinding()]
param(
    [string]$WorkRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_054456'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceCommit = '6689bb59fe4261ffbb0660533fbfdf007736a64f'
$SourcePath = 'research/installer/AOTR_8P_ISSUE33_FINALIZE_AND_REPRO_FINAL_1_1_1_BUILDER_V1_1.ps1'
$ExpectedGitBlobSha1 = '79f276f68f353c58b9a0a3800721221402baa9ab'
$SourceUrl = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $SourceCommit + '/' + $SourcePath
$SourceTemp = Join-Path $env:TEMP 'AOTR_8P_ISSUE33_FINALIZE_REPRO_V1_1_SOURCE.ps1'
$Runtime = Join-Path $env:TEMP 'AOTR_8P_ISSUE33_FINALIZE_REPRO_V1_2_RUNTIME.ps1'
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
$blobSha = Get-GitBlobSha1 $sourceBytes
if ($blobSha -ne $ExpectedGitBlobSha1) { throw ('Pinned V1.1 repro gate blob mismatch. Expected ' + $ExpectedGitBlobSha1 + ', got ' + $blobSha) }

$offset = if ($sourceBytes.Length -ge 3 -and $sourceBytes[0] -eq 0xEF -and $sourceBytes[1] -eq 0xBB -and $sourceBytes[2] -eq 0xBF) { 3 } else { 0 }
$text = [Text.UTF8Encoding]::new($false,$true).GetString($sourceBytes,$offset,$sourceBytes.Length-$offset)
$badLine = "Remove-Item -LiteralPath (Join-Path `$reproPackage 'AotR 8P WotR Mod.exe') -Force -ErrorAction SilentlyContinue"
$replacement = "# Keep the package-root seed EXE: the canonical V18 builder validates it as a required RC5 input."
$text = Replace-ExactOnce $text $badLine $replacement 'retain required package-root seed EXE for reproduction'

[IO.File]::WriteAllText($Runtime,$text,[Text.UTF8Encoding]::new($false))
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if (@($errors).Count -gt 0) {
    $errors | Format-List *
    throw 'STOP: Issue33 FINAL_1_1_1 repro V1.2 runtime has parser errors.'
}

Write-Host 'Issue33 FINAL_1_1_1 repro V1.2 runtime parser validation: PASS' -ForegroundColor Green
Write-Host ('Pinned V1.1 blob : ' + $ExpectedGitBlobSha1)
Write-Host ('Runtime          : ' + $Runtime)
Write-Host 'Fix              : retain required package-root seed EXE during canonical builder reproduction' -ForegroundColor Green
Write-Host ''

& $Runtime -WorkRoot $WorkRoot
