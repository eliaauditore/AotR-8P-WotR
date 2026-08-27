<#
.SYNOPSIS
Read-only helper for locating and auditing the authoritative AotR 8P launcher builder on the canonical Windows research machine.

.DESCRIPTION
Searches explicitly supplied local roots for V17 builder candidates, computes SHA256 hashes,
collects marker evidence, and prints relevant source lines with approximate enclosing function names.

This script performs no writes. It does not modify files, registry, game data, launcher files,
Git state, config, or temporary files.

Recommended runtime: PowerShell 7.x.
#>

[CmdletBinding()]
param(
    [string[]]$ResearchRoots = @(
        'D:\BFME_RESEARCH',
        'D:\Games\AotR'
    ),

    [string]$BuilderPattern = 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17*.ps1',

    [string]$InspectPath,

    [ValidateRange(0, 20)]
    [int]$ContextLines = 4,

    [switch]$AsJson
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'SilentlyContinue'

$KnownBuilderCheckpoints = @{
    'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_START_SIGNAL_MVP.ps1' = @{
        Length = 258905
        SHA256 = '79D31C3DCE6833781BFECF5B87230B1C463483EA4F31A89D2431238D42A17C6F'
    }
    'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_GLOBAL_LOBBY_MVP.ps1' = @{
        Length = 257283
        SHA256 = 'BAC0A4E8381919DA80B6FB98CEB258343DD481BE4F940EBDB401579ACDE99473'
    }
    'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_MULTIPLAYER_EXACT.ps1' = @{
        Length = 253487
        SHA256Prefix = '082967B350022B'
    }
}

$SearchTerms = @(
    'AOTR_HOME',
    'AgeoftheRing',
    'lotrbfme2ep1.exe',
    '_AotR8P_WotR_Runtime',
    'zGameDats',
    'game.dat',
    'repair-manifest',
    'reset_install',
    'retry_launch',
    'repair_payloads',
    'reset_runtime',
    'clear_compat_cache',
    'check_launcher_update',
    'REPORT ERROR',
    'launcher_gui',
    'source_mod',
    'aotr_root',
    'runtime',
    'config'
)

function Get-CanonicalPathReadOnly {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"')))
    }
    catch {
        return $null
    }
}

function Get-BuilderCandidates {
    param(
        [string[]]$Roots,
        [string]$Pattern
    )

    $seen = @{}
    $items = New-Object System.Collections.ArrayList

    foreach ($rawRoot in $Roots) {
        $root = Get-CanonicalPathReadOnly $rawRoot
        if (-not $root) { continue }
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }

        foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse -Filter $Pattern -ErrorAction SilentlyContinue) {
            $canonical = Get-CanonicalPathReadOnly $file.FullName
            if (-not $canonical) { continue }
            $key = $canonical.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true

            $hash = $null
            try { $hash = (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash.ToUpperInvariant() } catch { }

            $checkpoint = $null
            if ($KnownBuilderCheckpoints.ContainsKey($file.Name)) {
                $checkpoint = $KnownBuilderCheckpoints[$file.Name]
            }

            $checkpointMatch = 'NO_KNOWN_CHECKPOINT'
            if ($checkpoint) {
                $lengthMatch = ([int64]$checkpoint.Length -eq [int64]$file.Length)
                $hashMatch = $false
                $prefixMatch = $false

                if ($checkpoint.ContainsKey('SHA256') -and $hash) {
                    $hashMatch = ($hash -eq [string]$checkpoint.SHA256)
                    $checkpointMatch = if ($lengthMatch -and $hashMatch) { 'EXACT_MATCH' } else { 'MISMATCH' }
                }
                elseif ($checkpoint.ContainsKey('SHA256Prefix') -and $hash) {
                    $prefixMatch = $hash.StartsWith([string]$checkpoint.SHA256Prefix, [System.StringComparison]::OrdinalIgnoreCase)
                    $checkpointMatch = if ($lengthMatch -and $prefixMatch) { 'PREFIX_AND_LENGTH_MATCH' } else { 'MISMATCH' }
                }
            }

            [void]$items.Add([pscustomobject]@{
                Name = $file.Name
                FullName = $canonical
                Length = [int64]$file.Length
                LastWriteTime = $file.LastWriteTime
                SHA256 = $hash
                CheckpointMatch = $checkpointMatch
            })
        }
    }

    return @(
        $items | Sort-Object -Property `
            @{ Expression = 'LastWriteTime'; Descending = $true }, `
            @{ Expression = 'Name'; Descending = $false }
    )
}

function Get-FunctionRanges {
    param([string[]]$Lines)

    $functions = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match '^\s*function\s+([A-Za-z0-9_:\.-]+)\b') {
            [void]$functions.Add([pscustomobject]@{
                Name = $matches[1]
                StartLine = $i + 1
                EndLine = $Lines.Count
            })
        }
    }

    for ($i = 0; $i -lt $functions.Count - 1; $i++) {
        $functions[$i].EndLine = $functions[$i + 1].StartLine - 1
    }

    return @($functions)
}

function Get-EnclosingFunctionName {
    param(
        [int]$LineNumber,
        [object[]]$FunctionRanges
    )

    $match = $FunctionRanges |
        Where-Object { $LineNumber -ge $_.StartLine -and $LineNumber -le $_.EndLine } |
        Sort-Object StartLine -Descending |
        Select-Object -First 1

    if ($match) { return $match.Name }
    return '<GLOBAL_OR_EMBEDDED_TEXT>'
}

