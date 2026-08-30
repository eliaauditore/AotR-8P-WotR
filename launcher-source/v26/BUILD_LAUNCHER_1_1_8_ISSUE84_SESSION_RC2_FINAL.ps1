#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = "",
    [string]$LauncherVersion = "1.1.8"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$BaseBuilder = Join-Path $PSScriptRoot "BUILD_LAUNCHER_1_1_8_ISSUE84_SESSION_RC2.ps1"
if (-not (Test-Path -LiteralPath $BaseBuilder -PathType Leaf)) {
    throw "RC2 base builder missing: $BaseBuilder"
}

$text = Get-Content -LiteralPath $BaseBuilder -Raw -Encoding UTF8

function Replace-Once([string]$Source,[string]$Old,[string]$New,[string]$Label) {
    $first = $Source.IndexOf($Old,[StringComparison]::Ordinal)
    if ($first -lt 0 -or $first -ne $Source.LastIndexOf($Old,[StringComparison]::Ordinal)) {
        throw "$Label anchor is missing or not unique"
    }
    return $Source.Replace($Old,$New)
}

$text = Replace-Once $text `
    'apply_issue84_session_runtime_rc2_hardening.py' `
    'apply_issue84_session_runtime_rc2_hardening_v2.py' `
    'final RC2 hardening transform path'

$text = Replace-Once $text `
    'AotR_8P_War_of_the_Ring_1.1.8_Issue84_SESSION_RC2.zip' `
    'AotR_8P_War_of_the_Ring_1.1.8_Issue84_SESSION_RC2_FINAL.zip' `
    'final RC2 zip identity'

$text = Replace-Once $text `
    '"_V26_1_1_8_RC2_BUILD"' `
    '"_V26_1_1_8_RC2_FINAL_BUILD"' `
    'final RC2 output root'

$text = Replace-Once $text `
    '"_generated_v26_builder.ps1"' `
    '"_generated_v26_rc2_final_builder.ps1"' `
    'final RC2 generated builder name'

# The V21 compatibility builder originally asserted a literal one-step
# Join-Path $StateRoot "runtime\sessions" string. RC2 intentionally builds the
# same path in two steps so both runtime and sessions can be independently
# checked for reparse/junction manipulation. Patch the generated guard itself
# to validate those two semantic construction lines instead of relying on a
# comment/sentinel in production source.
$oldGuardTransform = @'
$text = Replace-Once $text 'if ($engineText -notmatch [regex]::Escape(''Join-Path $stateRoot "runtime"'')) { throw "Local runtime root patch missing" }' 'if ($engineText -notmatch [regex]::Escape(''Join-Path $StateRoot "runtime\sessions"'')) { throw "Local runtime session root patch missing" }' 'inherited local runtime guard'
'@.Trim()

$newGuardTransform = @'
$text = Replace-Once $text 'if ($engineText -notmatch [regex]::Escape(''Join-Path $stateRoot "runtime"'')) { throw "Local runtime root patch missing" }' 'if ($engineText -notmatch [regex]::Escape(''$runtimeRoot = Join-Path $stateRootFull "runtime"'') -or $engineText -notmatch [regex]::Escape(''$sessionRoot = Join-Path $runtimeRoot "sessions"'')) { throw "Local runtime session-root construction missing" }' 'inherited local runtime guard'
'@.Trim()

$text = Replace-Once $text $oldGuardTransform $newGuardTransform 'semantic inherited session-root guard transform'

$Generated = Join-Path $PSScriptRoot ("_generated_rc2_final_outer_" + [Guid]::NewGuid().ToString("N") + ".ps1")
[IO.File]::WriteAllText($Generated,$text,(New-Object Text.UTF8Encoding($false)))
try {
    & $Generated -OutputRoot $OutputRoot -LauncherVersion $LauncherVersion
}
finally {
    Remove-Item -LiteralPath $Generated -Force -ErrorAction SilentlyContinue
}
