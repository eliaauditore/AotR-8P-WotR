#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
$builder = Join-Path $PSScriptRoot "v24\BUILD_LAUNCHER_1_16_1_UX_CANDIDATE.ps1"
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) { throw "V24 launcher builder missing: $builder" }
& $builder -OutputRoot $OutputRoot -LauncherVersion "1.16.1"
if ($LASTEXITCODE -ne 0) { throw "V24 launcher builder failed with exit code $LASTEXITCODE" }
