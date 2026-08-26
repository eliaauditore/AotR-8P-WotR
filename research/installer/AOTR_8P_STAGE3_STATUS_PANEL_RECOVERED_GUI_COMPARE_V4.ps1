#requires -version 5.1
[CmdletBinding()]
param(
    [string]$EvidenceRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\STATUS_PANEL_EXE_RECOVERY_20260827_015504',
    [string]$CurrentBuilder = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE3_HASHFIX_V2_20260827_012753\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_HASHFIX_V2_NONRELEASE.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedCurrentBuilderSha256 = 'B244D987A99533DD3A79978032F64C261FF7EBBDDA1AAFA6BB0142FFA9BC2572'
$ExpectedCurrentGuiSha256 = 'AA8893A160CF790644FF794F4E8E47B3D1E05E1022AD22FB784A071B91920D8E'

function Get-Sha256File([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $stream.Dispose() }
    }
    finally { $sha.Dispose() }
}

function Get-Sha256Text([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Expand-GzipBase64([string]$Base64) {
    $compressed = [Convert]::FromBase64String(($Base64 -replace '\s',''))
    $input = New-Object IO.MemoryStream(,$compressed)
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

function Get-CurrentGui([string]$BuilderPath) {
    $builderText = [IO.File]::ReadAllText($BuilderPath)
    $outerPattern = '(?s)\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\s*(?<data>[A-Za-z0-9+/=\r\n]+?)\s*''@\)\)'
    $outer = [regex]::Match($builderText,$outerPattern)
    if (-not $outer.Success) { throw 'Could not locate outer C# template.' }
    $csharp = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($outer.Groups['data'].Value -replace '\s','')))
    $guiPattern = '(?s)(?:private\s+)?const\s+string\s+GuiGzipBase64\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
    $gm = [regex]::Match($csharp,$guiPattern)
    if (-not $gm.Success) { throw 'Could not locate GuiGzipBase64.' }
    return (Expand-GzipBase64 $gm.Groups['data'].Value)
}

function Get-StatusSignature([string]$Text) {
    $lines = $Text -split "`r?`n"
    $patterns = [ordered]@{
        HealthHeaderText = 'HealthHeaderText'
        HealthStatusText = 'HealthStatusText'
        StatusPanel = 'StatusPanel'
        StatusHeader = 'StatusHeader'
        StatusText = 'StatusText'
        SetHealth = 'function\s+Set-.*Health|Set-Health'
        SetStatus = 'function\s+Set-.*Status|Set-Status'
        Row1 = '\bRow1\w*\b'
        Row2 = '\bRow2\w*\b'
        Row3 = '\bRow3\w*\b'
        Ready = 'ReadyCleanPatch|READY TO LAUNCH|Ready to launch'
        Preflight = 'function\s+Invoke-Preflight'
        Game = 'game\.dat'
        Campaign = 'campaign payload|campaign'
        Roster = 'roster UI|8-player roster'
        Compatible = 'compatible|compatibility'
        Verified = 'verified|validation'
        Detected = 'detected|found'
    }
    $counts = [ordered]@{}
    foreach ($kv in $patterns.GetEnumerator()) {
        $counts[$kv.Key] = @($lines | Where-Object { $_ -match $kv.Value }).Count
    }
    return [PSCustomObject]$counts
}

function Show-FocusedContext([string]$Label,[string]$Text) {
    $lines = $Text -split "`r?`n"
    $focusPattern = '(?i)HealthHeaderText|HealthStatusText|StatusPanel|StatusHeader|StatusText|function\s+Set-.*(?:Health|Status)|Row[123]|ReadyCleanPatch|function\s+Invoke-Preflight'
    $hits = New-Object System.Collections.Generic.List[int]
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $focusPattern) { [void]$hits.Add($i+1) }
    }
    Write-Host ''
    Write-Host ("=== {0} FOCUSED STATUS CONTEXT ===" -f $Label) -ForegroundColor Cyan
    if ($hits.Count -eq 0) {
        Write-Host 'No focused status markers found.' -ForegroundColor Yellow
        return
    }
    $shown = @{}
    foreach ($ln in ($hits | Select-Object -First 24)) {
        $start = [Math]::Max(1,$ln-8)
        $end = [Math]::Min($lines.Count,$ln+16)
        $key = "$start-$end"
        if ($shown.ContainsKey($key)) { continue }
        $shown[$key] = $true
        Write-Host ''
        Write-Host ("--- lines {0}-{1} / hit {2} ---" -f $start,$end,$ln) -ForegroundColor DarkCyan
        for ($n=$start; $n -le $end; $n++) {
            $mark = if ($n -eq $ln) { '>>' } else { '  ' }
            Write-Host ('{0} {1,5}: {2}' -f $mark,$n,$lines[$n-1])
        }
    }
}

