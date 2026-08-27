#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SourceCommit = 'bcb274097a053718172c36ba9afce692be9306e4'
$SourcePath = 'research/installer/AOTR_8P_V18_STAGE4_AUTODETECT_MATRIX_CORE_V1.ps1'
$SourceUrl = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/$SourcePath"
$ExpectedGitBlobSha1 = 'cb9605f724cb9818b264c216586dbcbc8c33d095'

function Get-GitBlobSha1([string]$Path) {
    $body = [IO.File]::ReadAllBytes($Path)
    $header = [Text.Encoding]::UTF8.GetBytes(('blob ' + $body.Length + [char]0))
    $all = New-Object byte[] ($header.Length + $body.Length)
    [Array]::Copy($header,0,$all,0,$header.Length)
    [Array]::Copy($body,0,$all,$header.Length,$body.Length)
    $sha1 = [Security.Cryptography.SHA1]::Create()
    try { return ([BitConverter]::ToString($sha1.ComputeHash($all))).Replace('-','').ToLowerInvariant() }
    finally { $sha1.Dispose() }
}

function Replace-ExactOnce {
    param(
        [string]$Text,
        [string]$Old,
        [string]$New,
        [string]$Label
    )
    $count = ([regex]::Matches($Text,[regex]::Escape($Old))).Count
    if ($count -ne 1) { throw "Expected exactly one patch target for $Label, found $count." }
    return $Text.Replace($Old,$New)
}

$source = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE4_AUTODETECT_MATRIX_CORE_V1_SOURCE.ps1'
$runtime = Join-Path $env:TEMP 'AOTR_8P_V18_STAGE4_AUTODETECT_MATRIX_CORE_V1_3_RUNTIME.ps1'
Remove-Item $source,$runtime -Force -ErrorAction SilentlyContinue

Invoke-WebRequest -Uri $SourceUrl -OutFile $source
$blob = Get-GitBlobSha1 $source
if ($blob -ne $ExpectedGitBlobSha1) {
    throw "Pinned Stage4 source blob mismatch. Expected $ExpectedGitBlobSha1, got $blob"
}

$text = [IO.File]::ReadAllText($source)

# Load the GUI types referenced by the exact resolver source before dot-sourcing it.
$text = Replace-ExactOnce $text `
    'Set-StrictMode -Version Latest' `
    "Set-StrictMode -Version Latest`r`nAdd-Type -AssemblyName System.Windows.Forms -ErrorAction Stop" `
    'WinForms assembly load'

# Materialize the compared objects as an array before piping to Sort-Object.
$text = Replace-ExactOnce $text `
    '$ranked = @($full,$minimal | Sort-Object @{Expression=''Score'';Descending=$true},Root)' `
    '$ranked = @(@($full,$minimal) | Sort-Object @{Expression=''Score'';Descending=$true},Root)' `
    'full/minimal ranking materialization'

$text = Replace-ExactOnce $text `
    '$tieRanked = @($full,$tie | Sort-Object @{Expression=''Score'';Descending=$true},Root)' `
    '$tieRanked = @(@($full,$tie) | Sort-Object @{Expression=''Score'';Descending=$true},Root)' `
    'tie ranking materialization'

# PowerShell cannot use an if-expression directly as an ordinary argument in this location.
$oldConfigDetail = "    Add-Result 'real launcher config unchanged' ([bool]`$realConfigUnchanged) (if (`$realConfigExisted) { 'hash before/after compared' } else { 'remained absent' })"
$newConfigDetail = "    `$realConfigDetail = if (`$realConfigExisted) { 'hash before/after compared' } else { 'remained absent' }`r`n    Add-Result 'real launcher config unchanged' ([bool]`$realConfigUnchanged) `$realConfigDetail"
$text = Replace-ExactOnce $text $oldConfigDetail $newConfigDetail 'real-config detail expression'

# The original assertion used a regex double-quoted string containing \$true. PowerShell expands
# $true there and hands regex the invalid escape sequence \True. Use literal Contains instead.
$oldResolverMarker = 'if ($resolverText -notmatch "Sort-Object @{Expression=''Score'';Descending=\$true},Root") { throw ''Current resolver lacks expected score-first ranking.'' }'
$oldResolverMarker = $oldResolverMarker.Replace('\"','"')
$newResolverMarker = 'if (-not $resolverText.Contains(''Sort-Object @{Expression=''''Score'''';Descending=$true},Root'')) { throw ''Current resolver lacks expected score-first ranking.'' }'
$text = Replace-ExactOnce $text $oldResolverMarker $newResolverMarker 'literal resolver ranking marker check'

# Do not use Join-Path against a deliberately nonexistent Z: drive; that would test the provider,
# not the launcher resolver. Build the stale paths as literal strings instead.
$text = Replace-ExactOnce $text `
    "        runtime = (Join-Path `$staleRoot 'rotwk')" `
    "        runtime = (`$staleRoot + '\rotwk')" `
    'stale runtime literal path'
$text = Replace-ExactOnce $text `
    "        source_mod = (Join-Path `$staleRoot 'aotr')" `
    "        source_mod = (`$staleRoot + '\aotr')" `
    'stale source_mod literal path'
$text = Replace-ExactOnce $text `
    "        game_dat = (Join-Path `$staleRoot 'rotwk\game.dat')" `
    "        game_dat = (`$staleRoot + '\rotwk\game.dat')" `
    'stale game_dat literal path'

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) {
    $errors | Format-List * | Out-Host
    throw 'Stage4 core matrix V1.3 still has parser errors.'
}

[IO.File]::WriteAllText($runtime,$text,[Text.UTF8Encoding]::new($false))
Write-Host 'Stage4 core matrix V1.3 parser validation: PASS' -ForegroundColor Green
Write-Host "Pinned source blob : $blob" -ForegroundColor Green
Write-Host "Runtime            : $runtime"
Write-Host ''

& $runtime -Base $Base
