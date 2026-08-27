#requires -version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ReleaseCommit = '1303e0a6b268b082e9352ded1461fa8d794f16d3'
$BuilderRelativePath = 'launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10.ps1'
# IMPORTANT: 7D847B66... is the documented local pre-promotion builder hash.
# The immutable file stored in release commit 1303e0a6... has Git blob 9d8975828106a572f43344e57891014860d489d4
# and raw SHA256 8BDD8745... . This audit pins the actual released bytes.
$DocumentedPrePromotionBuilderSha256 = '7D847B66CAF060F3E1C5FD539DA3DF6E97865421651608CDD98898342C1BB2E0'
$ExpectedBuilderSha256 = '8BDD8745931B41AA2B062FB9ADCE8BBBD7EA2A33F4C0946C20A409D89639271A'
$ExpectedGitBlobSha = '9d8975828106a572f43344e57891014860d489d4'
$BuilderUrl = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$ReleaseCommit/$BuilderRelativePath"

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
    $input = [IO.MemoryStream]::new($compressed)
    try {
        $gzip = [IO.Compression.GZipStream]::new($input,[IO.Compression.CompressionMode]::Decompress)
        try {
            $output = [IO.MemoryStream]::new()
            try { $gzip.CopyTo($output); return $output.ToArray() }
            finally { $output.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally { $input.Dispose() }
}

function Get-OuterCSharp([string]$BuilderText) {
    $pattern = '(?s)\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\s*(?<data>[A-Za-z0-9+/=\r\n]+?)\s*''@\)\)'
    $m = [regex]::Match($BuilderText,$pattern)
    if (-not $m.Success) { throw 'Could not locate outer C# Base64 template.' }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($m.Groups['data'].Value -replace '\s','')))
}

function Get-Payload([string]$CSharp,[string]$Name) {
    $pattern = '(?s)(?:private\s+)?const\s+string\s+' + [regex]::Escape($Name) + '\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
    $m = [regex]::Match($CSharp,$pattern)
    if (-not $m.Success) { throw "Could not locate $Name in outer C# template." }
    $bytes = Expand-GzipBase64Bytes $m.Groups['data'].Value
    [PSCustomObject]@{ Bytes=$bytes; Text=[Text.Encoding]::UTF8.GetString($bytes); Sha256=(Get-Sha256Bytes $bytes) }
}

function Count-Matches([string]$Text,[string]$Pattern) {
    return @([regex]::Matches($Text,$Pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
}

function Show-MarkerTable([string]$Label,[string]$Text,[System.Collections.IDictionary]$Markers) {
    Write-Host ''
    Write-Host "=== $Label ===" -ForegroundColor Cyan
    foreach ($key in $Markers.Keys) {
        $count = Count-Matches $Text $Markers[$key]
        Write-Host ('{0,-36} {1,4}' -f $key,$count)
    }
}

function Show-Context([string]$Label,[string]$Text,[string]$Pattern,[int]$Before=5,[int]$After=18) {
    $lines = $Text -split "`r?`n"
    $hit = 0
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $Pattern) { $hit = $i + 1; break }
    }
    if ($hit -eq 0) {
        Write-Host ''
        Write-Host ("=== {0}: NOT FOUND ===" -f $Label) -ForegroundColor Yellow
        return
    }
    $start = [Math]::Max(1,$hit-$Before)
    $end = [Math]::Min($lines.Count,$hit+$After)
    Write-Host ''
    Write-Host ("=== {0} lines {1}-{2} / hit {3} ===" -f $Label,$start,$end,$hit) -ForegroundColor Cyan
    for ($ln=$start; $ln -le $end; $ln++) {
        $mark = if ($ln -eq $hit) { '>>' } else { '  ' }
        Write-Host ('{0} {1,5}: {2}' -f $mark,$ln,$lines[$ln-1])
    }
}

$tempBuilder = Join-Path $env:TEMP 'AOTR_8P_V18_FINAL_1_0_10_BASELINE.ps1'
Remove-Item -LiteralPath $tempBuilder -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -Uri $BuilderUrl -OutFile $tempBuilder

$builderHash = Get-Sha256File $tempBuilder
if ($builderHash -ne $ExpectedBuilderSha256) { throw "Authoritative V18 builder hash mismatch. Expected released bytes $ExpectedBuilderSha256, got $builderHash" }

$builderText = [IO.File]::ReadAllText($tempBuilder)
$csharp = Get-OuterCSharp $builderText
$gui = Get-Payload $csharp 'GuiGzipBase64'
$engine = Get-Payload $csharp 'EngineGzipBase64'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P V18 / 1.0.10 AUTHORITATIVE BASELINE AUDIT V1.1' -ForegroundColor Cyan
Write-Host ' READ ONLY / RELEASE-PINNED / POWERSHELL 7+' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Release commit                    : $ReleaseCommit"
Write-Host "Builder path                      : $BuilderRelativePath"
Write-Host "Released builder SHA256           : $builderHash" -ForegroundColor Green
Write-Host "Released Git blob SHA             : $ExpectedGitBlobSha"
Write-Host "Documented pre-promotion SHA256   : $DocumentedPrePromotionBuilderSha256" -ForegroundColor DarkYellow
Write-Host "GUI SHA256                        : $($gui.Sha256)" -ForegroundColor Green
Write-Host "ENGINE SHA256                     : $($engine.Sha256)" -ForegroundColor Green
Write-Host "GUI lines                         : $(($gui.Text -split "`r?`n").Count)"
Write-Host "ENGINE lines                      : $(($engine.Text -split "`r?`n").Count)"

