#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceCommit = 'e3040ecee032a0f441801f67d139b32dbbc8fd19'
$SourcePath = 'research/installer/AOTR_8P_V18_STAGE8_BUILD_1_1_RC_NO_FAKE_MAXIMIZE_V1.ps1'
$SourceUrl = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/$SourcePath"
$ExpectedGitBlobSha1 = '27ed4d9ee1437bf945629ab21266fd106e3b4665'

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

function Replace-ExactlyOnce([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $first = $Text.IndexOf($Old,[StringComparison]::Ordinal)
    if ($first -lt 0) { throw ('Patch target not found for ' + $Label) }
    $second = $Text.IndexOf($Old,$first+$Old.Length,[StringComparison]::Ordinal)
    if ($second -ge 0) { throw ('Patch target is ambiguous for ' + $Label) }
    return $Text.Substring(0,$first) + $New + $Text.Substring($first+$Old.Length)
}

$source = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE8_BUILD_1_1_RC_V1_SOURCE.ps1'
$runtime = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE8_BUILD_1_1_RC_V1_1_RUNTIME.ps1'
Remove-Item $source,$runtime -Force -ErrorAction SilentlyContinue

Invoke-WebRequest -Uri $SourceUrl -OutFile $source
$blob = Get-GitBlobSha1 $source
if ($blob -ne $ExpectedGitBlobSha1) {
    throw ('Pinned Stage8 V1 source blob mismatch. Expected ' + $ExpectedGitBlobSha1 + ', got ' + $blob)
}

$text = [IO.File]::ReadAllText($source)

$oldSaveCrop = @'
function Save-Crop([System.Drawing.Bitmap]$Bitmap,[System.Drawing.Rectangle]$Rect,[string]$Path) {
'@
$newSaveCrop = @'
try { Add-Type -AssemblyName System.Drawing.Common -ErrorAction Stop }
catch { Add-Type -AssemblyName System.Drawing -ErrorAction Stop }

function Save-Crop([System.Drawing.Bitmap]$Bitmap,[System.Drawing.Rectangle]$Rect,[string]$Path) {
'@
$text = Replace-ExactlyOnce $text $oldSaveCrop $newSaveCrop 'early System.Drawing load'

$oldLateLoad = @'
try { Add-Type -AssemblyName System.Drawing.Common -ErrorAction Stop }
catch { Add-Type -AssemblyName System.Drawing -ErrorAction Stop }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
'@
$newLateLoad = @'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
'@
$text = Replace-ExactlyOnce $text $oldLateLoad $newLateLoad 'remove duplicate late System.Drawing load'

$oldBitmap = @'
$src = [System.Drawing.Bitmap]::new($skinOriginal)
$out = [System.Drawing.Bitmap]::new($skinOriginal)
try {
'@
$newBitmap = @'
$src = [System.Drawing.Bitmap]::new($skinOriginal)
$out = [System.Drawing.Bitmap]::new($src.Width,$src.Height,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$copyGraphics = [System.Drawing.Graphics]::FromImage($out)
try { $copyGraphics.DrawImageUnscaled($src,0,0) }
finally { $copyGraphics.Dispose() }
try {
'@
$text = Replace-ExactlyOnce $text $oldBitmap $newBitmap 'force editable 32bpp skin copy'

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) {
    $errors | Format-List * | Out-Host
    throw 'Stage8 V1.1 runtime has parser errors.'
}

[IO.File]::WriteAllText($runtime,$text,[Text.UTF8Encoding]::new($false))
Write-Host 'Stage8 1.1 RC V1.1 parser validation: PASS' -ForegroundColor Green
Write-Host ('Pinned source blob : ' + $blob) -ForegroundColor Green
Write-Host ('Runtime            : ' + $runtime)
Write-Host ''

& $runtime -Base $Base
