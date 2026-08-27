#requires -version 5.1
[CmdletBinding()]
param(
    [string]$SearchRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING',
    [string]$CurrentBuilder = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE3_HASHFIX_V2_20260827_012753\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_HASHFIX_V2_NONRELEASE.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedCurrentBuilderSha256 = 'B244D987A99533DD3A79978032F64C261FF7EBBDDA1AAFA6BB0142FFA9BC2572'
$ExpectedCurrentGuiSha256 = 'AA8893A160CF790644FF794F4E8E47B3D1E05E1022AD22FB784A071B91920D8E'
$LegacyFileName = 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_RC4_STATUS_PANEL.ps1'
$LegacyMarker = 'dynamic center health/status panel independent of baked skin text'

function Get-Sha256File([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $stream.Dispose() }
    }
    finally { $sha.Dispose() }
}

function Get-Sha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Expand-GzipBase64Bytes([string]$Base64) {
    $compressed = [Convert]::FromBase64String(($Base64 -replace '\s',''))
    $input = New-Object IO.MemoryStream(,$compressed)
    try {
        $gzip = New-Object IO.Compression.GZipStream($input,[IO.Compression.CompressionMode]::Decompress)
        try {
            $output = New-Object IO.MemoryStream
            try { $gzip.CopyTo($output); return $output.ToArray() }
            finally { $output.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally { $input.Dispose() }
}

function Get-GuiFromBuilder([string]$BuilderPath) {
    $builderText = [IO.File]::ReadAllText($BuilderPath)
    $outerPattern = '(?s)\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\s*(?<data>[A-Za-z0-9+/=\r\n]+?)\s*''@\)\)'
    $outer = [regex]::Match($builderText,$outerPattern)
    if (-not $outer.Success) { throw "Could not locate outer C# Base64 template in $BuilderPath" }
    $csharp = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($outer.Groups['data'].Value -replace '\s','')))
    $guiPattern = '(?s)(?:private\s+)?const\s+string\s+GuiGzipBase64\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
    $gm = [regex]::Match($csharp,$guiPattern)
    if (-not $gm.Success) { throw "Could not locate GuiGzipBase64 in $BuilderPath" }
    $bytes = Expand-GzipBase64Bytes $gm.Groups['data'].Value
    return [PSCustomObject]@{ Bytes=$bytes; Text=[Text.Encoding]::UTF8.GetString($bytes); Sha256=(Get-Sha256Bytes $bytes) }
}

function Show-Hits([string]$Label,[string]$Text) {
    $lines = $Text -split "`r?`n"
    $patterns = @(
        'StatusPanel','HealthPanel','StatusRow','Status1','Status2','Status3','StatusGame','StatusCampaign','StatusUi',
        'game\.dat','campaign','roster','8.?player','READY','PASS','FAIL','OK','Invoke-Preflight','Set-.*Status',
        'Canvas\.Left="2[0-9][0-9]"','Canvas\.Top="2[5-9][0-9]"','Canvas\.Top="3[0-9][0-9]"','Canvas\.Top="4[0-9][0-9]"'
    )
    $hits = New-Object System.Collections.Generic.List[object]
    for ($i=0; $i -lt $lines.Count; $i++) {
        foreach ($p in $patterns) {
            if ($lines[$i] -match $p) {
                [void]$hits.Add([PSCustomObject]@{Line=$i+1; Text=$lines[$i]})
                break
            }
        }
    }
    Write-Host ''
    Write-Host ("=== $Label STATUS HITS ===") -ForegroundColor Cyan
    $hits | Format-Table -AutoSize | Out-Host

    $focus = @($hits | Where-Object { $_.Text -match '(?i)Status|Health|game\.dat|campaign|roster|Invoke-Preflight|Set-.*Status' })
    $shown = @{}
    foreach ($h in $focus) {
        $start = [Math]::Max(1,$h.Line-10)
        $end = [Math]::Min($lines.Count,$h.Line+22)
        $bucket = [Math]::Floor($h.Line / 20)
        if ($shown.ContainsKey($bucket)) { continue }
        $shown[$bucket] = $true
        Write-Host ''
        Write-Host ("--- $Label context lines $start-$end / hit $($h.Line) ---") -ForegroundColor DarkCyan
        for ($ln=$start; $ln -le $end; $ln++) {
            $mark = if ($ln -eq $h.Line) { '>>' } else { '  ' }
            Write-Host ('{0} {1,5}: {2}' -f $mark,$ln,$lines[$ln-1])
        }
    }
}

if (-not (Test-Path -LiteralPath $SearchRoot -PathType Container)) { throw "Search root missing: $SearchRoot" }
if (-not (Test-Path -LiteralPath $CurrentBuilder -PathType Leaf)) { throw "Current builder missing: $CurrentBuilder" }
$currentBuilderHash = Get-Sha256File $CurrentBuilder
if ($currentBuilderHash -ne $ExpectedCurrentBuilderSha256) { throw "Current builder hash mismatch. Expected $ExpectedCurrentBuilderSha256, got $currentBuilderHash" }
$currentGui = Get-GuiFromBuilder $CurrentBuilder
if ($currentGui.Sha256 -ne $ExpectedCurrentGuiSha256) { throw "Current GUI hash mismatch. Expected $ExpectedCurrentGuiSha256, got $($currentGui.Sha256)" }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P STAGE 3 STATUS PANEL RC4 RECOVERY AUDIT V2' -ForegroundColor Cyan
Write-Host ' EXACT FILENAME + SOURCE MARKER / READ ONLY' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Search root     : $SearchRoot"
Write-Host "Current builder : $CurrentBuilder"
Write-Host "Current SHA     : $currentBuilderHash" -ForegroundColor Green
Write-Host "Current GUI SHA : $($currentGui.Sha256)" -ForegroundColor Green

$candidates = @(Get-ChildItem -LiteralPath $SearchRoot -Recurse -File -Filter $LegacyFileName -ErrorAction SilentlyContinue)
Write-Host "RC4 filename matches: $($candidates.Count)"
if ($candidates.Count -eq 0) { throw "RC4 status-panel builder filename not found under $SearchRoot" }

$valid = New-Object System.Collections.Generic.List[object]
foreach ($f in $candidates) {
    try {
        $head = [IO.File]::ReadAllText($f.FullName)
        if ($head -notmatch [regex]::Escape($LegacyMarker)) { continue }
        [void]$valid.Add([PSCustomObject]@{Path=$f.FullName; Sha256=(Get-Sha256File $f.FullName)})
    } catch {}
}
if ($valid.Count -eq 0) { throw "Found filename matches, but none contained the proven RC4 status-panel marker." }

$groups = @($valid | Group-Object Sha256)
Write-Host ''
Write-Host '=== RC4 STATUS-PANEL CANDIDATES ===' -ForegroundColor Cyan
$valid | Format-Table -AutoSize | Out-Host
if ($groups.Count -ne 1) { throw "Multiple different RC4 status-panel builder hashes found. Refusing ambiguous recovery." }

$legacyPath = [string]$valid[0].Path
$legacyHash = [string]$valid[0].Sha256
$legacyGui = Get-GuiFromBuilder $legacyPath
Write-Host "Legacy builder  : $legacyPath" -ForegroundColor Green
Write-Host "Legacy SHA      : $legacyHash" -ForegroundColor Green
Write-Host "Legacy GUI SHA  : $($legacyGui.Sha256)" -ForegroundColor Green
Write-Host "Legacy GUI lines: $(($legacyGui.Text -split "`r?`n").Count)"

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outRoot = Join-Path $SearchRoot ("AOTR_8P_STATUS_PANEL_RC4_RECOVERY_" + $stamp)
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
[IO.File]::WriteAllText((Join-Path $outRoot 'LEGACY_RC4_GUI.ps1'),$legacyGui.Text,(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $outRoot 'CURRENT_HASHFIX_GUI.ps1'),$currentGui.Text,(New-Object Text.UTF8Encoding($false)))

Show-Hits 'LEGACY RC4' $legacyGui.Text
Show-Hits 'CURRENT HASHFIX' $currentGui.Text

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' RC4 STATUS PANEL RECOVERY AUDIT COMPLETE' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host "Output root : $outRoot"
Write-Host 'No builder, EXE, skin, config, game, cache, or release file was modified.' -ForegroundColor Green
