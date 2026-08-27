#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE1_20260827_022948\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10_ROBUST_AUTODETECT_V2_NONRELEASE.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = 'D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0'
$ExpectedGuiSha256 = 'CFAF397833536769D726B0DD0960D940AAA6896ED62BFEFA0764185C2CEA90DC'
$ExpectedEngineSha256 = '94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA'

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

function Find-MainForm([string]$GuiText) {
    $pattern = '(?im)^(?<indent>[ \t]*)\$(?<var>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:New-Object\s+(?:System\.)?Windows\.Forms\.Form|\[(?:System\.)?Windows\.Forms\.Form\]::new\(\))[^\r\n]*$'
    $forms = @([regex]::Matches($GuiText,$pattern))
    $rows = New-Object System.Collections.Generic.List[object]
    for ($i=0; $i -lt $forms.Count; $i++) {
        $m = $forms[$i]
        $end = if ($i+1 -lt $forms.Count) { $forms[$i+1].Index } else { $GuiText.Length }
        $segment = $GuiText.Substring($m.Index,$end-$m.Index)
        $var = $m.Groups['var'].Value
        $titlePattern = '(?im)^\s*\$' + [regex]::Escape($var) + '\.Text\s*=\s*["''](?<title>[^"''\r\n]*)["'']\s*$'
        $tm = [regex]::Match($segment,$titlePattern)
        $title = if ($tm.Success) { $tm.Groups['title'].Value } else { '' }
        [void]$rows.Add([PSCustomObject]@{ Match=$m; End=$end; Segment=$segment; Var=$var; Title=$title })
    }
    $main = @($rows | Where-Object { $_.Title -match '(?i)AotR.*8P|8P.*War of the Ring|AotR 8P' -and $_.Title -notmatch '(?i)Multiple|Choose|Select' })
    if ($main.Count -ne 1) {
        Write-Host ''
        Write-Host 'Detected WinForms Form candidates:' -ForegroundColor Yellow
        foreach ($r in $rows) { Write-Host ('  $' + $r.Var + '  title=[' + $r.Title + ']') }
        throw ('Expected exactly one main launcher form, found ' + $main.Count + '. No patch written.')
    }
    return $main[0]
}

if (-not (Test-Path -LiteralPath $BuilderPath -PathType Leaf)) { throw ('Builder missing: ' + $BuilderPath) }
$builderHash = Get-Sha256File $BuilderPath
if ($builderHash -ne $ExpectedBuilderSha256) { throw ('Builder hash mismatch. Expected ' + $ExpectedBuilderSha256 + ', got ' + $builderHash) }

$builderBytes = [IO.File]::ReadAllBytes($BuilderPath)
$builderText = Get-Utf8Text $builderBytes
Test-PowerShellText $builderText 'pinned autodetect builder'
$outer = Get-OuterInfo $builderText
$gui = Get-PayloadInfo $outer.Text 'GuiGzipBase64'
$engine = Get-PayloadInfo $outer.Text 'EngineGzipBase64'
if ($gui.Sha256 -ne $ExpectedGuiSha256) { throw ('GUI hash mismatch. Expected ' + $ExpectedGuiSha256 + ', got ' + $gui.Sha256) }
if ($engine.Sha256 -ne $ExpectedEngineSha256) { throw ('ENGINE hash mismatch. Expected ' + $ExpectedEngineSha256 + ', got ' + $engine.Sha256) }
Test-PowerShellText $gui.Text 'pinned GUI'
Test-PowerShellText $engine.Text 'pinned ENGINE'

