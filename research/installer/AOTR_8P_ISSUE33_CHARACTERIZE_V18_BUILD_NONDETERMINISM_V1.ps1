#requires -version 7.0
[CmdletBinding()]
param(
    [string]$WorkRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_054456'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$CanonicalBuilderName = 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_1.ps1'
$ExpectedCanonicalBuilderSha = '32BCAC9D82F2A8FC9651C9F6B4E655D8B161F788174854F7118D30F37EB2516F'
$ExpectedAcceptedExeSha = '2141EA9690708EA7A61B7298AD90E0C76CC417FED996AC0CF3685276BA2A4024'
$ExpectedUiSha = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
$ExpectedVersion = '1.1.1'
$ExpectedFiles = @('AotR 8P WotR Mod.exe','manifest.json','repair-manifest.json','payload_ui.big','payload_paper.inc')

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

function Get-PeTimestamp([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x40) { throw ('PE file too small: ' + $Path) }
    $peOffset = [BitConverter]::ToInt32($bytes,0x3C)
    if ($peOffset -lt 0 -or ($peOffset + 12) -gt $bytes.Length) { throw ('Invalid PE header offset in ' + $Path) }
    if ($bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset+1] -ne 0x45 -or $bytes[$peOffset+2] -ne 0 -or $bytes[$peOffset+3] -ne 0) {
        throw ('PE signature missing in ' + $Path)
    }
    return [BitConverter]::ToUInt32($bytes,$peOffset + 8)
}

function Get-ManifestIdentity($m) {
    return @(
        [string]$m.schema,
        [string]$m.launcher_version,
        [string]$m.launcher_url,
        [string][bool]$m.mandatory,
        [string]$m.repair_manifest_url,
        [string]$m.ui_url,
        [string]$m.ui_sha256,
        [string]$m.paper_url,
        [string]$m.paper_sha256
    ) -join '|'
}

if (-not (Test-Path -LiteralPath $WorkRoot -PathType Container)) { throw ('Work root missing: ' + $WorkRoot) }
$canonicalBuilder = Join-Path $WorkRoot $CanonicalBuilderName
$acceptedPackage = Join-Path $WorkRoot 'PACKAGE'
$acceptedBundle = Join-Path $acceptedPackage '_GITHUB_UPDATE'
if (-not (Test-Path -LiteralPath $acceptedPackage -PathType Container)) { throw ('Accepted package missing: ' + $acceptedPackage) }
if (-not (Test-Path -LiteralPath $acceptedBundle -PathType Container)) { throw ('Accepted bundle missing: ' + $acceptedBundle) }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' ISSUE #33 - CHARACTERIZE V18 BUILD NONDETERMINISM' -ForegroundColor Cyan
Write-Host ' TWO IDENTICAL DEFAULT-VERSION BUILDS FROM IDENTICAL INPUTS' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('Work root        : ' + $WorkRoot)
Write-Host ('Canonical builder: ' + $canonicalBuilder)
Write-Host ''

[void](Assert-Hash $canonicalBuilder $ExpectedCanonicalBuilderSha 'Canonical FINAL_1_1_1 builder')
[void](Assert-Hash (Join-Path $acceptedBundle 'AotR 8P WotR Mod.exe') $ExpectedAcceptedExeSha 'Accepted runtime-tested EXE')
[void](Assert-Hash (Join-Path $acceptedBundle 'payload_ui.big') $ExpectedUiSha 'Accepted UI')
[void](Assert-Hash (Join-Path $acceptedBundle 'payload_paper.inc') $ExpectedPaperSha 'Accepted paper')

$acceptedRepairSha = Get-Sha256File (Join-Path $acceptedBundle 'repair-manifest.json')
$acceptedManifest = Get-Content -LiteralPath (Join-Path $acceptedBundle 'manifest.json') -Raw | ConvertFrom-Json
$acceptedManifestIdentity = Get-ManifestIdentity $acceptedManifest
if ([string]$acceptedManifest.launcher_version -ne $ExpectedVersion) { throw 'Accepted manifest version mismatch.' }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$diagRoot = Join-Path $WorkRoot ('V18_NONDETERMINISM_' + $stamp)
New-Item -ItemType Directory -Path $diagRoot -Force | Out-Null

