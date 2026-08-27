#requires -version 5.1
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE1_20260827_003823\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_NONRELEASE.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = '6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386'
$ExpectedGuiSha256     = 'D8C3E27E35F3EDA101EE74362C9E744BB942D6F06928B61D22036640C22E5F47'
$ExpectedEngineSha256  = '3A03D47B6A094A4892A146866DFEAD53858C500F812615672D66690D7812A873'

function Get-Sha256File([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-Sha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','')
    }
    finally { $sha.Dispose() }
}

function Expand-GzipBase64Bytes([string]$Base64) {
    $compressed = [Convert]::FromBase64String(($Base64 -replace '\s',''))
    $input = New-Object IO.MemoryStream(,$compressed)
    try {
        $gzip = New-Object IO.Compression.GZipStream($input,[IO.Compression.CompressionMode]::Decompress)
        try {
            $output = New-Object IO.MemoryStream
            try {
                $gzip.CopyTo($output)
                return $output.ToArray()
            }
            finally { $output.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally { $input.Dispose() }
}

function Compress-BytesToGzipBase64([byte[]]$Bytes) {
    $output = New-Object IO.MemoryStream
    try {
        $gzip = New-Object IO.Compression.GZipStream($output,[IO.Compression.CompressionMode]::Compress,$true)
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
    if ($parseText.Length -gt 0 -and [int][char]$parseText[0] -eq 0xFEFF) {
        $parseText = $parseText.Substring(1)
    }
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
    $clean = ($m.Groups['data'].Value -replace '\s','')
    return [PSCustomObject]@{
        Match = $m
        CSharp = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($clean))
    }
}

function Get-PayloadInfo([string]$CSharp,[string]$Name) {
    $pattern = '(?s)(?:private\s+)?const\s+string\s+' + [regex]::Escape($Name) + '\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
    $m = [regex]::Match($CSharp,$pattern)
    if (-not $m.Success) { throw "Could not locate $Name in outer C# template." }
    $bytes = Expand-GzipBase64Bytes $m.Groups['data'].Value
    return [PSCustomObject]@{ Match=$m; Bytes=$bytes; Text=[Text.Encoding]::UTF8.GetString($bytes) }
}

function Replace-Payload([string]$CSharp,[string]$Name,[byte[]]$NewBytes) {
    $info = Get-PayloadInfo $CSharp $Name
    $newB64 = Wrap-Base64 (Compress-BytesToGzipBase64 $NewBytes)
    $g = $info.Match.Groups['data']
    return $CSharp.Substring(0,$g.Index) + $newB64 + $CSharp.Substring($g.Index+$g.Length)
}

function Replace-EmbeddedHashFunction([string]$Text,[string]$Label) {
    $pattern = '(?ms)^function Get-Sha256\(\[string\]\$Path\) \{\r?\n\s*\(Get-FileHash -LiteralPath \$Path -Algorithm SHA256\)\.Hash\.ToUpperInvariant\(\)\r?\n\}'
    $matches = [regex]::Matches($Text,$pattern)
    $directBefore = ([regex]::Matches($Text,'(?i)\bGet-FileHash\b')).Count

    Write-Host ("$Label Get-FileHash occurrences before: $directBefore")
    Write-Host ("$Label replaceable Get-Sha256 blocks : $($matches.Count)")

    if ($directBefore -eq 0) {
        return [PSCustomObject]@{ Text=$Text; Replaced=0; Before=0; After=0 }
    }
    if ($matches.Count -ne 1) {
        throw "$Label contains Get-FileHash but does not have exactly one proven replaceable Get-Sha256 block. Refusing broad patch."
    }

    $replacement = @'
function Get-Sha256([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::Open(
            $Path,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::ReadWrite
        )
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','')
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $sha.Dispose()
    }
}
'@

    $newText = [regex]::Replace($Text,$pattern,[System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement },1)
    $directAfter = ([regex]::Matches($newText,'(?i)\bGet-FileHash\b')).Count
    if ($directAfter -ne 0) {
        throw "$Label still contains $directAfter Get-FileHash occurrence(s) after targeted replacement."
    }
    Test-PowerShellText $newText ($Label + ' after .NET SHA256 replacement')
    return [PSCustomObject]@{ Text=$newText; Replaced=1; Before=$directBefore; After=$directAfter }
}

if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw "Base missing: $Base" }
if (-not (Test-Path -LiteralPath $BuilderPath -PathType Leaf)) { throw "Builder missing: $BuilderPath" }

$builderHash = Get-Sha256File $BuilderPath
if ($builderHash -ne $ExpectedBuilderSha256) { throw "Builder hash mismatch. Expected $ExpectedBuilderSha256, got $builderHash" }

$builderText = [IO.File]::ReadAllText($BuilderPath)
$outer = Get-OuterInfo $builderText
$guiInfo = Get-PayloadInfo $outer.CSharp 'GuiGzipBase64'
$engineInfo = Get-PayloadInfo $outer.CSharp 'EngineGzipBase64'

$guiHash = Get-Sha256Bytes $guiInfo.Bytes
$engineHash = Get-Sha256Bytes $engineInfo.Bytes
if ($guiHash -ne $ExpectedGuiSha256) { throw "GUI payload hash mismatch. Expected $ExpectedGuiSha256, got $guiHash" }
if ($engineHash -ne $ExpectedEngineSha256) { throw "Engine payload hash mismatch. Expected $ExpectedEngineSha256, got $engineHash" }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P STAGE 3 EMBEDDED Get-FileHash HOST FIX V1' -ForegroundColor Cyan
Write-Host ' TARGETED SOURCE PATCH / NON-RELEASE BUILDER ONLY' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Builder SHA : $builderHash" -ForegroundColor Green
Write-Host "GUI SHA     : $guiHash" -ForegroundColor Green
Write-Host "Engine SHA  : $engineHash" -ForegroundColor Green
Write-Host ''

$guiPatch = Replace-EmbeddedHashFunction $guiInfo.Text 'GUI'
$enginePatch = Replace-EmbeddedHashFunction $engineInfo.Text 'ENGINE'
if (($guiPatch.Replaced + $enginePatch.Replaced) -lt 1) { throw 'No embedded Get-FileHash dependency was found to patch.' }

$utf8NoBom = New-Object Text.UTF8Encoding($false)
# Preserve an existing U+FEFF character if present in decoded text; Encoding(false) does not add a new BOM.
$newGuiBytes = $utf8NoBom.GetBytes($guiPatch.Text)
$newEngineBytes = $utf8NoBom.GetBytes($enginePatch.Text)
$newGuiHash = Get-Sha256Bytes $newGuiBytes
$newEngineHash = Get-Sha256Bytes $newEngineBytes

$newCSharp = Replace-Payload $outer.CSharp 'GuiGzipBase64' $newGuiBytes
$newCSharp = Replace-Payload $newCSharp 'EngineGzipBase64' $newEngineBytes
$newOuterB64 = Wrap-Base64 ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($newCSharp)))
$gOuter = $outer.Match.Groups['data']
$newBuilderText = $builderText.Substring(0,$gOuter.Index) + $newOuterB64 + $builderText.Substring($gOuter.Index+$gOuter.Length)
Test-PowerShellText $newBuilderText 'patched V17 builder'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ("AUTODETECT_V2_STAGE3_HASHFIX_" + $stamp)
New-Item -ItemType Directory -Path $workRoot | Out-Null
$newBuilder = Join-Path $workRoot 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_HASHFIX_NONRELEASE.ps1'
[IO.File]::WriteAllText($newBuilder,$newBuilderText,$utf8NoBom)
$newBuilderHash = Get-Sha256File $newBuilder

