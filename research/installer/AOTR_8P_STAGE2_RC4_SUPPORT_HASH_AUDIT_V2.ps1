#requires -version 5.1
[CmdletBinding()]
param(
    [string]$ResearchRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedSeedSha256 = '97A8163CA72BDFB5C6C24931E06B2BFCE1D0E33C382FEA2462F73BC80BD3EA9F'
$ExpectedUiSha256   = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha256 = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'

$SeedName = 'AotR 8P WotR Mod.exe'
$SupportSpecs = @(
    [PSCustomObject]@{ Name='launcher.ico'; Relative='assets\launcher.ico'; Expected='' },
    [PSCustomObject]@{ Name='launcher_skin.png'; Relative='internal\assets\launcher_skin.png'; Expected='' },
    [PSCustomObject]@{ Name='!!!WOTR_8P_UI_TEST.big'; Relative='payload\!!!WOTR_8P_UI_TEST.big'; Expected=$ExpectedUiSha256 },
    [PSCustomObject]@{ Name='PaperScenario001.inc'; Relative='payload\data\ini\campaigns\scenarios\PaperScenario001.inc'; Expected=$ExpectedPaperSha256 }
)

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Write-HashGroups {
    param(
        [string]$Title,
        [object[]]$Rows,
        [string]$Expected = ''
    )

    Write-Host ''
    Write-Host ("=== " + $Title + " ===") -ForegroundColor Cyan

    if (-not $Rows -or $Rows.Count -eq 0) {
        Write-Host 'NONE FOUND' -ForegroundColor Yellow
        return
    }

    $groups = @(
        $Rows |
            Group-Object SHA256 |
            Sort-Object @{
                Expression = { $_.Count }
                Descending = $true
            }, @{
                Expression = { $_.Name }
                Ascending = $true
            }
    )
    foreach ($g in $groups) {
        $match = (-not [string]::IsNullOrWhiteSpace($Expected) -and $g.Name -eq $Expected)
        $tag = if ($match) { 'EXPECTED MATCH' } else { 'UNPINNED/OTHER' }
        $color = if ($match) { 'Green' } else { 'Yellow' }
        Write-Host ("SHA256: {0}  Count: {1}  [{2}]" -f $g.Name,$g.Count,$tag) -ForegroundColor $color
        foreach ($row in @($g.Group | Sort-Object Path)) {
            Write-Host ("  {0}" -f $row.Path)
        }
    }
}

if (-not (Test-Path -LiteralPath $ResearchRoot -PathType Container)) {
    throw "Research root missing: $ResearchRoot"
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P STAGE 2 RC4 SUPPORT HASH AUDIT V2' -ForegroundColor Cyan
Write-Host ' READ ONLY / NO BUILD / NO COPIES' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Research root: $ResearchRoot"

$allRows = New-Object System.Collections.Generic.List[object]

# Seed EXEs
$seedRows = New-Object System.Collections.Generic.List[object]
foreach ($f in @(Get-ChildItem -LiteralPath $ResearchRoot -Recurse -File -Filter $SeedName -ErrorAction SilentlyContinue)) {
    try {
        $h = Get-Sha256 $f.FullName
        [void]$seedRows.Add([PSCustomObject]@{ Path=$f.FullName; SHA256=$h })
    } catch {}
}
Write-HashGroups -Title $SeedName -Rows @($seedRows) -Expected $ExpectedSeedSha256

# Support files
$rowsByName = @{}
foreach ($spec in $SupportSpecs) {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($f in @(Get-ChildItem -LiteralPath $ResearchRoot -Recurse -File -Filter $spec.Name -ErrorAction SilentlyContinue)) {
        try {
            $full = [IO.Path]::GetFullPath($f.FullName)
            $suffix = '\' + $spec.Relative
            if (-not $full.EndsWith($suffix,[StringComparison]::OrdinalIgnoreCase)) { continue }
            $h = Get-Sha256 $full
            [void]$rows.Add([PSCustomObject]@{ Path=$full; SHA256=$h })
        } catch {}
    }
    $rowsByName[$spec.Name] = @($rows)
    Write-HashGroups -Title $spec.Name -Rows @($rows) -Expected $spec.Expected
}

# Infer candidate support roots from every matched support path.
$rootMap = @{}
foreach ($spec in $SupportSpecs) {
    foreach ($row in @($rowsByName[$spec.Name])) {
        $suffix = '\' + $spec.Relative
        if ($row.Path.EndsWith($suffix,[StringComparison]::OrdinalIgnoreCase)) {
            $root = $row.Path.Substring(0,$row.Path.Length-$suffix.Length)
            $key = $root.ToLowerInvariant()
            if (-not $rootMap.ContainsKey($key)) { $rootMap[$key] = $root }
        }
    }
}

$donors = New-Object System.Collections.Generic.List[object]
foreach ($root in @($rootMap.Values | Sort-Object)) {
    $icon = Join-Path $root 'assets\launcher.ico'
    $skin = Join-Path $root 'internal\assets\launcher_skin.png'
    $ui = Join-Path $root 'payload\!!!WOTR_8P_UI_TEST.big'
    $paper = Join-Path $root 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc'

    $hasIcon = Test-Path -LiteralPath $icon -PathType Leaf
    $hasSkin = Test-Path -LiteralPath $skin -PathType Leaf
    $hasUi = Test-Path -LiteralPath $ui -PathType Leaf
    $hasPaper = Test-Path -LiteralPath $paper -PathType Leaf

    $uiHash = if ($hasUi) { Get-Sha256 $ui } else { '' }
    $paperHash = if ($hasPaper) { Get-Sha256 $paper } else { '' }
    $verified = $hasIcon -and $hasSkin -and $hasUi -and $hasPaper -and
        ($uiHash -eq $ExpectedUiSha256) -and ($paperHash -eq $ExpectedPaperSha256)

    if ($hasIcon -or $hasSkin -or $hasUi -or $hasPaper) {
        [void]$donors.Add([PSCustomObject]@{
            Root=$root
            Icon=$hasIcon
            Skin=$hasSkin
            Ui=$hasUi
            UiHash=$uiHash
            UiExpected=($uiHash -eq $ExpectedUiSha256)
            Paper=$hasPaper
            PaperHash=$paperHash
            PaperExpected=($paperHash -eq $ExpectedPaperSha256)
            VerifiedSupportDonor=[bool]$verified
        })
    }
}

Write-Host ''
Write-Host '=== SUPPORT DONOR ROOTS ===' -ForegroundColor Cyan
$verifiedDonors = @($donors | Where-Object VerifiedSupportDonor | Sort-Object @{Expression={$_.Root.Length};Ascending=$true}, Root)
if ($verifiedDonors.Count -gt 0) {
    foreach ($d in $verifiedDonors) {
        Write-Host '[VERIFIED SUPPORT DONOR]' -ForegroundColor Green
        Write-Host ("  Root : " + $d.Root)
        Write-Host ("  Icon : " + (Join-Path $d.Root 'assets\launcher.ico'))
        Write-Host ("  Skin : " + (Join-Path $d.Root 'internal\assets\launcher_skin.png'))
        Write-Host ("  UI   : " + $d.UiHash) -ForegroundColor Green
        Write-Host ("  Paper: " + $d.PaperHash) -ForegroundColor Green
    }
} else {
    Write-Host 'No root contains icon + skin + expected UI + expected Paper together.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Partial donor roots:' -ForegroundColor Yellow
    foreach ($d in @($donors | Sort-Object Root)) {
        Write-Host ("  {0}" -f $d.Root)
        Write-Host ("    icon={0} skin={1} ui={2}/expected={3} paper={4}/expected={5}" -f $d.Icon,$d.Skin,$d.Ui,$d.UiExpected,$d.Paper,$d.PaperExpected)
    }
}

Write-Host ''
Write-Host '=== RECOMMENDED NEXT INPUTS ===' -ForegroundColor Cyan
$verifiedSeeds = @($seedRows | Where-Object { $_.SHA256 -eq $ExpectedSeedSha256 } | Sort-Object @{Expression={$_.Path.Length};Ascending=$true}, Path)
if ($verifiedSeeds.Count -gt 0) {
    Write-Host ('Verified seed : ' + $verifiedSeeds[0].Path) -ForegroundColor Green
    Write-Host ('Seed SHA256   : ' + $verifiedSeeds[0].SHA256) -ForegroundColor Green
} else {
    Write-Host 'Verified seed : NONE' -ForegroundColor Red
}
if ($verifiedDonors.Count -gt 0) {
    Write-Host ('Support donor : ' + $verifiedDonors[0].Root) -ForegroundColor Green
} else {
    Write-Host 'Support donor : NONE' -ForegroundColor Red
}

Write-Host ''
Write-Host 'Audit complete. No files were created, copied, changed, deleted or executed.' -ForegroundColor Green
