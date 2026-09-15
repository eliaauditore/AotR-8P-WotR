#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
$builder = Join-Path $PSScriptRoot "v27\BUILD_LAUNCHER_1_16_4_ISSUE103_CANDIDATE.ps1"
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) { throw "V27 launcher builder missing: $builder" }

& $builder -OutputRoot $OutputRoot -LauncherVersion "1.16.4"
if ($LASTEXITCODE -ne 0) { throw "V27 launcher builder failed with exit code $LASTEXITCODE" }
