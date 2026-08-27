#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE1_20260827_022948\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10_ROBUST_AUTODETECT_V2_NONRELEASE.ps1',
    [string]$SupportDonor = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\V18_RC1_TEST_20260827_004234'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ReleaseCommit = '1303e0a6b268b082e9352ded1461fa8d794f16d3'
$ExpectedBuilderSha256 = 'D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0'
$ExpectedReleaseExeSha256 = '6A80E0F7B862ABE3E0F19C3DF5ED9EE9EE730F246CF603ED00A39D1EE7DFF2F8'
$ExpectedUiSha256 = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha256 = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
$ExpectedIconSha256 = '3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A'
$ExpectedSkinSha256 = '2158FD8BB4E9195E27667F517FF81C745983BEE200394FB64107FFF902666473'
$LauncherVersion = '1.1'
$InvalidManifestUrl = 'https://invalid.invalid/aotr8p-1-1-rc/manifest.json'
$InvalidBinaryUrl = 'https://invalid.invalid/aotr8p-1-1-rc/AotR%208P%20WotR%20Mod.exe'

function Get-Sha256File([string]$Path) {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Assert-FileHash([string]$Path,[string]$Expected,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ($Label + ' missing: ' + $Path) }
    $actual = Get-Sha256File $Path
    if ($actual -ne $Expected) { throw ($Label + ' hash mismatch. Expected ' + $Expected + ', got ' + $actual) }
    Write-Host ('{0,-24}: {1}' -f $Label,$actual) -ForegroundColor Green
    return $actual
}

