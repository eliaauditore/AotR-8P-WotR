#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$FinalBundle = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_054456\PACKAGE\_GITHUB_UPDATE',
    [string]$FinalBuilder = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_054456\BUILD_ISSUE33_STANDALONE_SKIN_RC2.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoUrl = 'https://github.com/eliaauditore/AotR-8P-WotR.git'
$TargetBranch = 'fix/issue-33-standalone-skin'
$ExpectedTargetHead = 'f261a697f483dcd75abe564cc6054f4a5540b970'
$ExpectedMainHead = 'aec9559c9eb30ea79ef58fec77a2297d5900ee71'
$ExpectedVersion = '1.1.1'
$CanonicalBuilderPath = 'launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_1.ps1'

$ExpectedFiles = @(
    'AotR 8P WotR Mod.exe',
    'manifest.json',
    'repair-manifest.json',
    'payload_ui.big',
    'payload_paper.inc'
)

$ExpectedExeSha = '2141EA9690708EA7A61B7298AD90E0C76CC417FED996AC0CF3685276BA2A4024'
$ExpectedBuilderSha = 'B30EAFB0ABCE94DC22E5121FB7F9B3B9AF31A6D2FCDB5E5B14CB4056AF392560'
$ExpectedUiSha = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
$ExpectedOldExeSha = '9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4'

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
    if ($actual -ne $Expected) { throw ($Label + ' SHA256 mismatch. Expected ' + $Expected + ', got ' + $actual) }
    Write-Host (('{0,-34}: {1}' -f $Label,$actual)) -ForegroundColor Green
    return $actual
}

function Invoke-Git([string]$WorkingDirectory,[string[]]$Arguments,[switch]$ReturnText) {
    $allArgs = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        [void]$allArgs.Add('-C')
        [void]$allArgs.Add($WorkingDirectory)
    }
    foreach ($arg in $Arguments) { [void]$allArgs.Add($arg) }

    $output = & git @allArgs 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw ('git ' + ($Arguments -join ' ') + ' failed with exit code ' + $exitCode + [Environment]::NewLine + (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine))
    }
    $text = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    if ($ReturnText) { return $text }
    if (-not [string]::IsNullOrWhiteSpace($text)) { Write-Host $text }
}

function Get-RemoteRef([string]$RefName) {
    $text = Invoke-Git '' @('ls-remote',$RepoUrl,$RefName) -ReturnText
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    $firstLine = ($text -split "`r?`n")[0]
    return (($firstLine -split '\s+')[0]).Trim()
}

function Assert-PowerShellParses([string]$Path,[string]$Label) {
    $text = Get-Content -LiteralPath $Path -Raw
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        $messages = @($errors | ForEach-Object { $_.Message })
        throw ($Label + ' has parser errors: ' + ($messages -join '; '))
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git.exe was not found in PATH.' }
if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw ('Base missing: ' + $Base) }
if (-not (Test-Path -LiteralPath $FinalBundle -PathType Container)) { throw ('Final bundle missing: ' + $FinalBundle) }
if (-not (Test-Path -LiteralPath $FinalBuilder -PathType Leaf)) { throw ('Final builder missing: ' + $FinalBuilder) }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' ISSUE #33 - STAGE EXACT FINAL 1.1.1 TO GUARDED PR #34' -ForegroundColor Cyan
Write-Host ' TARGET BRANCH ONLY / MAIN NOT MODIFIED / NO FORCE PUSH' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('Final bundle : ' + $FinalBundle)
Write-Host ('Final builder: ' + $FinalBuilder)
Write-Host ('Target branch: ' + $TargetBranch)
Write-Host ('Pinned target: ' + $ExpectedTargetHead)
Write-Host ('Pinned main  : ' + $ExpectedMainHead)
Write-Host ''

