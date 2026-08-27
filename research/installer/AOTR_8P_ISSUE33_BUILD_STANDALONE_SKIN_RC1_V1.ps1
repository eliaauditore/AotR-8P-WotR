#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$SourcePackage = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE8_1_1_RC2_20260827_033705\PACKAGE',
    [string]$CandidateVersion = '1.1.1-issue33-rc1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceBuilderCommit = '7072e19bd43a350da0344b1b5e32ab9d052b3404'
$SourceBuilderPath = 'launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1.ps1'
$SourceBuilderUrl = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $SourceBuilderCommit + '/' + $SourceBuilderPath
$ExpectedBuilderSha = '2E19020B0B0C73C29E8C1F4FC4A13FD940A7C6FA9A2CA6274BF08B55A34FF665'
$ExpectedGuiSha = '23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C'
$ExpectedEngineSha = '94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA'
$ExpectedSkinSha = 'BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6'
$ExpectedUiSha = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
$ExpectedPaperSha = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'

function Get-Sha256File([string]$Path) {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Get-Sha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Assert-Hash([string]$Path,[string]$Expected,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ($Label + ' missing: ' + $Path) }
    $actual = Get-Sha256File $Path
    if ($actual -ne $Expected) { throw ($Label + ' SHA256 mismatch. Expected ' + $Expected + ', got ' + $actual) }
    Write-Host (('{0,-28}: {1}' -f $Label,$actual)) -ForegroundColor Green
    return $actual
}

function Test-PowerShellText([string]$Text,[string]$Label) {
    if ($Text.Length -gt 0 -and [int][char]$Text[0] -eq 0xFEFF) { $Text = $Text.Substring(1) }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) {
        $messages = @($errors | ForEach-Object { $_.Message }) -join '; '
        throw ($Label + ' parser errors: ' + $messages)
    }
}

