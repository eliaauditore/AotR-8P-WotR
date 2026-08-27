#requires -version 5.1
[CmdletBinding()]
param(
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE3_HASHFIX_V2_20260827_012753\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_HASHFIX_V2_NONRELEASE.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = 'B244D987A99533DD3A79978032F64C261FF7EBBDDA1AAFA6BB0142FFA9BC2572'
$ExpectedGuiSha256 = 'AA8893A160CF790644FF794F4E8E47B3D1E05E1022AD22FB784A071B91920D8E'

function Get-Sha256File([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','')
        }
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
            try {
                $gzip.CopyTo($output)
                return $output.ToArray()
            }
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

function Get-GuiPayload([string]$CSharp) {
    $pattern = '(?s)(?:private\s+)?const\s+string\s+GuiGzipBase64\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
    $m = [regex]::Match($CSharp,$pattern)
    if (-not $m.Success) { throw 'Could not locate GuiGzipBase64.' }
    return Expand-GzipBase64Bytes $m.Groups['data'].Value
}

function Show-Context {
    param(
        [string[]]$Lines,
        [int]$HitLine,
        [int]$Before = 16,
        [int]$After = 24,
        [string]$Label = ''
    )
    $start = [Math]::Max(1,$HitLine-$Before)
    $end = [Math]::Min($Lines.Count,$HitLine+$After)
    Write-Host ''
    Write-Host ("=== {0} lines {1}-{2} / hit {3} ===" -f $Label,$start,$end,$HitLine) -ForegroundColor Cyan
    for ($ln=$start; $ln -le $end; $ln++) {
        $marker = if ($ln -eq $HitLine) { '>>' } else { '  ' }
        Write-Host ('{0} {1,5}: {2}' -f $marker,$ln,$Lines[$ln-1])
    }
}

if (-not (Test-Path -LiteralPath $BuilderPath -PathType Leaf)) { throw "Builder missing: $BuilderPath" }
$builderHash = Get-Sha256File $BuilderPath
if ($builderHash -ne $ExpectedBuilderSha256) { throw "Builder hash mismatch. Expected $ExpectedBuilderSha256, got $builderHash" }

$builderText = [IO.File]::ReadAllText($BuilderPath)
$csharp = Get-OuterCSharp $builderText
$guiBytes = Get-GuiPayload $csharp
$guiHash = Get-Sha256Bytes $guiBytes
if ($guiHash -ne $ExpectedGuiSha256) { throw "GUI payload hash mismatch. Expected $ExpectedGuiSha256, got $guiHash" }
$gui = [Text.Encoding]::UTF8.GetString($guiBytes)
$lines = $gui -split "`r?`n"

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P STAGE 3 STATUS PANEL SOURCE AUDIT V1' -ForegroundColor Cyan
Write-Host ' XAML + PREFLIGHT VISIBILITY / READ ONLY' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Builder     : $BuilderPath"
Write-Host "Builder SHA : $builderHash" -ForegroundColor Green
Write-Host "GUI SHA     : $guiHash" -ForegroundColor Green
Write-Host "GUI lines   : $($lines.Count)"

$patterns = [ordered]@{
    'Invoke-Preflight' = 'function\s+Invoke-Preflight'
    'Row1Fail' = '\bRow1Fail\b'
    'Row1FailText' = '\bRow1FailText\b'
    'Row2Fail' = '\bRow2Fail\b'
    'Row2FailText' = '\bRow2FailText\b'
    'Row3Fail' = '\bRow3Fail\b'
    'Row3FailText' = '\bRow3FailText\b'
    'ReadyCleanPatch' = '\bReadyCleanPatch\b'
    'LaunchStateText' = 'LAUNCH \+ COMPAT CHECK|LAUNCH AOTR 8P WOTR'
    'PositiveWords' = '(?i)ready|installed|detected|verified|compatible|found|ok|pass'
    'PreflightWords' = '(?i)preflight|status|check'
}

$hits = New-Object System.Collections.Generic.List[object]
for ($i=0; $i -lt $lines.Count; $i++) {
    foreach ($entry in $patterns.GetEnumerator()) {
        if ($lines[$i] -match $entry.Value) {
            [void]$hits.Add([PSCustomObject]@{Line=$i+1; Kind=$entry.Key; Text=$lines[$i]})
        }
    }
}

Write-Host ''
Write-Host '=== KEY HITS ===' -ForegroundColor Cyan
$hits | Where-Object { $_.Kind -ne 'PositiveWords' -and $_.Kind -ne 'PreflightWords' } | Sort-Object Line,Kind | Format-Table -AutoSize | Out-Host

Write-Host ''
Write-Host '=== XAML CONTROL DECLARATIONS FOR STATUS ROWS ===' -ForegroundColor Cyan
$controlNames = @('Row1Fail','Row1FailText','Row2Fail','Row2FailText','Row3Fail','Row3FailText','ReadyCleanPatch')
foreach ($name in $controlNames) {
    $decl = @()
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('x:Name\s*=\s*["'']' + [regex]::Escape($name) + '["'']')) {
            $decl += ($i+1)
        }
    }
    if ($decl.Count -eq 0) {
        Write-Host ("$name : NO XAML DECLARATION FOUND") -ForegroundColor Yellow
    } else {
        Write-Host ("$name : XAML line(s) " + ($decl -join ',')) -ForegroundColor Green
        foreach ($ln in $decl) { Show-Context -Lines $lines -HitLine $ln -Before 8 -After 12 -Label ("XAML $name") }
    }
}

$invoke = @($hits | Where-Object Kind -eq 'Invoke-Preflight' | Select-Object -ExpandProperty Line)
if ($invoke.Count -gt 0) {
    Show-Context -Lines $lines -HitLine $invoke[0] -Before 4 -After 145 -Label 'Invoke-Preflight'
}

Write-Host ''
Write-Host '=== ALL RUNTIME VISIBILITY WRITES TO STATUS CONTROLS ===' -ForegroundColor Cyan
for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '\$(Row[123]Fail|ReadyCleanPatch)\.Visibility\s*=') {
        Write-Host ('{0,5}: {1}' -f ($i+1),$lines[$i])
    }
}

Write-Host ''
Write-Host '=== TEXT WRITES TO STATUS CONTROLS ===' -ForegroundColor Cyan
for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '\$(Row[123]FailText)\.Text\s*=') {
        Write-Host ('{0,5}: {1}' -f ($i+1),$lines[$i])
    }
}

Write-Host ''
Write-Host '=== POSSIBLE POSITIVE/READY STATUS TEXT NEAR XAML ===' -ForegroundColor Cyan
$positiveHits = @($hits | Where-Object Kind -eq 'PositiveWords')
foreach ($h in ($positiveHits | Select-Object -First 80)) {
    if ($h.Line -lt 1150) { Write-Host ('{0,5}: {1}' -f $h.Line,$h.Text) }
}

Write-Host ''
Write-Host 'Interpretation target:' -ForegroundColor Yellow
Write-Host '  - If Row1/2/3 exist only as FAIL overlays and PASS sets them Collapsed,' -ForegroundColor Yellow
Write-Host '    the empty middle panel is by design of the old fail-only UI, not a rendering failure.' -ForegroundColor Yellow
Write-Host '  - If positive/ready controls exist but are never made Visible, that is the concrete UI logic bug.' -ForegroundColor Yellow
Write-Host '  - If ReadyCleanPatch is the positive panel but is explicitly Collapsed on allOk, that is the likely fix target.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Audit complete. No builder, EXE, config, game, or release files were modified.' -ForegroundColor Green
