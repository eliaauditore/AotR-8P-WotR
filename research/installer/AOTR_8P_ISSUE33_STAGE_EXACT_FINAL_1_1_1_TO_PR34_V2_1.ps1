#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$FinalBundle = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_054456\PACKAGE\_GITHUB_UPDATE',
    [string]$FinalBuilder = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_054456\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_1.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceCommit = '1aad554f385d4674a2b4aa692482c5006768ca20'
$SourcePath = 'research/installer/AOTR_8P_ISSUE33_STAGE_EXACT_FINAL_1_1_1_TO_PR34_V2.ps1'
$ExpectedGitBlobSha1 = 'ef58a5446bcd7bc1f70892c4b88970ce323d5a17'
$SourceUrl = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $SourceCommit + '/' + $SourcePath
$SourceTemp = Join-Path $env:TEMP 'AOTR_8P_ISSUE33_PR34_STAGER_V2_SOURCE_FOR_V2_1.ps1'
$Runtime = Join-Path $env:TEMP 'AOTR_8P_ISSUE33_PR34_STAGER_V2_1_RUNTIME.ps1'
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
if ($blobSha -ne $ExpectedGitBlobSha1) { throw ('Pinned V2 stager blob mismatch. Expected ' + $ExpectedGitBlobSha1 + ', got ' + $blobSha) }

$offset = if ($sourceBytes.Length -ge 3 -and $sourceBytes[0] -eq 0xEF -and $sourceBytes[1] -eq 0xBB -and $sourceBytes[2] -eq 0xBF) { 3 } else { 0 }
$text = [Text.UTF8Encoding]::new($false,$true).GetString($sourceBytes,$offset,$sourceBytes.Length-$offset)

$oldClone = "Invoke-Git '' @('clone','--no-tags','--single-branch','--branch',`$TargetBranch,`$RepoUrl,`$cloneRoot)"
$newClone = "Invoke-Git '' @('-c','core.autocrlf=false','-c','core.safecrlf=false','clone','--no-tags','--single-branch','--branch',`$TargetBranch,`$RepoUrl,`$cloneRoot)"
$text = Replace-ExactOnce $text $oldClone $newClone 'apply EOL config before clone checkout'

[IO.File]::WriteAllText($Runtime,$text,[Text.UTF8Encoding]::new($false))
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if (@($errors).Count -gt 0) {
    $errors | Format-List *
    throw 'STOP: Issue33 PR34 stager V2.1 runtime has parser errors.'
}

$expectedCloneMarker = "@('-c','core.autocrlf=false','-c','core.safecrlf=false','clone'"
if ($text.IndexOf($expectedCloneMarker,[StringComparison]::Ordinal) -lt 0) { throw 'Runtime stager lost pre-checkout EOL clone configuration.' }
if ($text -notmatch '2141EA9690708EA7A61B7298AD90E0C76CC417FED996AC0CF3685276BA2A4024') { throw 'Runtime stager lost frozen runtime-tested EXE SHA pin.' }
if ($text -notmatch '32BCAC9D82F2A8FC9651C9F6B4E655D8B161F788174854F7118D30F37EB2516F') { throw 'Runtime stager lost canonical builder SHA pin.' }

Write-Host 'Issue33 PR34 final stager V2.1 runtime parser validation: PASS' -ForegroundColor Green
Write-Host ('Pinned V2 blob : ' + $ExpectedGitBlobSha1)
Write-Host 'Fix            : core.autocrlf=false is now applied before/during clone checkout' -ForegroundColor Green
Write-Host 'Safety         : all release hashes, pinned PR/main heads, commit-tree verification and no-force-push rules are unchanged' -ForegroundColor Green
Write-Host ''

& $Runtime -Base $Base -FinalBundle $FinalBundle -FinalBuilder $FinalBuilder
