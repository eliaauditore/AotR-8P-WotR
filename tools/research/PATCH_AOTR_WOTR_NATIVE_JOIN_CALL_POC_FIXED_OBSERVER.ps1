$ErrorActionPreference = 'Stop'
$Path = 'C:\AOTR_RESEARCH\AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1'
if (-not (Test-Path -LiteralPath $Path)) { throw "PoC not found: $Path" }

$txt = Get-Content -LiteralPath $Path -Raw
$old = @'
    $deadline = [DateTime]::UtcNow.AddSeconds($ObserveSeconds)
    $observedCurrent = [uint32]0
    $observedNetwork = [uint32]0
    do {
        Start-Sleep -Milliseconds 250
        $observedCurrent = Read-U32 ([int64]$session + 0x44)
        $observedNetwork = Read-U32 $networkGlobalAddr
        if ($observedCurrent -ne 0) { break }
    } while ([DateTime]::UtcNow -lt $deadline)
'@
$new = @'
    $observedCurrent = [uint32]0
    $observedNetwork = [uint32]0
    $pollCount = [int]($ObserveSeconds * 4)
    for ($poll = 0; $poll -lt $pollCount; $poll++) {
        Start-Sleep -Milliseconds 250
        $observedCurrent = Read-U32 ([int64]$session + 0x44)
        $observedNetwork = Read-U32 $networkGlobalAddr
        if ($observedCurrent -ne 0) { break }
    }
'@

if (-not $txt.Contains($old)) { throw 'Expected observation block not found; refusing to patch unknown file.' }
$txt = $txt.Replace($old,$new)
Set-Content -LiteralPath $Path -Value $txt -Encoding UTF8
Write-Host 'PATCH PASS: post-call observation now uses a fixed bounded poll count.' -ForegroundColor Green
