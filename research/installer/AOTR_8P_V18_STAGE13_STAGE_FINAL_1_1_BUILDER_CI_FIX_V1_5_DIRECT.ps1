#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$ProductionWorkRoot = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE8_1_1_RC2_20260827_033705'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoUrl = 'https://github.com/eliaauditore/AotR-8P-WotR.git'
$FixBranch = 'release/launcher-1.1-ci-builder-fix'
$ExpectedBase = 'bbd7eff483d2cdbf3e799f764433b49195dc55b6'
$GeneratedBuilderName = 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_RC2_TOPBAR_POLISH_NONRELEASE.ps1'
$FinalBuilderName = 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1.ps1'

$ExpectedGeneratedBuilderSha = '0F8303B0E177391AC68AD6EBE03353A1A9312BFF460F937448BEE4D43FA51E82'
$ExpectedGuiSha = '23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C'
$ExpectedEngineSha = '94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA'
$ExpectedReleaseHashes = [ordered]@{
    'AotR 8P WotR Mod.exe' = '9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4'
    'manifest.json' = '61B559D2AEAB72DE2ECB9BF0F2F1E437D2742C34947CA9B414CD7390AAEAA38A'
    'repair-manifest.json' = '684B8B4F39EE7ADB97D4C0837036F742D67C28B0EFC86A2006043BB2B3C36685'
    'payload_ui.big' = '827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376'
    'payload_paper.inc' = '3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43'
}

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

function Assert-Hash([string]$Path,[string]$Expected,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ($Label + ' missing: ' + $Path) }
    $actual = Get-Sha256File $Path
    if ($actual -ne $Expected) { throw ($Label + ' hash mismatch. Expected ' + $Expected + ', got ' + $actual) }
    Write-Host (('{0,-30}: {1}' -f $Label,$actual)) -ForegroundColor Green
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

function Invoke-Git([string]$WorkingDirectory,[string[]]$Arguments,[switch]$ReturnText) {
    $all = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        [void]$all.Add('-C')
        [void]$all.Add($WorkingDirectory)
    }
    foreach ($arg in $Arguments) { [void]$all.Add($arg) }
    $output = & git @all 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        throw ('git ' + ($Arguments -join ' ') + ' failed with exit code ' + $exit + [Environment]::NewLine + (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine))
    }
    if ($ReturnText) { return (($output | ForEach-Object { [string]$_ }) -join "`n").Trim() }
    foreach ($line in $output) { Write-Host ([string]$line) }
}

function Get-RemoteRef([string]$RefName) {
    $text = Invoke-Git '' @('ls-remote',$RepoUrl,$RefName) -ReturnText
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    return ((($text -split "`r?`n")[0] -split '\s+')[0]).Trim()
}

function Get-EmbeddedCSharp([string]$BuilderText) {
    $pattern = '(?s)\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\s*(?<data>[A-Za-z0-9+/=\r\n]+?)\s*''@\)\)'
    $match = [regex]::Match($BuilderText,$pattern)
    if (-not $match.Success) { throw 'Could not locate the outer C# Base64 template in generated builder.' }
    $bytes = [Convert]::FromBase64String(($match.Groups['data'].Value -replace '\s',''))
    $offset = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
    return [Text.UTF8Encoding]::new($false,$true).GetString($bytes,$offset,$bytes.Length-$offset)
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

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git.exe not found in PATH.' }
if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw ('Base missing: ' + $Base) }
if (-not (Test-Path -LiteralPath $ProductionWorkRoot -PathType Container)) { throw ('Production work root missing: ' + $ProductionWorkRoot) }

$generatedBuilder = Join-Path $ProductionWorkRoot $GeneratedBuilderName
[void](Assert-Hash $generatedBuilder $ExpectedGeneratedBuilderSha 'Generated builder')

$builderBytes = [IO.File]::ReadAllBytes($generatedBuilder)
$hadBom = ($builderBytes.Length -ge 3 -and $builderBytes[0] -eq 0xEF -and $builderBytes[1] -eq 0xBB -and $builderBytes[2] -eq 0xBF)
$builderOffset = if ($hadBom) { 3 } else { 0 }
$builderText = [Text.UTF8Encoding]::new($false,$true).GetString($builderBytes,$builderOffset,$builderBytes.Length-$builderOffset)
Test-PowerShellText $builderText 'generated builder'
if ($builderText -match '(?i)invalid\.invalid') { throw 'Generated production builder unexpectedly contains invalid.invalid.' }

