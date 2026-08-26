<#
.SYNOPSIS
Read-only research prototype for robust standalone Age of the Ring discovery.

.DESCRIPTION
This script only reads filesystem/environment state and prints discovery results.
It does NOT write config, registry, launcher, game, mod, runtime, or temporary files.
It intentionally does not modify repair-manifest.json or execute repair actions.

Hard-valid standalone root:
  <root>\rotwk\lotrbfme2ep1.exe
  <root>\rotwk\game.dat OR <root>\rotwk\zGameDats\game.dat
  <root>\aotr\

The script collects all candidates, canonicalizes/deduplicates them, validates them,
scores them, rejects/deprioritizes unsafe path classes, and reports whether automatic
selection would be unambiguous.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CachedAotrRoot,

    [Parameter(Mandatory = $false)]
    [string]$LauncherPath,

    [ValidateRange(1, 8)]
    [int]$SearchDepth = 4,

    [ValidateRange(100, 50000)]
    [int]$MaxDirectoriesPerDrive = 8000,

    [switch]$AsJson
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($LauncherPath)) {
    try { $LauncherPath = $MyInvocation.MyCommand.Path } catch { $LauncherPath = $null }
}

$script:CandidateMap = @{}

function Get-CanonicalPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
        $full = [System.IO.Path]::GetFullPath($expanded)
        $root = [System.IO.Path]::GetPathRoot($full)
        if ($full -ne $root) {
            $full = $full.TrimEnd('\', '/')
        }
        return $full
    }
    catch {
        return $null
    }
}

function Resolve-CandidateRoot {
    param([string]$Path)

    $canonical = Get-CanonicalPath $Path
    if (-not $canonical) { return $null }

    try {
        $leaf = Split-Path -Leaf $canonical
        if ($leaf -match '^(?i:rotwk|aotr)$') {
            return (Get-CanonicalPath (Split-Path -Parent $canonical))
        }

        if ((Test-Path -LiteralPath (Join-Path $canonical 'rotwk') -PathType Container) -or
            (Test-Path -LiteralPath (Join-Path $canonical 'aotr') -PathType Container)) {
            return $canonical
        }

        $nested = Join-Path $canonical 'AgeoftheRing'
        if (Test-Path -LiteralPath $nested -PathType Container) {
            return (Get-CanonicalPath $nested)
        }
    }
    catch { }

    return $canonical
}

function Add-Candidate {
    param(
        [string]$Path,
        [string]$Source,
        [string]$DriveClass = 'Unknown'
    )

    $root = Resolve-CandidateRoot $Path
    if (-not $root) { return }

    $key = $root.ToLowerInvariant()
    if (-not $script:CandidateMap.ContainsKey($key)) {
        $script:CandidateMap[$key] = [ordered]@{
            Root        = $root
            Sources     = New-Object System.Collections.ArrayList
            DriveClass  = $DriveClass
        }
    }

    if (-not $script:CandidateMap[$key].Sources.Contains($Source)) {
        [void]$script:CandidateMap[$key].Sources.Add($Source)
    }

    if ($script:CandidateMap[$key].DriveClass -eq 'Unknown' -and $DriveClass -ne 'Unknown') {
        $script:CandidateMap[$key].DriveClass = $DriveClass
    }
}

function Get-PathClassification {
    param([string]$Root)

    $flags = New-Object System.Collections.ArrayList
    $penalty = 0
    $hardReject = $false
    $autoEligible = $true

    $segmentPatterns = @(
        @{ Name = 'Runtime';     Pattern = '(?i)(^|[\\/])_AotR8P_WotR_Runtime([\\/]|$)'; Penalty = -1000; HardReject = $true;  AutoEligible = $false },
        @{ Name = 'AllInOne';    Pattern = '(?i)(^|[\\/])[^\\/]*all[ _-]*in[ _-]*one[^\\/]*([\\/]|$)'; Penalty = -1000; HardReject = $true; AutoEligible = $false },
        @{ Name = 'Research';    Pattern = '(?i)(^|[\\/])BFME_RESEARCH([\\/]|$)'; Penalty = -80; HardReject = $false; AutoEligible = $false },
        @{ Name = 'Backup';      Pattern = '(?i)(^|[\\/])[^\\/]*backup[^\\/]*([\\/]|$)'; Penalty = -60; HardReject = $false; AutoEligible = $false },
        @{ Name = 'Checkpoint';  Pattern = '(?i)(^|[\\/])[^\\/]*checkpoint[^\\/]*([\\/]|$)'; Penalty = -50; HardReject = $false; AutoEligible = $false },
        @{ Name = 'Temp';        Pattern = '(?i)(^|[\\/])(temp|tmp)([\\/]|$)'; Penalty = -40; HardReject = $false; AutoEligible = $false }
    )

    foreach ($rule in $segmentPatterns) {
        if ($Root -match $rule.Pattern) {
            [void]$flags.Add($rule.Name)
            $penalty += [int]$rule.Penalty
            if ($rule.HardReject) { $hardReject = $true }
            if (-not $rule.AutoEligible) { $autoEligible = $false }
        }
    }

    [pscustomobject]@{
        Flags        = @($flags)
        Penalty      = $penalty
        HardReject   = $hardReject
        AutoEligible = $autoEligible
    }
}

