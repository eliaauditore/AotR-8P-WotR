#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceCommit = '5a4c9334c1513f642b63bb034f700e2db7bb3fbc'
$SourcePath = 'research/installer/AOTR_8P_V18_STAGE8_BUILD_1_1_RC2_TOPBAR_POLISH_V1.ps1'
$ExpectedGitBlobSha1 = '5cefd1a710ca213ad349f7e29aaed1d18327132a'
$SourceUrl = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $SourceCommit + '/' + $SourcePath
$SourceTemp = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE10_PRODUCTION_SOURCE.ps1'
$Runtime = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE10_PRODUCTION_RUNTIME.ps1'
Remove-Item $SourceTemp,$Runtime -Force -ErrorAction SilentlyContinue

$ProdManifestUrl = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/manifest.json'
$ProdBinaryUrl = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/AotR%208P%20WotR%20Mod.exe'
$ProdRepairManifestUrl = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/repair-manifest.json'
$ProdUiUrl = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/payload_ui.big'
$ProdPaperUrl = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/payload_paper.inc'

$ExpectedRc2ExeSha256 = 'A3A20BD540E429330F6A97FD30DE6B416EB70426AEF8FD9223C03856B4EBBBF8'
$ExpectedRc2GuiSha256 = '23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C'
$ExpectedRc2SkinSha256 = 'BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6'
$ExpectedUiSha256 = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha256 = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
$ExpectedEngineSha256 = '94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA'

$AllowedRepairActions = @(
    'reset_install','retry_launch','repair_payloads','reset_runtime','stop_old_dev_launchers',
    'stop_legacy_runtime','stop_failed_game','check_launcher_update','clear_compat_cache'
)

function Get-GitBlobSha1([byte[]]$Bytes) {
    $header = [Text.Encoding]::ASCII.GetBytes(('blob ' + $Bytes.Length + [char]0))
    $all = New-Object byte[] ($header.Length + $Bytes.Length)
    [Array]::Copy($header,0,$all,0,$header.Length)
    [Array]::Copy($Bytes,0,$all,$header.Length,$Bytes.Length)
    $sha = [Security.Cryptography.SHA1]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($all))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
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

function Replace-ExactOnce([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $count = 0
    $index = 0
    while (($found = $Text.IndexOf($Old,$index,[StringComparison]::Ordinal)) -ge 0) {
        $count++
        $index = $found + $Old.Length
    }
    if ($count -ne 1) { throw ('Expected exactly one patch target for ' + $Label + ', found ' + $count) }
    return $Text.Replace($Old,$New)
}

function Assert-Hash([string]$Path,[string]$Expected,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ($Label + ' missing: ' + $Path) }
    $actual = Get-Sha256File $Path
    if ($actual -ne $Expected) { throw ($Label + ' hash mismatch. Expected ' + $Expected + ', got ' + $actual) }
    return $actual
}

Invoke-WebRequest -Uri $SourceUrl -OutFile $SourceTemp
$sourceBytes = [IO.File]::ReadAllBytes($SourceTemp)
$blob = Get-GitBlobSha1 $sourceBytes
if ($blob -ne $ExpectedGitBlobSha1) { throw ('Pinned RC2 source blob mismatch. Expected ' + $ExpectedGitBlobSha1 + ', got ' + $blob) }

$text = [Text.UTF8Encoding]::new($false,$true).GetString($sourceBytes)

# Reproduce the exact V1.1 RC2 buffer hardening that produced the user-approved RC2.
$text = Replace-ExactOnce $text '$minusPixels = New-Object ''System.Drawing.Color[,]'' 48,41' '$minusPixels = [Drawing.Color[]]::new(48*41)' '1D minus pixel buffer declaration'
$text = Replace-ExactOnce $text '$minusPixels[$x,$y] = $bmp.GetPixel(726+$x,$y)' '$minusPixels[($y*48)+$x] = $bmp.GetPixel(726+$x,$y)' '1D minus pixel buffer write'
$text = Replace-ExactOnce $text '$bmp.SetPixel(777+$x,$y,$minusPixels[$x,$y])' '$bmp.SetPixel(777+$x,$y,$minusPixels[($y*48)+$x])' '1D minus pixel buffer read'

# Change only the test update endpoints to the production root endpoints.
$text = Replace-ExactOnce $text "`$InvalidManifestUrl = 'https://invalid.invalid/aotr8p-1-1-rc2/manifest.json'" ("`$InvalidManifestUrl = '" + $ProdManifestUrl + "'") 'production manifest URL'
$text = Replace-ExactOnce $text "`$InvalidBinaryUrl = 'https://invalid.invalid/aotr8p-1-1-rc2/AotR%208P%20WotR%20Mod.exe'" ("`$InvalidBinaryUrl = '" + $ProdBinaryUrl + "'") 'production binary URL'