$results = @()
for ($i = 1; $i -le 2; $i++) {
    $runRoot = Join-Path $diagRoot ('RUN_' + $i)
    $packageRoot = Join-Path $runRoot 'PACKAGE'
    $isolatedLocalAppData = Join-Path $runRoot 'LOCALAPPDATA'
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $isolatedLocalAppData -Force | Out-Null
    Copy-Item -LiteralPath $acceptedPackage -Destination $packageRoot -Recurse -Force
    Remove-Item -LiteralPath (Join-Path $packageRoot '_GITHUB_UPDATE') -Recurse -Force -ErrorAction SilentlyContinue

    $oldLocalAppData = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = $isolatedLocalAppData
        Write-Host ('Building run ' + $i + ' with NO -LauncherVersion override...') -ForegroundColor Cyan
        & $canonicalBuilder -PackageRoot $packageRoot -EmitGitHubBundle
    }
    finally {
        $env:LOCALAPPDATA = $oldLocalAppData
    }

    $bundle = Join-Path $packageRoot '_GITHUB_UPDATE'
    if (-not (Test-Path -LiteralPath $bundle -PathType Container)) { throw ('Run ' + $i + ' did not produce _GITHUB_UPDATE.') }
    $files = @(Get-ChildItem -LiteralPath $bundle -File | Select-Object -ExpandProperty Name | Sort-Object)
    $expectedSorted = @($ExpectedFiles | Sort-Object)
    if ($files.Count -ne 5 -or (($files -join "`n") -cne ($expectedSorted -join "`n"))) {
        throw ('Run ' + $i + ' bundle is not exactly five public files. Found: ' + ($files -join ', '))
    }
    if (Test-Path -LiteralPath (Join-Path $bundle 'internal')) { throw ('Run ' + $i + ' bundle unexpectedly contains internal\.') }

    $exe = Join-Path $bundle 'AotR 8P WotR Mod.exe'
    $manifestPath = Join-Path $bundle 'manifest.json'
    $repairPath = Join-Path $bundle 'repair-manifest.json'
    $exeSha = Get-Sha256File $exe
    $uiSha = Get-Sha256File (Join-Path $bundle 'payload_ui.big')
    $paperSha = Get-Sha256File (Join-Path $bundle 'payload_paper.inc')
    $repairSha = Get-Sha256File $repairPath
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifestIdentity = Get-ManifestIdentity $manifest
    $versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
    $peTimestamp = Get-PeTimestamp $exe

    if ([string]$manifest.launcher_version -ne $ExpectedVersion) { throw ('Run ' + $i + ' manifest version mismatch: ' + [string]$manifest.launcher_version) }
    if ([string]$manifest.launcher_sha256 -ne $exeSha) { throw ('Run ' + $i + ' manifest EXE SHA mismatch.') }
    if ([string](Get-Content -LiteralPath $repairPath -Raw | ConvertFrom-Json).generated_for_launcher -ne $ExpectedVersion) { throw ('Run ' + $i + ' repair version mismatch.') }
    if ($uiSha -ne $ExpectedUiSha) { throw ('Run ' + $i + ' UI hash mismatch.') }
    if ($paperSha -ne $ExpectedPaperSha) { throw ('Run ' + $i + ' paper hash mismatch.') }
    if ($repairSha -ne $acceptedRepairSha) { throw ('Run ' + $i + ' repair-manifest bytes differ from accepted final repair-manifest.') }
    if ($manifestIdentity -cne $acceptedManifestIdentity) { throw ('Run ' + $i + ' manifest identity differs from accepted final manifest apart from launcher_sha256.') }
    if ([string]$versionInfo.FileVersion -ne '1.1.1.0') { throw ('Run ' + $i + ' file version mismatch: ' + [string]$versionInfo.FileVersion) }
    if ([string]$versionInfo.ProductVersion -ne '1.1.1') { throw ('Run ' + $i + ' product version mismatch: ' + [string]$versionInfo.ProductVersion) }

    $result = [pscustomobject]@{
        Run = $i
        ExeSha = $exeSha
        Size = (Get-Item -LiteralPath $exe).Length
        PeTimestamp = $peTimestamp
        FileVersion = [string]$versionInfo.FileVersion
        ProductVersion = [string]$versionInfo.ProductVersion
        ManifestIdentity = $manifestIdentity
        RepairSha = $repairSha
        Bundle = $bundle
    }
    $results += $result

    Write-Host ('Run ' + $i + ' EXE SHA                   : ' + $exeSha) -ForegroundColor Green
    Write-Host ('Run ' + $i + ' EXE size                  : ' + $result.Size)
    Write-Host ('Run ' + $i + ' PE TimeDateStamp           : ' + $peTimestamp)
    Write-Host ('Run ' + $i + ' File/Product version       : ' + $result.FileVersion + ' / ' + $result.ProductVersion)
    Write-Host '[PASS] semantic release metadata and payload hashes match accepted 1.1.1' -ForegroundColor Green
    Write-Host ''

    if ($i -eq 1) { Start-Sleep -Seconds 2 }
}