function Test-AotrStandaloneRoot {
    param(
        [string]$Root,
        [string[]]$Sources,
        [string]$DriveClass
    )

    $rotwk = Join-Path $Root 'rotwk'
    $aotr = Join-Path $Root 'aotr'
    $exe = Join-Path $rotwk 'lotrbfme2ep1.exe'
    $gameDatPrimary = Join-Path $rotwk 'game.dat'
    $gameDatZG = Join-Path $rotwk 'zGameDats\game.dat'
    $launcher = Join-Path $Root 'AotR_Launcher.exe'
    $ini = Join-Path $aotr 'data\ini'
    $changelist = Join-Path $aotr 'Changelist.txt'

    $hasExe = Test-Path -LiteralPath $exe -PathType Leaf
    $hasGameDatPrimary = Test-Path -LiteralPath $gameDatPrimary -PathType Leaf
    $hasGameDatZG = Test-Path -LiteralPath $gameDatZG -PathType Leaf
    $hasGameDat = $hasGameDatPrimary -or $hasGameDatZG
    $hasAotr = Test-Path -LiteralPath $aotr -PathType Container
    $hasLauncher = Test-Path -LiteralPath $launcher -PathType Leaf
    $hasIni = Test-Path -LiteralPath $ini -PathType Container
    $hasChangelist = Test-Path -LiteralPath $changelist -PathType Leaf

    $score = 0
    if ($hasExe) { $score += 40 }
    if ($hasGameDat) { $score += 30 }
    if ($hasAotr) { $score += 25 }
    if ($hasLauncher) { $score += 10 }
    if ($hasIni) { $score += 10 }
    if ($hasChangelist) { $score += 5 }

    $classification = Get-PathClassification $Root
    $score += $classification.Penalty

    $hardValid = $hasExe -and $hasGameDat -and $hasAotr
    $autoEligible = $hardValid -and (-not $classification.HardReject) -and $classification.AutoEligible

    $missing = New-Object System.Collections.ArrayList
    if (-not $hasExe) { [void]$missing.Add('rotwk\lotrbfme2ep1.exe') }
    if (-not $hasGameDat) { [void]$missing.Add('rotwk\game.dat OR rotwk\zGameDats\game.dat') }
    if (-not $hasAotr) { [void]$missing.Add('aotr\') }

    $selectedGameDat = $null
    if ($hasGameDatPrimary) { $selectedGameDat = $gameDatPrimary }
    elseif ($hasGameDatZG) { $selectedGameDat = $gameDatZG }

    $changelistPreview = $null
    if ($hasChangelist) {
        try {
            $changelistPreview = ((Get-Content -LiteralPath $changelist -TotalCount 5) -join ' | ')
        }
        catch { }
    }

    [pscustomobject]@{
        Root                   = $Root
        Sources                = @($Sources)
        DriveClass             = $DriveClass
        HardValid              = [bool]$hardValid
        AutoEligible           = [bool]$autoEligible
        Score                  = [int]$score
        PathFlags              = @($classification.Flags)
        PathPenalty            = [int]$classification.Penalty
        HardRejectedPath       = [bool]$classification.HardReject
        MissingRequired        = @($missing)
        HasLotrBfme2Ep1Exe     = [bool]$hasExe
        HasGameDatPrimary      = [bool]$hasGameDatPrimary
        HasGameDatZGameDats    = [bool]$hasGameDatZG
        HasAotrDirectory       = [bool]$hasAotr
        HasAotrLauncher        = [bool]$hasLauncher
        HasAotrIni             = [bool]$hasIni
        HasChangelist          = [bool]$hasChangelist
        ChangelistPreview      = $changelistPreview
        Runtime                = $rotwk
        SourceMod              = $aotr
        GameDat                = $selectedGameDat
        Writeability           = 'NOT_TESTED_READ_ONLY_PROTOTYPE'
    }
}

function Get-LocalDrivesByClass {
    $items = New-Object System.Collections.ArrayList

    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        try {
            if (-not $drive.IsReady) { continue }

            $class = switch ($drive.DriveType) {
                ([System.IO.DriveType]::Fixed)     { 'Fixed'; break }
                ([System.IO.DriveType]::Removable) { 'Removable'; break }
                default { $null }
            }

            if (-not $class) { continue }

            [void]$items.Add([pscustomobject]@{
                Root       = $drive.RootDirectory.FullName
                DriveClass = $class
                Format     = $drive.DriveFormat
                Label      = $drive.VolumeLabel
            })
        }
        catch { }
    }

    return @($items | Sort-Object @{ Expression = { if ($_.DriveClass -eq 'Fixed') { 0 } else { 1 } } }, Root)
}

function Add-KnownDriveCandidates {
    param([object[]]$Drives)

    $relativePaths = @(
        'AgeoftheRing',
        'Games\AotR\AgeoftheRing',
        'Games\AgeoftheRing',
        'AotR\AgeoftheRing',
        'Program Files\AgeoftheRing',
        'Program Files (x86)\AgeoftheRing'
    )

    foreach ($drive in $Drives) {
        foreach ($relative in $relativePaths) {
            $candidate = Join-Path $drive.Root $relative
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                Add-Candidate -Path $candidate -Source ("KnownPath:{0}" -f $relative) -DriveClass $drive.DriveClass
            }
        }
    }
}