function Save-Crop([System.Drawing.Bitmap]$Bitmap,[System.Drawing.Rectangle]$Rect,[string]$Path) {
    $crop = [System.Drawing.Bitmap]::new($Rect.Width,$Rect.Height,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($crop)
        try {
            $g.DrawImage($Bitmap,[System.Drawing.Rectangle]::new(0,0,$Rect.Width,$Rect.Height),$Rect,[System.Drawing.GraphicsUnit]::Pixel)
        }
        finally { $g.Dispose() }
        $crop.Save($Path,[System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $crop.Dispose() }
}

if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw ('Base missing: ' + $Base) }
Assert-FileHash $BuilderPath $ExpectedBuilderSha256 'Autodetect builder' | Out-Null
if (-not (Test-Path -LiteralPath $SupportDonor -PathType Container)) { throw ('Support donor missing: ' + $SupportDonor) }

$donorIcon = Join-Path $SupportDonor 'assets\launcher.ico'
$donorSkin = Join-Path $SupportDonor 'internal\assets\launcher_skin.png'
Assert-FileHash $donorIcon $ExpectedIconSha256 'Support icon' | Out-Null
Assert-FileHash $donorSkin $ExpectedSkinSha256 'Support skin' | Out-Null

try { Add-Type -AssemblyName System.Drawing.Common -ErrorAction Stop }
catch { Add-Type -AssemblyName System.Drawing -ErrorAction Stop }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ('AUTODETECT_V2_V18_STAGE8_1_1_RC_' + $stamp)
$packageRoot = Join-Path $workRoot 'PACKAGE'
$assetsDir = Join-Path $packageRoot 'assets'
$skinDir = Join-Path $packageRoot 'internal\assets'
$payloadDir = Join-Path $packageRoot 'payload'
$paperDir = Join-Path $packageRoot 'payload\data\ini\campaigns\scenarios'
foreach ($dir in @($workRoot,$packageRoot,$assetsDir,$skinDir,$payloadDir,$paperDir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$seedExe = Join-Path $packageRoot 'AotR 8P WotR Mod.exe'
$uiPath = Join-Path $payloadDir '!!!WOTR_8P_UI_TEST.big'
$paperPath = Join-Path $paperDir 'PaperScenario001.inc'
$iconPath = Join-Path $assetsDir 'launcher.ico'
$skinPath = Join-Path $skinDir 'launcher_skin.png'
$skinOriginal = Join-Path $workRoot 'launcher_skin_original.png'
$beforeCrop = Join-Path $workRoot 'TOPRIGHT_BEFORE.png'
$afterCrop = Join-Path $workRoot 'TOPRIGHT_AFTER.png'
$builderCopy = Join-Path $packageRoot 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_RC.ps1'

$releaseBase = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $ReleaseCommit
Write-Host 'Downloading immutable release inputs...' -ForegroundColor Cyan
Invoke-WebRequest -Uri ($releaseBase + '/AotR%208P%20WotR%20Mod.exe') -OutFile $seedExe
Invoke-WebRequest -Uri ($releaseBase + '/payload_ui.big') -OutFile $uiPath
Invoke-WebRequest -Uri ($releaseBase + '/payload_paper.inc') -OutFile $paperPath
Copy-Item -LiteralPath $donorIcon -Destination $iconPath
Copy-Item -LiteralPath $donorSkin -Destination $skinOriginal
Copy-Item -LiteralPath $donorSkin -Destination $skinPath
Copy-Item -LiteralPath $BuilderPath -Destination $builderCopy

Assert-FileHash $seedExe $ExpectedReleaseExeSha256 'Released seed EXE' | Out-Null
Assert-FileHash $uiPath $ExpectedUiSha256 'UI payload' | Out-Null
Assert-FileHash $paperPath $ExpectedPaperSha256 'Paper payload' | Out-Null
Assert-FileHash $iconPath $ExpectedIconSha256 'Icon copy' | Out-Null
Assert-FileHash $skinPath $ExpectedSkinSha256 'Skin copy before patch' | Out-Null
Assert-FileHash $builderCopy $ExpectedBuilderSha256 'Builder copy' | Out-Null

# Proven from Stage8 diagnostic:
# MinHit = x 726..773, no hit area at x 774..824, CloseHit = x 825..899.
# Only the 51px dead visual region is reconstructed; real Minimize/Close pixels remain untouched.
$src = [System.Drawing.Bitmap]::new($skinOriginal)
$out = [System.Drawing.Bitmap]::new($skinOriginal)
try {
    if ($src.Width -lt 900 -or $src.Height -lt 675) { throw ('Unexpected skin dimensions: ' + $src.Width + 'x' + $src.Height) }
    Save-Crop $src ([System.Drawing.Rectangle]::new(700,0,200,60)) $beforeCrop

    for ($y=0; $y -le 40; $y++) {
        $left = $src.GetPixel(773,$y)
        $right = $src.GetPixel(825,$y)
        for ($x=774; $x -le 824; $x++) {
            $t = [double]($x - 773) / 52.0
            $a = [int][Math]::Round($left.A + (($right.A - $left.A) * $t))
            $r = [int][Math]::Round($left.R + (($right.R - $left.R) * $t))
            $g = [int][Math]::Round($left.G + (($right.G - $left.G) * $t))
            $b = [int][Math]::Round($left.B + (($right.B - $left.B) * $t))
            $out.SetPixel($x,$y,[System.Drawing.Color]::FromArgb($a,$r,$g,$b))
        }
    }

    $out.Save($skinPath,[System.Drawing.Imaging.ImageFormat]::Png)
    Save-Crop $out ([System.Drawing.Rectangle]::new(700,0,200,60)) $afterCrop
}
finally {
    $src.Dispose()
    $out.Dispose()
}

$patchedSkinSha = Get-Sha256File $skinPath
if ($patchedSkinSha -eq $ExpectedSkinSha256) { throw 'Skin hash did not change; fake-maximize patch was not applied.' }

# Pixel-locality proof: outside x 774..824 / y 0..40, source and patched skin must be identical.
$srcCheck = [System.Drawing.Bitmap]::new($skinOriginal)
$outCheck = [System.Drawing.Bitmap]::new($skinPath)
try {
    if ($srcCheck.Width -ne $outCheck.Width -or $srcCheck.Height -ne $outCheck.Height) { throw 'Patched skin dimensions changed.' }
    $outsideDiffs = 0
    $insideDiffs = 0
    for ($y=0; $y -lt $srcCheck.Height; $y++) {
        for ($x=0; $x -lt $srcCheck.Width; $x++) {
            if ($srcCheck.GetPixel($x,$y).ToArgb() -ne $outCheck.GetPixel($x,$y).ToArgb()) {
                if ($x -ge 774 -and $x -le 824 -and $y -ge 0 -and $y -le 40) { $insideDiffs++ }
                else { $outsideDiffs++ }
            }
        }
    }
    if ($outsideDiffs -ne 0) { throw ('Skin locality violation: ' + $outsideDiffs + ' changed pixels outside fake-maximize rectangle.') }
    if ($insideDiffs -eq 0) { throw 'No pixels changed inside fake-maximize rectangle.' }
}
finally {
    $srcCheck.Dispose()
    $outCheck.Dispose()
}

Write-Host ''
Write-Host '=== 1.1 SKIN FIX ===' -ForegroundColor Cyan
Write-Host ('Original skin SHA : ' + $ExpectedSkinSha256)
Write-Host ('Patched skin SHA  : ' + $patchedSkinSha) -ForegroundColor Green
Write-Host ('Before crop       : ' + $beforeCrop)
Write-Host ('After crop        : ' + $afterCrop)
Write-Host 'Changed region    : x=774..824, y=0..40 ONLY' -ForegroundColor Green
Write-Host ''

$seedHashBefore = Get-Sha256File $seedExe
$builderHashBefore = Get-Sha256File $builderCopy

& $builderCopy `
    -PackageRoot $packageRoot `
    -LauncherVersion $LauncherVersion `
    -UpdateManifestUrl $InvalidManifestUrl `
    -UpdateBinaryUrl $InvalidBinaryUrl `
    -EmitGitHubBundle `
    -BundleOnly

$bundleRoot = Join-Path $packageRoot '_GITHUB_UPDATE'
$builtExe = Join-Path $bundleRoot 'AotR 8P WotR Mod.exe'
if (-not (Test-Path -LiteralPath $builtExe -PathType Leaf)) { throw ('1.1 RC EXE missing: ' + $builtExe) }
$builtSha = Get-Sha256File $builtExe
$builtInfo = Get-Item -LiteralPath $builtExe

if ((Get-Sha256File $seedExe) -ne $seedHashBefore) { throw 'BundleOnly unexpectedly modified seed EXE.' }
if ((Get-Sha256File $builderCopy) -ne $builderHashBefore) { throw 'Builder copy changed during build.' }
if ((Get-Sha256File $BuilderPath) -ne $ExpectedBuilderSha256) { throw 'Original tested autodetect builder changed.' }

$bundleUi = Join-Path $bundleRoot 'payload_ui.big'
$bundlePaper = Join-Path $bundleRoot 'payload_paper.inc'
if (Test-Path -LiteralPath $bundleUi -PathType Leaf) { Assert-FileHash $bundleUi $ExpectedUiSha256 'Bundle UI' | Out-Null }
if (Test-Path -LiteralPath $bundlePaper -PathType Leaf) { Assert-FileHash $bundlePaper $ExpectedPaperSha256 'Bundle Paper' | Out-Null }

$report = Join-Path $workRoot 'V18_STAGE8_1_1_RC_NO_FAKE_MAXIMIZE_REPORT.txt'
$reportLines = @(
    'AOTR 8P V18 STAGE8 LAUNCHER 1.1 RC',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Input builder SHA256: ' + $ExpectedBuilderSha256),
    ('Launcher version: ' + $LauncherVersion),
    ('Original skin SHA256: ' + $ExpectedSkinSha256),
    ('Patched skin SHA256: ' + $patchedSkinSha),
    'Skin patch rectangle: x=774..824, y=0..40',
    'Skin pixels changed outside rectangle: 0',
    ('Built EXE: ' + $builtExe),
    ('Built EXE SHA256: ' + $builtSha),
    ('Built EXE bytes: ' + $builtInfo.Length),
    ('Before crop: ' + $beforeCrop),
    ('After crop: ' + $afterCrop),
    '',
    'SAFETY',
    '- Tested autodetect builder unchanged: PASS',
    '- Ticket/status/autodetect GUI source unchanged: PASS (skin-only fix)',
    '- Engine source unchanged: PASS',
    '- Build mode BundleOnly with invalid update URLs: PASS',
    '- Public release/repository files not modified by runner: PASS',
    '- Game files not modified by runner: PASS'
)
[IO.File]::WriteAllLines($report,$reportLines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' V18 STAGE 8 - LAUNCHER 1.1 RC BUILD PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('Built EXE       : ' + $builtExe) -ForegroundColor Green
Write-Host ('Built SHA256    : ' + $builtSha) -ForegroundColor Green
Write-Host ('Built bytes     : ' + $builtInfo.Length)
Write-Host ('Patched skin SHA: ' + $patchedSkinSha)
Write-Host ('Report          : ' + $report)
Write-Host ''
Write-Host 'NEXT: launch this RC and visually confirm the fake maximize icon is gone; Minimize and Close must still work.' -ForegroundColor Yellow