function Get-SourceAudit {
    param(
        [string]$Path,
        [string[]]$Terms,
        [int]$Context
    )

    $canonical = Get-CanonicalPathReadOnly $Path
    if (-not $canonical -or -not (Test-Path -LiteralPath $canonical -PathType Leaf)) {
        throw "Builder not found: $Path"
    }

    $lines = @(Get-Content -LiteralPath $canonical)
    $functionRanges = @(Get-FunctionRanges -Lines $lines)
    $hits = New-Object System.Collections.ArrayList

    foreach ($term in $Terms) {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                continue
            }

            $lineNumber = $i + 1
            $start = [Math]::Max(1, $lineNumber - $Context)
            $end = [Math]::Min($lines.Count, $lineNumber + $Context)
            $contextRows = New-Object System.Collections.ArrayList

            for ($j = $start; $j -le $end; $j++) {
                [void]$contextRows.Add(('{0,6}: {1}' -f $j, $lines[$j - 1]))
            }

            [void]$hits.Add([pscustomobject]@{
                Term = $term
                Line = $lineNumber
                EnclosingFunction = Get-EnclosingFunctionName -LineNumber $lineNumber -FunctionRanges $functionRanges
                Text = $lines[$i].Trim()
                Context = @($contextRows)
            })
        }
    }

    $actionTerms = @(
        'reset_install',
        'retry_launch',
        'repair_payloads',
        'reset_runtime',
        'stop_old_dev_launchers',
        'stop_legacy_runtime',
        'stop_failed_game',
        'check_launcher_update',
        'clear_compat_cache'
    )

    $actionEvidence = New-Object System.Collections.ArrayList
    foreach ($action in $actionTerms) {
        $matchesForAction = @($hits | Where-Object { $_.Term -ieq $action })
        [void]$actionEvidence.Add([pscustomobject]@{
            Action = $action
            Occurrences = $matchesForAction.Count
            Lines = @($matchesForAction.Line)
            Functions = @($matchesForAction.EnclosingFunction | Sort-Object -Unique)
        })
    }

    $resolverEvidence = @($hits | Where-Object {
        $_.Term -in @('AOTR_HOME', 'AgeoftheRing', 'lotrbfme2ep1.exe', '_AotR8P_WotR_Runtime', 'zGameDats', 'game.dat', 'aotr_root', 'source_mod')
    })

    $candidateFunctions = @(
        $resolverEvidence.EnclosingFunction |
            Where-Object { $_ -and $_ -ne '<GLOBAL_OR_EMBEDDED_TEXT>' } |
            Group-Object |
            Sort-Object Count -Descending |
            ForEach-Object {
                [pscustomobject]@{
                    Function = $_.Name
                    RelevantHits = $_.Count
                }
            }
    )

    [pscustomobject]@{
        Path = $canonical
        LineCount = $lines.Count
        FunctionCount = $functionRanges.Count
        FunctionRanges = @($functionRanges)
        CandidateResolverFunctions = @($candidateFunctions)
        RepairActionEvidence = @($actionEvidence)
        Hits = @($hits | Sort-Object Line, Term)
    }
}

$candidates = @(Get-BuilderCandidates -Roots $ResearchRoots -Pattern $BuilderPattern)

$selectedInspectPath = $null
if (-not [string]::IsNullOrWhiteSpace($InspectPath)) {
    $selectedInspectPath = Get-CanonicalPathReadOnly $InspectPath
}

$audit = $null
if ($selectedInspectPath) {
    $audit = Get-SourceAudit -Path $selectedInspectPath -Terms $SearchTerms -Context $ContextLines
}

$result = [pscustomobject]@{
    Tool = 'AOTR_8P_MAIN_PC_SOURCE_AUDIT_V1'
    ReadOnly = $true
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    ResearchRoots = @($ResearchRoots)
    BuilderPattern = $BuilderPattern
    Candidates = @($candidates)
    Inspection = $audit
    Safety = [pscustomobject]@{
        WritesFiles = $false
        WritesRegistry = $false
        ModifiesGame = $false
        ModifiesLauncher = $false
        ModifiesGit = $false
        CreatesTempFiles = $false
    }
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 10
    return
}

Write-Host ''
Write-Host '=== AOTR 8P MAIN-PC SOURCE AUDIT / READ ONLY ==='
Write-Host ''

if ($candidates.Count -eq 0) {
    Write-Host 'No V17 builder candidates found in supplied roots.'
}
else {
    $candidates |
        Select-Object Name, Length, LastWriteTime, CheckpointMatch, SHA256, FullName |
        Format-Table -AutoSize
}

if (-not $selectedInspectPath) {
    Write-Host ''
    Write-Host 'Discovery complete. Re-run with -InspectPath <exact builder path> to inspect source markers.'
    Write-Host 'Do not choose a builder only by newest timestamp; compare checkpoint/hash and feature lineage first.'
    return
}

Write-Host ''
Write-Host ('Inspecting: {0}' -f $selectedInspectPath)
Write-Host ''

if ($audit.CandidateResolverFunctions.Count -gt 0) {
    Write-Host '=== CANDIDATE RESOLVER FUNCTIONS ==='
    $audit.CandidateResolverFunctions | Format-Table -AutoSize
    Write-Host ''
}

Write-Host '=== REPAIR ACTION EVIDENCE ==='
$audit.RepairActionEvidence | Format-Table -AutoSize
Write-Host ''

Write-Host '=== RELEVANT SOURCE HITS ==='
foreach ($hit in $audit.Hits) {
    Write-Host ''
    Write-Host ('[{0}] line {1} / function {2}' -f $hit.Term, $hit.Line, $hit.EnclosingFunction)
    foreach ($row in $hit.Context) {
        Write-Host $row
    }
}
