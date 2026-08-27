#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$ProductionBundle = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE8_1_1_RC2_20260827_033705\PACKAGE\_GITHUB_UPDATE'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoUrl = 'https://github.com/eliaauditore/AotR-8P-WotR.git'
$PromotionBranch = 'release/launcher-1.1-promotion'
$ExpectedMainHead = 'fa9f8f6a47d24e4971580dc7cadfbe1572daf86b'

$ExpectedFiles = @(
    'AotR 8P WotR Mod.exe',
    'manifest.json',
    'repair-manifest.json',
    'payload_ui.big',
    'payload_paper.inc'
)

$ExpectedHashes = [ordered]@{
    'AotR 8P WotR Mod.exe' = '9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4'
    'manifest.json'         = '61B559D2AEAB72DE2ECB9BF0F2F1E437D2742C34947CA9B414CD7390AAEAA38A'
    'repair-manifest.json'  = '684B8B4F39EE7ADB97D4C0837036F742D67C28B0EFC86A2006043BB2B3C36685'
    'payload_ui.big'        = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
    'payload_paper.inc'     = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
}

function Get-Sha256File([string]$Path) {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Assert-Hash([string]$Path,[string]$Expected,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ($Label + ' missing: ' + $Path) }
    $actual = Get-Sha256File $Path
    if ($actual -ne $Expected) { throw ($Label + ' hash mismatch. Expected ' + $Expected + ', got ' + $actual) }
    Write-Host (('{0,-28}: {1}' -f $Label,$actual)) -ForegroundColor Green
    return $actual
}

function Invoke-Git([string]$WorkingDirectory,[string[]]$Arguments,[switch]$ReturnText) {
    $allArgs = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        [void]$allArgs.Add('-C')
        [void]$allArgs.Add($WorkingDirectory)
    }
    foreach ($a in $Arguments) { [void]$allArgs.Add($a) }

    $output = & git @allArgs 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        throw ('git ' + ($Arguments -join ' ') + ' failed with exit code ' + $exit + [Environment]::NewLine + (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine))
    }
    if ($ReturnText) { return (($output | ForEach-Object { [string]$_ }) -join "`n").Trim() }
    foreach ($line in $output) { Write-Host ([string]$line) }
}

function Get-RemoteRef([string]$RefName) {
    $text = Invoke-Git '' @('ls-remote',$RepoUrl,$RefName) -ReturnText
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    $first = ($text -split "`r?`n")[0]
    return (($first -split '\s+')[0]).Trim()
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git.exe was not found in PATH.' }
if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw ('Base missing: ' + $Base) }
if (-not (Test-Path -LiteralPath $ProductionBundle -PathType Container)) { throw ('Production bundle missing: ' + $ProductionBundle) }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P V18 STAGE 12 - STAGE LAUNCHER 1.1 PROMOTION' -ForegroundColor Cyan
Write-Host ' TEMP CLONE / RELEASE BRANCH ONLY / MAIN NOT MODIFIED' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('Bundle           : ' + $ProductionBundle)
Write-Host ('Promotion branch : ' + $PromotionBranch)
Write-Host ('Expected main    : ' + $ExpectedMainHead)
Write-Host ''

# 1) Reverify the exact local five-file production set.
$actual = @(Get-ChildItem -LiteralPath $ProductionBundle -File | Select-Object -ExpandProperty Name | Sort-Object)
$expectedSorted = @($ExpectedFiles | Sort-Object)
if ($actual.Count -ne 5) { throw ('Production bundle must contain exactly five files; found ' + $actual.Count) }
for ($i=0; $i -lt 5; $i++) {
    if ($actual[$i] -ne $expectedSorted[$i]) { throw ('Production bundle file set mismatch. Got: ' + ($actual -join ', ')) }
}
foreach ($name in $ExpectedFiles) { [void](Assert-Hash (Join-Path $ProductionBundle $name) $ExpectedHashes[$name] ('Bundle ' + $name)) }

