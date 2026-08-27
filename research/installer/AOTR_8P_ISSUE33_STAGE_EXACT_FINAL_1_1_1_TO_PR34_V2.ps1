#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$FinalBundle = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_054456\PACKAGE\_GITHUB_UPDATE',
    [string]$FinalBuilder = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_054456\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_1.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceCommit = '75ee294a7395b626558bc4d3ed35123998adb5f4'
$SourcePath = 'research/installer/AOTR_8P_ISSUE33_STAGE_EXACT_FINAL_1_1_1_TO_PR34_V1.ps1'
$ExpectedGitBlobSha1 = '9eeebec78a586e22bd6fc1e67fd32f6341f7d03a'
$SourceUrl = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $SourceCommit + '/' + $SourcePath
$SourceTemp = Join-Path $env:TEMP 'AOTR_8P_ISSUE33_PR34_STAGER_V1_SOURCE_FOR_V2.ps1'
$Runtime = Join-Path $env:TEMP 'AOTR_8P_ISSUE33_PR34_STAGER_V2_RUNTIME.ps1'
Remove-Item $SourceTemp,$Runtime -Force -ErrorAction SilentlyContinue

$ExpectedCanonicalBuilderSha = '32BCAC9D82F2A8FC9651C9F6B4E655D8B161F788174854F7118D30F37EB2516F'
$ExpectedRuntimeTestedExeSha = '2141EA9690708EA7A61B7298AD90E0C76CC417FED996AC0CF3685276BA2A4024'

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
if ($blobSha -ne $ExpectedGitBlobSha1) { throw ('Pinned V1 stager blob mismatch. Expected ' + $ExpectedGitBlobSha1 + ', got ' + $blobSha) }

$offset = if ($sourceBytes.Length -ge 3 -and $sourceBytes[0] -eq 0xEF -and $sourceBytes[1] -eq 0xBB -and $sourceBytes[2] -eq 0xBF) { 3 } else { 0 }
$text = [Text.UTF8Encoding]::new($false,$true).GetString($sourceBytes,$offset,$sourceBytes.Length-$offset)

$oldDefaultBuilder = "    [string]`$FinalBuilder = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_054456\BUILD_ISSUE33_STANDALONE_SKIN_RC2.ps1'"
$newDefaultBuilder = "    [string]`$FinalBuilder = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_054456\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_1.ps1'"
$text = Replace-ExactOnce $text $oldDefaultBuilder $newDefaultBuilder 'canonical FINAL_1_1_1 builder path'

$oldBuilderShaLine = "`$ExpectedBuilderSha = 'B30EAFB0ABCE94DC22E5121FB7F9B3B9AF31A6D2FCDB5E5B14CB4056AF392560'"
$newBuilderShaLine = "`$ExpectedBuilderSha = '32BCAC9D82F2A8FC9651C9F6B4E655D8B161F788174854F7118D30F37EB2516F'"
$text = Replace-ExactOnce $text $oldBuilderShaLine $newBuilderShaLine 'canonical FINAL_1_1_1 builder SHA'

$badMarkerCheck = "if (`$builderText -notmatch 'Issue33SkinGzipBase64') { throw 'Final builder no longer contains the embedded skin bootstrap marker.' }"
$markerReplacement = "Write-Host '[PASS] exact canonical FINAL_1_1_1 builder SHA pins the embedded skin bootstrap source' -ForegroundColor Green"
$text = Replace-ExactOnce $text $badMarkerCheck $markerReplacement 'remove invalid plaintext marker search inside Base64 C# template'

$oldFinalBuilderReport = "    ('FINAL_1_1_1 builder SHA256: ' + `$ExpectedBuilderSha),"
$newFinalBuilderReport = $oldFinalBuilderReport + "`r`n    'V18 byte reproducibility note: repeated legacy csc builds are intentionally not required to reproduce the frozen EXE SHA.',"
$text = Replace-ExactOnce $text $oldFinalBuilderReport $newFinalBuilderReport 'record V18 build nondeterminism policy'

[IO.File]::WriteAllText($Runtime,$text,[Text.UTF8Encoding]::new($false))
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if (@($errors).Count -gt 0) {
    $errors | Format-List *
    throw 'STOP: Issue33 PR34 stager V2 runtime has parser errors.'
}

if ($text -notmatch [regex]::Escape($ExpectedCanonicalBuilderSha)) { throw 'Runtime stager lost canonical builder SHA pin.' }
if ($text -notmatch [regex]::Escape($ExpectedRuntimeTestedExeSha)) { throw 'Runtime stager lost frozen runtime-tested EXE SHA pin.' }

Write-Host 'Issue33 PR34 final stager V2 runtime parser validation: PASS' -ForegroundColor Green
Write-Host ('Pinned V1 blob            : ' + $ExpectedGitBlobSha1)
Write-Host ('Frozen runtime-tested EXE : ' + $ExpectedRuntimeTestedExeSha) -ForegroundColor Green
Write-Host ('Canonical builder         : ' + $ExpectedCanonicalBuilderSha) -ForegroundColor Green
Write-Host 'Policy                    : V18 legacy csc output is byte-nondeterministic; ship the exact tested EXE, pin the canonical source builder.' -ForegroundColor Green
Write-Host ''

& $Runtime -Base $Base -FinalBundle $FinalBundle -FinalBuilder $FinalBuilder
