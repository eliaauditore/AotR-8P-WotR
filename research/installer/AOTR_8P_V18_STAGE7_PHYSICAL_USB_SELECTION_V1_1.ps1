#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$UsbDrive = 'I:\'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceCommit = 'a2fd3ad9cfcde335967f5eb5a89b6116408399d3'
$SourcePath = 'research/installer/AOTR_8P_V18_STAGE7_PHYSICAL_USB_SELECTION_V1.ps1'
$SourceUrl = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/$SourcePath"
$ExpectedGitBlobSha1 = '8bb57e1987dad89cfbfe0fefe3a487e654308a5a'

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

$source = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE7_PHYSICAL_USB_SELECTION_V1_SOURCE.ps1'
$runtime = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE7_PHYSICAL_USB_SELECTION_V1_1_RUNTIME.ps1'
Remove-Item $source,$runtime -Force -ErrorAction SilentlyContinue

Invoke-WebRequest -Uri $SourceUrl -OutFile $source
$blob = Get-GitBlobSha1 $source
if ($blob -ne $ExpectedGitBlobSha1) {
    throw ('Pinned Stage7 source blob mismatch. Expected ' + $ExpectedGitBlobSha1 + ', got ' + $blob)
}

$text = [IO.File]::ReadAllText($source)
$old = @'
$usbRoot = Canon $UsbDrive
if (-not (Test-Path -LiteralPath $usbRoot -PathType Container)) { throw ('USB drive root missing: ' + $usbRoot) }
'@
$new = @'
$usbRoot = Canon $UsbDrive
$usbRootPath = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($UsbDrive))
if ([string]::IsNullOrWhiteSpace($usbRootPath) -or -not (Test-Path -LiteralPath $usbRootPath -PathType Container)) { throw ('USB drive root missing: ' + $UsbDrive) }
'@
$count = ([regex]::Matches($text,[regex]::Escape($old))).Count
if ($count -ne 1) { throw ('Expected exactly one Stage7 USB-root patch target, found ' + $count) }
$text = $text.Replace($old,$new)

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) {
    $errors | Format-List * | Out-Host
    throw 'Stage7 V1.1 runtime still has parser errors.'
}

[IO.File]::WriteAllText($runtime,$text,[Text.UTF8Encoding]::new($false))
Write-Host 'Stage7 V1.1 parser validation: PASS' -ForegroundColor Green
Write-Host ('Pinned source blob : ' + $blob) -ForegroundColor Green
Write-Host ('Runtime            : ' + $runtime)
Write-Host ''

& $runtime -Base $Base -UsbDrive $UsbDrive
