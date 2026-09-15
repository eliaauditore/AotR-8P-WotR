#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
$builder = Join-Path $PSScriptRoot "v25\BUILD_LAUNCHER_1_16_2_ISSUE97_CANDIDATE.ps1"
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) { throw "V25 launcher builder missing: $builder" }
& $builder -OutputRoot $OutputRoot -LauncherVersion "1.16.2"
if ($LASTEXITCODE -ne 0) { throw "V25 launcher builder failed with exit code $LASTEXITCODE" }