function Replace-ExactOnce([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $count = 0
    $index = 0
    while (($found = $Text.IndexOf($Old,$index,[StringComparison]::Ordinal)) -ge 0) {
        $count++
        $index = $found + $Old.Length
    }
    if ($count -ne 1) { throw ('Expected exactly one target for ' + $Label + ', found ' + $count) }
    return $Text.Replace($Old,$New)
}

function Get-GzipPayload([string]$CSharpText,[string]$ConstantName) {
    $pattern = '(?s)(?:private\s+)?const\s+string\s+' + [regex]::Escape($ConstantName) + '\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
    $match = [regex]::Match($CSharpText,$pattern)
    if (-not $match.Success) { throw ('Could not locate ' + $ConstantName + ' in embedded C# template.') }
    $compressed = [Convert]::FromBase64String(($match.Groups['data'].Value -replace '\s',''))
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

if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw ('Base missing: ' + $Base) }
if (-not (Test-Path -LiteralPath $SourcePackage -PathType Container)) { throw ('Source package missing: ' + $SourcePackage) }

$sourceSkin = Join-Path $SourcePackage 'internal\assets\launcher_skin.png'
$sourceUi = Join-Path $SourcePackage 'payload\!!!WOTR_8P_UI_TEST.big'
$sourcePaper = Join-Path $SourcePackage 'payload\data\ini\campaigns\scenarios\PaperScenario001.inc'
[void](Assert-Hash $sourceSkin $ExpectedSkinSha 'Source skin')
[void](Assert-Hash $sourceUi $ExpectedUiSha 'Source UI')
[void](Assert-Hash $sourcePaper $ExpectedPaperSha 'Source paper')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ('ISSUE33_STANDALONE_SKIN_RC1_' + $stamp)
$packageRoot = Join-Path $workRoot 'PACKAGE'
$sourceBuilderFile = Join-Path $workRoot 'SOURCE_FINAL_1_1.ps1'
$patchedBuilder = Join-Path $workRoot 'BUILD_ISSUE33_STANDALONE_SKIN_RC1.ps1'
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
Copy-Item -LiteralPath $SourcePackage -Destination $packageRoot -Recurse -Force

Invoke-WebRequest -Uri $SourceBuilderUrl -OutFile $sourceBuilderFile
[void](Assert-Hash $sourceBuilderFile $ExpectedBuilderSha 'Canonical FINAL_1_1')

$builderBytes = [IO.File]::ReadAllBytes($sourceBuilderFile)
$hadBom = ($builderBytes.Length -ge 3 -and $builderBytes[0] -eq 0xEF -and $builderBytes[1] -eq 0xBB -and $builderBytes[2] -eq 0xBF)
$builderOffset = if ($hadBom) { 3 } else { 0 }
$builderText = [Text.UTF8Encoding]::new($false,$true).GetString($builderBytes,$builderOffset,$builderBytes.Length-$builderOffset)
Test-PowerShellText $builderText 'canonical FINAL_1_1'

$outerPattern = '(?s)(?<prefix>\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\r?\n)(?<data>[A-Za-z0-9+/=\r\n]+?)(?<suffix>\r?\n''@\)\))'
$outerRegex = [regex]::new($outerPattern)
$outerMatches = $outerRegex.Matches($builderText)
if ($outerMatches.Count -ne 1) { throw ('Expected exactly one embedded C# template, found ' + $outerMatches.Count) }
$outer = $outerMatches[0]
$csharpBytes = [Convert]::FromBase64String(($outer.Groups['data'].Value -replace '\s',''))
$csharpText = [Text.UTF8Encoding]::new($false,$true).GetString($csharpBytes)

$guiBytes = Get-GzipPayload $csharpText 'GuiGzipBase64'
$engineBytes = Get-GzipPayload $csharpText 'EngineGzipBase64'
$guiSha = Get-Sha256Bytes $guiBytes
$engineSha = Get-Sha256Bytes $engineBytes
if ($guiSha -ne $ExpectedGuiSha) { throw ('GUI payload changed unexpectedly: ' + $guiSha) }
if ($engineSha -ne $ExpectedEngineSha) { throw ('ENGINE payload changed unexpectedly: ' + $engineSha) }
Write-Host ('Embedded GUI unchanged      : ' + $guiSha) -ForegroundColor Green
Write-Host ('Embedded ENGINE unchanged   : ' + $engineSha) -ForegroundColor Green

$guiOffset = if ($guiBytes.Length -ge 3 -and $guiBytes[0] -eq 0xEF -and $guiBytes[1] -eq 0xBB -and $guiBytes[2] -eq 0xBF) { 3 } else { 0 }
$guiText = [Text.UTF8Encoding]::new($false,$true).GetString($guiBytes,$guiOffset,$guiBytes.Length-$guiOffset)
if ($guiText -notmatch 'aotr-standalone-v2') { throw 'Config V2 marker missing from embedded GUI.' }

# Add build-time skin placeholders directly before the existing GUI payload constant.
$guiConstRegex = [regex]::new('(?m)^(?<indent>[ \t]*)private\s+const\s+string\s+GuiGzipBase64\s*=')
$guiConstMatches = $guiConstRegex.Matches($csharpText)
if ($guiConstMatches.Count -ne 1) { throw ('Expected one GuiGzipBase64 constant, found ' + $guiConstMatches.Count) }
$guiConst = $guiConstMatches[0]
$indent = $guiConst.Groups['indent'].Value
$constants = $indent + 'private const string Issue33SkinGzipBase64 = @"__ISSUE33_SKIN_GZIP_BASE64__";' + "`r`n" +
             $indent + 'private const string Issue33SkinSha256 = "__ISSUE33_SKIN_SHA256__";' + "`r`n"
$csharpPatched = $csharpText.Insert($guiConst.Index,$constants)

# Add a self-materializer before Main. It writes the embedded, hash-verified skin only if missing/wrong.
$mainBlockRegex = [regex]::new('(?ms)^(?<indent>[ \t]*)(?:(?:\[[^\r\n]+\])[ \t]*\r?\n[ \t]*)*(?:private[ \t]+|public[ \t]+|internal[ \t]+)?static[ \t]+(?:void|int)[ \t]+Main[ \t]*\([^)]*\)[ \t]*\{')
$mainBlocks = $mainBlockRegex.Matches($csharpPatched)
if ($mainBlocks.Count -ne 1) { throw ('Expected exactly one C# Main block, found ' + $mainBlocks.Count) }
$mainIndent = $mainBlocks[0].Groups['indent'].Value
$helper = @'
private static byte[] Issue33GunzipSkin()
{
    byte[] compressed = Convert.FromBase64String(Issue33SkinGzipBase64);
    using (MemoryStream input = new MemoryStream(compressed))
    using (GZipStream gzip = new GZipStream(input, CompressionMode.Decompress))
    using (MemoryStream output = new MemoryStream())
    {
        gzip.CopyTo(output);
        return output.ToArray();
    }
}

private static string Issue33Sha256(byte[] bytes)
{
    using (SHA256 sha = SHA256.Create())
    {
        return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "");
    }
}

private static void Issue33EnsureEmbeddedSkin()
{
    byte[] expectedBytes = Issue33GunzipSkin();
    string embeddedHash = Issue33Sha256(expectedBytes);
    if (!String.Equals(embeddedHash, Issue33SkinSha256, StringComparison.OrdinalIgnoreCase))
        throw new InvalidOperationException("Embedded launcher skin SHA256 mismatch: " + embeddedHash);

    string skinPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "internal", "assets", "launcher_skin.png");
    if (File.Exists(skinPath))
    {
        string existingHash = Issue33Sha256(File.ReadAllBytes(skinPath));
        if (String.Equals(existingHash, Issue33SkinSha256, StringComparison.OrdinalIgnoreCase))
            return;
    }

    string directory = Path.GetDirectoryName(skinPath);
    if (!Directory.Exists(directory)) Directory.CreateDirectory(directory);
    File.WriteAllBytes(skinPath, expectedBytes);

    string writtenHash = Issue33Sha256(File.ReadAllBytes(skinPath));
    if (!String.Equals(writtenHash, Issue33SkinSha256, StringComparison.OrdinalIgnoreCase))
        throw new IOException("Materialized launcher skin SHA256 mismatch: " + writtenHash);
}

