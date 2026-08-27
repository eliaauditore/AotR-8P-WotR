#requires -version 5.1
[CmdletBinding()]
param(
    [string]$EvidenceRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\STATUS_PANEL_EXE_RECOVERY_20260827_015504'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-Sha256File([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $stream.Dispose() }
    }
    finally { $sha.Dispose() }
}

function Get-Matches([string]$Text,[string]$Pattern) {
    return @([regex]::Matches($Text,$Pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase))
}

function Get-UniqueNames([string]$Text,[string]$Pattern,[string]$Group) {
    $values = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($Text,$Pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $v = [string]$m.Groups[$Group].Value
        if (-not [string]::IsNullOrWhiteSpace($v) -and -not $values.Contains($v)) { [void]$values.Add($v) }
    }
    return @($values)
}

function Show-Context([string[]]$Lines,[int]$HitLine,[int]$Before=10,[int]$After=18,[string]$Label='') {
    if ($HitLine -lt 1) { return }
    $start = [Math]::Max(1,$HitLine-$Before)
    $end = [Math]::Min($Lines.Count,$HitLine+$After)
    Write-Host ''
    Write-Host ("=== {0} lines {1}-{2} / hit {3} ===" -f $Label,$start,$end,$HitLine) -ForegroundColor Cyan
    for ($ln=$start; $ln -le $end; $ln++) {
        $mark = if ($ln -eq $HitLine) { '>>' } else { '  ' }
        Write-Host ('{0} {1,5}: {2}' -f $mark,$ln,$Lines[$ln-1])
    }
}

