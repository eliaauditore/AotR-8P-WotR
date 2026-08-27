<#
.SYNOPSIS
Read-only audit for the Base64-encoded launcher source embedded in a V17 builder.

.DESCRIPTION
Reads one builder PS1, locates the first [Convert]::FromBase64String(@' ... '@) payload,
decodes it in memory only, and reports resolver/config/repair markers plus nearby method/function context.
No files, registry keys, game data, launcher binaries, config, Git state, or temporary files are modified.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BuilderPath,

    [ValidateRange(0, 20)]
    [int]$ContextLines = 2,

    [switch]$AsJson
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

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

function Get-EnclosingDeclaration {
    param(
        [string[]]$Lines,
        [int]$LineNumber
    )

    $patterns = @(
        '^\s*function\s+([A-Za-z0-9_:\.-]+)\b',
        '^\s*(?:public|private|protected|internal)?\s*(?:static\s+)?(?:async\s+)?[A-Za-z0-9_<>,\[\]\.?]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*\)\s*(?:\{|$)',
        '^\s*(?:public|private|protected|internal)?\s*(?:static\s+)?(?:async\s+)?(?:void|bool|int|string|object|Task(?:<[^>]+>)?)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\('
    )

    for ($i = $LineNumber - 1; $i -ge 0; $i--) {
        $line = $Lines[$i]
        foreach ($pattern in $patterns) {
            if ($line -match $pattern) {
                return [pscustomobject]@{
                    Name = $matches[1]
                    DeclarationLine = $i + 1
                    DeclarationText = $line.Trim()
                }
            }
        }
    }

    return [pscustomobject]@{
        Name = '<GLOBAL_OR_UNKNOWN>'
        DeclarationLine = $null
        DeclarationText = $null
    }
}

$canonicalBuilder = Get-CanonicalPathReadOnly $BuilderPath
if (-not $canonicalBuilder -or -not (Test-Path -LiteralPath $canonicalBuilder -PathType Leaf)) {
    throw "Builder not found: $BuilderPath"
}

$builderText = [System.IO.File]::ReadAllText($canonicalBuilder)
$builderHash = (Get-FileHash -LiteralPath $canonicalBuilder -Algorithm SHA256).Hash.ToUpperInvariant()

$pattern = "FromBase64String\(@'\s*(?<payload>[A-Za-z0-9+/=\r\n]+?)\s*'@\)"
$match = [regex]::Match($builderText, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

if (-not $match.Success) {
    throw 'No Base64 here-string passed to FromBase64String was found in the builder.'
}

$payload = ($match.Groups['payload'].Value -replace '\s', '')
$decodedBytes = [Convert]::FromBase64String($payload)
$decodedText = [Text.Encoding]::UTF8.GetString($decodedBytes)
$decodedLines = @($decodedText -split "`r?`n")

$terms = @(
    'AOTR_HOME',
    'AgeoftheRing',
    'Age of the Ring',
    'lotrbfme2ep1.exe',
    'lotrbfme2ep1',
    'rotwk',
    'game.dat',
    'zGameDats',
    '_AotR8P_WotR_Runtime',
    'aotr\\',
    'AotR_Launcher.exe',
    'Changelist.txt',
    'data\\ini',
    'config',
    'registry',
    'HKCU',
    'HKLM',
    'GetLogicalDrives',
    'DriveInfo',
    'Directory.GetDirectories',
    'Directory.EnumerateDirectories',
    'repair-manifest',
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

$hits = New-Object System.Collections.ArrayList

foreach ($term in $terms) {
    for ($i = 0; $i -lt $decodedLines.Count; $i++) {
        if ($decodedLines[$i].IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            continue
        }

        $lineNumber = $i + 1
        $decl = Get-EnclosingDeclaration -Lines $decodedLines -LineNumber $lineNumber
        $start = [Math]::Max(1, $lineNumber - $ContextLines)
        $end = [Math]::Min($decodedLines.Count, $lineNumber + $ContextLines)
        $context = New-Object System.Collections.ArrayList

        for ($j = $start; $j -le $end; $j++) {
            [void]$context.Add(('{0,6}: {1}' -f $j, $decodedLines[$j - 1]))
        }

        [void]$hits.Add([pscustomobject]@{
            Term = $term
            Line = $lineNumber
            EnclosingDeclaration = $decl.Name
            DeclarationLine = $decl.DeclarationLine
            DeclarationText = $decl.DeclarationText
            Text = $decodedLines[$i].Trim()
            Context = @($context)
        })
    }
}

$markerCounts = @(
    $hits |
        Group-Object Term |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                Term = $_.Name
                Count = $_.Count
            }
        }
)

$declarationCounts = @(
    $hits |
        Where-Object { $_.EnclosingDeclaration -ne '<GLOBAL_OR_UNKNOWN>' } |
        Group-Object EnclosingDeclaration |
        Sort-Object Count -Descending |
        ForEach-Object {
            [pscustomobject]@{
                Declaration = $_.Name
                RelevantHits = $_.Count
                Terms = @($_.Group.Term | Sort-Object -Unique)
                FirstHitLine = ($_.Group.Line | Measure-Object -Minimum).Minimum
            }
        }
)

$result = [pscustomobject]@{
    Tool = 'AOTR_8P_EMBEDDED_TEMPLATE_AUDIT_V1'
    ReadOnly = $true
    BuilderPath = $canonicalBuilder
    BuilderSHA256 = $builderHash
    EmbeddedPayloadCharacters = $payload.Length
    DecodedBytes = $decodedBytes.Length
    DecodedLineCount = $decodedLines.Count
    MarkerCounts = @($markerCounts)
    CandidateDeclarations = @($declarationCounts)
    Hits = @($hits | Sort-Object Line, Term)
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
Write-Host '=== AOTR 8P EMBEDDED TEMPLATE AUDIT / READ ONLY ==='
Write-Host ('Builder : {0}' -f $canonicalBuilder)
Write-Host ('SHA256  : {0}' -f $builderHash)
Write-Host ('Decoded : {0} bytes / {1} lines' -f $decodedBytes.Length, $decodedLines.Count)
Write-Host ''

Write-Host '=== MARKER COUNTS ==='
$markerCounts | Format-Table -AutoSize
Write-Host ''

Write-Host '=== CANDIDATE DECLARATIONS ==='
$declarationCounts | Select-Object Declaration, RelevantHits, FirstHitLine, @{N='Terms';E={$_.Terms -join ', '}} | Format-Table -Wrap -AutoSize
Write-Host ''

Write-Host '=== DIRECT RESOLVER HITS ==='
$hits |
    Where-Object { $_.Term -in @('AOTR_HOME','AgeoftheRing','Age of the Ring','lotrbfme2ep1.exe','lotrbfme2ep1','rotwk','game.dat','zGameDats','_AotR8P_WotR_Runtime','AotR_Launcher.exe','Changelist.txt','data\\ini') } |
    Select-Object Term, Line, EnclosingDeclaration, Text |
    Format-Table -Wrap -AutoSize
Write-Host ''

Write-Host '=== REPAIR ACTION HITS ==='
$hits |
    Where-Object { $_.Term -in @('repair-manifest','reset_install','retry_launch','repair_payloads','reset_runtime','stop_old_dev_launchers','stop_legacy_runtime','stop_failed_game','check_launcher_update','clear_compat_cache') } |
    Select-Object Term, Line, EnclosingDeclaration, Text |
    Format-Table -Wrap -AutoSize