$guiMarkers = [ordered]@{
    'Resolve-AotRInstall function' = 'function\s+Resolve-AotRInstall\b'
    'Get-AotRInstallFromPath function' = 'function\s+Get-AotRInstallFromPath\b'
    'Resolve call' = '\$Install\s*=\s*Resolve-AotRInstall'
    'AOTR_HOME' = '\bAOTR_HOME\b'
    'launcher_config.json' = 'launcher_config\.json'
    'schema 2 / config v2' = 'aotr-standalone-v2|"schema"\s*:\s*2|schema\s*=\s*2'
    'REPORT ERROR' = 'REPORT ERROR'
    'MESSAGES' = '\bMESSAGES\b'
    'ReportReady' = '\bReportReady\b'
    'A8P-FP marker' = 'A8P-FP-'
    'Auto-Repair text' = 'AUTO-REPAIR|Auto-Repair'
    'StatusRowsHost' = '\bStatusRowsHost\b'
    'StatusGameText' = '\bStatusGameText\b'
    'StatusCampaignText' = '\bStatusCampaignText\b'
    'StatusUiText' = '\bStatusUiText\b'
    'OverallStatusText' = '\bOverallStatusText\b'
    'Set-StatusChecking' = 'function\s+Set-StatusChecking\b'
    'Get-FileHash' = '\bGet-FileHash\b'
    'Get-Sha256 function' = 'function\s+Get-Sha256\b'
    'Synthetic A8P_TEST_FORCE_ERROR' = 'A8P_TEST_FORCE_ERROR'
    'Synthetic A8P-TEST-001' = 'A8P-TEST-001'
}

$engineMarkers = [ordered]@{
    'Resolve-AotRInstall function' = 'function\s+Resolve-AotRInstall\b'
    'Get-AotRInstallFromPath function' = 'function\s+Get-AotRInstallFromPath\b'
    'launcher_config.json' = 'launcher_config\.json'
    'AOTR_HOME' = '\bAOTR_HOME\b'
    'schema 2 / config v2' = 'aotr-standalone-v2|"schema"\s*:\s*2|schema\s*=\s*2'
    'Get-FileHash' = '\bGet-FileHash\b'
    'Get-Sha256 function' = 'function\s+Get-Sha256\b'
    'FINAL_STABLE_V7' = 'FINAL_STABLE_V7'
}

Show-MarkerTable 'GUI BASELINE MARKERS' $gui.Text $guiMarkers
Show-MarkerTable 'ENGINE BASELINE MARKERS' $engine.Text $engineMarkers
Show-Context 'GUI RESOLVER ENTRY' $gui.Text 'function\s+Resolve-AotRInstall\b' 8 90
Show-Context 'GUI INSTALL PATH VALIDATOR' $gui.Text 'function\s+Get-AotRInstallFromPath\b' 8 75
Show-Context 'GUI PREFLIGHT' $gui.Text 'function\s+Invoke-Preflight\b' 4 125
Show-Context 'GUI REPORT ERROR / DIAGNOSTICS' $gui.Text 'REPORT ERROR' 18 35
Show-Context 'GUI MESSAGES' $gui.Text '\bMESSAGES\b' 18 35
Show-Context 'ENGINE INSTALL RESOLUTION' $engine.Text 'function\s+Resolve-AotRInstall\b|launcher_config\.json' 8 90

$critical = [ordered]@{
    BuilderHashMatchesReleasedBytes = ($builderHash -eq $ExpectedBuilderSha256)
    GuiHasReportError = ((Count-Matches $gui.Text 'REPORT ERROR') -gt 0)
    GuiHasMessages = ((Count-Matches $gui.Text '\bMESSAGES\b') -gt 0)
    GuiHasDynamicStatus = ((Count-Matches $gui.Text '\bStatusRowsHost\b') -gt 0)
    GuiGetFileHashZero = ((Count-Matches $gui.Text '\bGet-FileHash\b') -eq 0)
    EngineGetFileHashZero = ((Count-Matches $engine.Text '\bGet-FileHash\b') -eq 0)
    SyntheticHookZero = ((Count-Matches $gui.Text 'A8P_TEST_FORCE_ERROR|A8P-TEST-001') -eq 0)
}

Write-Host ''
Write-Host '=== CRITICAL 1.0.10 PRESERVATION BASELINE ===' -ForegroundColor Cyan
foreach ($entry in $critical.GetEnumerator()) {
    $color = if ($entry.Value) { 'Green' } else { 'Red' }
    Write-Host ('{0,-34} {1}' -f $entry.Key,$entry.Value) -ForegroundColor $color
}

if (@($critical.Values | Where-Object { -not $_ }).Count -gt 0) { throw 'One or more authoritative 1.0.10 baseline invariants failed. Do not patch this builder.' }

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' V18 / 1.0.10 BASELINE AUDIT PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host 'No builder, EXE, manifest, config, cache, game, or release file was modified.' -ForegroundColor Green
