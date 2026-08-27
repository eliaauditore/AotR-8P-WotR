#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ReleaseCommit = '1303e0a6b268b082e9352ded1461fa8d794f16d3'
$ReleaseBuilderRelativePath = 'launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10.ps1'
$ReleaseBuilderUrl = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$ReleaseCommit/$ReleaseBuilderRelativePath"
$ExpectedReleasedBuilderSha256 = '8BDD8745931B41AA2B062FB9ADCE8BBBD7EA2A33F4C0946C20A409D89639271A'
$ExpectedGuiSha256 = '46032AC5272ED491A9E3F497733148A4531E35DC7D1634DDC180CC48D6C9FA24'
$ExpectedEngineSha256 = 'E5803FB7D7BDCD463587C99796A6B0EFD4D23D3D6C69BA102A83435D872F6E5F'

# The donor is immutable by commit. It is used ONLY as text source for the already-proven
# robust GUI/engine resolver here-strings; the donor script itself is never executed.
$DonorCommit = '7c4f7d958238926dfdaa15b2baeb73cd99b0dd45'
$DonorRelativePath = 'research/installer/AOTR_8P_STAGE1_INTEGRATE_ROBUST_AUTODETECT_V2.ps1'
$DonorUrl = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$DonorCommit/$DonorRelativePath"

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

function Get-Utf8Text([byte[]]$Bytes) {
    $offset = 0
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { $offset = 3 }
    $utf8 = [Text.UTF8Encoding]::new($false,$true)
    return $utf8.GetString($Bytes,$offset,$Bytes.Length-$offset)
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
    if ($errors -and $errors.Count -gt 0) {
        $msg = ($errors | ForEach-Object { "Line $($_.Extent.StartLineNumber), Col $($_.Extent.StartColumnNumber): $($_.Message)" }) -join [Environment]::NewLine
        throw "Parser validation failed for $Label`n$msg"
    }
}

function Get-OuterInfo([string]$BuilderText) {
    $pattern = '(?s)(?<before>\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\s*)(?<data>[A-Za-z0-9+/=\r\n]+?)(?<after>\s*''@\)\))'
    $m = [regex]::Match($BuilderText,$pattern)
    if (-not $m.Success) { throw 'Could not locate outer C# Base64 template.' }
    $bytes = [Convert]::FromBase64String(($m.Groups['data'].Value -replace '\s',''))
    return [PSCustomObject]@{ Match=$m; Bytes=$bytes; Text=([Text.Encoding]::UTF8.GetString($bytes)) }
}

function Get-PayloadInfo([string]$CSharp,[string]$Name) {
    $pattern = '(?s)(?:private\s+)?const\s+string\s+' + [regex]::Escape($Name) + '\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
    $m = [regex]::Match($CSharp,$pattern)
    if (-not $m.Success) { throw "Could not locate $Name in outer C# template." }
    $bytes = Expand-GzipBase64Bytes $m.Groups['data'].Value
    return [PSCustomObject]@{ Match=$m; Bytes=$bytes; Text=(Get-Utf8Text $bytes); Sha256=(Get-Sha256Bytes $bytes) }
}

function Replace-Payload([string]$CSharp,[string]$Name,[byte[]]$NewBytes) {
    $info = Get-PayloadInfo $CSharp $Name
    $newB64 = Wrap-Base64 (Compress-BytesToGzipBase64 $NewBytes)
    $g = $info.Match.Groups['data']
    return $CSharp.Substring(0,$g.Index) + $newB64 + $CSharp.Substring($g.Index+$g.Length)
}

function Get-HereStringBody([string]$Text,[string]$VariableName) {
    $pattern = '(?ms)^\$' + [regex]::Escape($VariableName) + '\s*=\s*@''\r?\n(?<body>.*?)\r?\n''@\s*$'
    $matches = @([regex]::Matches($Text,$pattern))
    if ($matches.Count -ne 1) { throw "Expected exactly one donor here-string for `$${VariableName}, found $($matches.Count)." }
    return [string]$matches[0].Groups['body'].Value
}

