#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = "",
    [string]$LauncherVersion = "1.1.6"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$Template = Join-Path $RepoRoot "launcher-source\v21\BUILD_LAUNCHER_1_1_4_ISSUE78_CANDIDATE.ps1"
if (-not (Test-Path -LiteralPath $Template -PathType Leaf)) { throw "V21 builder template missing: $Template" }

$text = Get-Content -LiteralPath $Template -Raw -Encoding UTF8
function Replace-Once([string]$Source,[string]$Old,[string]$New,[string]$Label) {
    $first = $Source.IndexOf($Old,[StringComparison]::Ordinal)
    if ($first -lt 0 -or $first -ne $Source.LastIndexOf($Old,[StringComparison]::Ordinal)) { throw "$Label anchor is missing or not unique" }
    return $Source.Replace($Old,$New)
}

$text = Replace-Once $text '[string]$LauncherVersion = "1.1.4"' '[string]$LauncherVersion = "1.1.6"' 'version default'
$text = Replace-Once $text '"_V21_1_1_4_BUILD"' '"_V23_1_1_6_BUILD"' 'default output root'
$text = Replace-Once $text 'Assert-Hash $DonorExe "41CE4281105E61D4595621D0D0C9CFE70CEBA7EB692F1E4ED1C7703899B9FE21" "Frozen public 1.1.3 EXE"' 'Assert-Hash $DonorExe "FF5F907E2D8B2D87A410899ABE9A4512EAB419FF1D48327900932D6F97A85459" "Frozen public 1.1.5 EXE"' 'donor EXE identity'
$text = Replace-Once $text 'Assert-Hash (Join-Path $Resources "launcher_gui.ps1") "585E3D43B407E2E7A26D6B8B6B4D8F06952C81EA58847B21AE71BC6BC54A4A24" "Frozen 1.1.3 GUI"' 'Assert-Hash (Join-Path $Resources "launcher_gui.ps1") "25F1BC0B00EED30144215D1979E3B00663FAF20941AB5929B9396AF66EFF1C81" "Frozen 1.1.5 GUI"' 'donor GUI identity'
$text = Replace-Once $text 'Assert-Hash (Join-Path $Resources "launcher_engine.ps1") "5DB2F749F10E84322BC471FFF04E25326EFF194FA440175FE9841ED13367F938" "Frozen 1.1.3 engine"' 'Assert-Hash (Join-Path $Resources "launcher_engine.ps1") "E9E2452FF56A66D57FF63C0B1654CFE0C856F4D5FA66C558E8F237C9ABABF641" "Frozen 1.1.5 engine"' 'donor engine identity'

$oldTransform = @'
& $Python (Join-Path $PSScriptRoot "apply_issue78_runtime_fs.py") (Join-Path $Resources "launcher_engine.ps1") (Join-Path $Resources "launcher_gui.ps1")
if ($LASTEXITCODE -ne 0) { throw "Issue78 runtime filesystem transform failed" }
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
