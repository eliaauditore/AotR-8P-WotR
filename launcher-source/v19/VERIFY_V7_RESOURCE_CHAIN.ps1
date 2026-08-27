#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourcesRoot,
    [string]$ExePath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-","").ToUpperInvariant() }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace("-","").ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Read-ManifestBytes([Reflection.Assembly]$Assembly,[string]$Name) {
    $stream = $Assembly.GetManifestResourceStream($Name)
    if ($null -eq $stream) { throw "Embedded resource missing: $Name" }
    try {
        $memory = New-Object IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            return [byte[]]$memory.ToArray()
        }
        finally { $memory.Dispose() }
    }
    finally { $stream.Dispose() }
}

$ResourcesRoot = [IO.Path]::GetFullPath($ResourcesRoot)
$enginePath = Join-Path $ResourcesRoot "launcher_engine.ps1"
$finalPath = Join-Path $ResourcesRoot "final_stable_v7.ps1"
$shellcodePath = Join-Path $ResourcesRoot "v7_shellcode.bin"

foreach ($path in @($enginePath,$finalPath,$shellcodePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "V7 verifier required resource missing: $path"
    }
}

$engineText = Get-Content -LiteralPath $enginePath -Raw -Encoding UTF8
$finalText = Get-Content -LiteralPath $finalPath -Raw -Encoding UTF8
$actualEngineHash = Get-Sha256 $enginePath
$actualFinalHash = Get-Sha256 $finalPath
$actualShellcodeHash = Get-Sha256 $shellcodePath

$expectedShellcodeHash = "60EECE4660C3BA0AD183EB82B82DCDACF3ECA6DC892C8FAFCD629A92170ED45A"
if ($actualShellcodeHash -ne $expectedShellcodeHash) {
    throw "V7 shellcode resource hash mismatch. Expected $expectedShellcodeHash, got $actualShellcodeHash"
}

$engineFinalHashMatch = [regex]::Match(
    $engineText,
    '(?m)^\$FinalStableV7Sha256\s*=\s*"([A-Fa-f0-9]{64})"\s*$'
)
if (-not $engineFinalHashMatch.Success) {
    throw "Engine FINAL_STABLE_V7 expected-hash constant is missing."
}
$engineExpectedFinalHash = $engineFinalHashMatch.Groups[1].Value.ToUpperInvariant()
if ($engineExpectedFinalHash -ne $actualFinalHash) {
    throw "V7 cross-resource hash mismatch. Engine expects $engineExpectedFinalHash but final_stable_v7.ps1 is $actualFinalHash"
}

$engineChildHandoff = 'AddParameter("V7Shellcode", [byte[]]$global:AOTR8P_V7_SHELLCODE_BYTES)'.Replace('\"','"')
if ($engineText.IndexOf($engineChildHandoff,[StringComparison]::Ordinal) -lt 0) {
    throw "Engine -> child PowerShell V7Shellcode AddParameter handoff is missing."
}
if ($finalText.IndexOf('[byte[]]$V7Shellcode',[StringComparison]::Ordinal) -lt 0) {
    throw "FINAL_STABLE_V7 explicit [byte[]] V7Shellcode parameter is missing."
}
if ($finalText.IndexOf('[byte[]]$ShellcodeTemplate = [byte[]]$V7Shellcode',[StringComparison]::Ordinal) -lt 0) {
    throw "FINAL_STABLE_V7 does not initialize ShellcodeTemplate from the explicit V7Shellcode parameter."
}
if ($finalText.IndexOf('AOTR8P_V7_SHELLCODE_BYTES',[StringComparison]::Ordinal) -ge 0) {
    throw "FINAL_STABLE_V7 still depends on parent-runspace AOTR8P_V7_SHELLCODE_BYTES global state."
}

Write-Host "V7_SOURCE_CHAIN_GATE=PASS" -ForegroundColor Green
Write-Host "V7_ENGINE_SHA256=$actualEngineHash"
Write-Host "V7_FINAL_SHA256=$actualFinalHash"
Write-Host "V7_SHELLCODE_SHA256=$actualShellcodeHash"

