#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$FrozenDonorRoot,
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Builder = Join-Path $PSScriptRoot "v20\BUILD_LAUNCHER_1_1_3_CLEAN_CANDIDATE.ps1"
if (-not (Test-Path -LiteralPath $Builder -PathType Leaf)) {
    throw "Canonical V20 launcher 1.1.3 builder is missing: $Builder"
}

& $Builder -FrozenDonorRoot $FrozenDonorRoot -OutputRoot $OutputRoot -LauncherVersion "1.1.3"
if ($LASTEXITCODE -ne 0) {
    throw "Canonical V20 launcher 1.1.3 builder failed with exit code $LASTEXITCODE"
}
