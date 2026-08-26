#requires -version 5.1
[CmdletBinding()]
param(
    [string]$Stage2V3Path = (Join-Path $env:TEMP 'AOTR_8P_STAGE2_BUILD_NONRELEASE_V3.ps1')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedV3Sha256 = 'BF2F4146585132D4E9ECB92A3158DAEF6AD25F44F33D78AC2B667CE357D23C78'

if (-not (Test-Path -LiteralPath $Stage2V3Path -PathType Leaf)) {
    throw "Stage 2 V3 script not found: $Stage2V3Path"
}

$actual = (Get-FileHash -LiteralPath $Stage2V3Path -Algorithm SHA256).Hash.ToUpperInvariant()
if ($actual -ne $ExpectedV3Sha256) {
    throw "Stage 2 V3 checkpoint mismatch. Expected $ExpectedV3Sha256, got $actual. Refusing hotfix."
}

$source = [IO.File]::ReadAllText($Stage2V3Path)

$old1 = '$rows | Sort-Object Path | Format-Table -AutoSize'
$new1 = '$rows | Sort-Object Path | Format-Table -AutoSize | Out-Host'
$old2 = '$rows | Sort-Object @{Expression={$_.Match};Descending=$true}, Path | Format-Table -AutoSize'
$new2 = '$rows | Sort-Object @{Expression={$_.Match};Descending=$true}, Path | Format-Table -AutoSize | Out-Host'

if (-not $source.Contains($old1)) {
    throw 'Expected discovery-results Format-Table statement not found.'
}
if (-not $source.Contains($old2)) {
    throw 'Expected verified-seed Format-Table statement not found.'
}

$patched = $source.Replace($old1,$new1).Replace($old2,$new2)

if ($patched -eq $source) {
    throw 'Output-isolation hotfix made no changes.'
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($patched,[ref]$tokens,[ref]$errors)
if ($errors -and $errors.Count -gt 0) {
    $msg = ($errors | ForEach-Object { "Line $($_.Extent.StartLineNumber): $($_.Message)" }) -join [Environment]::NewLine
    throw "Hotfixed Stage 2 V3 failed parser validation:`n$msg"
}

$runtimePath = Join-Path $env:TEMP 'AOTR_8P_STAGE2_BUILD_NONRELEASE_V3_1_RUNTIME.ps1'
[IO.File]::WriteAllText($runtimePath,$patched,(New-Object Text.UTF8Encoding($false)))
$runtimeHash = (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToUpperInvariant()

Write-Host ''
Write-Host '=== STAGE 2 V3 OUTPUT HOTFIX V3.1 ===' -ForegroundColor Cyan
Write-Host "Original V3    : $Stage2V3Path"
Write-Host "Original SHA256: $actual" -ForegroundColor Green
Write-Host "Runtime V3.1   : $runtimePath"
Write-Host "Runtime SHA256 : $runtimeHash" -ForegroundColor Green
Write-Host 'Fix             : pipe both Format-Table calls to Out-Host so Resolve-VerifiedSeed returns only the seed path'
Write-Host ''

& $runtimePath
