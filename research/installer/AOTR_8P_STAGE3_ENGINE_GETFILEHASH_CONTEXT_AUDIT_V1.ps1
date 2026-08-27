#requires -version 5.1
[CmdletBinding()]
param(
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE1_20260827_003823\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_NONRELEASE.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = '6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386'

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Expand-GzipBase64([string]$Base64) {
    $bytes = [Convert]::FromBase64String(($Base64 -replace '\s',''))
    $ms = New-Object IO.MemoryStream(,$bytes)
    try {
        $gz = New-Object IO.Compression.GZipStream($ms,[IO.Compression.CompressionMode]::Decompress)
        try {
            $out = New-Object IO.MemoryStream
            try {
                $gz.CopyTo($out)
                return [Text.Encoding]::UTF8.GetString($out.ToArray())
            }
            finally { $out.Dispose() }
        }
        finally { $gz.Dispose() }
    }
    finally { $ms.Dispose() }
}

if (-not (Test-Path -LiteralPath $BuilderPath -PathType Leaf)) {
    throw "Builder missing: $BuilderPath"
}
$builderHash = Get-Sha256 $BuilderPath
if ($builderHash -ne $ExpectedBuilderSha256) {
    throw "Builder checkpoint mismatch. Expected $ExpectedBuilderSha256, got $builderHash"
}

$builderText = Get-Content -LiteralPath $BuilderPath -Raw
$outerPattern = '(?s)\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\s*(?<data>[A-Za-z0-9+/=\r\n]+?)\s*''@\)\)'
$outer = [regex]::Match($builderText,$outerPattern)
if (-not $outer.Success) { throw 'Could not locate outer C# Base64 template.' }

$csharp = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($outer.Groups['data'].Value -replace '\s','')))
$enginePattern = '(?s)(?:private\s+)?const\s+string\s+EngineGzipBase64\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
$engineMatch = [regex]::Match($csharp,$enginePattern)
if (-not $engineMatch.Success) { throw 'Could not locate EngineGzipBase64.' }

$engine = Expand-GzipBase64 $engineMatch.Groups['data'].Value
$lines = $engine -split "`r?`n"

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P STAGE 3 ENGINE Get-FileHash CONTEXT AUDIT V1' -ForegroundColor Cyan
Write-Host ' READ ONLY / DECODE ONLY' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Builder     : $BuilderPath"
Write-Host "Builder SHA : $builderHash" -ForegroundColor Green
Write-Host "Engine lines: $($lines.Count)"
Write-Host ''

$hits = New-Object System.Collections.Generic.List[object]
for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '\bGet-FileHash\b') {
        [void]$hits.Add([PSCustomObject]@{ Line=$i+1; Text=$lines[$i] })
    }
}

Write-Host ('Get-FileHash occurrences: ' + $hits.Count)
if ($hits.Count -eq 0) {
    Write-Host 'No Engine Get-FileHash usage found.' -ForegroundColor Green
    exit 0
}

$hits.ToArray() | Format-Table -AutoSize | Out-Host

foreach ($hit in $hits.ToArray()) {
    $start = [Math]::Max(1,$hit.Line-24)
    $end = [Math]::Min($lines.Count,$hit.Line+24)
    Write-Host ''
    Write-Host ("=== ENGINE CONTEXT lines {0}-{1} / hit {2} ===" -f $start,$end,$hit.Line) -ForegroundColor Cyan
    for ($ln=$start; $ln -le $end; $ln++) {
        $mark = if ($ln -eq $hit.Line) { '>>' } else { '  ' }
        Write-Host ('{0} {1,5}: {2}' -f $mark,$ln,$lines[$ln-1])
    }
}

Write-Host ''
Write-Host '=== FUNCTION DECLARATIONS NEAR HASHING ===' -ForegroundColor Cyan
for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*function\s+[^\s{]*(Hash|Sha|File|Verify|Manifest)[^\s{]*') {
        Write-Host ('{0,5}: {1}' -f ($i+1),$lines[$i])
    }
}

Write-Host ''
Write-Host 'Audit complete. No builder, EXE, config, game, cache, or release files were modified.' -ForegroundColor Green
