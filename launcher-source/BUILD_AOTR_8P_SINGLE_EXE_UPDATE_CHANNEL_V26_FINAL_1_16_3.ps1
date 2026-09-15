#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
$builder = Join-Path $PSScriptRoot "v26\BUILD_LAUNCHER_1_16_3_ISSUE100_DIAGNOSTIC_CANDIDATE.ps1"
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) { throw "V26 launcher builder missing: $builder" }
& $builder -OutputRoot $OutputRoot -LauncherVersion "1.16.3"
if ($LASTEXITCODE -ne 0) { throw "V26 launcher builder failed with exit code $LASTEXITCODE" }
