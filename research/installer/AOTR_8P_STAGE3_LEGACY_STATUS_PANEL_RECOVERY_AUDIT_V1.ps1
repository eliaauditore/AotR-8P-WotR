#requires -version 5.1
[CmdletBinding()]
param(
    [string]$SearchRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedLegacyBuilderSha256 = '5F806FB048BF7761252AC9D7B557B0177D71C3E9FFEA1E9003CD4DC300867E2'

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Expand-GzipBase64([string]$Base64) {
    $bytes = [Convert]::FromBase64String(($Base64 -replace '\s',''))
    $input = New-Object IO.MemoryStream(,$bytes)
    try {
        $gzip = New-Object IO.Compression.GZipStream($input,[IO.Compression.CompressionMode]::Decompress)
        try {
            $output = New-Object IO.MemoryStream
            try {
                $gzip.CopyTo($output)
                return [Text.Encoding]::UTF8.GetString($output.ToArray())
            }
            finally { $output.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally { $input.Dispose() }
}

function Get-GuiFromBuilder([string]$BuilderPath) {
    $builderText = Get-Content -LiteralPath $BuilderPath -Raw
    $outerPattern = '(?s)\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\s*(?<data>[A-Za-z0-9+/=\r\n]+?)\s*''@\)\)'
    $outer = [regex]::Match($builderText,$outerPattern)
    if (-not $outer.Success) { throw "Could not locate outer C# Base64 template in $BuilderPath" }

    $csharp = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($outer.Groups['data'].Value -replace '\s','')))
    $guiPattern = '(?s)(?:private\s+)?const\s+string\s+GuiGzipBase64\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
    $guiMatch = [regex]::Match($csharp,$guiPattern)
    if (-not $guiMatch.Success) { throw "Could not locate GuiGzipBase64 in $BuilderPath" }
    return (Expand-GzipBase64 $guiMatch.Groups['data'].Value)
}

if (-not (Test-Path -LiteralPath $SearchRoot -PathType Container)) {
    throw "Search root missing: $SearchRoot"
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P LEGACY STATUS PANEL RECOVERY AUDIT V1' -ForegroundColor Cyan
Write-Host ' EXACT-HASH LEGACY BUILDER / READ ONLY' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Search root : $SearchRoot"
Write-Host "Target SHA  : $ExpectedLegacyBuilderSha256"
Write-Host ''

$candidates = @(
    Get-ChildItem -LiteralPath $SearchRoot -Recurse -File -Filter 'BUILD_AOTR_8P_SINGLE_EXE*.ps1' -ErrorAction SilentlyContinue
)
Write-Host "Builder candidates: $($candidates.Count)"

$legacy = $null
foreach ($file in $candidates) {
    try {
        $hash = Get-Sha256 $file.FullName
        if ($hash -eq $ExpectedLegacyBuilderSha256) {
            $legacy = $file.FullName
            break
        }
    }
    catch {
        Write-Host ("[WARN] Could not hash: " + $file.FullName + " :: " + $_.Exception.Message) -ForegroundColor DarkYellow
    }
}

if (-not $legacy) {
    throw "Exact LAN_UI_POLISH builder SHA was not found under $SearchRoot"
}

Write-Host "Legacy builder: $legacy" -ForegroundColor Green
Write-Host "Legacy SHA    : $(Get-Sha256 $legacy)" -ForegroundColor Green

$gui = Get-GuiFromBuilder $legacy
$lines = $gui -split "`r?`n"
Write-Host "GUI lines     : $($lines.Count)"
Write-Host ''

$patterns = @(
    'Row1', 'Row2', 'Row3', 'Ready', 'Preflight',
    'game\.dat', 'campaign', 'roster', 'payload', '8.?player',
    'status', 'launch', 'TextBlock', 'Visibility'
)

$hits = New-Object System.Collections.Generic.List[object]
for ($i=0; $i -lt $lines.Count; $i++) {
    foreach ($p in $patterns) {
        if ($lines[$i] -match $p) {
            [void]$hits.Add([PSCustomObject]@{ Line=$i+1; Pattern=$p; Text=$lines[$i] })
            break
        }
    }
}

Write-Host '=== LEGACY STATUS-RELATED HITS ===' -ForegroundColor Cyan
$hits | Format-Table -AutoSize | Out-Host

$focus = @($hits | Where-Object {
    $_.Text -match '(?i)Row[123]|Ready|Preflight|game\.dat|campaign|roster|8.?player|launch'
})

$shown = @{}
foreach ($hit in $focus) {
    $start = [Math]::Max(1,$hit.Line-12)
    $end = [Math]::Min($lines.Count,$hit.Line+18)
    $key = "$start-$end"
    if ($shown.ContainsKey($key)) { continue }
    $shown[$key] = $true
    Write-Host ''
    Write-Host ("=== LEGACY CONTEXT lines {0}-{1} / hit {2} ===" -f $start,$end,$hit.Line) -ForegroundColor Cyan
    for ($ln=$start; $ln -le $end; $ln++) {
        $marker = if ($ln -eq $hit.Line) { '>>' } else { '  ' }
        Write-Host ('{0} {1,5}: {2}' -f $marker,$ln,$lines[$ln-1])
    }
}

Write-Host ''
Write-Host 'Audit complete. No builder, EXE, skin, config, game, or release files were modified.' -ForegroundColor Green