$csharpText = Get-EmbeddedCSharp $builderText
$guiBytes = Get-GzipPayload $csharpText 'GuiGzipBase64'
$engineBytes = Get-GzipPayload $csharpText 'EngineGzipBase64'
$guiSha = Get-Sha256Bytes $guiBytes
$engineSha = Get-Sha256Bytes $engineBytes
if ($guiSha -ne $ExpectedGuiSha) { throw ('Embedded GUI SHA mismatch. Expected ' + $ExpectedGuiSha + ', got ' + $guiSha) }
if ($engineSha -ne $ExpectedEngineSha) { throw ('Embedded ENGINE SHA mismatch. Expected ' + $ExpectedEngineSha + ', got ' + $engineSha) }
$guiOffset = if ($guiBytes.Length -ge 3 -and $guiBytes[0] -eq 0xEF -and $guiBytes[1] -eq 0xBB -and $guiBytes[2] -eq 0xBF) { 3 } else { 0 }
$guiText = [Text.UTF8Encoding]::new($false,$true).GetString($guiBytes,$guiOffset,$guiBytes.Length-$guiOffset)
if ($guiText -notmatch 'aotr-standalone-v2') { throw 'Robust autodetect Config V2 marker missing from embedded GUI payload.' }
Write-Host ('Embedded GUI Config V2      : PASS (' + $guiSha + ')') -ForegroundColor Green
Write-Host ('Embedded ENGINE unchanged   : PASS (' + $engineSha + ')') -ForegroundColor Green

$launcherPattern = '^(?<indent>\s*)\[string\]\$LauncherVersion\s*=\s*"1\.0\.0",\s*$'
$launcherRegex = [regex]::new($launcherPattern,[Text.RegularExpressions.RegexOptions]::Multiline)
$launcherMatches = $launcherRegex.Matches($builderText)
if ($launcherMatches.Count -ne 1) { throw ('Expected exactly one V18 LauncherVersion = "1.0.0" declaration, found ' + $launcherMatches.Count) }
$patchedText = $launcherRegex.Replace($builderText,'${indent}[string]$LauncherVersion = "1.1",',1)
Test-PowerShellText $patchedText 'canonical FINAL_1_1 builder'

$reversePattern = '^(?<indent>\s*)\[string\]\$LauncherVersion\s*=\s*"1\.1",\s*$'
$reverseRegex = [regex]::new($reversePattern,[Text.RegularExpressions.RegexOptions]::Multiline)
if ($reverseRegex.Matches($patchedText).Count -ne 1) { throw 'Patched builder does not contain exactly one LauncherVersion = "1.1" declaration.' }
$roundTrip = $reverseRegex.Replace($patchedText,'${indent}[string]$LauncherVersion = "1.0.0",',1)
if ($roundTrip -cne $builderText) { throw 'LauncherVersion patch changed bytes outside the single canonical declaration.' }
Write-Host 'Canonical LauncherVersion     : PASS (1.0.0 -> 1.1 only)' -ForegroundColor Green

$remoteMain = Get-RemoteRef 'refs/heads/main'
$remoteFix = Get-RemoteRef ('refs/heads/' + $FixBranch)
if ($remoteMain -ne $ExpectedBase) { throw ('main moved. Expected ' + $ExpectedBase + ', got ' + $remoteMain) }
if ($remoteFix -ne $ExpectedBase) { throw ('CI-fix branch moved. Expected ' + $ExpectedBase + ', got ' + $remoteFix) }
Write-Host ('GitHub refs pinned             : PASS (' + $ExpectedBase + ')') -ForegroundColor Green

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ('AUTODETECT_V2_V18_STAGE13_DIRECT_' + $stamp)
$cloneRoot = Join-Path $workRoot 'repo'
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

Invoke-Git '' @('clone','--no-tags','--single-branch','--branch',$FixBranch,$RepoUrl,$cloneRoot)
Invoke-Git $cloneRoot @('config','core.autocrlf','false')
Invoke-Git $cloneRoot @('config','core.safecrlf','false')
Invoke-Git $cloneRoot @('config','user.name','eliaauditore')
Invoke-Git $cloneRoot @('config','user.email','eliaauditore@users.noreply.github.com')
$cloneHead = Invoke-Git $cloneRoot @('rev-parse','HEAD') -ReturnText
if ($cloneHead -ne $ExpectedBase) { throw ('Clone baseline mismatch. Expected ' + $ExpectedBase + ', got ' + $cloneHead) }