'@
$helperLines = ($helper -split "`r?`n") | ForEach-Object { if ($_.Length -gt 0) { $mainIndent + $_ } else { '' } }
$helperText = ($helperLines -join "`r`n") + "`r`n"
$csharpPatched = $csharpPatched.Insert($mainBlocks[0].Index,$helperText)

$mainOpenRegex = [regex]::new('(?s)(?<sig>(?:private\s+|public\s+|internal\s+)?static\s+(?:void|int)\s+Main\s*\([^)]*\)\s*\{)')
$mainOpenMatches = $mainOpenRegex.Matches($csharpPatched)
if ($mainOpenMatches.Count -ne 1) { throw ('Expected exactly one Main opening brace, found ' + $mainOpenMatches.Count) }
$mainOpen = $mainOpenMatches[0]
$callText = "`r`n" + $mainIndent + '    Issue33EnsureEmbeddedSkin();'
$csharpPatched = $csharpPatched.Insert($mainOpen.Index + $mainOpen.Length,$callText)

if (($csharpPatched -split 'Issue33EnsureEmbeddedSkin').Count -ne 3) { throw 'Unexpected Issue33EnsureEmbeddedSkin marker count after C# patch.' }
if ($csharpPatched -notmatch '__ISSUE33_SKIN_GZIP_BASE64__') { throw 'Skin Base64 placeholder missing after C# patch.' }
if ($csharpPatched -notmatch '__ISSUE33_SKIN_SHA256__') { throw 'Skin SHA placeholder missing after C# patch.' }

$csharpPatchedBytes = [Text.UTF8Encoding]::new($false).GetBytes($csharpPatched)
$csharpPatchedBase64 = [Convert]::ToBase64String($csharpPatchedBytes)
$builderPatched = $builderText.Substring(0,$outer.Groups['data'].Index) + $csharpPatchedBase64 + $builderText.Substring($outer.Groups['data'].Index + $outer.Groups['data'].Length)

# Builder-side embedding: compress the validated build-time skin and substitute it into C#.
$expectedPaperLine = '$ExpectedPaper = "3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43"'
$builderPatched = Replace-ExactOnce $builderPatched $expectedPaperLine ($expectedPaperLine + "`r`n" + '$ExpectedSkin = "' + $ExpectedSkinSha + '"') 'ExpectedSkin declaration'

$paperCheck = 'if ((Get-Sha256 $Paper) -ne $ExpectedPaper) { throw "RC5 PaperScenario hash mismatch. Aborting." }'
$skinCheck = 'if ((Get-Sha256 $Skin) -ne $ExpectedSkin) { throw "Launcher skin hash mismatch. Aborting." }'
$builderPatched = Replace-ExactOnce $builderPatched $paperCheck ($paperCheck + "`r`n" + $skinCheck) 'skin hash check'

$safeUrlLine = '    $safeUrl = $UpdateManifestUrl.Replace("\", "\\").Replace(''"'',''\"'')'
$skinEmbedBlock = @'
    $skinRaw = [IO.File]::ReadAllBytes($Skin)
    $skinBuffer = [IO.MemoryStream]::new()
    try {
        $skinGzip = [IO.Compression.GZipStream]::new($skinBuffer,[IO.Compression.CompressionMode]::Compress,$true)
        try { $skinGzip.Write($skinRaw,0,$skinRaw.Length) }
        finally { $skinGzip.Dispose() }
        $skinGzipBase64 = [Convert]::ToBase64String($skinBuffer.ToArray())
    }
    finally { $skinBuffer.Dispose() }
    $skinSha256 = Get-Sha256 $Skin

'@
$builderPatched = Replace-ExactOnce $builderPatched $safeUrlLine ($skinEmbedBlock + $safeUrlLine) 'skin compression block'

$sourceLine = '    $source = $template.Replace("__UPDATE_URL__", $safeUrl).Replace("__LAUNCHER_VERSION__", $safeVersion).Replace("__FILE_VERSION__", $fileVersion)'
$newSourceLine = $sourceLine + '.Replace("__ISSUE33_SKIN_GZIP_BASE64__", $skinGzipBase64).Replace("__ISSUE33_SKIN_SHA256__", $skinSha256)'
$builderPatched = Replace-ExactOnce $builderPatched $sourceLine $newSourceLine 'skin source substitution'

