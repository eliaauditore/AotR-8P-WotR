#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [string]$ReportPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToUpperInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Add-Finding(
    [System.Collections.Generic.List[string]]$Findings,
    [string]$Category,
    [string]$Path,
    [string]$Detail
) {
    $Findings.Add(("- **{0}** `{1}` - {2}" -f $Category, $Path, $Detail))
}

function Test-ByteSequence([byte[]]$Haystack, [byte[]]$Needle) {
    if ($null -eq $Haystack -or $null -eq $Needle -or $Needle.Length -eq 0 -or $Haystack.Length -lt $Needle.Length) {
        return $false
    }

    for ($i = 0; $i -le ($Haystack.Length - $Needle.Length); $i++) {
        $match = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Haystack[$i + $j] -ne $Needle[$j]) {
                $match = $false
                break
            }
        }
        if ($match) { return $true }
    }
    return $false
}

$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "SourceRoot does not exist or is not a directory: $SourceRoot"
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $reportRoot = Join-Path $env:TEMP "AotR8P_Guardian"
    New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $ReportPath = Join-Path $reportRoot ("SIGNPATH_SOURCE_BOUNDARY_{0}.md" -f $stamp)
}
else {
    $ReportPath = [IO.Path]::GetFullPath($ReportPath)
    $parent = Split-Path -Parent $ReportPath
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
}

$blockedAssetHashes = [ordered]@{
    "BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6" = "frozen AotR/Middle-earth launcher skin"
    "3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A" = "donor-extracted launcher icon"
    "D4DC9A47F0E2FD9715D92F8DD4C3831B9AB95F8CA34E98937F019B7574294177" = "frozen row-1 patch image"
    "58B9A7173CE1C9C30C85EE76D15D54E3D40B3E7E14E25D0C1FE5D8EFD89E6D8E" = "frozen row-2 patch image"
    "7F86C02BC02D2E57D66202AF9C526D6FAE13CFC9B7CB1EFF1BB61C165B25278C" = "frozen row-3 patch image"
    "35DCBCBE6E625C5C06EC36BAB3CA51A6F4EE29DA3DFF4CAEEDD69BC87D873DF3" = "frozen ready patch image"
}

$knownCodeSequences = [ordered]@{
    "8B45FCC1E8100FBFC089460C" = "original RawWheelHook bytes"
    "558BEC51518B4508" = "original Strategic Map Handler bytes"
    "F30F588634010000F30F118634010000" = "original Zoom Update bytes"
    "8B0D5849DE00" = "original LivingWorld camera-global reference bytes"
    "8B411C8B5424043BD07412505189511C" = "original Strategic Cancel/Release callback bytes"
}

$donorTokens = @(
    "FrozenDonorRoot",
    "Issue33SkinGzipBase64",
    "GuiGzipBase64",
    "EngineGzipBase64"
)

$findings = New-Object 'System.Collections.Generic.List[string]'
$files = @(Get-ChildItem -LiteralPath $SourceRoot -File -Recurse -ErrorAction Stop)

foreach ($file in $files) {
    $relative = $file.FullName.Substring($SourceRoot.Length).TrimStart('\', '/')

    try {
        $hash = Get-Sha256 $file.FullName
        if ($blockedAssetHashes.Contains($hash)) {
            Add-Finding $findings "BLOCKED_ASSET" $relative ("SHA256 {0} matches {1}." -f $hash, $blockedAssetHashes[$hash])
        }
    }
    catch {
        Add-Finding $findings "READ_ERROR" $relative ("could not hash file: {0}" -f $_.Exception.Message)
        continue
    }

    $extension = $file.Extension.ToLowerInvariant()
    if ($extension -in @('.ps1', '.psm1', '.cs', '.py')) {
        try {
            $text = [IO.File]::ReadAllText($file.FullName)
            foreach ($token in $donorTokens) {
                if ($text.IndexOf($token, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    Add-Finding $findings "DONOR_DEPENDENCY" $relative ("contains forbidden donor token '{0}'." -f $token)
                }
            }

            $compact = ($text -replace '\s', '').ToUpperInvariant()
            foreach ($hex in $knownCodeSequences.Keys) {
                $bytes = @()
                for ($i = 0; $i -lt $hex.Length; $i += 2) {
                    $bytes += ("0X" + $hex.Substring($i, 2))
                }
                $literal = ($bytes -join ',')
                if ($compact.Contains($literal) -or $compact.Contains($hex)) {
                    Add-Finding $findings "LITERAL_GAME_CODE" $relative ("contains {0}." -f $knownCodeSequences[$hex])
                }
            }
        }
        catch {
            Add-Finding $findings "READ_ERROR" $relative ("could not inspect text source: {0}" -f $_.Exception.Message)
        }
    }

    if ($extension -eq '.bin') {
        try {
            [byte[]]$data = [IO.File]::ReadAllBytes($file.FullName)
            foreach ($hex in $knownCodeSequences.Keys) {
                [byte[]]$needle = New-Object byte[] ($hex.Length / 2)
                for ($i = 0; $i -lt $needle.Length; $i++) {
                    $needle[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
                }
                if (Test-ByteSequence $data $needle) {
                    Add-Finding $findings "BINARY_GAME_CODE" $relative ("contains {0}." -f $knownCodeSequences[$hex])
                }
            }
        }
        catch {
            Add-Finding $findings "READ_ERROR" $relative ("could not inspect binary: {0}" -f $_.Exception.Message)
        }
    }
}

$lines = New-Object 'System.Collections.Generic.List[string]'
$lines.Add("# SignPath launcher source-boundary verification")
$lines.Add("")
$lines.Add(("- Timestamp: {0}" -f (Get-Date -Format o)))
$lines.Add(("- Source root: {0}" -f $SourceRoot))
$lines.Add(("- Files inspected: {0}" -f $files.Count))
$lines.Add("")

if ($findings.Count -eq 0) {
    $lines.Add("Overall: **PASS**")
    $lines.Add("")
    $lines.Add("No currently known frozen visual-resource hashes, donor-source tokens, or known original game-code byte sequences were found in this candidate source boundary.")
}
else {
    $lines.Add("Overall: **FAIL / REVIEW_REQUIRED**")
    $lines.Add("")
    $lines.Add("## Findings")
    $lines.Add("")
    foreach ($finding in $findings) { $lines.Add($finding) }
}

$lines.Add("")
$lines.Add("## Evidence boundary")
$lines.Add("")
$lines.Add("A PASS proves only that this directory avoids the currently known blocked hashes/tokens/byte sequences. It does not itself establish copyright ownership, OSI-license eligibility, SignPath Foundation approval, runtime correctness, or Smart App Control acceptance.")

$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

Write-Host "Source root: $SourceRoot"
Write-Host "Files inspected: $($files.Count)"
Write-Host "Findings: $($findings.Count)"
Write-Host "Report: $ReportPath"

if ($findings.Count -eq 0) {
    Write-Host "PASS: no known SignPath source-boundary blockers detected." -ForegroundColor Green
    exit 0
}

Write-Host "FAIL: known SignPath source-boundary blockers detected." -ForegroundColor Red
exit 1