# Full roundtrip proof from the newly written builder.
$roundText = [IO.File]::ReadAllText($newBuilder)
$roundOuter = Get-OuterInfo $roundText
$roundGui = Get-PayloadInfo $roundOuter.CSharp 'GuiGzipBase64'
$roundEngine = Get-PayloadInfo $roundOuter.CSharp 'EngineGzipBase64'
$roundGuiHash = Get-Sha256Bytes $roundGui.Bytes
$roundEngineHash = Get-Sha256Bytes $roundEngine.Bytes
if ($roundGuiHash -ne $newGuiHash) { throw 'GUI roundtrip hash mismatch.' }
if ($roundEngineHash -ne $newEngineHash) { throw 'Engine roundtrip hash mismatch.' }
if (([regex]::Matches($roundGui.Text,'(?i)\bGet-FileHash\b')).Count -ne 0) { throw 'GUI roundtrip still contains Get-FileHash.' }
if (([regex]::Matches($roundEngine.Text,'(?i)\bGet-FileHash\b')).Count -ne 0) { throw 'Engine roundtrip still contains Get-FileHash.' }
Test-PowerShellText $roundGui.Text 'GUI roundtrip'
Test-PowerShellText $roundEngine.Text 'ENGINE roundtrip'

$reportPath = Join-Path $workRoot 'STAGE3_HASHFIX_REPORT.txt'
$report = @(
    'AOTR 8P STAGE 3 EMBEDDED Get-FileHash HOST FIX V1',
    ('Timestamp: ' + (Get-Date -Format o)),
    ('Input builder: ' + $BuilderPath),
    ('Input builder SHA256: ' + $builderHash),
    ('Input GUI SHA256: ' + $guiHash),
    ('Input ENGINE SHA256: ' + $engineHash),
    ('GUI replacements: ' + $guiPatch.Replaced),
    ('ENGINE replacements: ' + $enginePatch.Replaced),
    ('Output GUI SHA256: ' + $newGuiHash),
    ('Output ENGINE SHA256: ' + $newEngineHash),
    ('Output builder: ' + $newBuilder),
    ('Output builder SHA256: ' + $newBuilderHash),
    ('GUI Get-FileHash after: 0'),
    ('ENGINE Get-FileHash after: 0'),
    ('Original builder modified: NO'),
    ('Release EXE modified: NO'),
    ('Game files modified: NO')
) -join [Environment]::NewLine
[IO.File]::WriteAllText($reportPath,$report+[Environment]::NewLine,$utf8NoBom)

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' STAGE 3 HASH HOST FIX COMPLETE' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host "Work root      : $workRoot"
Write-Host "Patched builder: $newBuilder"
Write-Host "Builder SHA256 : $newBuilderHash" -ForegroundColor Green
Write-Host "GUI SHA256     : $newGuiHash" -ForegroundColor Green
Write-Host "ENGINE SHA256  : $newEngineHash" -ForegroundColor Green
Write-Host "Report         : $reportPath"
Write-Host ''
Write-Host 'GUI Get-FileHash remaining   : 0' -ForegroundColor Green
Write-Host 'ENGINE Get-FileHash remaining: 0' -ForegroundColor Green
Write-Host 'Original builder modified    : NO' -ForegroundColor Green
Write-Host 'Public/release EXE modified  : NO' -ForegroundColor Green
Write-Host 'Game files modified          : NO' -ForegroundColor Green
