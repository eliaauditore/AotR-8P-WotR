#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToUpperInvariant() }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Replace-RegexExactlyOnce([string]$Text,[string]$Pattern,[string]$Replacement,[string]$Label) {
    $matches = [regex]::Matches($Text,$Pattern)
    if ($matches.Count -ne 1) { throw "Expected exactly one match for $Label; found $($matches.Count)." }
    return [regex]::Replace($Text,$Pattern,$Replacement,1)
}

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$HistoricalRoot = Join-Path $RepoRoot 'launcher-source\v19-successor\resources'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $env:TEMP 'AOTR8P_SIGNING_CLEAN_V7_MATERIALIZE_V1'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$enginePath = Join-Path $HistoricalRoot 'launcher_engine.ps1'
$finalPath = Join-Path $HistoricalRoot 'final_stable_v7.ps1'
$shellPath = Join-Path $HistoricalRoot 'v7_shellcode.bin'

$expected = [ordered]@{
    engine = '5DB2F749F10E84322BC471FFF04E25326EFF194FA440175FE9841ED13367F938'
    final = '72D00490538BE2222F5BAAF3D8A1648A86071D3A098946A7B8751E7D337300E2'
    shell = '60EECE4660C3BA0AD183EB82B82DCDACF3ECA6DC892C8FAFCD629A92170ED45A'
}
foreach ($pair in @(@($enginePath,$expected.engine,'historical Engine'),@($finalPath,$expected.final,'historical FINAL_STABLE_V7'),@($shellPath,$expected.shell,'historical V7 shellcode'))) {
    if (-not (Test-Path -LiteralPath $pair[0] -PathType Leaf)) { throw "$($pair[2]) missing: $($pair[0])" }
    $actual = Get-Sha256 $pair[0]
    if ($actual -ne $pair[1]) { throw "$($pair[2]) hash mismatch: $actual" }
}

$RawHash = '0D40841FEA16CCBF82D3ACF45F5D4F3E88DCEE25DEE3E8979CFC861D9DEBEB98'
$MapHash = 'AA4F89C4B315D0CDE15CD3A90DF96C069E83EB4419AFB5AB9429B4630C98D731'
$ZoomHash = '13DB5AB30A882A36D343C74FD28182A5383740BAFD4A39061229B2DF552EE6F0'
$CameraHash = '8D9A0E5FCD6B9396376D74BDCD71348F16619D3A688753683957208D39C99E51'
$CancelHash = '4884272792A6E35438C4261E8D1F10905C24516654A148A0B6611B0B77B7BE7C'
$CleanPrefixHash = 'C2134A124371FD3DBB4BB7F5A20D46DE8CDAE3BF46EA6F248DD53A9488069811'

# ----- Engine: preserve exact read-only compatibility behavior, but compare digests instead of copied code bytes. -----
$engine = [IO.File]::ReadAllText($enginePath)
$hashFunction = @'
function Assert-CompatHash {
    param(
        [Int64]$Address,
        [int]$Length,
        [string]$ExpectedSha256,
        [string]$Name
    )
    if ($Length -le 0) { throw "$Name : invalid compatibility window length." }
    [byte[]]$actual = [byte[]]::new($Length)
    [IntPtr]$read = [IntPtr]::Zero
    $ok = [AotR8PChildPatch]::ReadProcessMemory($h,[IntPtr]$Address,$actual,$Length,[ref]$read)
    if ((-not $ok) -or ($read.ToInt64() -ne $Length)) {
        throw "$Name : compatibility read was incomplete. Nothing patched."
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actualSha = ([BitConverter]::ToString($sha.ComputeHash($actual))).Replace('-','').ToUpperInvariant() }
    finally { $sha.Dispose() }
    if ($actualSha -ne $ExpectedSha256) {
        throw "$Name changed in this AotR build. SHA256=$actualSha. Nothing patched."
    }
}

