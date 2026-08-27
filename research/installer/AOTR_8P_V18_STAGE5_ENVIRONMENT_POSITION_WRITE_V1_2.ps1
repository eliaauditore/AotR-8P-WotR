#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceCommit = '6315dfcf1a02ea512f43046871ab9e7707ad1aba'
$SourcePath = 'research/installer/AOTR_8P_V18_STAGE5_ENVIRONMENT_POSITION_WRITE_V1.ps1'
$SourceUrl = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/$SourcePath"
$ExpectedGitBlobSha1 = 'ee1af1073597baee9eb3ad3828d02fb97938ad0a'

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

function Replace-ExactOnce {
    param([string]$Text,[string]$Old,[string]$New,[string]$Label)
    $count = ([regex]::Matches($Text,[regex]::Escape($Old))).Count
    if ($count -ne 1) { throw "Expected exactly one patch target for $Label, found $count." }
    return $Text.Replace($Old,$New)
}

$source = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE5_ENVIRONMENT_POSITION_WRITE_V1_SOURCE.ps1'
$runtime = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE5_ENVIRONMENT_POSITION_WRITE_V1_2_RUNTIME.ps1'
Remove-Item $source,$runtime -Force -ErrorAction SilentlyContinue

Invoke-WebRequest -Uri $SourceUrl -OutFile $source
$blob = Get-GitBlobSha1 $source
if ($blob -ne $ExpectedGitBlobSha1) {
    throw "Pinned Stage5 source blob mismatch. Expected $ExpectedGitBlobSha1, got $blob"
}

$text = [IO.File]::ReadAllText($source)

# Keep result reporting null-safe so a genuine discovery failure is recorded as FAIL
# instead of crashing the harness while formatting .Root.
$text = Replace-ExactOnce $text `
    '    Add-Result ''launcher/package in Downloads-style location'' $downloadsPass ("resolved=" + [string]$fromDownloads.Root + '', error='' + [string]$script:LastErrorCode)' `
    "    `$downloadsResolvedText = if (`$fromDownloads) { [string]`$fromDownloads.Root } else { '<null>' }`r`n    Add-Result 'launcher/package in Downloads-style location' `$downloadsPass ('resolved=' + `$downloadsResolvedText + ', error=' + [string]`$script:LastErrorCode)" `
    'safe Downloads result detail'

$text = Replace-ExactOnce $text `
    '    Add-Result ''launcher/package directly inside AotR root'' $insidePass ("resolved=" + [string]$fromInstall.Root + '', error='' + [string]$script:LastErrorCode)' `
    "    `$insideResolvedText = if (`$fromInstall) { [string]`$fromInstall.Root } else { '<null>' }`r`n    Add-Result 'launcher/package directly inside AotR root' `$insidePass ('resolved=' + `$insideResolvedText + ', error=' + [string]`$script:LastErrorCode)" `
    'safe inside-install result detail'

# Run the real ACL-denied case on LOCALAPPDATA so it is a Windows/NTFS permission test,
# independent of the filesystem used by D:\BFME_RESEARCH.
$text = Replace-ExactOnce $text `
    "    `$denyRoot = Join-Path `$workRoot 'ACL_DENY_STATE'" `
    "    `$denyRoot = Join-Path `$env:LOCALAPPDATA ('A8P_STAGE5_ACL_DENY_' + [Guid]::NewGuid().ToString('N'))" `
    'ACL test root on LOCALAPPDATA'

# Deliberately do NOT inject a text-based cleanup edit into the ACL finally block.
# The original Stage5 source already restores the exact original SDDL and throws if restoration fails.
# Leaving an empty restored test directory is safer than making ACL restoration depend on another
# fragile multiline source replacement.

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) {
    $errors | Format-List * | Out-Host
    throw 'Stage5 V1.2 runtime still has parser errors.'
}

[IO.File]::WriteAllText($runtime,$text,[Text.UTF8Encoding]::new($false))
Write-Host 'Stage5 V1.2 parser validation: PASS' -ForegroundColor Green
Write-Host "Pinned source blob : $blob" -ForegroundColor Green
Write-Host "Runtime            : $runtime"
Write-Host ''

& $runtime -Base $Base
