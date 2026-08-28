#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = "",
    [string]$LauncherVersion = "1.1.6"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$Template = Join-Path $RepoRoot "launcher-source\v22\BUILD_LAUNCHER_1_1_5_MESSAGES_CANDIDATE.ps1"
if (-not (Test-Path -LiteralPath $Template -PathType Leaf)) { throw "V22 builder template missing: $Template" }

$text = Get-Content -LiteralPath $Template -Raw -Encoding UTF8
function Replace-Once([string]$Source,[string]$Old,[string]$New,[string]$Label) {
    $first = $Source.IndexOf($Old,[StringComparison]::Ordinal)
    if ($first -lt 0 -or $first -ne $Source.LastIndexOf($Old,[StringComparison]::Ordinal)) { throw "$Label anchor is missing or not unique" }
    return $Source.Replace($Old,$New)
}

$text = Replace-Once $text '[string]$LauncherVersion = "1.1.5"' '[string]$LauncherVersion = "1.1.6"' 'version default'
$text = Replace-Once $text '"_V22_1_1_5_BUILD"' '"_V23_1_1_6_BUILD"' 'default output root'
$text = Replace-Once $text 'Assert-Hash $DonorExe "4421AD355F99C34CF530F3F1B32C63C73BD28190B8C13652989EB197BC8A1C42" "Frozen public 1.1.4 EXE"' 'Assert-Hash $DonorExe "FF5F907E2D8B2D87A410899ABE9A4512EAB419FF1D48327900932D6F97A85459" "Frozen public 1.1.5 EXE"' 'donor EXE identity'
$text = Replace-Once $text 'Assert-Hash (Join-Path $Resources "launcher_gui.ps1") "4BC7F23B763C8F38AD36557B95A68717A101E2290A9CDAFAEEA104909BB301AE" "Frozen 1.1.4 GUI"' 'Assert-Hash (Join-Path $Resources "launcher_gui.ps1") "25F1BC0B00EED30144215D1979E3B00663FAF20941AB5929B9396AF66EFF1C81" "Frozen 1.1.5 GUI"' 'donor GUI identity'

$oldTransform = @'
& $Python (Join-Path $PSScriptRoot "apply_messages_master_lookup.py") (Join-Path $Resources "launcher_gui.ps1")
if ($LASTEXITCODE -ne 0) { throw "Messages master lookup transform failed" }
'@
$newTransform = @'
& $Python (Join-Path $PSScriptRoot "apply_messages_comments_array.py") (Join-Path $Resources "launcher_gui.ps1")
if ($LASTEXITCODE -ne 0) { throw "Messages PS5 comments-array transform failed" }
'@
$text = Replace-Once $text $oldTransform $newTransform 'transform invocation'

$Generated = Join-Path $PSScriptRoot "_generated_v23_builder.ps1"
[IO.File]::WriteAllText($Generated,$text,(New-Object Text.UTF8Encoding($false)))
try {
    & $Generated -OutputRoot $OutputRoot -LauncherVersion $LauncherVersion
    if ($LASTEXITCODE -ne 0) { throw "Generated V23 builder failed with exit code $LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $Generated -Force -ErrorAction SilentlyContinue
}
