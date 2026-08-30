#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = "",
    [string]$LauncherVersion = "1.1.8"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$BaseBuilder = Join-Path $PSScriptRoot "BUILD_LAUNCHER_1_1_8_ISSUE84_SESSION_RC2.ps1"
if (-not (Test-Path -LiteralPath $BaseBuilder -PathType Leaf)) { throw "RC2 base builder missing: $BaseBuilder" }

$text = Get-Content -LiteralPath $BaseBuilder -Raw -Encoding UTF8
function Replace-Once([string]$Source,[string]$Old,[string]$New,[string]$Label) {
    $first = $Source.IndexOf($Old,[StringComparison]::Ordinal)
    if ($first -lt 0 -or $first -ne $Source.LastIndexOf($Old,[StringComparison]::Ordinal)) { throw "$Label anchor is missing or not unique" }
    return $Source.Replace($Old,$New)
}

$text = Replace-Once $text `
    'apply_issue84_session_runtime_rc2_hardening.py' `
    'apply_issue84_session_runtime_rc2_hardening_v2.py' `
    'RC2 hardening transform path'
$text = Replace-Once $text `
    'AotR_8P_War_of_the_Ring_1.1.8_Issue84_SESSION_RC2.zip' `
    'AotR_8P_War_of_the_Ring_1.1.8_Issue84_SESSION_RC2_V2.zip' `
    'RC2 V2 zip identity'
$text = Replace-Once $text `
    '"_V26_1_1_8_RC2_BUILD"' `
    '"_V26_1_1_8_RC2_V2_BUILD"' `
    'RC2 V2 output root'
$text = Replace-Once $text `
    '"_generated_v26_builder.ps1"' `
    '"_generated_v26_rc2_v2_builder.ps1"' `
    'RC2 V2 generated builder name'

# Keep the generated wrapper beside V26 so its $PSScriptRoot remains the repo path.
$Generated = Join-Path $PSScriptRoot ("_generated_rc2_v2_outer_" + [Guid]::NewGuid().ToString("N") + ".ps1")
[IO.File]::WriteAllText($Generated,$text,(New-Object Text.UTF8Encoding($false)))
try {
    & $Generated -OutputRoot $OutputRoot -LauncherVersion $LauncherVersion
}
finally {
    Remove-Item -LiteralPath $Generated -Force -ErrorAction SilentlyContinue
}
