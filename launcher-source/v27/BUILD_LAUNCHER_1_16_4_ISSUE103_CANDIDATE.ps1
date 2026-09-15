#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = "",
    [string]$LauncherVersion = "1.16.4"
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

$text = Replace-Once $text '[string]$LauncherVersion = "1.1.4"' '[string]$LauncherVersion = "1.16.4"' 'version default'
$text = Replace-Once $text '"_V21_1_1_4_BUILD"' '"_V27_1_16_4_ISSUE103_REPORTING_BUILD"' 'default output root'
$text = Replace-Once $text 'Assert-Hash $DonorExe "41CE4281105E61D4595621D0D0C9CFE70CEBA7EB692F1E4ED1C7703899B9FE21" "Frozen public 1.1.3 EXE"' 'Assert-Hash $DonorExe "90A71B36DB8E842E288968A6A3929E4B1D9DB7DA00C25AA12D773D6FB14533AA" "Frozen public 1.16.3 EXE"' 'donor EXE identity'
$text = Replace-Once $text 'Assert-Hash (Join-Path $Resources "launcher_gui.ps1") "585E3D43B407E2E7A26D6B8B6B4D8F06952C81EA58847B21AE71BC6BC54A4A24" "Frozen 1.1.3 GUI"' 'Assert-Hash (Join-Path $Resources "launcher_gui.ps1") "D887A562E7C5700EC4F98AF49F9B807D95A5A91773E1C80091D8D97C3FE9FED3" "Frozen public 1.16.3 GUI"' 'donor GUI identity'
$text = Replace-Once $text 'Assert-Hash (Join-Path $Resources "launcher_engine.ps1") "5DB2F749F10E84322BC471FFF04E25326EFF194FA440175FE9841ED13367F938" "Frozen 1.1.3 engine"' 'Assert-Hash (Join-Path $Resources "launcher_engine.ps1") "72967D49C4D35B4A3FAEBAC4F5866D8B910B9A7FC83568D04B9BA81364AC8917" "Frozen public 1.16.3 engine"' 'donor engine identity'
$text = Replace-Once $text 'Assert-Hash (Join-Path $Resources "final_stable_v7.ps1") "72D00490538BE2222F5BAAF3D8A1648A86071D3A098946A7B8751E7D337300E2" "FINAL_STABLE_V7"' 'Assert-Hash (Join-Path $Resources "final_stable_v7.ps1") "F16522820D7B25CDD4ACF1267B8A300C6BFE661C7FEF636BB611819F7BDC84D3" "FINAL_STABLE_V7"' 'donor FINAL_STABLE_V7 identity'

$oldTransform = @'
& $Python (Join-Path $PSScriptRoot "apply_issue78_runtime_fs.py") (Join-Path $Resources "launcher_engine.ps1") (Join-Path $Resources "launcher_gui.ps1")
if ($LASTEXITCODE -ne 0) { throw "Issue78 runtime filesystem transform failed" }
'@
$newTransform = @'
& $Python (Join-Path $PSScriptRoot "apply_issue103_reporting_gap_fix.py") (Join-Path $Resources "launcher_engine.ps1") (Join-Path $Resources "final_stable_v7.ps1") (Join-Path $Resources "launcher_gui.ps1")
if ($LASTEXITCODE -ne 0) { throw "Issue103 reporting-gap transform failed" }
'@
$text = Replace-Once $text $oldTransform $newTransform 'transform invocation'
$text = Replace-Once $text '"AotR_8P_War_of_the_Ring_1.1.4_Issue78_RC1.zip"' '"AotR_8P_War_of_the_Ring_1.16.4_Issue103_RC1.zip"' 'zip name'
$text = Replace-Once $text 'Write-Host "V21 ISSUE78 CANDIDATE PASS" -ForegroundColor Green' 'Write-Host "V27 ISSUE103 1.16.4 CANDIDATE PASS" -ForegroundColor Green' 'final PASS label'

$Generated = Join-Path $PSScriptRoot "_generated_v27_builder.ps1"
[IO.File]::WriteAllText($Generated,$text,(New-Object Text.UTF8Encoding($false)))
try {
    & $Generated -OutputRoot $OutputRoot -LauncherVersion $LauncherVersion
    if ($LASTEXITCODE -ne 0) { throw "Generated V27 builder failed with exit code $LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $Generated -Force -ErrorAction SilentlyContinue
}
