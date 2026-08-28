#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
$builder = Join-Path $PSScriptRoot "v23\BUILD_LAUNCHER_1_1_6_MESSAGES_CANDIDATE.ps1"
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) { throw "V23 launcher builder missing: $builder" }
& $builder -OutputRoot $OutputRoot -LauncherVersion "1.1.6"
if ($LASTEXITCODE -ne 0) { throw "V23 launcher builder failed with exit code $LASTEXITCODE" }
