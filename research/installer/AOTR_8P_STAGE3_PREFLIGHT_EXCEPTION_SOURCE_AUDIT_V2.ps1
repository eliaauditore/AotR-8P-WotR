#requires -version 5.1
[CmdletBinding()]
param(
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE1_20260827_003823\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_NONRELEASE.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = '6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386'
$Patterns = @(
    '\$Known931GameSize',
    '\$Known931GameSha256',
    '\$CompatCachePath',
    'function\s+Get-Sha256',
    'function\s+Test-CachedCompatibleBuild',
    'Set-StrictMode',
    'function\s+Invoke-Preflight',
    'game\.dat not found'
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
Write-Host ' AOTR 8P STAGE 3 PREFLIGHT EXCEPTION SOURCE AUDIT V2' -ForegroundColor Cyan
Write-Host ' READ ONLY / DECODE ONLY' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Builder     : $BuilderPath"
Write-Host "Builder SHA : $builderHash" -ForegroundColor Green
Write-Host "GUI lines   : $($lines.Count)"
Write-Host ''

$hits = New-Object System.Collections.Generic.List[object]
for ($i=0; $i -lt $lines.Count; $i++) {
    foreach ($p in $Patterns) {
        if ($lines[$i] -match $p) {
            [void]$hits.Add([PSCustomObject]@{ Line=$i+1; Pattern=$p; Text=$lines[$i] })
            break
        }
    }
}

Write-Host '=== TARGET HITS ===' -ForegroundColor Cyan
if ($hits.Count -eq 0) {
    Write-Host 'No target strings found.' -ForegroundColor Red
    exit 2
}
$hits.ToArray() | Sort-Object Line | Format-Table -AutoSize | Out-Host

Write-Host ''
Write-Host '=== DEFINITION COUNTS ===' -ForegroundColor Cyan
$defs = @(
    [PSCustomObject]@{ Name='Known931GameSize'; DefinitionRegex='^\s*\$(?:script:|global:)?Known931GameSize\s*='; UsageRegex='\$Known931GameSize' },
    [PSCustomObject]@{ Name='Known931GameSha256'; DefinitionRegex='^\s*\$(?:script:|global:)?Known931GameSha256\s*='; UsageRegex='\$Known931GameSha256' },
    [PSCustomObject]@{ Name='CompatCachePath'; DefinitionRegex='^\s*\$(?:script:|global:)?CompatCachePath\s*='; UsageRegex='\$CompatCachePath' }
)
foreach ($d in $defs) {
    $defLines = @()
    $useLines = @()
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $d.DefinitionRegex) { $defLines += ($i+1) }
        if ($lines[$i] -match $d.UsageRegex) { $useLines += ($i+1) }
    }
    $defText = if ($defLines.Count) { $defLines -join ',' } else { 'NONE' }
    $useText = if ($useLines.Count) { $useLines -join ',' } else { 'NONE' }
    $color = if ($defLines.Count) { 'Green' } else { 'Red' }
    Write-Host ("{0}: definitions={1}; usages={2}" -f $d.Name,$defText,$useText) -ForegroundColor $color
}

Write-Host ''
Write-Host '=== FOCUSED CONTEXT ===' -ForegroundColor Cyan
$focusLines = @(
    ($hits.ToArray() | Where-Object { $_.Text -match 'Known931GameSize|Known931GameSha256|CompatCachePath|function\s+Test-CachedCompatibleBuild|function\s+Invoke-Preflight' } | Select-Object -ExpandProperty Line)
) | Sort-Object -Unique
$shown = @{}
foreach ($lineNo in $focusLines) {
    $start = [Math]::Max(1,[int]$lineNo-8)
    $end = [Math]::Min($lines.Count,[int]$lineNo+14)
    $key = "$start-$end"
    if ($shown.ContainsKey($key)) { continue }
    $shown[$key] = $true
    Write-Host ''
    Write-Host ("--- lines {0}-{1} ---" -f $start,$end) -ForegroundColor Cyan
    for ($ln=$start; $ln -le $end; $ln++) {
        $marker = if ($ln -eq [int]$lineNo) { '>>' } else { '  ' }
        Write-Host ('{0} {1,5}: {2}' -f $marker,$ln,$lines[$ln-1])
    }
}

Write-Host ''
Write-Host 'Interpretation rule:' -ForegroundColor Yellow
Write-Host '  If Known931GameSize or Known931GameSha256 has usages but ZERO definitions,' -ForegroundColor Yellow
Write-Host '  Set-StrictMode makes Invoke-Preflight throw; its empty catch then misreports game.dat not found.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Audit complete. No builder, EXE, config, game, cache, or release files were modified.' -ForegroundColor Green