$manifest = Get-Content -LiteralPath (Join-Path $ProductionBundle 'manifest.json') -Raw | ConvertFrom-Json
$repair = Get-Content -LiteralPath (Join-Path $ProductionBundle 'repair-manifest.json') -Raw | ConvertFrom-Json
if ([string]$manifest.launcher_version -ne '1.1') { throw 'Bundle manifest is not launcher 1.1.' }
if ([string]$manifest.launcher_sha256 -ne $ExpectedHashes['AotR 8P WotR Mod.exe']) { throw 'Bundle manifest launcher SHA mismatch.' }
if ([string]$repair.generated_for_launcher -ne '1.1') { throw 'Bundle repair manifest is not generated for 1.1.' }
if ((Get-Content -LiteralPath (Join-Path $ProductionBundle 'manifest.json') -Raw) -match '(?i)invalid\.invalid') { throw 'Bundle manifest still contains invalid.invalid.' }
Write-Host '[PASS] exact Stage11-approved local production bundle reverified' -ForegroundColor Green

# 2) Confirm GitHub refs have not moved since the final gate.
$remoteMainBefore = Get-RemoteRef 'refs/heads/main'
$remotePromotionBefore = Get-RemoteRef ('refs/heads/' + $PromotionBranch)
if ($remoteMainBefore -ne $ExpectedMainHead) { throw ('main moved since final gate. Expected ' + $ExpectedMainHead + ', got ' + $remoteMainBefore + '. Stop and reassess.') }
if ($remotePromotionBefore -ne $ExpectedMainHead) { throw ('promotion branch is not at the expected baseline. Expected ' + $ExpectedMainHead + ', got ' + $remotePromotionBefore) }
Write-Host ('[PASS] main/promotion refs still pinned at ' + $ExpectedMainHead) -ForegroundColor Green

# 3) Clone only the pre-created promotion branch and disable line-ending rewriting.
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ('AUTODETECT_V2_V18_STAGE12_PROMOTION_' + $stamp)
$cloneRoot = Join-Path $workRoot 'repo'
$archivePath = Join-Path $workRoot 'STAGED_COMMIT.zip'
$archiveExtract = Join-Path $workRoot 'STAGED_COMMIT_VERIFY'
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

Invoke-Git '' @('clone','--no-tags','--single-branch','--branch',$PromotionBranch,$RepoUrl,$cloneRoot)
Invoke-Git $cloneRoot @('config','core.autocrlf','false')
Invoke-Git $cloneRoot @('config','core.safecrlf','false')
Invoke-Git $cloneRoot @('config','user.name','eliaauditore')
Invoke-Git $cloneRoot @('config','user.email','eliaauditore@users.noreply.github.com')
Invoke-Git $cloneRoot @('fetch','origin','main')

$head = Invoke-Git $cloneRoot @('rev-parse','HEAD') -ReturnText
$originMain = Invoke-Git $cloneRoot @('rev-parse','origin/main') -ReturnText
if ($head -ne $ExpectedMainHead -or $originMain -ne $ExpectedMainHead) { throw ('Clone baseline mismatch. HEAD=' + $head + ', origin/main=' + $originMain) }

# 4) Copy all five verified files. UI/Paper are expected to remain byte-identical and may not appear as changed Git paths.
foreach ($name in $ExpectedFiles) {
    Copy-Item -LiteralPath (Join-Path $ProductionBundle $name) -Destination (Join-Path $cloneRoot $name) -Force
    [void](Assert-Hash (Join-Path $cloneRoot $name) $ExpectedHashes[$name] ('Clone ' + $name))
}

