#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$Builder = Join-Path $PSScriptRoot "v22\BUILD_LAUNCHER_1_1_5_MESSAGES_CANDIDATE.ps1"
if (-not (Test-Path -LiteralPath $Builder -PathType Leaf)) { throw "Canonical V22 launcher 1.1.5 builder is missing: $Builder" }
& $Builder -OutputRoot $OutputRoot -LauncherVersion "1.1.5"
if ($LASTEXITCODE -ne 0) { throw "Canonical V22 launcher 1.1.5 builder failed with exit code $LASTEXITCODE" }