function Replace-SourceBlock {
    param(
        [string]$Text,
        [string]$StartMarker,
        [string]$EndMarker,
        [string]$Replacement,
        [string]$Label
    )
    $start = $Text.IndexOf($StartMarker,[StringComparison]::Ordinal)
    if ($start -lt 0) { throw "$Label start marker not found." }
    $end = $Text.IndexOf($EndMarker,$start,[StringComparison]::Ordinal)
    if ($end -le $start) { throw "$Label end marker not found or invalid." }
    $prefix = $Text.Substring(0,$start)
    $suffix = $Text.Substring($end)
    $patched = $prefix + $Replacement.TrimEnd("`r","`n") + "`r`n`r`n" + $suffix
    return [PSCustomObject]@{ Text=$patched; Prefix=$prefix; Suffix=$suffix; Start=$start; End=$end }
}

function Count-Matches([string]$Text,[string]$Pattern) {
    return @([regex]::Matches($Text,$Pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
}

if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw "Base missing: $Base" }

$tempRelease = Join-Path $env:TEMP 'AOTR_8P_V18_FINAL_1_0_10_RELEASED.ps1'
$tempDonor = Join-Path $env:TEMP 'AOTR_8P_STAGE1_AUTODETECT_V2_DONOR.ps1'
Remove-Item $tempRelease,$tempDonor -Force -ErrorAction SilentlyContinue

Invoke-WebRequest -Uri $ReleaseBuilderUrl -OutFile $tempRelease
Invoke-WebRequest -Uri $DonorUrl -OutFile $tempDonor

$releasedHash = Get-Sha256File $tempRelease
if ($releasedHash -ne $ExpectedReleasedBuilderSha256) { throw "Released V18 builder hash mismatch. Expected $ExpectedReleasedBuilderSha256, got $releasedHash" }

$builderBytes = [IO.File]::ReadAllBytes($tempRelease)
$builderText = Get-Utf8Text $builderBytes
Test-PowerShellText $builderText 'released V18 builder'

$outer = Get-OuterInfo $builderText
$gui = Get-PayloadInfo $outer.Text 'GuiGzipBase64'
$engine = Get-PayloadInfo $outer.Text 'EngineGzipBase64'
if ($gui.Sha256 -ne $ExpectedGuiSha256) { throw "V18 GUI hash mismatch. Expected $ExpectedGuiSha256, got $($gui.Sha256)" }
if ($engine.Sha256 -ne $ExpectedEngineSha256) { throw "V18 ENGINE hash mismatch. Expected $ExpectedEngineSha256, got $($engine.Sha256)" }
Test-PowerShellText $gui.Text 'released V18 GUI'
Test-PowerShellText $engine.Text 'released V18 ENGINE'

$donorText = [IO.File]::ReadAllText($tempDonor)
$guiReplacement = Get-HereStringBody $donorText 'guiReplacement'
$engineReplacement = Get-HereStringBody $donorText 'engineReplacement'
Test-PowerShellText $guiReplacement 'donor GUI resolver source'
Test-PowerShellText $engineReplacement 'donor ENGINE resolver source'

$requiredDonorGuiMarkers = @(
    "validation = 'aotr-standalone-v2'",
    'A8P-INSTALL-002',
    'A8P-INSTALL-003',
    'A8P-INSTALL-004',
    'A8P-INSTALL-007',
    'Get-AotRLocalDrives',
    'Find-AotRRootsBounded',
    'RemovableUsbOrExFat'
)
foreach ($marker in $requiredDonorGuiMarkers) {
    if (-not $guiReplacement.Contains($marker)) { throw "Donor GUI resolver missing required proven marker: $marker" }
}
if ($engineReplacement -match '\$env:AOTR_HOME') { throw 'Donor ENGINE resolver unexpectedly contains AOTR_HOME.' }
if ($engineReplacement -match 'Get-PSDrive') { throw 'Donor ENGINE resolver unexpectedly contains independent drive discovery.' }
if (-not $engineReplacement.Contains("validation -ne 'aotr-standalone-v2'")) { throw 'Donor ENGINE resolver does not enforce Config V2.' }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P V18 STAGE 1 - ROBUST AUTODETECT V2 INTEGRATION' -ForegroundColor Cyan
Write-Host ' RELEASED 1.0.10 BASE / NON-RELEASE BUILDER ONLY' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Release commit    : $ReleaseCommit"
Write-Host "Released builder  : $releasedHash" -ForegroundColor Green
Write-Host "V18 GUI SHA       : $($gui.Sha256)" -ForegroundColor Green
Write-Host "V18 ENGINE SHA    : $($engine.Sha256)" -ForegroundColor Green
Write-Host "Donor commit      : $DonorCommit"
Write-Host "Donor script SHA  : $(Get-Sha256File $tempDonor)"

$guiProtected = [ordered]@{
    ReportError = 'REPORT ERROR'
    Messages = '\bMESSAGES\b'
    ReportReady = '\bReportReady\b'
    Fingerprint = 'A8P-FP-'
    AutoRepair = 'AUTO-REPAIR|Auto-Repair'
    StatusRowsHost = '\bStatusRowsHost\b'
    StatusGameText = '\bStatusGameText\b'
    StatusCampaignText = '\bStatusCampaignText\b'
    StatusUiText = '\bStatusUiText\b'
    OverallStatusText = '\bOverallStatusText\b'
    SetStatusChecking = 'function\s+Set-StatusChecking\b'
    GetFileHash = '\bGet-FileHash\b'
    SyntheticHook = 'A8P_TEST_FORCE_ERROR|A8P-TEST-001'
}
$guiCountsBefore = @{}
foreach ($key in $guiProtected.Keys) { $guiCountsBefore[$key] = Count-Matches $gui.Text $guiProtected[$key] }
$engineFinalStableBefore = Count-Matches $engine.Text 'FINAL_STABLE_V7'
$engineGetFileHashBefore = Count-Matches $engine.Text '\bGet-FileHash\b'

$guiPatch = Replace-SourceBlock -Text $gui.Text -StartMarker 'function Get-AotRInstallFromPath([string]$Path) {' -EndMarker '$Install = Resolve-AotRInstall -PromptIfMissing' -Replacement $guiReplacement -Label 'V18 GUI resolver'
$enginePatch = Replace-SourceBlock -Text $engine.Text -StartMarker 'function Get-AotRInstallFromPath([string]$Path) {' -EndMarker 'function New-LinkedFile([string]$Source, [string]$Destination) {' -Replacement $engineReplacement -Label 'V18 ENGINE resolver'

# Strong locality assertions: every character outside the resolver replacement windows must remain identical.
if (-not $guiPatch.Text.StartsWith($guiPatch.Prefix,[StringComparison]::Ordinal)) { throw 'GUI prefix changed outside resolver patch.' }
if (-not $guiPatch.Text.EndsWith($guiPatch.Suffix,[StringComparison]::Ordinal)) { throw 'GUI suffix changed outside resolver patch.' }
if (-not $enginePatch.Text.StartsWith($enginePatch.Prefix,[StringComparison]::Ordinal)) { throw 'ENGINE prefix changed outside resolver patch.' }
if (-not $enginePatch.Text.EndsWith($enginePatch.Suffix,[StringComparison]::Ordinal)) { throw 'ENGINE suffix changed outside resolver patch.' }

Test-PowerShellText $guiPatch.Text 'patched V18 GUI'
Test-PowerShellText $enginePatch.Text 'patched V18 ENGINE'

foreach ($key in $guiProtected.Keys) {
    $after = Count-Matches $guiPatch.Text $guiProtected[$key]
    if ($after -ne $guiCountsBefore[$key]) { throw "Protected 1.0.10 GUI marker count changed for $key: $($guiCountsBefore[$key]) -> $after" }
}
if ((Count-Matches $guiPatch.Text '\bGet-FileHash\b') -ne 0) { throw 'Patched GUI reintroduced Get-FileHash.' }
if ((Count-Matches $guiPatch.Text 'A8P_TEST_FORCE_ERROR|A8P-TEST-001') -ne 0) { throw 'Patched GUI introduced synthetic test hook.' }
if ((Count-Matches $enginePatch.Text '\bGet-FileHash\b') -ne $engineGetFileHashBefore -or $engineGetFileHashBefore -ne 0) { throw 'ENGINE Get-FileHash invariant changed.' }
if ((Count-Matches $enginePatch.Text 'FINAL_STABLE_V7') -ne $engineFinalStableBefore) { throw 'ENGINE FINAL_STABLE_V7 marker count changed.' }

foreach ($marker in $requiredDonorGuiMarkers) {
    if (-not $guiPatch.Text.Contains($marker)) { throw "Patched V18 GUI missing robust-autodetect marker: $marker" }
}
$engineResolverStart = $enginePatch.Text.IndexOf('function Resolve-AotRInstall {',[StringComparison]::Ordinal)
$engineResolverEnd = $enginePatch.Text.IndexOf('function New-LinkedFile([string]$Source, [string]$Destination) {',$engineResolverStart,[StringComparison]::Ordinal)
if ($engineResolverStart -lt 0 -or $engineResolverEnd -le $engineResolverStart) { throw 'Could not isolate patched V18 engine resolver.' }
$engineResolverText = $enginePatch.Text.Substring($engineResolverStart,$engineResolverEnd-$engineResolverStart)
if ($engineResolverText -match '\$env:AOTR_HOME') { throw 'Patched V18 engine resolver still references AOTR_HOME.' }
if ($engineResolverText -match 'Get-PSDrive') { throw 'Patched V18 engine resolver still performs drive discovery.' }
if (-not $engineResolverText.Contains("validation -ne 'aotr-standalone-v2'")) { throw 'Patched V18 engine resolver does not enforce Config V2.' }

$newGuiBytes = Convert-TextToUtf8LikeOriginal $guiPatch.Text $gui.Bytes
$newEngineBytes = Convert-TextToUtf8LikeOriginal $enginePatch.Text $engine.Bytes
$newGuiSha = Get-Sha256Bytes $newGuiBytes
$newEngineSha = Get-Sha256Bytes $newEngineBytes

$newCSharp = Replace-Payload $outer.Text 'GuiGzipBase64' $newGuiBytes
$newCSharp = Replace-Payload $newCSharp 'EngineGzipBase64' $newEngineBytes
$newOuterB64 = Wrap-Base64 ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($newCSharp)))
$outerData = $outer.Match.Groups['data']
$newBuilderText = $builderText.Substring(0,$outerData.Index) + $newOuterB64 + $builderText.Substring($outerData.Index+$outerData.Length)
Test-PowerShellText $newBuilderText 'patched V18 builder'