'@
$engine = Replace-RegexExactlyOnce $engine '(?m)^function Assert-CompatBytes \{' ($hashFunction + 'function Assert-CompatBytes {') 'Engine hash helper insertion'

$engineReplacements = @(
    @('(?m)^Assert-CompatBytes -Address \(\$base \+ 0x0004128C\).*?-Name "V7 Raw Wheel Hook"\s*$', 'Assert-CompatHash -Address ($base + 0x0004128C) -Length 12 -ExpectedSha256 "'+$RawHash+'" -Name "V7 Raw Wheel Hook"', 'Engine Raw Wheel signature'),
    @('(?m)^Assert-CompatBytes -Address \(\$base \+ 0x00575507\).*?-Name "V7 Strategic Map Handler"\s*$', 'Assert-CompatHash -Address ($base + 0x00575507) -Length 8 -ExpectedSha256 "'+$MapHash+'" -Name "V7 Strategic Map Handler"', 'Engine Map signature'),
    @('(?m)^Assert-CompatBytes -Address \(\$base \+ 0x0009AB21\).*?-Name "V7 Zoom Update"\s*$', 'Assert-CompatHash -Address ($base + 0x0009AB21) -Length 16 -ExpectedSha256 "'+$ZoomHash+'" -Name "V7 Zoom Update"', 'Engine Zoom signature'),
    @('(?m)^Assert-CompatBytes -Address 0x0097548E .*?-Name "LivingWorld Camera Global Reference"\s*$', 'Assert-CompatHash -Address 0x0097548E -Length 6 -ExpectedSha256 "'+$CameraHash+'" -Name "LivingWorld Camera Global Reference"', 'Engine Camera signature'),
    @('(?m)^Assert-CompatBytes -Address 0x009D9167 .*?-Name "Strategic Cancel/Release Callback"\s*$', 'Assert-CompatHash -Address 0x009D9167 -Length 16 -ExpectedSha256 "'+$CancelHash+'" -Name "Strategic Cancel/Release Callback"', 'Engine Cancel signature')
)
foreach ($r in $engineReplacements) { $engine = Replace-RegexExactlyOnce $engine $r[0] $r[1] $r[2] }

# ----- FINAL_STABLE_V7: replace original-byte arrays with length + digest facts. -----
$final = [IO.File]::ReadAllText($finalPath)
$final = Replace-RegexExactlyOnce $final '(?ms)^\[byte\[\]\]\$OriginalRawWheelHook\s*=\s*@\(.*?^\)\s*' ("`$RawWheelHookLength = 12`r`n`$RawWheelHookSha256 = \"$RawHash\"`r`n`r`n") 'FINAL original Raw Wheel block'
$final = Replace-RegexExactlyOnce $final '(?ms)^\[byte\[\]\]\$OriginalMapHandler\s*=\s*@\(.*?^\)\s*' ("`$MapHandlerLength = 8`r`n`$MapHandlerSha256 = \"$MapHash\"`r`n`r`n") 'FINAL original Map block'
$final = Replace-RegexExactlyOnce $final '(?ms)^\[byte\[\]\]\$OriginalZoomUpdate\s*=\s*@\(.*?^\)\s*' ("`$ZoomUpdateLength = 16`r`n`$ZoomUpdateSha256 = \"$ZoomHash\"`r`n`r`n") 'FINAL original Zoom block'
$final = Replace-RegexExactlyOnce $final '(?ms)^\$CameraGlobalRefAddress\s*=\s*\[IntPtr\]0x0097548E\s*\r?\n\[byte\[\]\]\$ExpectedCameraGlobalRef\s*=\s*@\(.*?\)\s*\r?\n\$CancelReleaseAddress\s*=\s*\[IntPtr\]0x009D9167\s*\r?\n\[byte\[\]\]\$ExpectedCancelRelease\s*=\s*@\(.*?^\)\s*' ("`$CameraGlobalRefAddress = [IntPtr]0x0097548E`r`n`$CameraGlobalRefLength = 6`r`n`$CameraGlobalRefSha256 = \"$CameraHash\"`r`n`$CancelReleaseAddress = [IntPtr]0x009D9167`r`n`$CancelReleaseLength = 16`r`n`$CancelReleaseSha256 = \"$CancelHash\"`r`n`r`n") 'FINAL Camera/Cancel blocks'

