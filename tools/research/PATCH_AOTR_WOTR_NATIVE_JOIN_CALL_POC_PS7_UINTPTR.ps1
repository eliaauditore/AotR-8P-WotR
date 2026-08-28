param(
    [string]$Target = 'C:\AOTR_RESEARCH\AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Target)) {
    throw "Target not found: $Target"
}

$text = Get-Content -LiteralPath $Target -Raw

$oldAlloc = '[UIntPtr]0x1000'
$newAlloc = '[UIntPtr]::new([uint64]0x1000)'
$oldFlush = '[UIntPtr]$stubBytes.Length'
$newFlush = '[UIntPtr]::new([uint64]$stubBytes.Length)'

$allocCount = ([regex]::Matches($text,[regex]::Escape($oldAlloc))).Count
$flushCount = ([regex]::Matches($text,[regex]::Escape($oldFlush))).Count

if ($allocCount -ne 1) {
    throw "Expected exactly one VirtualAllocEx UIntPtr cast '$oldAlloc'; found $allocCount. Refusing to patch."
}
if ($flushCount -ne 1) {
    throw "Expected exactly one FlushInstructionCache UIntPtr cast '$oldFlush'; found $flushCount. Refusing to patch."
}

$before = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash
$text = $text.Replace($oldAlloc,$newAlloc).Replace($oldFlush,$newFlush)
Set-Content -LiteralPath $Target -Value $text -Encoding utf8
$after = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash

Write-Host '============================================================'
Write-Host ' AOTR NATIVE JOIN CALL POC - PS7 UINTPTR HOTFIX'
Write-Host '============================================================'
Write-Host ("Target : {0}" -f $Target)
Write-Host ("Before : {0}" -f $before)
Write-Host ("After  : {0}" -f $after)
Write-Host ''
Write-Host 'Patched exactly two PowerShell 7 interop casts:'
Write-Host ("  {0} -> {1}" -f $oldAlloc,$newAlloc)
Write-Host ("  {0} -> {1}" -f $oldFlush,$newFlush)
Write-Host ''
Write-Host 'No game.dat file or process memory was modified by this hotfix.'