Test-PowerShellText $builderPatched 'Issue33 patched builder'

$utf8 = [Text.UTF8Encoding]::new($false)
if ($hadBom) {
    $body = $utf8.GetBytes($builderPatched)
    $outBytes = New-Object byte[] ($body.Length + 3)
    $outBytes[0]=0xEF; $outBytes[1]=0xBB; $outBytes[2]=0xBF
    [Array]::Copy($body,0,$outBytes,3,$body.Length)
    [IO.File]::WriteAllBytes($patchedBuilder,$outBytes)
} else {
    [IO.File]::WriteAllText($patchedBuilder,$builderPatched,$utf8)
}
$patchedBuilderSha = Get-Sha256File $patchedBuilder
Write-Host ('Issue33 builder SHA256      : ' + $patchedBuilderSha) -ForegroundColor Green

Write-Host ''
Write-Host 'Building non-release standalone-skin candidate...' -ForegroundColor Cyan
& $patchedBuilder -PackageRoot $packageRoot -LauncherVersion $CandidateVersion -EmitGitHubBundle

$bundle = Join-Path $packageRoot '_GITHUB_UPDATE'
$candidateExe = Join-Path $bundle 'AotR 8P WotR Mod.exe'
$candidateManifest = Join-Path $bundle 'manifest.json'
$candidateRepair = Join-Path $bundle 'repair-manifest.json'
$candidateUi = Join-Path $bundle 'payload_ui.big'
$candidatePaper = Join-Path $bundle 'payload_paper.inc'
foreach ($p in @($candidateExe,$candidateManifest,$candidateRepair,$candidateUi,$candidatePaper)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw ('Candidate bundle missing: ' + $p) }
}
$files = @(Get-ChildItem -LiteralPath $bundle -File)
if ($files.Count -ne 5) { throw ('Candidate release-root must contain exactly five files before first launch; found ' + $files.Count) }
if (Test-Path -LiteralPath (Join-Path $bundle 'internal')) { throw 'Candidate release-root already contains internal/ before first launch; isolated proof invalid.' }

[void](Assert-Hash $candidateUi $ExpectedUiSha 'Candidate UI')
[void](Assert-Hash $candidatePaper $ExpectedPaperSha 'Candidate paper')
$candidateExeSha = Get-Sha256File $candidateExe
$manifest = Get-Content -LiteralPath $candidateManifest -Raw | ConvertFrom-Json
$repair = Get-Content -LiteralPath $candidateRepair -Raw | ConvertFrom-Json
if ([string]$manifest.launcher_version -ne $CandidateVersion) { throw ('Candidate manifest version mismatch: ' + [string]$manifest.launcher_version) }
if ([string]$manifest.launcher_sha256 -ne $candidateExeSha) { throw 'Candidate manifest EXE SHA does not match candidate EXE.' }
if ([string]$repair.generated_for_launcher -ne $CandidateVersion) { throw 'Candidate repair-manifest version mismatch.' }

$report = Join-Path $workRoot 'ISSUE33_RC1_BUILD_REPORT.txt'
$lines = @(
    'AOTR 8P WOTR ISSUE #33 STANDALONE SKIN RC1',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Source builder commit: ' + $SourceBuilderCommit),
    ('Source builder SHA256: ' + $ExpectedBuilderSha),
    ('Patched builder SHA256: ' + $patchedBuilderSha),
    ('Candidate version: ' + $CandidateVersion),
    ('Candidate EXE SHA256: ' + $candidateExeSha),
    ('GUI SHA256 unchanged: ' + $guiSha),
    ('ENGINE SHA256 unchanged: ' + $engineSha),
    ('Skin SHA256 embedded: ' + $ExpectedSkinSha),
    ('UI SHA256: ' + $ExpectedUiSha),
    ('Paper SHA256: ' + $ExpectedPaperSha),
    ('Isolated bundle: ' + $bundle),
    'Pre-launch internal/ absent: PASS',
    'Pre-launch root file count = 5: PASS',
    '',
    'NEXT',
    'Run the candidate EXE from this isolated five-file bundle. It must create internal\assets\launcher_skin.png itself and open the GUI.'
)
[IO.File]::WriteAllLines($report,$lines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' ISSUE #33 RC1 BUILD: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('Candidate version : ' + $CandidateVersion) -ForegroundColor Green
Write-Host ('Candidate EXE SHA : ' + $candidateExeSha) -ForegroundColor Green
Write-Host ('Patched builder    : ' + $patchedBuilder)
Write-Host ('Five-file bundle   : ' + $bundle)
Write-Host ('Report             : ' + $report)
Write-Host ''
Write-Host 'DO NOT PUBLISH. Next gate is isolated first-launch bootstrap + START smoke.' -ForegroundColor Yellow