# 1) Reverify the exact final release bundle accepted by the runtime gate.
$bundleFiles = @(Get-ChildItem -LiteralPath $FinalBundle -File | Select-Object -ExpandProperty Name | Sort-Object)
$bundleDirs = @(Get-ChildItem -LiteralPath $FinalBundle -Directory)
$expectedSorted = @($ExpectedFiles | Sort-Object)
if ($bundleFiles.Count -ne 5 -or (($bundleFiles -join "`n") -cne ($expectedSorted -join "`n"))) {
    throw ('Final bundle is not exactly the five public files. Found: ' + ($bundleFiles -join ', '))
}
if ($bundleDirs.Count -ne 0) { throw ('Final bundle contains unexpected directories: ' + (($bundleDirs | Select-Object -ExpandProperty Name) -join ', ')) }
Write-Host '[PASS] local final bundle is exactly five files with no directories' -ForegroundColor Green

[void](Assert-Hash (Join-Path $FinalBundle 'AotR 8P WotR Mod.exe') $ExpectedExeSha 'Final EXE')
[void](Assert-Hash (Join-Path $FinalBundle 'payload_ui.big') $ExpectedUiSha 'Final UI')
[void](Assert-Hash (Join-Path $FinalBundle 'payload_paper.inc') $ExpectedPaperSha 'Final paper')
[void](Assert-Hash $FinalBuilder $ExpectedBuilderSha 'Final builder')
Assert-PowerShellParses $FinalBuilder 'Final builder'

$manifestPath = Join-Path $FinalBundle 'manifest.json'
$repairPath = Join-Path $FinalBundle 'repair-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$repair = Get-Content -LiteralPath $repairPath -Raw | ConvertFrom-Json
$manifestSha = Get-Sha256File $manifestPath
$repairSha = Get-Sha256File $repairPath