function Find-AgeOfTheRingDirectories {
    param(
        [string]$StartRoot,
        [string]$DriveClass,
        [int]$MaxDepth,
        [int]$MaxDirectories
    )

    $queue = New-Object System.Collections.Queue
    $queue.Enqueue([pscustomobject]@{ Path = $StartRoot; Depth = 0 })
    $visited = 0

    $skipNames = @('$Recycle.Bin', 'System Volume Information', 'Windows', 'Recovery')

    while ($queue.Count -gt 0 -and $visited -lt $MaxDirectories) {
        $node = $queue.Dequeue()
        if ($node.Depth -ge $MaxDepth) { continue }

        $children = @()
        try {
            $children = [System.IO.Directory]::EnumerateDirectories($node.Path)
        }
        catch {
            continue
        }

        foreach ($child in $children) {
            $visited++
            if ($visited -ge $MaxDirectories) { break }

            $name = Split-Path -Leaf $child
            if ($skipNames -contains $name) { continue }

            if ($name -ieq 'AgeoftheRing') {
                Add-Candidate -Path $child -Source ("BoundedSearch:{0}" -f $StartRoot) -DriveClass $DriveClass
                continue
            }

            $classification = Get-PathClassification $child
            if ($classification.HardReject) {
                continue
            }

            $queue.Enqueue([pscustomobject]@{
                Path = $child
                Depth = $node.Depth + 1
            })
        }
    }

    [pscustomobject]@{
        StartRoot = $StartRoot
        DriveClass = $DriveClass
        VisitedDirectories = $visited
        Limit = $MaxDirectories
        MaxDepth = $MaxDepth
    }
}

# 1. Cached canonical root, if supplied.
$cachedState = 'NOT_PROVIDED'
if (-not [string]::IsNullOrWhiteSpace($CachedAotrRoot)) {
    Add-Candidate -Path $CachedAotrRoot -Source 'CachedConfig' -DriveClass 'Unknown'
    $cachedRoot = Resolve-CandidateRoot $CachedAotrRoot
    if ($cachedRoot) {
        $cachedTest = Test-AotrStandaloneRoot -Root $cachedRoot -Sources @('CachedConfig') -DriveClass 'Unknown'
        if ($cachedTest.HardValid -and -not $cachedTest.HardRejectedPath) {
            $cachedState = 'VALID'
        }
        else {
            $cachedState = 'INVALID_OR_MOVED'
        }
    }
    else {
        $cachedState = 'INVALID_OR_MOVED'
    }
}

# 2. Explicit environment override.
if (-not [string]::IsNullOrWhiteSpace($env:AOTR_HOME)) {
    Add-Candidate -Path $env:AOTR_HOME -Source 'AOTR_HOME' -DriveClass 'Unknown'
}