$testHashFunction = @'
function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Test-BytesHash([byte[]]$Actual,[string]$ExpectedSha256) {
    if ($null -eq $Actual) { return $false }
    return (Get-BytesSha256 $Actual) -eq $ExpectedSha256
}

'@
$final = Replace-RegexExactlyOnce $final '(?m)^function Test-Bytes\(' ($testHashFunction + 'function Test-Bytes(') 'FINAL hash helper insertion'

$literalReplacements = [ordered]@{
    '$OriginalRawWheelHook.Length' = '$RawWheelHookLength'
    '$OriginalMapHandler.Length' = '$MapHandlerLength'
    '$OriginalZoomUpdate.Length' = '$ZoomUpdateLength'
    '$ExpectedCameraGlobalRef.Length' = '$CameraGlobalRefLength'
    '$ExpectedCancelRelease.Length' = '$CancelReleaseLength'
    '(Test-Bytes $rawBefore $OriginalRawWheelHook)' = '(Test-BytesHash $rawBefore $RawWheelHookSha256)'
    '(Test-Bytes $mapBefore $OriginalMapHandler)' = '(Test-BytesHash $mapBefore $MapHandlerSha256)'
    '(Test-Bytes $zoomBefore $OriginalZoomUpdate)' = '(Test-BytesHash $zoomBefore $ZoomUpdateSha256)'
    '(Test-Bytes $cameraGlobalRefBefore $ExpectedCameraGlobalRef)' = '(Test-BytesHash $cameraGlobalRefBefore $CameraGlobalRefSha256)'
    '(Test-Bytes $cancelReleaseBefore $ExpectedCancelRelease)' = '(Test-BytesHash $cancelReleaseBefore $CancelReleaseSha256)'
    '(Test-Bytes $currentRaw $OriginalRawWheelHook)' = '(Test-BytesHash $currentRaw $RawWheelHookSha256)'
    '(Test-Bytes $currentMap $OriginalMapHandler)' = '(Test-BytesHash $currentMap $MapHandlerSha256)'
    '(Test-Bytes $currentZoom $OriginalZoomUpdate)' = '(Test-BytesHash $currentZoom $ZoomUpdateSha256)'
}
foreach ($key in $literalReplacements.Keys) { $final = $final.Replace($key,$literalReplacements[$key]) }

foreach ($forbidden in @('$OriginalRawWheelHook','$OriginalMapHandler','$OriginalZoomUpdate','$ExpectedCameraGlobalRef','$ExpectedCancelRelease')) {
    if ($final.Contains($forbidden)) { throw "FINAL still references removed proprietary-byte variable: $forbidden" }
}

# ----- Shellcode: replace only the first 12 overwritten bytes with a same-length semantic implementation. -----
[byte[]]$historicalShell = [IO.File]::ReadAllBytes($shellPath)
if ($historicalShell.Length -ne 1577) { throw "Historical shellcode length changed: $($historicalShell.Length)" }
[byte[]]$oldPrefix = New-Object byte[] 12
[Array]::Copy($historicalShell,0,$oldPrefix,0,12)
if ((Get-BytesSha256 $oldPrefix) -ne $RawHash) { throw 'Historical shellcode no longer starts with the pinned Raw Wheel window.' }

