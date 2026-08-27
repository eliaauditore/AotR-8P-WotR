#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$ProductionWorkRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE8_1_1_RC2_20260827_033705'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceCommit = '74741c3d02c7f6cb547a31ce0dd3b43476730b61'
$SourcePath = 'research/installer/AOTR_8P_V18_STAGE13_STAGE_FINAL_1_1_BUILDER_CI_FIX_V1.ps1'
$ExpectedSourceBlobSha1 = '38a6235d89cb4c2b06192c648a67005e53997f5b'
$SourceUrl = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $SourceCommit + '/' + $SourcePath
$SourceTemp = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE13_V1_SOURCE.ps1'
$Runtime = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE13_V1_1_RUNTIME.ps1'
Remove-Item $SourceTemp,$Runtime -Force -ErrorAction SilentlyContinue

function Get-GitBlobSha1([byte[]]$Bytes) {
    $header = [Text.Encoding]::ASCII.GetBytes(('blob ' + $Bytes.Length + [char]0))
    $all = New-Object byte[] ($header.Length + $Bytes.Length)
    [Array]::Copy($header,0,$all,0,$header.Length)
    [Array]::Copy($Bytes,0,$all,$header.Length,$Bytes.Length)
    $sha = [Security.Cryptography.SHA1]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($all))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
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

Invoke-WebRequest -Uri $SourceUrl -OutFile $SourceTemp
$sourceBytes = [IO.File]::ReadAllBytes($SourceTemp)
$blob = Get-GitBlobSha1 $sourceBytes
if ($blob -ne $ExpectedSourceBlobSha1) { throw ('Pinned Stage13 V1 blob mismatch. Expected ' + $ExpectedSourceBlobSha1 + ', got ' + $blob) }

$text = [Text.UTF8Encoding]::new($false,$true).GetString($sourceBytes)
$old = "if (`$text -notmatch 'aotr-standalone-v2') { throw 'Robust autodetect Config V2 marker missing from generated builder.' }"
$new = @'
# Config V2 lives inside the gzip+Base64 GUI payload, not in the outer builder text.
$outerPattern = '(?s)\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\s*(?<data>[A-Za-z0-9+/=\r\n]+?)\s*''@\)\)'
$outerMatch = [regex]::Match($text,$outerPattern)
if (-not $outerMatch.Success) { throw 'Could not locate outer C# Base64 template while validating Config V2.' }
$csharpBytes = [Convert]::FromBase64String(($outerMatch.Groups['data'].Value -replace '\s',''))
$csharpOffset = if ($csharpBytes.Length -ge 3 -and $csharpBytes[0] -eq 0xEF -and $csharpBytes[1] -eq 0xBB -and $csharpBytes[2] -eq 0xBF) { 3 } else { 0 }
$csharpText = [Text.UTF8Encoding]::new($false,$true).GetString($csharpBytes,$csharpOffset,$csharpBytes.Length-$csharpOffset)
$guiPattern = '(?s)(?:private\s+)?const\s+string\s+GuiGzipBase64\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
$guiMatch = [regex]::Match($csharpText,$guiPattern)
if (-not $guiMatch.Success) { throw 'Could not locate GuiGzipBase64 while validating Config V2.' }
$guiCompressed = [Convert]::FromBase64String(($guiMatch.Groups['data'].Value -replace '\s',''))
$guiInput = [IO.MemoryStream]::new($guiCompressed)
try {
    $guiGzip = [IO.Compression.GZipStream]::new($guiInput,[IO.Compression.CompressionMode]::Decompress)
    try {
        $guiOutput = [IO.MemoryStream]::new()
        try { $guiGzip.CopyTo($guiOutput); $guiBytes = $guiOutput.ToArray() }
        finally { $guiOutput.Dispose() }
    }
    finally { $guiGzip.Dispose() }
}
finally { $guiInput.Dispose() }
$guiShaObj = [Security.Cryptography.SHA256]::Create()
try { $embeddedGuiSha = ([BitConverter]::ToString($guiShaObj.ComputeHash($guiBytes))).Replace('-','') }
finally { $guiShaObj.Dispose() }
if ($embeddedGuiSha -ne $ExpectedGuiSha) { throw ('Embedded GUI SHA mismatch while validating Config V2. Expected ' + $ExpectedGuiSha + ', got ' + $embeddedGuiSha) }
$guiOffset = if ($guiBytes.Length -ge 3 -and $guiBytes[0] -eq 0xEF -and $guiBytes[1] -eq 0xBB -and $guiBytes[2] -eq 0xBF) { 3 } else { 0 }
$guiText = [Text.UTF8Encoding]::new($false,$true).GetString($guiBytes,$guiOffset,$guiBytes.Length-$guiOffset)
if ($guiText -notmatch 'aotr-standalone-v2') { throw 'Robust autodetect Config V2 marker missing from embedded GUI payload.' }
Write-Host ('Embedded GUI Config V2    : PASS (' + $embeddedGuiSha + ')') -ForegroundColor Green
'@
$text = Replace-ExactOnce $text $old $new 'Config V2 validation layer'

[IO.File]::WriteAllText($Runtime,$text,[Text.UTF8Encoding]::new($false))
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) {
    $errors | Format-List *
    throw 'STOP: Stage13 V1.1 runtime has parser errors.'
}

Write-Host 'Stage13 V1.1 parser validation: PASS' -ForegroundColor Green
Write-Host ('Pinned V1 blob : ' + $ExpectedSourceBlobSha1)
Write-Host ('Runtime        : ' + $Runtime)
Write-Host ''

& $Runtime -Base $Base -ProductionWorkRoot $ProductionWorkRoot