if (-not (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) { throw "Evidence root missing: $EvidenceRoot" }
$files = @(Get-ChildItem -LiteralPath $EvidenceRoot -File -Filter 'GUI_*.ps1' | Sort-Object Name)
if ($files.Count -ne 4) { throw "Expected exactly 4 recovered GUI files, found $($files.Count). Refusing ambiguous donor selection." }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P STAGE 3 STATUS PANEL DONOR SELECTOR V5' -ForegroundColor Cyan
Write-Host ' STRUCTURAL COMPARISON / READ ONLY' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Evidence root: $EvidenceRoot"
Write-Host "Recovered GUIs: $($files.Count)"

$rows = New-Object System.Collections.Generic.List[object]
$details = @{}
foreach ($file in $files) {
    $text = [IO.File]::ReadAllText($file.FullName)
    $lines = $text -split "`r?`n"
    $controls = Get-UniqueNames $text 'x:Name\s*=\s*["''](?<name>[^"'']*(?:Health|Status)[^"'']*)["'']' 'name'
    $functions = Get-UniqueNames $text 'function\s+(?<name>[A-Za-z0-9_-]*(?:Health|Status)[A-Za-z0-9_-]*)\s*\{' 'name'
    $setFunctions = Get-UniqueNames $text 'function\s+(?<name>Set-[A-Za-z0-9_-]+)\s*\{' 'name'
    $statusSetFunctions = @($setFunctions | Where-Object { $_ -match '(?i)health|status|preflight|ready' })
    $versions = Get-UniqueNames $text '(?<name>1\.0\.[0-9]+(?:-[A-Za-z0-9._-]+)?)' 'name'

    $healthHeader = (Get-Matches $text '\bHealthHeaderText\b').Count
    $healthStatus = (Get-Matches $text '\bHealthStatusText\b').Count
    $statusPanel = (Get-Matches $text '\bStatusPanel\b').Count
    $statusText = (Get-Matches $text '\bStatusText\b').Count
    $invoke = (Get-Matches $text 'function\s+Invoke-Preflight').Count
    $rowFail = (Get-Matches $text '\bRow[123]Fail\b').Count
    $readyPatch = (Get-Matches $text '\bReadyCleanPatch\b').Count
    $successWords = (Get-Matches $text 'READY TO LAUNCH|READY|VERIFIED|FOUND|OK|PASS|COMPATIBLE').Count

    # Evidence score only: rewards explicit dynamic controls/functions + preflight integration.
    $score = ($controls.Count * 10) + ($functions.Count * 15) + ($statusSetFunctions.Count * 10) + ($invoke * 8)
    if ($healthHeader -gt 0) { $score += 8 }
    if ($healthStatus -gt 0) { $score += 8 }
    if ($statusPanel -gt 0) { $score += 8 }
    if ($statusText -gt 0) { $score += 5 }

    $row = [PSCustomObject]@{
        File = $file.Name
        SHA256 = Get-Sha256File $file.FullName
        Lines = $lines.Count
        VersionMarkers = ($versions -join ',')
        DynamicControls = $controls.Count
        DynamicFunctions = $functions.Count
        StatusSetFunctions = $statusSetFunctions.Count
        InvokePreflight = $invoke
        RowFailRefs = $rowFail
        ReadyPatchRefs = $readyPatch
        SuccessWords = $successWords
        EvidenceScore = $score
    }
    [void]$rows.Add($row)
    $details[$file.Name] = [PSCustomObject]@{ Text=$text; Lines=$lines; Controls=$controls; Functions=$functions; StatusSetFunctions=$statusSetFunctions; Versions=$versions }
}

Write-Host ''
Write-Host '=== DONOR SIGNATURE MATRIX ===' -ForegroundColor Cyan
$rows | Sort-Object EvidenceScore -Descending,File | Format-Table File,Lines,VersionMarkers,DynamicControls,DynamicFunctions,StatusSetFunctions,InvokePreflight,RowFailRefs,ReadyPatchRefs,SuccessWords,EvidenceScore -AutoSize | Out-Host

Write-Host ''
Write-Host '=== EXACT DYNAMIC CONTROL / FUNCTION SETS ===' -ForegroundColor Cyan
foreach ($row in ($rows | Sort-Object File)) {
    $d = $details[$row.File]
    Write-Host ''
    Write-Host ("[{0}]" -f $row.File) -ForegroundColor Yellow
    Write-Host ("SHA256          : " + $row.SHA256)
    Write-Host ("Version markers : " + $(if ($d.Versions.Count) { $d.Versions -join ', ' } else { '<none>' }))
    Write-Host ("Controls        : " + $(if ($d.Controls.Count) { $d.Controls -join ', ' } else { '<none>' }))
    Write-Host ("Functions       : " + $(if ($d.Functions.Count) { $d.Functions -join ', ' } else { '<none>' }))
    Write-Host ("Status setters  : " + $(if ($d.StatusSetFunctions.Count) { $d.StatusSetFunctions -join ', ' } else { '<none>' }))
}

$ordered = @($rows | Sort-Object EvidenceScore -Descending,Lines -Descending,File)
$topScore = $ordered[0].EvidenceScore
$top = @($ordered | Where-Object EvidenceScore -eq $topScore)

Write-Host ''
Write-Host '=== DONOR DECISION ===' -ForegroundColor Cyan
if ($top.Count -eq 1) {
    $donor = $top[0]
    Write-Host 'Unique structural donor candidate: YES' -ForegroundColor Green
    Write-Host "Donor file : $($donor.File)" -ForegroundColor Green
    Write-Host "Donor SHA  : $($donor.SHA256)" -ForegroundColor Green
    Write-Host "Score      : $($donor.EvidenceScore)"

    $d = $details[$donor.File]
    $lines = $d.Lines
    $firstControl = 0
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'x:Name\s*=\s*["''][^"'']*(?:Health|Status)[^"'']*["'']') { $firstControl=$i+1; break }
    }
    $firstFunction = 0
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'function\s+[A-Za-z0-9_-]*(?:Health|Status)[A-Za-z0-9_-]*\s*\{') { $firstFunction=$i+1; break }
    }
    $preflight = 0
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'function\s+Invoke-Preflight') { $preflight=$i+1; break }
    }
    Show-Context $lines $firstControl 14 50 'DONOR XAML / FIRST DYNAMIC STATUS CONTROL'
    Show-Context $lines $firstFunction 10 55 'DONOR DYNAMIC STATUS FUNCTION'
    Show-Context $lines $preflight 5 130 'DONOR PREFLIGHT INTEGRATION'
} else {
    Write-Host 'Unique structural donor candidate: NO' -ForegroundColor Yellow
    Write-Host "Top-score tie count: $($top.Count)" -ForegroundColor Yellow
    $top | Format-Table File,SHA256,Lines,VersionMarkers,EvidenceScore -AutoSize | Out-Host
    Write-Host 'No donor is auto-selected on a tie.' -ForegroundColor Yellow
}

$report = Join-Path $EvidenceRoot 'STATUS_PANEL_DONOR_SELECTOR_V5.txt'
$summary = @()
$summary += 'AOTR 8P STATUS PANEL DONOR SELECTOR V5'
$summary += ('Generated: ' + [DateTime]::UtcNow.ToString('o'))
$summary += ''
$summary += ($rows | Sort-Object EvidenceScore -Descending,File | Format-Table File,SHA256,Lines,VersionMarkers,DynamicControls,DynamicFunctions,StatusSetFunctions,InvokePreflight,RowFailRefs,ReadyPatchRefs,SuccessWords,EvidenceScore -AutoSize | Out-String)
if ($top.Count -eq 1) {
    $summary += ('UNIQUE_DONOR=' + $top[0].File)
    $summary += ('UNIQUE_DONOR_SHA256=' + $top[0].SHA256)
} else {
    $summary += 'UNIQUE_DONOR=NONE_TIE'
    $summary += ('TOP_TIE_COUNT=' + $top.Count)
}
[IO.File]::WriteAllText($report,($summary -join [Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' DONOR SELECTOR COMPLETE' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host "Report: $report"
Write-Host 'No builder, EXE, game, config, cache, or release files were modified.' -ForegroundColor Green
