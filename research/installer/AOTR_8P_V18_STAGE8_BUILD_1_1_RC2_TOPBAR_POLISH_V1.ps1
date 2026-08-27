#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE1_20260827_022948\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10_ROBUST_AUTODETECT_V2_NONRELEASE.ps1',
    [string]$SupportDonor = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\V18_RC1_TEST_20260827_004234'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing

$ReleaseCommit = '1303e0a6b268b082e9352ded1461fa8d794f16d3'
$ExpectedBuilderSha256 = 'D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0'
$ExpectedGuiSha256 = 'CFAF397833536769D726B0DD0960D940AAA6896ED62BFEFA0764185C2CEA90DC'
$ExpectedEngineSha256 = '94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA'
$ExpectedReleaseExeSha256 = '6A80E0F7B862ABE3E0F19C3DF5ED9EE9EE730F246CF603ED00A39D1EE7DFF2F8'
$ExpectedUiSha256 = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha256 = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
$ExpectedIconSha256 = '3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A'
$ExpectedOriginalSkinSha256 = '2158FD8BB4E9195E27667F517FF81C745983BEE200394FB64107FFF902666473'
$LauncherVersion = '1.1'
$InvalidManifestUrl = 'https://invalid.invalid/aotr8p-1-1-rc2/manifest.json'
$InvalidBinaryUrl = 'https://invalid.invalid/aotr8p-1-1-rc2/AotR%208P%20WotR%20Mod.exe'

function Get-Sha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
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

function Assert-FileHash([string]$Path,[string]$Expected,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ($Label + ' missing: ' + $Path) }
    $actual = Get-Sha256File $Path
    if ($actual -ne $Expected) { throw ($Label + ' hash mismatch. Expected ' + $Expected + ', got ' + $actual) }
    Write-Host (('{0,-26}: {1}' -f $Label,$actual)) -ForegroundColor Green
    return $actual
}

function Get-Utf8Text([byte[]]$Bytes) {
    $offset = 0
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { $offset = 3 }
    return [Text.UTF8Encoding]::new($false,$true).GetString($Bytes,$offset,$Bytes.Length-$offset)
}

function Convert-TextToUtf8LikeOriginal([string]$Text,[byte[]]$OriginalBytes) {
    $hadBom = ($OriginalBytes.Length -ge 3 -and $OriginalBytes[0] -eq 0xEF -and $OriginalBytes[1] -eq 0xBB -and $OriginalBytes[2] -eq 0xBF)
    if ($Text.Length -gt 0 -and [int][char]$Text[0] -eq 0xFEFF) { $Text = $Text.Substring(1) }
    $body = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    if (-not $hadBom) { return $body }
    $result = New-Object byte[] ($body.Length + 3)
    $result[0] = 0xEF; $result[1] = 0xBB; $result[2] = 0xBF
    [Array]::Copy($body,0,$result,3,$body.Length)
    return $result
}