$protected = [ordered]@{
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
$expectedCounts = [ordered]@{
    ReportError=6; Messages=11; ReportReady=13; Fingerprint=3; AutoRepair=4; StatusRowsHost=1;
    StatusGameText=6; StatusCampaignText=6; StatusUiText=6; OverallStatusText=9;
    SetStatusChecking=1; GetFileHash=0; SyntheticHook=0
}
$beforeCounts = @{}
foreach ($key in $protected.Keys) {
    $beforeCounts[$key] = Count-Matches $gui.Text $protected[$key]
    if ($beforeCounts[$key] -ne $expectedCounts[$key]) {
        throw ('Protected GUI baseline mismatch for ' + $key + '. Expected ' + $expectedCounts[$key] + ', got ' + $beforeCounts[$key])
    }
}
if ((Count-Matches $engine.Text 'FINAL_STABLE_V7') -ne 7) { throw 'ENGINE FINAL_STABLE_V7 baseline mismatch.' }
if ((Count-Matches $engine.Text '\bGet-FileHash\b') -ne 0) { throw 'ENGINE Get-FileHash regression present.' }

$main = Find-MainForm $gui.Text
$formVar = $main.Var
$formTitle = $main.Title
$segment = $main.Segment
$assignPattern = '(?im)^\s*\$' + [regex]::Escape($formVar) + '\.MaximizeBox\s*=\s*(?<value>\$?(?:true|false))\s*$'
$assigns = @([regex]::Matches($segment,$assignPattern))

$newGuiText = $gui.Text
$patchMode = ''
if ($assigns.Count -eq 1) {
    $value = $assigns[0].Groups['value'].Value
    if ($value -match '(?i)false') {
        throw ('Main form already has MaximizeBox=false. The observed button is not the standard WinForms maximize box; refusing to guess.')
    }
    $absoluteIndex = $main.Match.Index + $assigns[0].Index
    $oldLine = $assigns[0].Value
    $newLine = '$' + $formVar + '.MaximizeBox = $false'
    $newGuiText = $gui.Text.Substring(0,$absoluteIndex) + $newLine + $gui.Text.Substring($absoluteIndex+$oldLine.Length)
    $patchMode = 'replace existing MaximizeBox=true'
}
elif ($assigns.Count -eq 0) {
    $newline = if ($gui.Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $insertAt = $main.Match.Index + $main.Match.Length
    $insert = $newline + '$' + $formVar + '.MaximizeBox = $false'
    $newGuiText = $gui.Text.Substring(0,$insertAt) + $insert + $gui.Text.Substring($insertAt)
    $patchMode = 'insert MaximizeBox=false on main form'
}
else {
    throw ('Main form has ' + $assigns.Count + ' MaximizeBox assignments; refusing ambiguous patch.')
}

Test-PowerShellText $newGuiText '1.1 GUI no-maximize patch'
$newMain = Find-MainForm $newGuiText
$newAssigns = @([regex]::Matches($newMain.Segment,$assignPattern))
if ($newAssigns.Count -ne 1 -or $newAssigns[0].Groups['value'].Value -notmatch '(?i)false') {
    throw 'Post-patch MaximizeBox=false assertion failed.'
}

foreach ($key in $protected.Keys) {
    $after = Count-Matches $newGuiText $protected[$key]
    if ($after -ne $beforeCounts[$key]) { throw ('Protected GUI marker count changed for ' + $key + ': ' + $beforeCounts[$key] + ' -> ' + $after) }
}
if (-not $newGuiText.Contains("validation = 'aotr-standalone-v2'")) { throw 'Config V2 marker missing after UI patch.' }
if ((Count-Matches $newGuiText 'A8P-INSTALL-002') -eq 0 -or (Count-Matches $newGuiText 'A8P-INSTALL-004') -eq 0 -or (Count-Matches $newGuiText 'A8P-INSTALL-007') -eq 0) { throw 'Autodetect error markers missing after UI patch.' }

$newGuiBytes = Convert-TextToUtf8LikeOriginal $newGuiText $gui.Bytes
$newCSharpText = Replace-Payload $outer.Text 'GuiGzipBase64' $newGuiBytes
$newCSharpBytes = Convert-TextToUtf8LikeOriginal $newCSharpText $outer.Bytes
$newOuterB64 = Wrap-Base64 ([Convert]::ToBase64String($newCSharpBytes))
$outerGroup = $outer.Match.Groups['data']
$newBuilderText = $builderText.Substring(0,$outerGroup.Index) + $newOuterB64 + $builderText.Substring($outerGroup.Index+$outerGroup.Length)
Test-PowerShellText $newBuilderText '1.1 no-maximize builder'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ('AUTODETECT_V2_V18_STAGE8_UI_1_1_' + $stamp)
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$outBuilder = Join-Path $workRoot 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_ROBUST_AUTODETECT_V2_NO_MAXIMIZE_NONRELEASE.ps1'
$outBytes = Convert-TextToUtf8LikeOriginal $newBuilderText $builderBytes
[IO.File]::WriteAllBytes($outBuilder,$outBytes)

$outHash = Get-Sha256File $outBuilder
$outText = Get-Utf8Text ([IO.File]::ReadAllBytes($outBuilder))
$outOuter = Get-OuterInfo $outText
$outGui = Get-PayloadInfo $outOuter.Text 'GuiGzipBase64'
$outEngine = Get-PayloadInfo $outOuter.Text 'EngineGzipBase64'
Test-PowerShellText $outGui.Text 'roundtrip 1.1 GUI'
Test-PowerShellText $outEngine.Text 'roundtrip ENGINE'
if ($outEngine.Sha256 -ne $ExpectedEngineSha256) { throw ('ENGINE changed unexpectedly: ' + $outEngine.Sha256) }
if ($outGui.Sha256 -eq $ExpectedGuiSha256) { throw 'GUI hash did not change after MaximizeBox patch.' }
if ((Count-Matches $outGui.Text '\bGet-FileHash\b') -ne 0) { throw 'GUI Get-FileHash regression introduced.' }

$report = Join-Path $workRoot 'V18_STAGE8_PREPARE_1_1_NO_MAXIMIZE_REPORT.txt'
$lines = @(
    'AOTR 8P V18 STAGE8 PREPARE LAUNCHER 1.1 NO-MAXIMIZE',
    ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o')),
    ('Input builder SHA256: ' + $builderHash),
    ('Input GUI SHA256: ' + $gui.Sha256),
    ('Output builder SHA256: ' + $outHash),
    ('Output GUI SHA256: ' + $outGui.Sha256),
    ('ENGINE SHA256 unchanged: ' + $outEngine.Sha256),
    ('Main form variable: $' + $formVar),
    ('Main form title: ' + $formTitle),
    ('Patch mode: ' + $patchMode),
    'MaximizeBox after patch: false',
    'Protected V18 counts unchanged: PASS',
    'Robust Autodetect V2 markers preserved: PASS',
    'GUI Get-FileHash count: 0',
    'ENGINE Get-FileHash count: 0',
    '',
    'NON-RELEASE ONLY. Build and visual smoke required before promotion.'
)
[IO.File]::WriteAllLines($report,$lines,[Text.UTF8Encoding]::new($false))

Write-Host '============================================================' -ForegroundColor Green
Write-Host ' V18 STAGE 8 - LAUNCHER 1.1 UI PATCH PREPARED' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('Main form      : $' + $formVar + '  [' + $formTitle + ']')
Write-Host ('Patch mode     : ' + $patchMode) -ForegroundColor Green
Write-Host ('Input builder  : ' + $builderHash)
Write-Host ('Output builder : ' + $outBuilder) -ForegroundColor Green
Write-Host ('Output SHA256  : ' + $outHash) -ForegroundColor Green
Write-Host ('Output GUI SHA : ' + $outGui.Sha256) -ForegroundColor Green
Write-Host ('ENGINE SHA256  : ' + $outEngine.Sha256) -ForegroundColor Green
Write-Host ('Report         : ' + $report)
Write-Host ''
Write-Host 'STAGE 8 PREPARE 1.1: PASS' -ForegroundColor Green
Write-Host 'No EXE was built and no release, config, cache, game, or installed launcher file was modified.' -ForegroundColor Green
