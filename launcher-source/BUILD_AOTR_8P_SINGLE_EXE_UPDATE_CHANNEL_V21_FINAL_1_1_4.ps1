#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Builder = Join-Path $PSScriptRoot "v21\BUILD_LAUNCHER_1_1_4_ISSUE78_CANDIDATE.ps1"
if (-not (Test-Path -LiteralPath $Builder -PathType Leaf)) {
    throw "Canonical V21 launcher 1.1.4 builder is missing: $Builder"
}

& $Builder -OutputRoot $OutputRoot -LauncherVersion "1.1.4"
if ($LASTEXITCODE -ne 0) {
    throw "Canonical V21 launcher 1.1.4 builder failed with exit code $LASTEXITCODE"
}
