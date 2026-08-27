#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$FrozenDonorRoot,
    [string]$OutputRoot = "",
    [string]$LauncherVersion = "1.1.2"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Builder = Join-Path $PSScriptRoot "v19\BUILD_LAUNCHER_1_1_2_CLEAN_CANDIDATE.ps1"
$ExpectedBuilderSha256 = "27F45FF2CF4825D2A7ED443FF8166D2BECCB03800D55460BF9647BF5F4A41082"

if (-not (Test-Path -LiteralPath $Builder -PathType Leaf)) {
    throw "Canonical v19 launcher 1.1.2 builder is missing: $Builder"
}

$ActualBuilderSha256 = (Get-FileHash -LiteralPath $Builder -Algorithm SHA256).Hash.ToUpperInvariant()
if ($ActualBuilderSha256 -ne $ExpectedBuilderSha256) {
    throw "Canonical v19 launcher 1.1.2 builder hash mismatch. Expected $ExpectedBuilderSha256, got $ActualBuilderSha256"
}

& $Builder -FrozenDonorRoot $FrozenDonorRoot -OutputRoot $OutputRoot -LauncherVersion $LauncherVersion
if ($LASTEXITCODE -ne 0) {
    throw "Canonical v19 launcher 1.1.2 builder failed with exit code $LASTEXITCODE"
}
