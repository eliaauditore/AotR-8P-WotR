#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceCommit = 'f1d2c6a54f9014d7ec5ed123eb0e6f4859038d8a'
$SourcePath = 'research/installer/AOTR_8P_V18_STAGE11_FINAL_FIVE_FILE_PROMOTION_GATE_V1.ps1'
$ExpectedGitBlobSha1 = 'ec7bbfd1dc0171c299f6d855d832b98b541d7bf4'
$SourceUrl = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $SourceCommit + '/' + $SourcePath
$SourceTemp = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE11_GATE_V1_SOURCE.ps1'
$Runtime = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE11_GATE_V1_1_RUNTIME.ps1'
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

# Source retrieval is also bounded so this wrapper cannot silently hang forever.
& curl.exe -L --fail --silent --show-error --connect-timeout 10 --max-time 30 -o $SourceTemp $SourceUrl
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $SourceTemp -PathType Leaf)) {
    throw ('Could not download pinned Stage11 V1 source. curl exit=' + $LASTEXITCODE)
}

$sourceBytes = [IO.File]::ReadAllBytes($SourceTemp)
$blob = Get-GitBlobSha1 $sourceBytes
if ($blob -ne $ExpectedGitBlobSha1) { throw ('Pinned V1 blob mismatch. Expected ' + $ExpectedGitBlobSha1 + ', got ' + $blob) }
$text = [Text.UTF8Encoding]::new($false,$true).GetString($sourceBytes)

$old = @'
Write-Host ''
Write-Host 'Downloading current live five-file root as rollback snapshot...' -ForegroundColor Cyan
foreach ($name in $ExpectedBundleFiles) {
    $encoded = if ($name -eq $LauncherName) { 'AotR%208P%20WotR%20Mod.exe' } else { $name }
    Invoke-WebRequest -Uri ($RootBase + '/' + $encoded) -OutFile (Join-Path $rollbackRoot $name)
}
'@

$new = @'
Write-Host ''
Write-Host 'Downloading current live five-file root as rollback snapshot...' -ForegroundColor Cyan
$downloadIndex = 0
foreach ($name in $ExpectedBundleFiles) {
    $downloadIndex++
    $encoded = if ($name -eq $LauncherName) { 'AotR%208P%20WotR%20Mod.exe' } else { $name }
    $url = $RootBase + '/' + $encoded
    $dest = Join-Path $rollbackRoot $name
    $ok = $false
    for ($attempt = 1; $attempt -le 3 -and -not $ok; $attempt++) {
        Write-Host ('  [' + $downloadIndex + '/5] ' + $name + '  attempt ' + $attempt + '/3') -ForegroundColor DarkCyan
        Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
        & curl.exe -L --fail --silent --show-error --connect-timeout 10 --max-time 45 -o $dest $url
        $curlExit = $LASTEXITCODE
        if ($curlExit -eq 0 -and (Test-Path -LiteralPath $dest -PathType Leaf) -and (Get-Item -LiteralPath $dest).Length -gt 0) {
            $ok = $true
            Write-Host ('       downloaded ' + (Get-Item -LiteralPath $dest).Length + ' bytes') -ForegroundColor Green
        } else {
            Write-Host ('       download failed, curl exit=' + $curlExit) -ForegroundColor Yellow
            if ($attempt -lt 3) { Start-Sleep -Seconds 2 }
        }
    }
    if (-not $ok) { throw ('Rollback download failed after 3 attempts: ' + $name) }
}
'@

$text = Replace-ExactOnce $text $old $new 'bounded rollback download loop'
[IO.File]::WriteAllText($Runtime,$text,[Text.UTF8Encoding]::new($false))

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) {
    $errors | Format-List *
    throw 'STOP: Stage11 V1.1 runtime has parser errors.'
}

Write-Host 'Stage11 V1.1 parser validation: PASS' -ForegroundColor Green
Write-Host ('Pinned V1 source blob: ' + $ExpectedGitBlobSha1)
Write-Host 'Rollback downloads: curl timeout + 3 attempts + per-file progress' -ForegroundColor Green
Write-Host ''

& $Runtime -Base $Base
