#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceCommit = 'bcb274097a053718172c36ba9afce692be9306e4'
$SourcePath = 'research/installer/AOTR_8P_V18_STAGE4_AUTODETECT_MATRIX_CORE_V1.ps1'
$SourceUrl = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/$SourcePath"
$ExpectedGitBlobSha1 = 'cb9605f724cb9818b264c216586dbcbc8c33d095'

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

$source = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE4_AUTODETECT_MATRIX_CORE_V1_SOURCE.ps1'
$runtime = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE4_AUTODETECT_MATRIX_CORE_V1_1_RUNTIME.ps1'
Remove-Item $source,$runtime -Force -ErrorAction SilentlyContinue

Invoke-WebRequest -Uri $SourceUrl -OutFile $source
$blob = Get-GitBlobSha1 $source
if ($blob -ne $ExpectedGitBlobSha1) {
    throw "Pinned Stage4 source blob mismatch. Expected $ExpectedGitBlobSha1, got $blob"
}

$text = [IO.File]::ReadAllText($source)

$patches = @(
    [PSCustomObject]@{
        Old = '$ranked = @($full,$minimal | Sort-Object @{Expression=''Score'';Descending=$true},Root)'
        New = '$ranked = @(@($full,$minimal) | Sort-Object @{Expression=''Score'';Descending=$true},Root)'
        Label = 'full/minimal ranking materialization'
    },
    [PSCustomObject]@{
        Old = '$tieRanked = @($full,$tie | Sort-Object @{Expression=''Score'';Descending=$true},Root)'
        New = '$tieRanked = @(@($full,$tie) | Sort-Object @{Expression=''Score'';Descending=$true},Root)'
        Label = 'tie ranking materialization'
    },
    [PSCustomObject]@{
        Old = "    Add-Result 'real launcher config unchanged' ([bool]`$realConfigUnchanged) (if (`$realConfigExisted) { 'hash before/after compared' } else { 'remained absent' })"
        New = "    `$realConfigDetail = if (`$realConfigExisted) { 'hash before/after compared' } else { 'remained absent' }`r`n    Add-Result 'real launcher config unchanged' ([bool]`$realConfigUnchanged) `$realConfigDetail"
        Label = 'real-config detail expression'
    }
)

foreach ($patch in $patches) {
    $count = ([regex]::Matches($text,[regex]::Escape([string]$patch.Old))).Count
    if ($count -ne 1) { throw "Expected exactly one $($patch.Label) patch target, found $count." }
    $text = $text.Replace([string]$patch.Old,[string]$patch.New)
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) {
    $errors | Format-List * | Out-Host
    throw 'Stage4 core matrix V1.1 still has parser errors.'
}

[IO.File]::WriteAllText($runtime,$text,[Text.UTF8Encoding]::new($false))
Write-Host 'Stage4 core matrix V1.1 parser validation: PASS' -ForegroundColor Green
Write-Host "Pinned source blob : $blob" -ForegroundColor Green
Write-Host "Runtime            : $runtime"
Write-Host ''

& $runtime -Base $Base