if (-not (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) { throw "Evidence root missing: $EvidenceRoot" }
if (-not (Test-Path -LiteralPath $CurrentBuilder -PathType Leaf)) { throw "Current builder missing: $CurrentBuilder" }
$currentBuilderHash = Get-Sha256File $CurrentBuilder
if ($currentBuilderHash -ne $ExpectedCurrentBuilderSha256) { throw "Current builder hash mismatch: $currentBuilderHash" }
$currentGui = Get-CurrentGui $CurrentBuilder
$currentGuiHash = Get-Sha256Text $currentGui
if ($currentGuiHash -ne $ExpectedCurrentGuiSha256) { throw "Current GUI hash mismatch: $currentGuiHash" }

$guiFiles = @(Get-ChildItem -LiteralPath $EvidenceRoot -File -Filter 'GUI_*.ps1' -ErrorAction Stop | Sort-Object Name)
if ($guiFiles.Count -ne 4) { throw "Expected exactly 4 recovered GUI files, found $($guiFiles.Count)." }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P STAGE 3 RECOVERED GUI STATUS COMPARE V4' -ForegroundColor Cyan
Write-Host ' FOUR RECOVERED V18 GUIs VS CURRENT HASHFIX GUI' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Evidence root : $EvidenceRoot"
Write-Host "Current GUI   : $currentGuiHash"
Write-Host ''

$rows = New-Object System.Collections.Generic.List[object]
$payloads = @{}
foreach ($file in $guiFiles) {
    $text = [IO.File]::ReadAllText($file.FullName)
    $sha = Get-Sha256Text $text
    $sig = Get-StatusSignature $text
    $payloads[$file.Name] = $text
    [void]$rows.Add([PSCustomObject]@{
        Name=$file.Name; GuiSha=$sha.Substring(0,12);
        HealthHeader=$sig.HealthHeaderText; HealthStatus=$sig.HealthStatusText;
        StatusPanel=$sig.StatusPanel; StatusText=$sig.StatusText;
        SetHealth=$sig.SetHealth; SetStatus=$sig.SetStatus;
        Row1=$sig.Row1; Row2=$sig.Row2; Row3=$sig.Row3;
        Ready=$sig.Ready; Preflight=$sig.Preflight
    })
}
$currentSig = Get-StatusSignature $currentGui
[void]$rows.Add([PSCustomObject]@{
    Name='CURRENT_HASHFIX_GUI'; GuiSha=$currentGuiHash.Substring(0,12);
    HealthHeader=$currentSig.HealthHeaderText; HealthStatus=$currentSig.HealthStatusText;
    StatusPanel=$currentSig.StatusPanel; StatusText=$currentSig.StatusText;
    SetHealth=$currentSig.SetHealth; SetStatus=$currentSig.SetStatus;
    Row1=$currentSig.Row1; Row2=$currentSig.Row2; Row3=$currentSig.Row3;
    Ready=$currentSig.Ready; Preflight=$currentSig.Preflight
})

Write-Host '=== STATUS SIGNATURE MATRIX ===' -ForegroundColor Cyan
$rows | Format-Table -AutoSize | Out-Host

$candidates = @($rows | Where-Object { $_.Name -ne 'CURRENT_HASHFIX_GUI' -and (($_.HealthHeader + $_.HealthStatus + $_.StatusPanel + $_.StatusText + $_.SetHealth + $_.SetStatus) -gt 0) })
Write-Host ''
Write-Host "Dynamic-status candidates: $($candidates.Count)" -ForegroundColor Yellow
$candidates | Format-Table -AutoSize | Out-Host

if ($candidates.Count -eq 0) {
    throw 'None of the four recovered GUIs contains dynamic status-panel markers.'
}

foreach ($c in $candidates) {
    Show-FocusedContext -Label $c.Name -Text ([string]$payloads[$c.Name])
}
Show-FocusedContext -Label 'CURRENT_HASHFIX_GUI' -Text $currentGui

$report = Join-Path $EvidenceRoot 'RECOVERED_GUI_STATUS_COMPARE_V4.txt'
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine('AOTR 8P STAGE 3 RECOVERED GUI STATUS COMPARE V4')
[void]$sb.AppendLine("Current GUI: $currentGuiHash")
[void]$sb.AppendLine("Recovered GUIs: $($guiFiles.Count)")
[void]$sb.AppendLine("Dynamic-status candidates: $($candidates.Count)")
foreach ($c in $candidates) { [void]$sb.AppendLine(("Candidate: {0} SHA={1}" -f $c.Name,$c.GuiSha)) }
[IO.File]::WriteAllText($report,$sb.ToString(),(New-Object Text.UTF8Encoding($false)))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' RECOVERED GUI STATUS COMPARE COMPLETE' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host "Dynamic-status candidates: $($candidates.Count)"
Write-Host "Report                   : $report"
Write-Host 'No builder, EXE, game, config, cache, or release files were modified.' -ForegroundColor Green