[IO.File]::WriteAllText($Runtime,$text,[Text.UTF8Encoding]::new($false))
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) {
    $errors | Format-List *
    throw 'STOP: Stage10 production runtime has parser errors.'
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P V18 STAGE 10 - BUILD LAUNCHER 1.1 PRODUCTION' -ForegroundColor Cyan
Write-Host ' EXACT USER-APPROVED RC2 LOGIC / REAL UPDATE URLS' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('Pinned RC2 source blob: ' + $ExpectedGitBlobSha1)
Write-Host ('Production manifest URL: ' + $ProdManifestUrl)
Write-Host ('Production binary URL  : ' + $ProdBinaryUrl)
Write-Host ''

$beforeDirs = @(Get-ChildItem -LiteralPath $Base -Directory -Filter 'AUTODETECT_V2_V18_STAGE8_1_1_RC2_*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
& $Runtime -Base $Base
$afterDirs = @(Get-ChildItem -LiteralPath $Base -Directory -Filter 'AUTODETECT_V2_V18_STAGE8_1_1_RC2_*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
$newDirs = @($afterDirs | Where-Object { $_ -notin $beforeDirs })
if ($newDirs.Count -ne 1) { throw ('Expected exactly one new production work root, found ' + $newDirs.Count) }
$workRoot = $newDirs[0]
$packageRoot = Join-Path $workRoot 'PACKAGE'
$bundleRoot = Join-Path $packageRoot '_GITHUB_UPDATE'

$exe = Join-Path $bundleRoot 'AotR 8P WotR Mod.exe'
$manifestPath = Join-Path $bundleRoot 'manifest.json'
$repairPath = Join-Path $bundleRoot 'repair-manifest.json'
$uiPath = Join-Path $bundleRoot 'payload_ui.big'
$paperPath = Join-Path $bundleRoot 'payload_paper.inc'
$skinPath = Join-Path $packageRoot 'internal\assets\launcher_skin.png'
foreach ($p in @($exe,$manifestPath,$repairPath,$uiPath,$paperPath,$skinPath)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw ('Production output missing: ' + $p) }
}

$exeSha = Get-Sha256File $exe
$skinSha = Assert-Hash $skinPath $ExpectedRc2SkinSha256 'RC2 production skin'
$uiSha = Assert-Hash $uiPath $ExpectedUiSha256 'Production UI'
$paperSha = Assert-Hash $paperPath $ExpectedPaperSha256 'Production Paper'

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ([int]$manifest.schema -ne 1) { throw 'Production manifest schema is not 1.' }
if ([string]$manifest.launcher_version -ne '1.1') { throw ('Production launcher_version mismatch: ' + [string]$manifest.launcher_version) }
if ([string]$manifest.launcher_url -ne $ProdBinaryUrl) { throw 'Production launcher_url mismatch.' }
if ([string]$manifest.launcher_sha256 -ne $exeSha) { throw 'Production launcher_sha256 does not match built EXE.' }
if ([string]$manifest.repair_manifest_url -ne $ProdRepairManifestUrl) { throw 'Production repair_manifest_url mismatch.' }
if ([string]$manifest.ui_url -ne $ProdUiUrl) { throw 'Production ui_url mismatch.' }
if ([string]$manifest.ui_sha256 -ne $ExpectedUiSha256) { throw 'Production ui_sha256 mismatch.' }
if ([string]$manifest.paper_url -ne $ProdPaperUrl) { throw 'Production paper_url mismatch.' }
if ([string]$manifest.paper_sha256 -ne $ExpectedPaperSha256) { throw 'Production paper_sha256 mismatch.' }

$repair = Get-Content -LiteralPath $repairPath -Raw | ConvertFrom-Json
if ([int]$repair.schema -ne 1) { throw 'Repair manifest schema is not 1.' }
if ([string]$repair.generated_for_launcher -ne '1.1') { throw ('Repair manifest generated_for_launcher mismatch: ' + [string]$repair.generated_for_launcher) }
$actions = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
foreach ($prop in $repair.plans.PSObject.Properties) {
    foreach ($action in @($prop.Value.actions)) { [void]$actions.Add([string]$action) }
}
$unknown = @($actions | Where-Object { $_ -notin $AllowedRepairActions })
if ($unknown.Count -gt 0) { throw ('Repair manifest contains unproven actions: ' + ($unknown -join ', ')) }

# Production must differ from RC2 EXE because the embedded update URLs are now real.
if ($exeSha -eq $ExpectedRc2ExeSha256) { throw 'Production EXE unexpectedly equals RC2 EXE despite production URL change.' }

$report = Join-Path $workRoot 'V18_STAGE10_LAUNCHER_1_1_PRODUCTION_BUILD_REPORT.txt'
$lines = @(
    'AOTR 8P V18 STAGE10 LAUNCHER 1.1 PRODUCTION BUILD',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('User-approved RC2 EXE SHA256: ' + $ExpectedRc2ExeSha256),
    ('User-approved RC2 GUI SHA256: ' + $ExpectedRc2GuiSha256),
    ('User-approved RC2 skin SHA256: ' + $ExpectedRc2SkinSha256),
    ('Expected ENGINE SHA256: ' + $ExpectedEngineSha256),
    ('Production EXE SHA256: ' + $exeSha),
    ('Production skin SHA256: ' + $skinSha),
    ('Production UI SHA256: ' + $uiSha),
    ('Production Paper SHA256: ' + $paperSha),
    ('Production manifest: ' + $manifestPath),
    ('Production repair manifest: ' + $repairPath),
    ('Bundle root: ' + $bundleRoot),
    '',
    'PRODUCTION ASSERTIONS',
    '- launcher_version = 1.1: PASS',
    '- real launcher URL: PASS',
    '- launcher_sha256 matches EXE: PASS',
    '- repair manifest URL: PASS',
    '- UI URL + SHA: PASS',
    '- Paper URL + SHA: PASS',
    '- repair manifest generated_for_launcher = 1.1: PASS',
    '- repair actions restricted to proven dispatcher actions: PASS',
    '- RC2 skin byte-identical to user-approved visual candidate: PASS',
    '- public repository root NOT modified by this runner: PASS'
)
[IO.File]::WriteAllLines($report,$lines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' STAGE 10 - LAUNCHER 1.1 PRODUCTION BUILD: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('Production EXE SHA : ' + $exeSha) -ForegroundColor Green
Write-Host ('Production skin SHA: ' + $skinSha) -ForegroundColor Green
Write-Host ('Bundle root        : ' + $bundleRoot)
Write-Host ('Report             : ' + $report)
Write-Host ''
Write-Host 'DO NOT publish yet. Send this complete output back for the final five-file promotion gate.' -ForegroundColor Yellow
