#requires -version 5.1
[CmdletBinding()]
param(
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE1_20260827_003823\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_NONRELEASE.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = '6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386'
$Patterns = @(
    'game\.dat not found',
    'A8P-INSTALL-001',
    'installation could not be resolved',
    '\$Install\.GameDat',
    'game_dat',
    'GameDat'
)

function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
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
$guiPattern = '(?s)(?:private\s+)?const\s+string\s+GuiGzipBase64\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
$guiMatch = [regex]::Match($csharp,$guiPattern)
if (-not $guiMatch.Success) { throw 'Could not locate GuiGzipBase64.' }

$gui = Expand-GzipBase64 $guiMatch.Groups['data'].Value
$lines = $gui -split "`r?`n"

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P STAGE 3 DOWNSTREAM game.dat SOURCE AUDIT' -ForegroundColor Cyan
Write-Host ' READ ONLY / DECODE ONLY' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Builder     : $BuilderPath"
Write-Host "Builder SHA : $builderHash" -ForegroundColor Green
Write-Host "GUI lines   : $($lines.Count)"
Write-Host ''

$hits = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
    foreach ($p in $Patterns) {
        if ($lines[$i] -match $p) {
            $hits += [PSCustomObject]@{ Line = $i + 1; Pattern = $p; Text = $lines[$i] }
            break
        }
    }
}

if ($hits.Count -eq 0) {
    Write-Host 'No target strings found.' -ForegroundColor Yellow
    exit 2
}

Write-Host '=== TARGET HITS ===' -ForegroundColor Cyan
$hits | Sort-Object Line | Format-Table -AutoSize | Out-Host

$shown = @{}
foreach ($hit in ($hits | Sort-Object Line)) {
    $start = [Math]::Max(1, $hit.Line - 14)
    $end = [Math]::Min($lines.Count, $hit.Line + 18)
    $key = "$start-$end"
    if ($shown.ContainsKey($key)) { continue }
    $shown[$key] = $true

    Write-Host ''
    Write-Host ("=== CONTEXT lines {0}-{1} (hit {2}) ===" -f $start,$end,$hit.Line) -ForegroundColor Cyan
    for ($ln = $start; $ln -le $end; $ln++) {
        $marker = if ($ln -eq $hit.Line) { '>>' } else { '  ' }
        Write-Host ('{0} {1,5}: {2}' -f $marker,$ln,$lines[$ln-1])
    }
}

Write-Host ''
Write-Host 'Audit complete. No builder, EXE, config, game, or release files were modified.' -ForegroundColor Green
