#requires -version 5.1
[CmdletBinding()]
param(
    [string]$ResearchRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedLauncherSha256 = '97A8163CA72BDFB5C6C24931E06B2BFCE1D0E33C382FEA2462F73BC80BD3EA9F'
$ExpectedUiSha256 = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha256 = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'

$Required = [ordered]@{
    Launcher = 'AotR 8P WotR Mod.exe'
    Icon     = 'assets\launcher.ico'
    Skin     = 'internal\assets\launcher_skin.png'
    UI       = 'payload\!!!WOTR_8P_UI_TEST.big'
    Paper    = 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc'
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-FileRow([string]$Path,[string]$ExpectedHash = '') {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [PSCustomObject]@{ Exists=$false; Path=$Path; SHA256=''; HashMatch=$false }
    }
    $hash = Get-Sha256 $Path
    return [PSCustomObject]@{
        Exists = $true
        Path = $Path
        SHA256 = $hash
        HashMatch = if ([string]::IsNullOrWhiteSpace($ExpectedHash)) { $true } else { $hash -eq $ExpectedHash }
    }
}

if (-not (Test-Path -LiteralPath $ResearchRoot -PathType Container)) {
    throw "Research root missing: $ResearchRoot"
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P STAGE 2 RC4 INPUT AUDIT' -ForegroundColor Cyan
Write-Host ' READ ONLY / NO BUILD / NO COPIES' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Research root: $ResearchRoot"
Write-Host ''

$launcherFiles = @(Get-ChildItem -LiteralPath $ResearchRoot -Recurse -File -Filter 'AotR 8P WotR Mod.exe' -ErrorAction SilentlyContinue)
$roots = New-Object System.Collections.Generic.List[object]

foreach ($launcher in $launcherFiles) {
    $root = $launcher.Directory.FullName
    $launcherRow = Get-FileRow (Join-Path $root $Required.Launcher) $ExpectedLauncherSha256
    $iconRow     = Get-FileRow (Join-Path $root $Required.Icon)
    $skinRow     = Get-FileRow (Join-Path $root $Required.Skin)
    $uiRow       = Get-FileRow (Join-Path $root $Required.UI) $ExpectedUiSha256
    $paperRow    = Get-FileRow (Join-Path $root $Required.Paper) $ExpectedPaperSha256

    $allPresent = $launcherRow.Exists -and $iconRow.Exists -and $skinRow.Exists -and $uiRow.Exists -and $paperRow.Exists
    $verifiedKnown = $launcherRow.HashMatch -and $uiRow.HashMatch -and $paperRow.HashMatch

    [void]$roots.Add([PSCustomObject]@{
        Root = $root
        Launcher = $launcherRow.Exists
        LauncherHashMatch = $launcherRow.HashMatch
        Icon = $iconRow.Exists
        Skin = $skinRow.Exists
        UI = $uiRow.Exists
        UIHashMatch = $uiRow.HashMatch
        Paper = $paperRow.Exists
        PaperHashMatch = $paperRow.HashMatch
        Complete = [bool]$allPresent
        VerifiedKnownHashes = [bool]($allPresent -and $verifiedKnown)
    })
}

Write-Host '=== PACKAGE ROOT CANDIDATES ===' -ForegroundColor Cyan
if ($roots.Count -gt 0) {
    $roots |
        Sort-Object @{Expression={$_.VerifiedKnownHashes};Descending=$true}, @{Expression={$_.Complete};Descending=$true}, Root |
        Format-Table -AutoSize |
        Out-Host
} else {
    Write-Host 'No launcher-named package roots found.' -ForegroundColor Yellow
}

$complete = @($roots | Where-Object VerifiedKnownHashes | Sort-Object Root)
if ($complete.Count -gt 0) {
    Write-Host ''
    Write-Host '=== VERIFIED COMPLETE PACKAGE ROOTS ===' -ForegroundColor Green
    foreach ($row in $complete) {
        Write-Host $row.Root -ForegroundColor Green
        foreach ($entry in $Required.GetEnumerator()) {
            $path = Join-Path $row.Root $entry.Value
            $hash = Get-Sha256 $path
            Write-Host ("  {0,-8} {1}" -f ($entry.Key + ':'), $path)
            Write-Host ("           SHA256 $hash")
        }
    }
} else {
    Write-Host ''
    Write-Host '=== NO VERIFIED COMPLETE PACKAGE ROOT FOUND ===' -ForegroundColor Yellow
    Write-Host 'Inventorying the missing RC4 support files independently.' -ForegroundColor Yellow

    foreach ($name in @('launcher.ico','launcher_skin.png','!!!WOTR_8P_UI_TEST.big','PaperScenario001.inc')) {
        Write-Host ''
        Write-Host ("--- " + $name + " ---") -ForegroundColor Cyan
        $hits = @(Get-ChildItem -LiteralPath $ResearchRoot -Recurse -File -Filter $name -ErrorAction SilentlyContinue)
        if ($hits.Count -eq 0) {
            Write-Host 'NONE FOUND' -ForegroundColor Yellow
            continue
        }
        $rows2 = foreach ($f in $hits) {
            [PSCustomObject]@{
                Path = $f.FullName
                SHA256 = Get-Sha256 $f.FullName
                Bytes = $f.Length
            }
        }
        $rows2 | Sort-Object SHA256, Path | Format-Table -AutoSize | Out-Host
    }
}

Write-Host ''
Write-Host 'Audit complete. No files were created, copied, changed, deleted or executed.' -ForegroundColor Green
