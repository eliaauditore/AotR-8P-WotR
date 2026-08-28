param(
    [int]$ProcessId = 0,
    [string]$ExpectedRemoteIp = '192.168.0.224',
    [int]$ExpectedRemotePort = 8086,
    [int]$ObserveSeconds = 8,
    [switch]$Execute,
    [string]$SourcePath = 'C:\AOTR_RESEARCH\AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 compatibility wrapper for the research native-join PoC.
# The original PoC passes non-zero values to UIntPtr parameters with PowerShell casts:
#   [UIntPtr]0x1000
#   [UIntPtr]$stubBytes.Length
# Windows PowerShell 5.1 on the VM rejects those conversions before the native join executes.
# This wrapper creates a temporary copy and replaces only those two PowerShell-side
# conversions with explicit UIntPtr constructor calls. No game.dat bytes are changed.
#
# IMPORTANT: invoke the patched script with NAMED splatting (hashtable), not array
# splatting. Array splatting passes '-ProcessId' as the first positional argument and
# causes PS5.1 to try converting the literal string '-ProcessId' to Int32.
#
# Do not inspect $LASTEXITCODE after invoking another PowerShell script. Under StrictMode
# it may be undefined when no native executable set it. Script exceptions already propagate.

if (-not (Test-Path -LiteralPath $SourcePath)) {
    throw "Source PoC not found: $SourcePath"
}

$src = Get-Content -LiteralPath $SourcePath -Raw
$oldAlloc = '[UIntPtr]0x1000'
$newAlloc = '[UIntPtr]::new([uint32]0x1000)'
$oldFlush = '[UIntPtr]$stubBytes.Length'
$newFlush = '[UIntPtr]::new([uint32]$stubBytes.Length)'

if (-not $src.Contains($oldAlloc)) {
    throw "Expected VirtualAllocEx UIntPtr cast not found in source: $oldAlloc"
}
if (-not $src.Contains($oldFlush)) {
    throw "Expected FlushInstructionCache UIntPtr cast not found in source: $oldFlush"
}

$patched = $src.Replace($oldAlloc,$newAlloc).Replace($oldFlush,$newFlush)
$temp = Join-Path $env:TEMP ('AOTR_WOTR_NATIVE_JOIN_CALL_POC_PS51_' + [guid]::NewGuid().ToString('N') + '.ps1')

try {
    Set-Content -LiteralPath $temp -Value $patched -Encoding UTF8

    Write-Host '============================================================'
    Write-Host ' AOTR WOTR NATIVE JOIN POC - PS5.1 COMPAT WRAPPER'
    Write-Host '============================================================'
    Write-Host ("Source : {0}" -f $SourcePath)
    Write-Host ("Temp   : {0}" -f $temp)
    Write-Host 'Fixes  : UIntPtr(0x1000), UIntPtr(stub length), named parameter splatting, StrictMode cleanup'
    Write-Host ''

    $invoke = @{
        ProcessId          = [int]$ProcessId
        ExpectedRemoteIp   = [string]$ExpectedRemoteIp
        ExpectedRemotePort = [int]$ExpectedRemotePort
        ObserveSeconds     = [int]$ObserveSeconds
    }
    if ($Execute) { $invoke['Execute'] = $true }

    & $temp @invoke
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