# Project-authored semantic replacement, 12 bytes exactly:
# lea eax,[ebp-4] ; mov eax,[eax] ; shr eax,16 ; cwde ; mov [esi+0x0C],eax
[byte[]]$cleanPrefix = @(0x8D,0x45,0xFC,0x8B,0x00,0xC1,0xE8,0x10,0x98,0x89,0x46,0x0C)
if ($cleanPrefix.Length -ne 12 -or (Get-BytesSha256 $cleanPrefix) -ne $CleanPrefixHash) { throw 'Clean semantic prefix identity mismatch.' }
[byte[]]$cleanShell = [byte[]]$historicalShell.Clone()
[Array]::Copy($cleanPrefix,0,$cleanShell,0,12)
for ($i=12; $i -lt $historicalShell.Length; $i++) {
    if ($cleanShell[$i] -ne $historicalShell[$i]) { throw "Unexpected shellcode change after clean prefix at offset $i" }
}

$forbiddenWindows = @(
    [PSCustomObject]@{ Name='RawWheel'; Length=12; Sha256=$RawHash },
    [PSCustomObject]@{ Name='MapHandler'; Length=8; Sha256=$MapHash },
    [PSCustomObject]@{ Name='ZoomUpdate'; Length=16; Sha256=$ZoomHash },
    [PSCustomObject]@{ Name='CameraGlobal'; Length=6; Sha256=$CameraHash },
    [PSCustomObject]@{ Name='CancelRelease'; Length=16; Sha256=$CancelHash }
)
foreach ($window in $forbiddenWindows) {
    for ($offset=0; $offset -le ($cleanShell.Length - $window.Length); $offset++) {
        [byte[]]$slice = New-Object byte[] $window.Length
        [Array]::Copy($cleanShell,$offset,$slice,0,$window.Length)
        if ((Get-BytesSha256 $slice) -eq $window.Sha256) {
            throw "Forbidden historical compatibility window remains in clean shellcode: $($window.Name) at offset $offset"
        }
    }
}

$cleanEnginePath = Join-Path $OutputRoot 'launcher_engine_signing_clean.ps1'
$cleanFinalPath = Join-Path $OutputRoot 'final_stable_v7_signing_clean.ps1'
$cleanShellPath = Join-Path $OutputRoot 'v7_shellcode_signing_clean.bin'
[IO.File]::WriteAllText($cleanEnginePath,$engine,(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($cleanFinalPath,$final,(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllBytes($cleanShellPath,$cleanShell)

foreach ($path in @($cleanEnginePath,$cleanFinalPath)) {
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) { throw "Generated PowerShell 5.1 parse failed: $path :: $($errors[0].Message)" }
}

$report = [ordered]@{
    schema = 1
    state = 'NON_RELEASE_SIGNING_CLEAN_V7_MATERIALIZATION'
    historical = [ordered]@{
        engine_sha256 = $expected.engine
        final_sha256 = $expected.final
        shellcode_sha256 = $expected.shell
    }
    clean = [ordered]@{
        engine_sha256 = Get-Sha256 $cleanEnginePath
        final_sha256 = Get-Sha256 $cleanFinalPath
        shellcode_sha256 = Get-Sha256 $cleanShellPath
        shellcode_length = $cleanShell.Length
        shellcode_prefix_sha256 = Get-BytesSha256 $cleanPrefix
    }
    invariants = [ordered]@{
        bytes_after_offset_12_unchanged = $true
        forbidden_historical_windows_absent_from_clean_shellcode = $true
        engine_uses_hash_compatibility_windows = $true
        final_uses_hash_compatibility_windows = $true
        powershell_5_1_parse = $true
        public_release_modified = $false
        field_execution_allowed = $false
    }
}
$reportPath = Join-Path $OutputRoot 'SIGNING_CLEAN_V7_MATERIALIZATION_REPORT.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host 'SIGNING_CLEAN_V7_MATERIALIZATION=PASS' -ForegroundColor Green
Write-Host "CLEAN_ENGINE_SHA256=$($report.clean.engine_sha256)"
Write-Host "CLEAN_FINAL_SHA256=$($report.clean.final_sha256)"
Write-Host "CLEAN_SHELLCODE_SHA256=$($report.clean.shellcode_sha256)"
Write-Host "CLEAN_SHELLCODE_PREFIX_SHA256=$($report.clean.shellcode_prefix_sha256)"
Write-Host "REPORT=$reportPath"
