#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = "",
    [string]$LauncherVersion = "1.1.8"
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

$text = Replace-Once $text '[string]$LauncherVersion = "1.1.4"' '[string]$LauncherVersion = "1.1.8"' 'version default'
$text = Replace-Once $text '"_V21_1_1_4_BUILD"' '"_V25_1_1_8_BUILD"' 'default output root'
$text = Replace-Once $text 'Assert-Hash $DonorExe "41CE4281105E61D4595621D0D0C9CFE70CEBA7EB692F1E4ED1C7703899B9FE21" "Frozen public 1.1.3 EXE"' 'Assert-Hash $DonorExe "E5FD1761FB84E452782AFD970225775CB55096C22628F1B9061344C282861431" "Frozen public 1.1.6 EXE"' 'donor EXE identity'
$text = Replace-Once $text 'Assert-Hash (Join-Path $Resources "launcher_gui.ps1") "585E3D43B407E2E7A26D6B8B6B4D8F06952C81EA58847B21AE71BC6BC54A4A24" "Frozen 1.1.3 GUI"' 'Assert-Hash (Join-Path $Resources "launcher_gui.ps1") "8A31D3EDC48B5915AC552EFB26DFF48CEABB1022D24C0A90834930117046A2AA" "Frozen 1.1.6 GUI"' 'donor GUI identity'
$text = Replace-Once $text 'Assert-Hash (Join-Path $Resources "launcher_engine.ps1") "5DB2F749F10E84322BC471FFF04E25326EFF194FA440175FE9841ED13367F938" "Frozen 1.1.3 engine"' 'Assert-Hash (Join-Path $Resources "launcher_engine.ps1") "E9E2452FF56A66D57FF63C0B1654CFE0C856F4D5FA66C558E8F237C9ABABF641" "Frozen 1.1.6 engine"' 'donor engine identity'

$oldTransform = @'
& $Python (Join-Path $PSScriptRoot "apply_issue78_runtime_fs.py") (Join-Path $Resources "launcher_engine.ps1") (Join-Path $Resources "launcher_gui.ps1")
if ($LASTEXITCODE -ne 0) { throw "Issue78 runtime filesystem transform failed" }
'@
$newTransform = @'
$SourceTemplateV25 = Join-Path $Work "launcher_v25.cs"
& $Python `
    (Join-Path $PSScriptRoot "apply_issue84_session_runtime.py") `
    (Join-Path $Resources "launcher_engine.ps1") `
    (Join-Path $Resources "launcher_gui.ps1") `
    (Join-Path $RepoRoot "launcher-source\v20\launcher.cs") `
    $SourceTemplateV25
if ($LASTEXITCODE -ne 0) { throw "Issue84 transient-session transform failed" }
& $Python `
    (Join-Path $PSScriptRoot "apply_issue84_session_runtime_hardening.py") `
    (Join-Path $Resources "launcher_engine.ps1")
if ($LASTEXITCODE -ne 0) { throw "Issue84 session hardening transform failed" }
& $Python `
    (Join-Path $PSScriptRoot "apply_issue84_legacy_cleanup_hardening.py") `
    (Join-Path $Resources "launcher_gui.ps1")
if ($LASTEXITCODE -ne 0) { throw "Issue84 chained legacy cleanup hardening failed" }
'@
$text = Replace-Once $text $oldTransform $newTransform 'session transform invocation'
$text = Replace-Once $text '$SourceTemplate = Join-Path $RepoRoot "launcher-source\v20\launcher.cs"' '$SourceTemplate = $SourceTemplateV25' 'C# source template redirect'
$text = Replace-Once $text 'AotR_8P_War_of_the_Ring_1.1.4_Issue78_RC1.zip' 'AotR_8P_War_of_the_Ring_1.1.8_Issue84_SESSION_RC1.zip' 'RC zip name'
$text = Replace-Once $text 'if ($engineText -notmatch [regex]::Escape(''Join-Path $stateRoot "runtime"'')) { throw "Local runtime root patch missing" }' 'if ($engineText -notmatch [regex]::Escape(''Join-Path $StateRoot "runtime\sessions"'')) { throw "Local runtime session root patch missing" }' 'inherited local runtime guard'

$oldStatic = 'Write-Host "ISSUE78 STATIC CONTRACT PASS" -ForegroundColor Green'
$newStatic = @'
Write-Host "ISSUE78 STATIC CONTRACT PASS" -ForegroundColor Green
if ($engineText -notmatch 'AOTR8P_SESSION_') { throw "Issue84 session runtime naming missing" }
if ($engineText -notmatch 'AOTR8P_SESSION\.json') { throw "Issue84 runtime marker missing" }
if ($engineText -notmatch '--cleanup-runtime') { throw "Issue84 engine cleanup watcher missing" }
if ($engineText -notmatch [regex]::Escape('runtime\sessions')) { throw "Issue84 local session root missing" }
if ($engineText -notmatch 'Write-AotR8PSessionMarker') { throw "Issue84 prelaunch marker writer missing" }
if ($engineText -match [regex]::Escape('Join-Path $runtimeStageRoot ("_AOTR_8P_WOTR_RUNTIME_V4_" + $PID)')) { throw "Issue84 legacy V4 runtime creation remains" }
if ($guiText -notmatch '--cleanup-runtime') { throw "Issue84 Auto-Repair transient cleanup helper missing" }
if ($guiText -match [regex]::Escape('Move-Item -LiteralPath $runtimePath -Destination $quarantine')) { throw "Issue84 persistent quarantine move remains" }
if ($guiText -match [regex]::Escape('$leaf + "_REPAIR_"')) { throw "Issue84 persistent REPAIR name construction remains" }
if ($guiText -notmatch [regex]::Escape('(?:_REPAIR_\d{8}_\d{6}_\d+)+')) { throw "Issue84 chained legacy repair matcher missing" }
$csText = [IO.File]::ReadAllText($SourceTemplateV25)
foreach ($needle in @('RunRuntimeCleanupHelper','DeleteRuntimeTreeNoFollow','CleanupStaleRuntimeSessions','IsValidRuntimeSessionPath')) {
    if ($csText -notmatch [regex]::Escape($needle)) { throw "Issue84 C# runtime cleanup contract missing: $needle" }
}
Write-Host "ISSUE84 TRANSIENT SESSION STATIC CONTRACT PASS" -ForegroundColor Green
'@
$text = Replace-Once $text $oldStatic $newStatic 'Issue84 transient-session static contract insertion'

$Generated = Join-Path $PSScriptRoot "_generated_v25_builder.ps1"
[IO.File]::WriteAllText($Generated,$text,(New-Object Text.UTF8Encoding($false)))
try {
    & $Generated -OutputRoot $OutputRoot -LauncherVersion $LauncherVersion
}
finally {
    Remove-Item -LiteralPath $Generated -Force -ErrorAction SilentlyContinue
}