# Exercise the same child PowerShell parameter-binding path used by Install-FinalStableV7.
# The GameDat path is deliberately invalid; only shellcode/parameter transport failures are fatal here.
$child = [PowerShell]::Create()
try {
    [void]$child.AddScript($finalText)
    [void]$child.AddParameter('GameDat','Z:\__AOTR_V7_VERIFIER_NONEXISTENT__\game.dat')
    [void]$child.AddParameter('AnchorGain',[single]2.0)
    [void]$child.AddParameter('DragSpeed',[single]-16.0)
    [void]$child.AddParameter('V7Shellcode',[byte[]][IO.File]::ReadAllBytes($shellcodePath))

    $caught = ""
    try { $null = $child.Invoke() }
    catch { $caught = $_.Exception.ToString() }
    $streamErrors = ($child.Streams.Error | ForEach-Object { $_.ToString() }) -join " | "
    $detail = ($caught + " | " + $streamErrors).Trim(' ','|')

    if ($detail -match 'Shellcode-Resource fehlt|Shellcode-Laengenfehler|V7Shellcode.*parameter|parameter.*V7Shellcode|named parameter.*V7Shellcode') {
        throw "V7 child parameter transport failed: $detail"
    }
    Write-Host "V7_CHILD_PARAMETER_BINDING_GATE=PASS" -ForegroundColor Green
    if (-not [string]::IsNullOrWhiteSpace($detail)) {
        Write-Host "V7_CHILD_EXPECTED_NONRUNTIME_DETAIL=$detail" -ForegroundColor DarkGray
    }
}
finally { $child.Dispose() }

if (-not [string]::IsNullOrWhiteSpace($ExePath)) {
    $ExePath = [IO.Path]::GetFullPath($ExePath)
    if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) {
        throw "V7 verifier EXE missing: $ExePath"
    }

    # Load from bytes so verification never locks the packaged EXE.
    $assembly = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($ExePath))
    $resourceChecks = @(
        @('AotR8P.EngineScript',$enginePath),
        @('AotR8P.FinalStableV7',$finalPath),
        @('AotR8P.V7Shellcode',$shellcodePath)
    )

    foreach ($check in $resourceChecks) {
        $name = [string]$check[0]
        $sourcePath = [string]$check[1]
        $embeddedBytes = Read-ManifestBytes $assembly $name
        $embeddedHash = Get-BytesSha256 $embeddedBytes
        $sourceHash = Get-Sha256 $sourcePath
        if ($embeddedHash -ne $sourceHash) {
            throw "Embedded resource differs from verified source: $name embedded=$embeddedHash source=$sourceHash"
        }
        Write-Host "V7_EMBEDDED_RESOURCE_GATE=PASS :: $name :: $embeddedHash" -ForegroundColor Green
    }

    $embeddedEngineBytes = Read-ManifestBytes $assembly 'AotR8P.EngineScript'
    $embeddedFinalBytes = Read-ManifestBytes $assembly 'AotR8P.FinalStableV7'
    $embeddedEngineText = [Text.Encoding]::UTF8.GetString($embeddedEngineBytes).TrimStart([char]0xFEFF)
    $embeddedFinalHash = Get-BytesSha256 $embeddedFinalBytes
    $embeddedHashMatch = [regex]::Match(
        $embeddedEngineText,
        '(?m)^\$FinalStableV7Sha256\s*=\s*"([A-Fa-f0-9]{64})"\s*$'
    )
    if (-not $embeddedHashMatch.Success) {
        throw "Embedded Engine FINAL_STABLE_V7 hash constant is missing."
    }
    if ($embeddedHashMatch.Groups[1].Value.ToUpperInvariant() -ne $embeddedFinalHash) {
        throw "Embedded Engine/V7 cross-resource mismatch. Engine expects $($embeddedHashMatch.Groups[1].Value), actual embedded V7 is $embeddedFinalHash"
    }
    Write-Host "V7_EMBEDDED_CROSS_RESOURCE_GATE=PASS :: $embeddedFinalHash" -ForegroundColor Green
}