Invoke-Git $cloneRoot (@('add','--') + $ExpectedFiles)
$changedText = Invoke-Git $cloneRoot @('diff','--cached','--name-only') -ReturnText
$changed = @($changedText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$unexpected = @($changed | Where-Object { $_ -notin $ExpectedFiles })
if ($unexpected.Count -gt 0) { throw ('Unexpected staged paths: ' + ($unexpected -join ', ')) }
foreach ($required in @('AotR 8P WotR Mod.exe','manifest.json','repair-manifest.json')) {
    if ($required -notin $changed) { throw ('Required release change was not staged: ' + $required) }
}
Write-Host ('Staged changed paths: ' + ($changed -join ', ')) -ForegroundColor Green
Write-Host 'Note: payload_ui.big and payload_paper.inc are byte-identical to 1.0.10 and therefore normally remain the existing Git blobs.' -ForegroundColor DarkGray

# 5) Create one local atomic release commit.
Invoke-Git $cloneRoot @('commit','-m','Release launcher 1.1')
$commit = Invoke-Git $cloneRoot @('rev-parse','HEAD') -ReturnText
$parent = Invoke-Git $cloneRoot @('rev-parse','HEAD^') -ReturnText
if ($parent -ne $ExpectedMainHead) { throw ('Release commit parent mismatch. Expected ' + $ExpectedMainHead + ', got ' + $parent) }

# 6) Archive the exact commit tree and verify its five release-root bytes before any push.
Invoke-Git $cloneRoot (@('archive','--format=zip','-o',$archivePath,$commit,'--') + $ExpectedFiles)
Expand-Archive -LiteralPath $archivePath -DestinationPath $archiveExtract -Force
foreach ($name in $ExpectedFiles) { [void](Assert-Hash (Join-Path $archiveExtract $name) $ExpectedHashes[$name] ('Committed ' + $name)) }
Write-Host '[PASS] exact staged Git commit bytes match all five Stage11-approved hashes' -ForegroundColor Green

# 7) Last race check. Main must still be untouched, promotion branch must still be the baseline.
$remoteMainRace = Get-RemoteRef 'refs/heads/main'
$remotePromotionRace = Get-RemoteRef ('refs/heads/' + $PromotionBranch)
if ($remoteMainRace -ne $ExpectedMainHead) { throw ('main moved before staging push. Expected ' + $ExpectedMainHead + ', got ' + $remoteMainRace) }
if ($remotePromotionRace -ne $ExpectedMainHead) { throw ('promotion branch moved before staging push. Expected ' + $ExpectedMainHead + ', got ' + $remotePromotionRace) }

# 8) Push ONLY the promotion branch. main remains live 1.0.10.
Write-Host ''
Write-Host 'Pushing verified atomic commit to release/launcher-1.1-promotion only...' -ForegroundColor Cyan
Invoke-Git $cloneRoot @('push','origin',('HEAD:refs/heads/' + $PromotionBranch))
$remotePromotionAfter = Get-RemoteRef ('refs/heads/' + $PromotionBranch)
$remoteMainAfter = Get-RemoteRef 'refs/heads/main'
if ($remotePromotionAfter -ne $commit) { throw ('Promotion branch push verification failed. Expected ' + $commit + ', got ' + $remotePromotionAfter) }
if ($remoteMainAfter -ne $ExpectedMainHead) { throw ('main changed unexpectedly during staging. Expected ' + $ExpectedMainHead + ', got ' + $remoteMainAfter) }

$report = Join-Path $workRoot 'V18_STAGE12_PROMOTION_BRANCH_STAGING_REPORT.txt'
$lines = @(
    'AOTR 8P V18 STAGE12 LAUNCHER 1.1 PROMOTION BRANCH STAGING',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Production bundle: ' + $ProductionBundle),
    ('Expected main baseline: ' + $ExpectedMainHead),
    ('Promotion branch: ' + $PromotionBranch),
    ('Staged commit: ' + $commit),
    ('Staged commit parent: ' + $parent),
    ('Remote promotion after push: ' + $remotePromotionAfter),
    ('Remote main after push: ' + $remoteMainAfter),
    ('Production EXE SHA256: ' + $ExpectedHashes['AotR 8P WotR Mod.exe']),
    ('Manifest SHA256: ' + $ExpectedHashes['manifest.json']),
    ('Repair manifest SHA256: ' + $ExpectedHashes['repair-manifest.json']),
    ('UI SHA256: ' + $ExpectedHashes['payload_ui.big']),
    ('Paper SHA256: ' + $ExpectedHashes['payload_paper.inc']),
    '',
    'RESULT',
    '- Local five-file bundle reverified: PASS',
    '- Main race checks: PASS',
    '- Atomic Git commit archive reverified against five hashes: PASS',
    '- Promotion branch push verified: PASS',
    '- main NOT modified: PASS'
)
[IO.File]::WriteAllLines($report,$lines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' STAGE 12 PROMOTION BRANCH STAGING: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('Staged commit : ' + $commit) -ForegroundColor Green
Write-Host ('Promotion ref : ' + $remotePromotionAfter) -ForegroundColor Green
Write-Host ('Main ref      : ' + $remoteMainAfter) -ForegroundColor Green
Write-Host ('Report        : ' + $report)
Write-Host ''
Write-Host 'MAIN IS STILL 1.0.10. Send this output back; the staged commit can then be inspected and main fast-forwarded atomically.' -ForegroundColor Yellow