foreach ($name in $ExpectedReleaseHashes.Keys) {
    [void](Assert-Hash (Join-Path $cloneRoot $name) $ExpectedReleaseHashes[$name] ('Release root ' + $name))
}

$dest = Join-Path $cloneRoot ('launcher-source\' + $FinalBuilderName)
$utf8NoBom = [Text.UTF8Encoding]::new($false)
if ($hadBom) {
    $body = $utf8NoBom.GetBytes($patchedText)
    $finalBytes = New-Object byte[] ($body.Length + 3)
    $finalBytes[0] = 0xEF
    $finalBytes[1] = 0xBB
    $finalBytes[2] = 0xBF
    [Array]::Copy($body,0,$finalBytes,3,$body.Length)
    [IO.File]::WriteAllBytes($dest,$finalBytes)
} else {
    [IO.File]::WriteAllText($dest,$patchedText,$utf8NoBom)
}
$finalBuilderSha = Get-Sha256File $dest
Test-PowerShellText (Get-Content -LiteralPath $dest -Raw) 'written FINAL_1_1 builder'
Write-Host ('Canonical FINAL_1_1 SHA256  : ' + $finalBuilderSha) -ForegroundColor Green

foreach ($name in $ExpectedReleaseHashes.Keys) {
    [void](Assert-Hash (Join-Path $cloneRoot $name) $ExpectedReleaseHashes[$name] ('Release root after write ' + $name))
}

$targetPath = 'launcher-source/' + $FinalBuilderName
Invoke-Git $cloneRoot @('add','--',$targetPath)
$changedText = Invoke-Git $cloneRoot @('diff','--cached','--name-only') -ReturnText
$changed = @($changedText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($changed.Count -ne 1 -or $changed[0] -ne $targetPath) { throw ('Unexpected staged paths: ' + ($changed -join ', ')) }
Write-Host ('Staged path                    : ' + $changed[0]) -ForegroundColor Green

$remoteMainRace = Get-RemoteRef 'refs/heads/main'
$remoteFixRace = Get-RemoteRef ('refs/heads/' + $FixBranch)
if ($remoteMainRace -ne $ExpectedBase -or $remoteFixRace -ne $ExpectedBase) { throw 'GitHub refs moved before CI-fix commit. Stop and reassess.' }

Invoke-Git $cloneRoot @('commit','-m','Add canonical launcher 1.1 final builder')
$commit = Invoke-Git $cloneRoot @('rev-parse','HEAD') -ReturnText
$parent = Invoke-Git $cloneRoot @('rev-parse','HEAD^') -ReturnText
if ($parent -ne $ExpectedBase) { throw ('CI-fix commit parent mismatch. Expected ' + $ExpectedBase + ', got ' + $parent) }
Invoke-Git $cloneRoot @('push','origin',('HEAD:refs/heads/' + $FixBranch))

$remoteFixAfter = Get-RemoteRef ('refs/heads/' + $FixBranch)
$remoteMainAfter = Get-RemoteRef 'refs/heads/main'
if ($remoteFixAfter -ne $commit) { throw ('CI-fix branch push verification failed. Expected ' + $commit + ', got ' + $remoteFixAfter) }
if ($remoteMainAfter -ne $ExpectedBase) { throw ('main changed unexpectedly. Expected ' + $ExpectedBase + ', got ' + $remoteMainAfter) }

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' STAGE 13 V1.5 DIRECT FINAL BUILDER STAGING: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('Staged commit        : ' + $commit) -ForegroundColor Green
Write-Host ('Final builder SHA256 : ' + $finalBuilderSha) -ForegroundColor Green
Write-Host ('Branch               : ' + $FixBranch) -ForegroundColor Green
Write-Host ('Main remains         : ' + $remoteMainAfter) -ForegroundColor Green
Write-Host ''
Write-Host 'Only the canonical FINAL_1_1 builder was committed. Release-root bytes remain unchanged.' -ForegroundColor Yellow