if ($results.Count -ne 2) { throw ('Expected two build results, got ' + $results.Count) }
if ($results[0].ExeSha -eq $results[1].ExeSha) {
    throw ('Two identical-input builds produced the SAME EXE SHA (' + $results[0].ExeSha + '). Byte nondeterminism is not proven; investigate seed/input differences before changing the release gate.')
}
if ($results[0].ManifestIdentity -cne $results[1].ManifestIdentity) { throw 'The two run manifests differ semantically.' }
if ($results[0].RepairSha -ne $results[1].RepairSha) { throw 'The two run repair manifests differ.' }
if ($results[0].FileVersion -ne $results[1].FileVersion -or $results[0].ProductVersion -ne $results[1].ProductVersion) { throw 'The two run version identities differ.' }

$report = Join-Path $diagRoot 'ISSUE33_V18_BUILD_NONDETERMINISM_REPORT.txt'
$lines = @(
    'AOTR 8P WOTR ISSUE #33 V18 BUILD NONDETERMINISM: PASS',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Canonical builder SHA256: ' + $ExpectedCanonicalBuilderSha),
    ('Accepted runtime-tested EXE SHA256: ' + $ExpectedAcceptedExeSha),
    ('Run 1 EXE SHA256: ' + $results[0].ExeSha),
    ('Run 2 EXE SHA256: ' + $results[1].ExeSha),
    ('Run 1 PE TimeDateStamp: ' + $results[0].PeTimestamp),
    ('Run 2 PE TimeDateStamp: ' + $results[1].PeTimestamp),
    ('Run 1 size: ' + $results[0].Size),
    ('Run 2 size: ' + $results[1].Size),
    ('File version both: ' + $results[0].FileVersion),
    ('Product version both: ' + $results[0].ProductVersion),
    ('Repair-manifest SHA256 both: ' + $results[0].RepairSha),
    ('UI SHA256 both: ' + $ExpectedUiSha),
    ('Paper SHA256 both: ' + $ExpectedPaperSha),
    'Conclusion: the legacy V18 .NET Framework csc build path is byte-nondeterministic under identical builder/version/release inputs.',
    'Release implication: pin and ship the exact runtime-tested EXE; validate canonical builder by source/default/semantic equivalence, not by expecting a repeated compile to reproduce the same EXE SHA256.',
    'No GitHub release branch was modified by this diagnostic.'
)
[IO.File]::WriteAllLines($report,$lines,[Text.UTF8Encoding]::new($false))

Write-Host '============================================================' -ForegroundColor Green
Write-Host ' ISSUE #33 V18 BUILD NONDETERMINISM: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('Accepted tested EXE : ' + $ExpectedAcceptedExeSha) -ForegroundColor Green
Write-Host ('Run 1 EXE SHA       : ' + $results[0].ExeSha) -ForegroundColor Green
Write-Host ('Run 2 EXE SHA       : ' + $results[1].ExeSha) -ForegroundColor Green
Write-Host ('Run 1 PE timestamp  : ' + $results[0].PeTimestamp)
Write-Host ('Run 2 PE timestamp  : ' + $results[1].PeTimestamp)
Write-Host ('Canonical builder   : ' + $ExpectedCanonicalBuilderSha) -ForegroundColor Green
Write-Host ('Report              : ' + $report)
Write-Host ''
Write-Host 'NEXT: use the accepted 2141EA... EXE as the frozen release artifact and the 32BC... builder as its canonical 1.1.1 source; do not require byte-identical recompilation.' -ForegroundColor Cyan