if ([int]$manifest.schema -ne 1) { throw ('Final manifest schema mismatch: ' + [string]$manifest.schema) }
if ([string]$manifest.launcher_version -ne $ExpectedVersion) { throw ('Final manifest launcher_version mismatch: ' + [string]$manifest.launcher_version) }
if ([string]$manifest.launcher_sha256 -ne $ExpectedExeSha) { throw ('Final manifest launcher_sha256 mismatch: ' + [string]$manifest.launcher_sha256) }
if ([string]$manifest.ui_sha256 -ne $ExpectedUiSha) { throw 'Final manifest UI SHA mismatch.' }
if ([string]$manifest.paper_sha256 -ne $ExpectedPaperSha) { throw 'Final manifest paper SHA mismatch.' }
if ([string]$manifest.launcher_url -ne 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/AotR%208P%20WotR%20Mod.exe') { throw 'Final manifest launcher_url changed unexpectedly.' }
if ([string]$manifest.repair_manifest_url -ne 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/repair-manifest.json') { throw 'Final manifest repair_manifest_url changed unexpectedly.' }
if ([string]$manifest.ui_url -ne 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/payload_ui.big') { throw 'Final manifest ui_url changed unexpectedly.' }
if ([string]$manifest.paper_url -ne 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/payload_paper.inc') { throw 'Final manifest paper_url changed unexpectedly.' }
if ([int]$repair.schema -ne 1) { throw ('Final repair-manifest schema mismatch: ' + [string]$repair.schema) }
if ([string]$repair.generated_for_launcher -ne $ExpectedVersion) { throw ('Final repair-manifest version mismatch: ' + [string]$repair.generated_for_launcher) }
if ((Get-Content -LiteralPath $manifestPath -Raw) -match '(?i)invalid\.invalid') { throw 'Final manifest contains invalid.invalid.' }

$builderText = Get-Content -LiteralPath $FinalBuilder -Raw
$versionMatches = [regex]::Matches($builderText,'(?m)^\s*\[string\]\$LauncherVersion\s*=\s*["'']1\.1\.1["'']\s*,?\s*$')
if ($versionMatches.Count -ne 1) { throw ('Final builder must contain exactly one LauncherVersion default 1.1.1; found ' + $versionMatches.Count) }
if ($builderText -notmatch 'Issue33SkinGzipBase64') { throw 'Final builder no longer contains the embedded skin bootstrap marker.' }

Write-Host ('Final manifest SHA             : ' + $manifestSha) -ForegroundColor Green
Write-Host ('Final repair-manifest SHA      : ' + $repairSha) -ForegroundColor Green
Write-Host '[PASS] exact final 1.1.1 metadata and builder identity verified' -ForegroundColor Green

# 2) Race-check the protected base and the PR branch before touching a clone.
$remoteMainBefore = Get-RemoteRef 'refs/heads/main'
$remoteTargetBefore = Get-RemoteRef ('refs/heads/' + $TargetBranch)
if ($remoteMainBefore -ne $ExpectedMainHead) { throw ('main moved. Expected ' + $ExpectedMainHead + ', got ' + $remoteMainBefore + '. Stop and reassess.') }
if ($remoteTargetBefore -ne $ExpectedTargetHead) { throw ('PR branch moved. Expected ' + $ExpectedTargetHead + ', got ' + $remoteTargetBefore + '. Stop and reassess.') }
Write-Host '[PASS] main and PR branch are still on the accepted pinned heads' -ForegroundColor Green

# 3) Clone the exact PR branch and fetch main into an explicit tracking ref.
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ('ISSUE33_FINAL_1_1_1_PR34_STAGE_' + $stamp)
$cloneRoot = Join-Path $workRoot 'repo'
$archivePath = Join-Path $workRoot 'STAGED_COMMIT.zip'
$archiveExtract = Join-Path $workRoot 'STAGED_COMMIT_VERIFY'
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

Invoke-Git '' @('clone','--no-tags','--single-branch','--branch',$TargetBranch,$RepoUrl,$cloneRoot)
Invoke-Git $cloneRoot @('config','core.autocrlf','false')
Invoke-Git $cloneRoot @('config','core.safecrlf','false')
Invoke-Git $cloneRoot @('config','user.name','eliaauditore')
Invoke-Git $cloneRoot @('config','user.email','eliaauditore@users.noreply.github.com')
Invoke-Git $cloneRoot @('fetch','origin','+refs/heads/main:refs/remotes/origin/main')

$headBefore = Invoke-Git $cloneRoot @('rev-parse','HEAD') -ReturnText
$originMain = Invoke-Git $cloneRoot @('rev-parse','origin/main') -ReturnText
if ($headBefore -ne $ExpectedTargetHead) { throw ('Clone target HEAD mismatch: ' + $headBefore) }
if ($originMain -ne $ExpectedMainHead) { throw ('Clone origin/main mismatch: ' + $originMain) }
if (-not [string]::IsNullOrWhiteSpace((Invoke-Git $cloneRoot @('status','--porcelain') -ReturnText))) { throw 'Fresh clone is unexpectedly dirty.' }

# Protect the historical 1.1 root before replacing it in the PR branch.
[void](Assert-Hash (Join-Path $cloneRoot 'AotR 8P WotR Mod.exe') $ExpectedOldExeSha 'PR baseline 1.1 EXE')
$currentManifest = Get-Content -LiteralPath (Join-Path $cloneRoot 'manifest.json') -Raw | ConvertFrom-Json
$currentRepair = Get-Content -LiteralPath (Join-Path $cloneRoot 'repair-manifest.json') -Raw | ConvertFrom-Json
if ([string]$currentManifest.launcher_version -ne '1.1') { throw ('PR baseline manifest is not 1.1: ' + [string]$currentManifest.launcher_version) }
if ([string]$currentRepair.generated_for_launcher -ne '1.1') { throw ('PR baseline repair-manifest is not 1.1: ' + [string]$currentRepair.generated_for_launcher) }

$oldPlans = ($currentRepair.plans | ConvertTo-Json -Depth 20 -Compress)
$newPlans = ($repair.plans | ConvertTo-Json -Depth 20 -Compress)
if ($oldPlans -cne $newPlans) { throw 'Final 1.1.1 repair plans differ from the current 1.1 dispatcher plan set. Refusing promotion.' }
Write-Host '[PASS] final repair plan set is byte-semantically unchanged from 1.1' -ForegroundColor Green

$canonicalBuilderFull = Join-Path $cloneRoot ($CanonicalBuilderPath -replace '/','\')
if (Test-Path -LiteralPath $canonicalBuilderFull) { throw ('Canonical FINAL_1_1_1 builder path already exists unexpectedly: ' + $CanonicalBuilderPath) }

# 4) Copy only the accepted final release bytes plus the exact accepted builder.
foreach ($name in $ExpectedFiles) {
    Copy-Item -LiteralPath (Join-Path $FinalBundle $name) -Destination (Join-Path $cloneRoot $name) -Force
}
Copy-Item -LiteralPath $FinalBuilder -Destination $canonicalBuilderFull -Force

[void](Assert-Hash (Join-Path $cloneRoot 'AotR 8P WotR Mod.exe') $ExpectedExeSha 'Staged working EXE')
[void](Assert-Hash (Join-Path $cloneRoot 'payload_ui.big') $ExpectedUiSha 'Staged working UI')
[void](Assert-Hash (Join-Path $cloneRoot 'payload_paper.inc') $ExpectedPaperSha 'Staged working paper')
[void](Assert-Hash $canonicalBuilderFull $ExpectedBuilderSha 'Staged working builder')
if ((Get-Sha256File (Join-Path $cloneRoot 'manifest.json')) -ne $manifestSha) { throw 'Staged working manifest bytes differ from accepted local final bytes.' }
if ((Get-Sha256File (Join-Path $cloneRoot 'repair-manifest.json')) -ne $repairSha) { throw 'Staged working repair-manifest bytes differ from accepted local final bytes.' }

$pathsToAdd = @($ExpectedFiles + $CanonicalBuilderPath)
Invoke-Git $cloneRoot (@('add','--') + $pathsToAdd)

$stagedPaths = @((Invoke-Git $cloneRoot @('diff','--cached','--name-only') -ReturnText) -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object)
$expectedChangedPaths = @(
    'AotR 8P WotR Mod.exe',
    'launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_1.ps1',
    'manifest.json',
    'repair-manifest.json'
) | Sort-Object
if (($stagedPaths -join "`n") -cne ($expectedChangedPaths -join "`n")) {
    throw ('Unexpected staged path set. Expected: ' + ($expectedChangedPaths -join ', ') + ' ; got: ' + ($stagedPaths -join ', '))
}
Write-Host ('Staged changed paths            : ' + ($stagedPaths -join ', ')) -ForegroundColor Green
Write-Host '[PASS] payload_ui.big and payload_paper.inc remain byte-identical to 1.1 and are not changed' -ForegroundColor Green

# 5) Last race check immediately before committing.
$remoteMainCommitGate = Get-RemoteRef 'refs/heads/main'
$remoteTargetCommitGate = Get-RemoteRef ('refs/heads/' + $TargetBranch)
if ($remoteMainCommitGate -ne $ExpectedMainHead) { throw 'main moved during staging. Stop.' }
if ($remoteTargetCommitGate -ne $ExpectedTargetHead) { throw 'PR branch moved during staging. Stop.' }

Invoke-Git $cloneRoot @('commit','-m','Release launcher 1.1.1 standalone skin fix')
$commitSha = Invoke-Git $cloneRoot @('rev-parse','HEAD') -ReturnText
$parentSha = Invoke-Git $cloneRoot @('rev-parse','HEAD^') -ReturnText
if ($parentSha -ne $ExpectedTargetHead) { throw ('Created commit parent mismatch. Expected ' + $ExpectedTargetHead + ', got ' + $parentSha) }

$commitPaths = @((Invoke-Git $cloneRoot @('diff-tree','--no-commit-id','--name-only','-r','HEAD') -ReturnText) -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object)
if (($commitPaths -join "`n") -cne ($expectedChangedPaths -join "`n")) { throw ('Commit changed unexpected paths: ' + ($commitPaths -join ', ')) }

# 6) Verify the actual Git commit tree, not merely the working directory.
Invoke-Git $cloneRoot (@('archive','--format=zip','--output',$archivePath,'HEAD','--') + $ExpectedFiles + $CanonicalBuilderPath)
New-Item -ItemType Directory -Path $archiveExtract -Force | Out-Null
Expand-Archive -LiteralPath $archivePath -DestinationPath $archiveExtract -Force

[void](Assert-Hash (Join-Path $archiveExtract 'AotR 8P WotR Mod.exe') $ExpectedExeSha 'Commit-tree EXE')
[void](Assert-Hash (Join-Path $archiveExtract 'payload_ui.big') $ExpectedUiSha 'Commit-tree UI')
[void](Assert-Hash (Join-Path $archiveExtract 'payload_paper.inc') $ExpectedPaperSha 'Commit-tree paper')
[void](Assert-Hash (Join-Path $archiveExtract ($CanonicalBuilderPath -replace '/','\')) $ExpectedBuilderSha 'Commit-tree builder')
if ((Get-Sha256File (Join-Path $archiveExtract 'manifest.json')) -ne $manifestSha) { throw 'Commit-tree manifest bytes differ from accepted final bytes.' }
if ((Get-Sha256File (Join-Path $archiveExtract 'repair-manifest.json')) -ne $repairSha) { throw 'Commit-tree repair-manifest bytes differ from accepted final bytes.' }
Write-Host '[PASS] exact accepted final bytes are present in the created Git commit tree' -ForegroundColor Green

# 7) Final remote race check, then push only the PR branch. Never touch main.
$remoteMainPushGate = Get-RemoteRef 'refs/heads/main'
$remoteTargetPushGate = Get-RemoteRef ('refs/heads/' + $TargetBranch)
if ($remoteMainPushGate -ne $ExpectedMainHead) { throw 'main moved before push. Stop.' }
if ($remoteTargetPushGate -ne $ExpectedTargetHead) { throw 'PR branch moved before push. Stop.' }

Invoke-Git $cloneRoot @('push','origin',('HEAD:refs/heads/' + $TargetBranch))

$remoteMainAfter = Get-RemoteRef 'refs/heads/main'
$remoteTargetAfter = Get-RemoteRef ('refs/heads/' + $TargetBranch)
if ($remoteMainAfter -ne $ExpectedMainHead) { throw ('main changed unexpectedly during push. Expected ' + $ExpectedMainHead + ', got ' + $remoteMainAfter) }
if ($remoteTargetAfter -ne $commitSha) { throw ('PR branch push verification failed. Expected ' + $commitSha + ', got ' + $remoteTargetAfter) }

$report = Join-Path $workRoot 'ISSUE33_FINAL_1_1_1_PR34_STAGE_REPORT.txt'
$reportLines = @(
    'AOTR 8P WOTR ISSUE #33 FINAL 1.1.1 PR #34 STAGING: PASS',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Target branch: ' + $TargetBranch),
    ('Previous target head: ' + $ExpectedTargetHead),
    ('Created commit: ' + $commitSha),
    ('Main remained: ' + $ExpectedMainHead),
    ('Final EXE SHA256: ' + $ExpectedExeSha),
    ('Final manifest SHA256: ' + $manifestSha),
    ('Final repair-manifest SHA256: ' + $repairSha),
    ('Final UI SHA256: ' + $ExpectedUiSha),
    ('Final paper SHA256: ' + $ExpectedPaperSha),
    ('FINAL_1_1_1 builder SHA256: ' + $ExpectedBuilderSha),
    ('Changed paths: ' + ($commitPaths -join ', ')),
    'main was not modified by this stager.',
    'No force push was used.',
    'Next: wait for PR #34 Guardian CI; do not merge until all required checks pass.'
)
[IO.File]::WriteAllLines($report,$reportLines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' ISSUE #33 FINAL 1.1.1 -> PR #34 STAGING: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('Created commit    : ' + $commitSha) -ForegroundColor Green
Write-Host ('PR branch         : ' + $TargetBranch) -ForegroundColor Green
Write-Host ('Main remains      : ' + $ExpectedMainHead) -ForegroundColor Green
Write-Host ('Final EXE SHA     : ' + $ExpectedExeSha) -ForegroundColor Green
Write-Host ('Manifest SHA      : ' + $manifestSha) -ForegroundColor Green
Write-Host ('Repair SHA        : ' + $repairSha) -ForegroundColor Green
Write-Host ('FINAL builder SHA : ' + $ExpectedBuilderSha) -ForegroundColor Green
Write-Host ('Report            : ' + $report)
Write-Host ''
Write-Host 'PR #34 now contains the exact final release bytes. DO NOT MERGE MANUALLY YET; wait for Guardian CI.' -ForegroundColor Cyan