# 3. Launcher/install environment. Do not assume launcher location is the install root.
if (-not [string]::IsNullOrWhiteSpace($LauncherPath)) {
    try {
        $launcherCanonical = Get-CanonicalPath $LauncherPath
        $launcherDir = if (Test-Path -LiteralPath $launcherCanonical -PathType Leaf) {
            Split-Path -Parent $launcherCanonical
        }
        else {
            $launcherCanonical
        }

        if ($launcherDir) {
            Add-Candidate -Path $launcherDir -Source 'LauncherDirectory' -DriveClass 'Unknown'
            $parent = Split-Path -Parent $launcherDir
            if ($parent) { Add-Candidate -Path $parent -Source 'LauncherParent' -DriveClass 'Unknown' }
            $grandParent = if ($parent) { Split-Path -Parent $parent } else { $null }
            if ($grandParent) { Add-Candidate -Path $grandParent -Source 'LauncherGrandParent' -DriveClass 'Unknown' }
        }
    }
    catch { }
}

# 4. Fixed drives first, then Removable. Network drives are deliberately absent.
$drives = Get-LocalDrivesByClass
$fixedDrives = @($drives | Where-Object { $_.DriveClass -eq 'Fixed' })
$removableDrives = @($drives | Where-Object { $_.DriveClass -eq 'Removable' })

Add-KnownDriveCandidates -Drives $fixedDrives

$searchStats = New-Object System.Collections.ArrayList
foreach ($drive in $fixedDrives) {
    [void]$searchStats.Add((Find-AgeOfTheRingDirectories -StartRoot $drive.Root -DriveClass $drive.DriveClass -MaxDepth $SearchDepth -MaxDirectories $MaxDirectoriesPerDrive))
}

# 5. Removable / USB / exFAT only after Fixed-drive discovery.
Add-KnownDriveCandidates -Drives $removableDrives
foreach ($drive in $removableDrives) {
    [void]$searchStats.Add((Find-AgeOfTheRingDirectories -StartRoot $drive.Root -DriveClass $drive.DriveClass -MaxDepth $SearchDepth -MaxDirectories $MaxDirectoriesPerDrive))
}

# Validate every deduplicated candidate.
$results = New-Object System.Collections.ArrayList
foreach ($entry in $script:CandidateMap.Values) {
    [void]$results.Add((Test-AotrStandaloneRoot -Root $entry.Root -Sources @($entry.Sources) -DriveClass $entry.DriveClass))
}

$ranked = @($results | Sort-Object @{ Expression = 'HardValid'; Descending = $true }, @{ Expression = 'AutoEligible'; Descending = $true }, @{ Expression = 'Score'; Descending = $true }, Root)
$eligible = @($ranked | Where-Object { $_.AutoEligible })
$validButDeprioritized = @($ranked | Where-Object { $_.HardValid -and -not $_.AutoEligible })

$status = 'NOT_FOUND'
$errorCode = 'A8P-INSTALL-001'
$selected = $null
$ambiguity = @()

if ($eligible.Count -gt 0) {
    $topScore = ($eligible | Measure-Object -Property Score -Maximum).Maximum
    $top = @($eligible | Where-Object { $_.Score -eq $topScore })

    if ($top.Count -eq 1) {
        $status = 'AUTO_SELECTED'
        $errorCode = $null
        $selected = $top[0]
    }
    else {
        $status = 'MULTIPLE_VALID_INSTALLATIONS'
        $errorCode = 'A8P-INSTALL-002'
        $ambiguity = $top
    }
}
elseif ($validButDeprioritized.Count -gt 0) {
    $status = 'VALID_ONLY_IN_DEPRIORITIZED_PATHS'
    $errorCode = 'A8P-INSTALL-001'
}

$suggestedConfig = $null
if ($selected) {
    $suggestedConfig = [ordered]@{
        schema = 2
        aotr_root = $selected.Root
        runtime = $selected.Runtime
        source_mod = $selected.SourceMod
        game_dat = $selected.GameDat
        validation = 'aotr-standalone-v2'
        score = $selected.Score
        last_verified_utc = ''
    }
}

$output = [pscustomobject]@{
    Prototype = 'AOTR_8P_ROBUST_AUTODETECT_PROTOTYPE_V1'
    ReadOnly = $true
    Status = $status
    ErrorCode = $errorCode
    CachedPathState = $cachedState
    Selected = $selected
    AmbiguityCandidates = @($ambiguity)
    SuggestedConfigV2 = $suggestedConfig
    Candidates = @($ranked)
    SearchStats = @($searchStats)
    Safety = [pscustomobject]@{
        NetworkRecursiveScan = $false
        WritesFiles = $false
        WritesRegistry = $false
        ModifiesLauncher = $false
        ModifiesGame = $false
        ExecutesRepairActions = $false
        WriteabilityTest = 'NOT_PERFORMED'
    }
}

if ($AsJson) {
    $output | ConvertTo-Json -Depth 8
}
else {
    $output
}