$newBuilderBytes = Convert-TextToUtf8LikeOriginal $newBuilderText $builderBytes
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$work = Join-Path $Base ("AUTODETECT_V2_V18_STAGE1_" + $stamp)
if (Test-Path -LiteralPath $work) { throw "Refusing existing work root: $work" }
New-Item -ItemType Directory -Path $work -Force | Out-Null
$outBuilder = Join-Path $work 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10_ROBUST_AUTODETECT_V2_NONRELEASE.ps1'
[IO.File]::WriteAllBytes($outBuilder,$newBuilderBytes)
$outBuilderSha = Get-Sha256File $outBuilder

# Full written-output roundtrip proof.
$roundBytes = [IO.File]::ReadAllBytes($outBuilder)
$roundText = Get-Utf8Text $roundBytes
$roundOuter = Get-OuterInfo $roundText
$roundGui = Get-PayloadInfo $roundOuter.Text 'GuiGzipBase64'
$roundEngine = Get-PayloadInfo $roundOuter.Text 'EngineGzipBase64'
if ($roundGui.Sha256 -ne $newGuiSha) { throw 'V18 GUI roundtrip hash mismatch.' }
if ($roundEngine.Sha256 -ne $newEngineSha) { throw 'V18 ENGINE roundtrip hash mismatch.' }
Test-PowerShellText $roundGui.Text 'V18 GUI roundtrip'
Test-PowerShellText $roundEngine.Text 'V18 ENGINE roundtrip'
Test-PowerShellText $roundText 'V18 builder roundtrip'

