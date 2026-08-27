#requires -version 5.1
[CmdletBinding()]
param(
    [string]$Stage1Path = (Join-Path $env:TEMP 'AOTR_8P_STAGE1_INTEGRATE_ROBUST_AUTODETECT_V2.ps1'),
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$BuilderPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedStage1Sha256 = '5518DDE7284F58C908FA99CE41A3F641D89A786C469EB1B4D2E56D94428062A6'

if (-not (Test-Path -LiteralPath $Stage1Path -PathType Leaf)) {
    throw "Stage 1 script not found: $Stage1Path"
}

$actual = (Get-FileHash -LiteralPath $Stage1Path -Algorithm SHA256).Hash.ToUpperInvariant()
if ($actual -ne $ExpectedStage1Sha256) {
    throw "Stage 1 checkpoint mismatch. Expected $ExpectedStage1Sha256, got $actual. Refusing hotfix."
}

$source = [IO.File]::ReadAllText($Stage1Path)

$old = @'
function Convert-GzipBase64ToText([string]$Base64) {
    $bytes = [Convert]::FromBase64String(($Base64 -replace '\s',''))
    $input = New-Object IO.MemoryStream(,$bytes)
    try {
        $gzip = New-Object IO.Compression.GZipStream(
            $input,
            [IO.Compression.CompressionMode]::Decompress
        )
        try {
            $reader = New-Object IO.StreamReader($gzip,[Text.Encoding]::UTF8,$true)
            try {
                return $reader.ReadToEnd()
            }
            finally { $reader.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally { $input.Dispose() }
}
'@

$new = @'
function Convert-GzipBase64ToText([string]$Base64) {
    # Preserve the exact decompressed UTF-8 byte stream, including a UTF-8 BOM.
    # StreamReader with BOM detection consumes the BOM and changes the checkpoint hash.
    $packed = [Convert]::FromBase64String(($Base64 -replace '\s',''))
    $input = New-Object IO.MemoryStream(,$packed)
    try {
        $gzip = New-Object IO.Compression.GZipStream(
            $input,
            [IO.Compression.CompressionMode]::Decompress
        )
        try {
            $output = New-Object IO.MemoryStream
            try {
                $gzip.CopyTo($output)
                $raw = $output.ToArray()
                return [Text.Encoding]::UTF8.GetString($raw)
            }
            finally { $output.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally { $input.Dispose() }
}
'@

$first = $source.IndexOf($old,[StringComparison]::Ordinal)
if ($first -lt 0) {
    throw 'Expected BOM-stripping Convert-GzipBase64ToText implementation was not found.'
}
$second = $source.IndexOf($old,$first + $old.Length,[StringComparison]::Ordinal)
if ($second -ge 0) {
    throw 'Expected GZip helper occurs more than once; refusing ambiguous hotfix.'
}

$patched = $source.Substring(0,$first) + $new + $source.Substring($first + $old.Length)

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($patched,[ref]$tokens,[ref]$errors)
if ($errors -and $errors.Count -gt 0) {
    $msg = ($errors | ForEach-Object { "Line $($_.Extent.StartLineNumber): $($_.Message)" }) -join [Environment]::NewLine
    throw "Hotfixed Stage 1 script failed parser validation:`n$msg"
}

$patchedPath = Join-Path $env:TEMP 'AOTR_8P_STAGE1_INTEGRATE_ROBUST_AUTODETECT_V2_1_RUNTIME.ps1'
[IO.File]::WriteAllText($patchedPath,$patched,(New-Object Text.UTF8Encoding($false)))
$patchedSha = (Get-FileHash -LiteralPath $patchedPath -Algorithm SHA256).Hash.ToUpperInvariant()

Write-Host ''
Write-Host '=== STAGE 1 BOM HOTFIX V2.1 ===' -ForegroundColor Cyan
Write-Host "Original Stage1 : $Stage1Path"
Write-Host "Original SHA256 : $actual" -ForegroundColor Green
Write-Host "Patched runtime : $patchedPath"
Write-Host "Patched SHA256  : $patchedSha" -ForegroundColor Green
Write-Host 'Change           : preserve decompressed UTF-8 BOM before checkpoint hashing'
Write-Host ''

if ([string]::IsNullOrWhiteSpace($BuilderPath)) {
    & $patchedPath -Base $Base
}
else {
    & $patchedPath -Base $Base -BuilderPath $BuilderPath
}