function Expand-GzipBase64Bytes([string]$Base64) {
    $compressed = [Convert]::FromBase64String(($Base64 -replace '\s',''))
    $input = [IO.MemoryStream]::new($compressed)
    try {
        $gzip = [IO.Compression.GZipStream]::new($input,[IO.Compression.CompressionMode]::Decompress)
        try {
            $output = [IO.MemoryStream]::new()
            try { $gzip.CopyTo($output); return $output.ToArray() }
            finally { $output.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally { $input.Dispose() }
}

function Compress-BytesToGzipBase64([byte[]]$Bytes) {
    $output = [IO.MemoryStream]::new()
    try {
        $gzip = [IO.Compression.GZipStream]::new($output,[IO.Compression.CompressionMode]::Compress,$true)
        try { $gzip.Write($Bytes,0,$Bytes.Length) }
        finally { $gzip.Dispose() }
        return [Convert]::ToBase64String($output.ToArray())
    }
    finally { $output.Dispose() }
}

function Wrap-Base64([string]$Text,[int]$Width=120) {
    $parts = New-Object System.Collections.Generic.List[string]
    for ($i=0; $i -lt $Text.Length; $i += $Width) {
        $len = [Math]::Min($Width,$Text.Length-$i)
        [void]$parts.Add($Text.Substring($i,$len))
    }
    return ($parts -join "`r`n")
}

function Test-PowerShellText([string]$Text,[string]$Label) {
    $parseText = $Text
    if ($parseText.Length -gt 0 -and [int][char]$parseText[0] -eq 0xFEFF) { $parseText = $parseText.Substring(1) }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($parseText,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) {
        $msg = ($errors | ForEach-Object { 'Line ' + $_.Extent.StartLineNumber + ', Col ' + $_.Extent.StartColumnNumber + ': ' + $_.Message }) -join [Environment]::NewLine
        throw ('Parser validation failed for ' + $Label + [Environment]::NewLine + $msg)
    }
}

function Get-OuterInfo([string]$BuilderText) {
    $pattern = '(?s)(?<before>\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\s*)(?<data>[A-Za-z0-9+/=\r\n]+?)(?<after>\s*''@\)\))'
    $m = [regex]::Match($BuilderText,$pattern)
    if (-not $m.Success) { throw 'Could not locate outer C# Base64 template.' }
    $bytes = [Convert]::FromBase64String(($m.Groups['data'].Value -replace '\s',''))
    return [PSCustomObject]@{ Match=$m; Bytes=$bytes; Text=(Get-Utf8Text $bytes) }
}

function Get-PayloadInfo([string]$CSharp,[string]$Name) {
    $pattern = '(?s)(?:private\s+)?const\s+string\s+' + [regex]::Escape($Name) + '\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
    $m = [regex]::Match($CSharp,$pattern)
    if (-not $m.Success) { throw ('Could not locate payload ' + $Name + '.') }
    $bytes = Expand-GzipBase64Bytes $m.Groups['data'].Value
    return [PSCustomObject]@{ Match=$m; Bytes=$bytes; Text=(Get-Utf8Text $bytes); Sha256=(Get-Sha256Bytes $bytes) }
}

function Replace-Payload([string]$CSharp,[string]$Name,[byte[]]$NewBytes) {
    $info = Get-PayloadInfo $CSharp $Name
    $newB64 = Wrap-Base64 (Compress-BytesToGzipBase64 $NewBytes)
    $g = $info.Match.Groups['data']
    return $CSharp.Substring(0,$g.Index) + $newB64 + $CSharp.Substring($g.Index+$g.Length)
}

function Count-Matches([string]$Text,[string]$Pattern) {
    return @([regex]::Matches($Text,$Pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
}

function Save-Crop([System.Drawing.Bitmap]$Bitmap,[string]$Path,[int]$X,[int]$Y,[int]$Width,[int]$Height) {
    $rect = New-Object System.Drawing.Rectangle($X,$Y,$Width,$Height)
    $crop = $Bitmap.Clone($rect,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try { $crop.Save($Path,[Drawing.Imaging.ImageFormat]::Png) }
    finally { $crop.Dispose() }
}

if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw ('Base missing: ' + $Base) }
[void](Assert-FileHash $BuilderPath $ExpectedBuilderSha256 'Autodetect builder')
if (-not (Test-Path -LiteralPath $SupportDonor -PathType Container)) { throw ('Support donor missing: ' + $SupportDonor) }

$donorIcon = Join-Path $SupportDonor 'assets\launcher.ico'
$donorSkin = Join-Path $SupportDonor 'internal\assets\launcher_skin.png'
[void](Assert-FileHash $donorIcon $ExpectedIconSha256 'Support icon')
[void](Assert-FileHash $donorSkin $ExpectedOriginalSkinSha256 'Original skin')

# --- Patch only the main WPF MinHit XAML position in the pinned builder. ---
$builderBytes = [IO.File]::ReadAllBytes($BuilderPath)
$builderText = Get-Utf8Text $builderBytes
Test-PowerShellText $builderText 'pinned builder'
$outer = Get-OuterInfo $builderText
$gui = Get-PayloadInfo $outer.Text 'GuiGzipBase64'
$engine = Get-PayloadInfo $outer.Text 'EngineGzipBase64'
if ($gui.Sha256 -ne $ExpectedGuiSha256) { throw ('GUI hash mismatch. Expected ' + $ExpectedGuiSha256 + ', got ' + $gui.Sha256) }
if ($engine.Sha256 -ne $ExpectedEngineSha256) { throw ('ENGINE hash mismatch. Expected ' + $ExpectedEngineSha256 + ', got ' + $engine.Sha256) }

$protected = [ordered]@{
    ReportError = 'REPORT ERROR'; Messages = '\bMESSAGES\b'; ReportReady = '\bReportReady\b'; Fingerprint = 'A8P-FP-';
    AutoRepair = 'AUTO-REPAIR|Auto-Repair'; StatusRowsHost = '\bStatusRowsHost\b'; StatusGameText = '\bStatusGameText\b';
    StatusCampaignText = '\bStatusCampaignText\b'; StatusUiText = '\bStatusUiText\b'; OverallStatusText = '\bOverallStatusText\b';
    SetStatusChecking = 'function\s+Set-StatusChecking\b'; GetFileHash = '\bGet-FileHash\b'; SyntheticHook = 'A8P_TEST_FORCE_ERROR|A8P-TEST-001'
}
$expectedCounts = [ordered]@{
    ReportError=6; Messages=11; ReportReady=13; Fingerprint=3; AutoRepair=4; StatusRowsHost=1;
    StatusGameText=6; StatusCampaignText=6; StatusUiText=6; OverallStatusText=9; SetStatusChecking=1; GetFileHash=0; SyntheticHook=0
}
$beforeCounts = @{}
foreach ($key in $protected.Keys) {
    $beforeCounts[$key] = Count-Matches $gui.Text $protected[$key]
    if ($beforeCounts[$key] -ne $expectedCounts[$key]) { throw ('Protected GUI baseline mismatch for ' + $key) }
}
if ((Count-Matches $engine.Text 'FINAL_STABLE_V7') -ne 7) { throw 'ENGINE FINAL_STABLE_V7 baseline mismatch.' }
if ((Count-Matches $engine.Text '\bGet-FileHash\b') -ne 0) { throw 'ENGINE Get-FileHash regression present.' }
if (-not $gui.Text.Contains('WindowStyle="None"')) { throw 'Main WPF WindowStyle=None marker missing.' }
if (-not $gui.Text.Contains('ResizeMode="NoResize"')) { throw 'Main WPF ResizeMode=NoResize marker missing.' }

$minPattern = '(?ms)(<Border\s+x:Name="MinHit"\s*\r?\n\s*Canvas\.Left=")726("\s+Canvas\.Top="0"\s*\r?\n\s*Width="48"\s+Height="41")'
$minMatches = @([regex]::Matches($gui.Text,$minPattern))
if ($minMatches.Count -ne 1) { throw ('Expected exactly one MinHit x=726 target, found ' + $minMatches.Count) }
$newGuiText = [regex]::Replace($gui.Text,$minPattern,'${1}777${2}',1)
if ((Count-Matches $newGuiText 'x:Name="MinHit"') -ne 1) { throw 'MinHit count changed unexpectedly.' }
if (-not $newGuiText.Contains('x:Name="CloseHit"')) { throw 'CloseHit marker missing after patch.' }
if (-not $newGuiText.Contains('Canvas.Left="825" Canvas.Top="0"')) { throw 'CloseHit x=825 marker missing after patch.' }
Test-PowerShellText $newGuiText 'RC2 GUI'
foreach ($key in $protected.Keys) {
    $after = Count-Matches $newGuiText $protected[$key]
    if ($after -ne $beforeCounts[$key]) { throw ('Protected GUI marker count changed for ' + $key + ': ' + $beforeCounts[$key] + ' -> ' + $after) }
}
if (-not $newGuiText.Contains("validation = 'aotr-standalone-v2'")) { throw 'Config V2 marker missing after topbar patch.' }

$newGuiBytes = Convert-TextToUtf8LikeOriginal $newGuiText $gui.Bytes
$newCSharpText = Replace-Payload $outer.Text 'GuiGzipBase64' $newGuiBytes
$newCSharpBytes = Convert-TextToUtf8LikeOriginal $newCSharpText $outer.Bytes
$outerGroup = $outer.Match.Groups['data']
$newOuterB64 = Wrap-Base64 ([Convert]::ToBase64String($newCSharpBytes))
$newBuilderText = $builderText.Substring(0,$outerGroup.Index) + $newOuterB64 + $builderText.Substring($outerGroup.Index+$outerGroup.Length)
$newBuilderBytes = Convert-TextToUtf8LikeOriginal $newBuilderText $builderBytes
Test-PowerShellText (Get-Utf8Text $newBuilderBytes) 'RC2 patched builder'

# Verify round-trip payloads before writing anything executable.
$verifyOuter = Get-OuterInfo (Get-Utf8Text $newBuilderBytes)
$verifyGui = Get-PayloadInfo $verifyOuter.Text 'GuiGzipBase64'
$verifyEngine = Get-PayloadInfo $verifyOuter.Text 'EngineGzipBase64'
if ($verifyEngine.Sha256 -ne $ExpectedEngineSha256) { throw 'ENGINE changed during RC2 builder patch.' }
if ($verifyGui.Sha256 -eq $ExpectedGuiSha256) { throw 'GUI hash did not change after MinHit patch.' }
if (-not $verifyGui.Text.Contains('Canvas.Left="777" Canvas.Top="0"')) { throw 'Round-trip GUI does not contain MinHit x=777.' }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ('AUTODETECT_V2_V18_STAGE8_1_1_RC2_' + $stamp)
$packageRoot = Join-Path $workRoot 'PACKAGE'
$assetsDir = Join-Path $packageRoot 'assets'
$skinDir = Join-Path $packageRoot 'internal\assets'
$payloadDir = Join-Path $packageRoot 'payload'
$paperDir = Join-Path $payloadDir 'data\ini\campaigns\scenarios'
foreach ($dir in @($workRoot,$packageRoot,$assetsDir,$skinDir,$payloadDir,$paperDir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$patchedBuilder = Join-Path $workRoot 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_RC2_TOPBAR_POLISH_NONRELEASE.ps1'
[IO.File]::WriteAllBytes($patchedBuilder,$newBuilderBytes)
$newBuilderSha = Get-Sha256File $patchedBuilder

$seedExe = Join-Path $packageRoot 'AotR 8P WotR Mod.exe'
$uiPath = Join-Path $payloadDir '!!!WOTR_8P_UI_TEST.big'
$paperPath = Join-Path $paperDir 'PaperScenario001.inc'
$iconPath = Join-Path $assetsDir 'launcher.ico'
$skinPath = Join-Path $skinDir 'launcher_skin.png'

$releaseBase = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $ReleaseCommit
Write-Host 'Downloading immutable release inputs...' -ForegroundColor Cyan
Invoke-WebRequest -Uri ($releaseBase + '/AotR%208P%20WotR%20Mod.exe') -OutFile $seedExe
Invoke-WebRequest -Uri ($releaseBase + '/payload_ui.big') -OutFile $uiPath
Invoke-WebRequest -Uri ($releaseBase + '/payload_paper.inc') -OutFile $paperPath
Copy-Item -LiteralPath $donorIcon -Destination $iconPath
Copy-Item -LiteralPath $donorSkin -Destination $skinPath

[void](Assert-FileHash $seedExe $ExpectedReleaseExeSha256 'Released seed EXE')
[void](Assert-FileHash $uiPath $ExpectedUiSha256 'UI payload')
[void](Assert-FileHash $paperPath $ExpectedPaperSha256 'Paper payload')
[void](Assert-FileHash $iconPath $ExpectedIconSha256 'Icon copy')
[void](Assert-FileHash $skinPath $ExpectedOriginalSkinSha256 'Skin before polish')

# --- Skin polish: preserve X at far right, move only minus directly next to it. ---
$sourceImage = [Drawing.Image]::FromFile($skinPath)
try {
    if ($sourceImage.Width -ne 900 -or $sourceImage.Height -ne 675) { throw ('Unexpected skin dimensions: ' + $sourceImage.Width + 'x' + $sourceImage.Height) }
    $bmp = New-Object Drawing.Bitmap(900,675,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    try { $g.DrawImage($sourceImage,0,0,900,675) }
    finally { $g.Dispose() }
}
finally { $sourceImage.Dispose() }

$beforeCrop = Join-Path $workRoot 'TOPRIGHT_BEFORE.png'
$afterCrop = Join-Path $workRoot 'TOPRIGHT_AFTER.png'
Save-Crop $bmp $beforeCrop 680 0 220 70

$minusPixels = New-Object 'System.Drawing.Color[,]' 48,41
for ($x=0; $x -lt 48; $x++) {
    for ($y=0; $y -lt 41; $y++) { $minusPixels[$x,$y] = $bmp.GetPixel(726+$x,$y) }
}

# Clear the entire original two-slot area (old Minimize + fake Maximize) using row-wise background interpolation.
# Endpoints x=725 and x=825 are outside the modified range; x=825 is the left edge of CloseHit and visually background there.
for ($y=0; $y -lt 41; $y++) {
    $left = $bmp.GetPixel(725,$y)
    $right = $bmp.GetPixel(825,$y)
    for ($x=726; $x -le 824; $x++) {
        $t = [double]($x-725) / 100.0
        $a = [int][Math]::Round($left.A + (($right.A-$left.A)*$t))
        $r = [int][Math]::Round($left.R + (($right.R-$left.R)*$t))
        $gg = [int][Math]::Round($left.G + (($right.G-$left.G)*$t))
        $b = [int][Math]::Round($left.B + (($right.B-$left.B)*$t))
        $bmp.SetPixel($x,$y,[Drawing.Color]::FromArgb($a,$r,$gg,$b))
    }
}

# Paste the original 48x41 Minimize artwork at x=777..824, immediately adjacent to CloseHit at x=825.
for ($x=0; $x -lt 48; $x++) {
    for ($y=0; $y -lt 41; $y++) { $bmp.SetPixel(777+$x,$y,$minusPixels[$x,$y]) }
}

Save-Crop $bmp $afterCrop 680 0 220 70
$bmp.Save($skinPath,[Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$patchedSkinSha = Get-Sha256File $skinPath
if ($patchedSkinSha -eq $ExpectedOriginalSkinSha256) { throw 'Skin hash did not change.' }

Write-Host ''
Write-Host '=== 1.1 RC2 TOPBAR POLISH ===' -ForegroundColor Cyan
Write-Host ('Patched builder SHA: ' + $newBuilderSha)
Write-Host ('Patched GUI SHA    : ' + $verifyGui.Sha256)
Write-Host ('ENGINE SHA         : ' + $verifyEngine.Sha256) -ForegroundColor Green
Write-Host ('Patched skin SHA   : ' + $patchedSkinSha)
Write-Host ('Before crop        : ' + $beforeCrop)
Write-Host ('After crop         : ' + $afterCrop)
Write-Host 'Visual layout       : background | Minimize x=777..824 | Close x=825..899' -ForegroundColor Green
Write-Host 'Functional MinHit   : moved from x=726 to x=777; CloseHit unchanged at x=825' -ForegroundColor Green

& $patchedBuilder `
    -PackageRoot $packageRoot `
    -LauncherVersion $LauncherVersion `
    -UpdateManifestUrl $InvalidManifestUrl `
    -UpdateBinaryUrl $InvalidBinaryUrl `
    -EmitGitHubBundle `
    -BundleOnly

$bundleRoot = Join-Path $packageRoot '_GITHUB_UPDATE'
$builtExe = Join-Path $bundleRoot 'AotR 8P WotR Mod.exe'
if (-not (Test-Path -LiteralPath $builtExe -PathType Leaf)) { throw ('RC2 build did not produce EXE: ' + $builtExe) }
$builtSha = Get-Sha256File $builtExe
$builtInfo = Get-Item -LiteralPath $builtExe
$bundleUi = Join-Path $bundleRoot 'payload_ui.big'
$bundlePaper = Join-Path $bundleRoot 'payload_paper.inc'
[void](Assert-FileHash $bundleUi $ExpectedUiSha256 'Bundle UI')
[void](Assert-FileHash $bundlePaper $ExpectedPaperSha256 'Bundle Paper')
if ((Get-Sha256File $BuilderPath) -ne $ExpectedBuilderSha256) { throw 'Original pinned builder changed.' }

$report = Join-Path $workRoot 'V18_STAGE8_1_1_RC2_TOPBAR_POLISH_REPORT.txt'
$reportLines = @(
    'AOTR 8P V18 STAGE8 LAUNCHER 1.1 RC2 TOPBAR POLISH',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Input builder SHA256: ' + $ExpectedBuilderSha256),
    ('Input GUI SHA256: ' + $ExpectedGuiSha256),
    ('Output builder SHA256: ' + $newBuilderSha),
    ('Output GUI SHA256: ' + $verifyGui.Sha256),
    ('ENGINE SHA256 unchanged: ' + $verifyEngine.Sha256),
    ('Original skin SHA256: ' + $ExpectedOriginalSkinSha256),
    ('Patched skin SHA256: ' + $patchedSkinSha),
    ('Built EXE SHA256: ' + $builtSha),
    ('Built EXE bytes: ' + $builtInfo.Length),
    'Launcher version: 1.1',
    'Minimize visual: moved 726..773 -> 777..824',
    'MinHit XAML: Canvas.Left 726 -> 777',
    'Close visual/hit: unchanged at 825..899 / Canvas.Left 825',
    'Old Minimize + fake Maximize visual area cleared with row-wise background interpolation',
    ('Before crop: ' + $beforeCrop),
    ('After crop: ' + $afterCrop),
    '',
    'SAFETY',
    '- Robust autodetect Config V2 preserved: PASS',
    '- Protected ticket/status/MESSAGES/Auto-Repair marker counts unchanged: PASS',
    '- ENGINE byte-identical: PASS',
    '- Get-FileHash remains absent: PASS',
    '- Invalid test update URLs used: PASS',
    '- No public release file modified: PASS',
    '- No game file modified: PASS'
)
[IO.File]::WriteAllLines($report,$reportLines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' V18 STAGE 8 - LAUNCHER 1.1 RC2 TOPBAR POLISH PASS' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('Built EXE        : ' + $builtExe) -ForegroundColor Green
Write-Host ('Built SHA256     : ' + $builtSha) -ForegroundColor Green
Write-Host ('Built bytes      : ' + $builtInfo.Length) -ForegroundColor Green
Write-Host ('Patched GUI SHA  : ' + $verifyGui.Sha256) -ForegroundColor Green
Write-Host ('Patched skin SHA : ' + $patchedSkinSha) -ForegroundColor Green
Write-Host ('Report           : ' + $report)
Write-Host ''
Write-Host 'NEXT: launch RC2 from a full runtime package and confirm the topbar now looks natural.' -ForegroundColor Yellow