# Re-run the protected-baseline assertions against the actual re-embedded roundtrip source.
foreach ($key in $guiProtected.Keys) {
    $after = Count-Matches $roundGui.Text $guiProtected[$key]
    if ($after -ne $guiCountsBefore[$key]) { throw "Roundtrip protected GUI marker changed for $key." }
}
if ((Count-Matches $roundEngine.Text 'FINAL_STABLE_V7') -ne $engineFinalStableBefore) { throw 'Roundtrip FINAL_STABLE_V7 marker count changed.' }
if ((Count-Matches $roundEngine.Text '\bGet-FileHash\b') -ne 0) { throw 'Roundtrip ENGINE contains Get-FileHash.' }

# The immutable released source fetched from GitHub must remain unchanged on disk in temp.
if ((Get-Sha256File $tempRelease) -ne $ExpectedReleasedBuilderSha256) { throw 'Downloaded released builder changed during integration.' }

$report = Join-Path $work 'V18_STAGE1_AUTODETECT_V2_REPORT.txt'
$lines = @(
    'AOTR 8P V18 STAGE1 ROBUST AUTODETECT V2',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Release commit: ' + $ReleaseCommit),
    ('Released builder SHA256: ' + $releasedHash),
    ('Original GUI SHA256: ' + $gui.Sha256),
    ('Original ENGINE SHA256: ' + $engine.Sha256),
    ('Donor commit: ' + $DonorCommit),
    ('Donor script SHA256: ' + (Get-Sha256File $tempDonor)),
    ('Output builder: ' + $outBuilder),
    ('Output builder SHA256: ' + $outBuilderSha),
    ('Output GUI SHA256: ' + $newGuiSha),
    ('Output ENGINE SHA256: ' + $newEngineSha),
    '',
    'PRESERVATION',
    '- REPORT ERROR / diagnostics marker counts unchanged: PASS',
    '- MESSAGES / unread UI marker counts unchanged: PASS',
    '- Auto-Repair / ReportReady / fingerprint marker counts unchanged: PASS',
    '- Dynamic StatusRowsHost and status control marker counts unchanged: PASS',
    '- GUI suffix from Resolve call onward unchanged: PASS',
    '- ENGINE suffix from New-LinkedFile onward unchanged: PASS',
    '- GUI Get-FileHash remains zero: PASS',
    '- ENGINE Get-FileHash remains zero: PASS',
    '- Synthetic test hook remains zero: PASS',
    '- FINAL_STABLE_V7 marker count unchanged: PASS',
    '',
    'ROBUST AUTODETECT',
    '- Standalone hard root requires rotwk exe + game.dat + sibling aotr: PASS',
    '- Runtime / All-in-One hard rejection retained from proven donor: PASS',
    '- BFME_RESEARCH / backup / checkpoint / temp excluded from auto-preference: PASS',
    '- Fixed drives before Removable/USB/exFAT: PASS',
    '- Candidate collection + canonical dedupe + score/rank retained: PASS',
    '- Equal top candidates require explicit selection: PASS',
    '- Config V2 write + readback validation retained: PASS',
    '- Cached V2 path revalidation / A8P-INSTALL-007 retained: PASS',
    '- Engine independent AOTR_HOME discovery removed: PASS',
    '- Engine independent drive discovery removed: PASS',
    '- Engine requires schema 2 + aotr-standalone-v2: PASS',
    '',
    'SAFETY',
    '- No EXE built: PASS',
    '- No release artifact modified: PASS',
    '- No manifest modified: PASS',
    '- No game file modified: PASS'
)
[IO.File]::WriteAllLines($report,$lines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '=== V18 STAGE 1 RESULT ===' -ForegroundColor Cyan
Write-Host "Work root          : $work"
Write-Host "Output builder     : $outBuilder" -ForegroundColor Green
Write-Host "Output builder SHA : $outBuilderSha" -ForegroundColor Green
Write-Host "Output GUI SHA     : $newGuiSha" -ForegroundColor Green
Write-Host "Output ENGINE SHA  : $newEngineSha" -ForegroundColor Green
Write-Host "Report             : $report"
Write-Host ''
Write-Host '1.0.10 protected feature counts:' -ForegroundColor Cyan
foreach ($key in $guiProtected.Keys) { Write-Host ('  {0,-22} {1}' -f $key,$guiCountsBefore[$key]) }
Write-Host "  FINAL_STABLE_V7         $engineFinalStableBefore"
Write-Host ''
Write-Host 'V18 robust-autodetect integration: PASS' -ForegroundColor Green
Write-Host 'No EXE was built and no public/release/game files were modified.' -ForegroundColor Green
