#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [string]$ExpectedSha256 = "",

    [string]$ExpectedSubjectContains = "",

    [switch]$AllowMissingTimestamp,

    [switch]$RequireSignTool,

    [string]$ReportPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToUpperInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Add-Result(
    [System.Collections.Generic.List[string]]$Lines,
    [string]$Name,
    [bool]$Pass,
    [string]$Detail
) {
    $status = if ($Pass) { "PASS" } else { "FAIL" }
    $Lines.Add(("- **{0}:** {1} - {2}" -f $Name, $status, $Detail))
}

function Find-SignTool {
    $roots = New-Object 'System.Collections.Generic.List[string]'

    if (${env:ProgramFiles(x86)}) {
        $roots.Add((Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"))
    }
    if ($env:ProgramFiles) {
        $roots.Add((Join-Path $env:ProgramFiles "Windows Kits\10\bin"))
    }

    $candidates = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }

        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $candidate = Join-Path $_.FullName "x64\signtool.exe"
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    $candidates.Add((Get-Item -LiteralPath $candidate))
                }
            }
    }

    if ($candidates.Count -eq 0) { return $null }

    return $candidates |
        Sort-Object -Property @{ Expression = {
            try { [version]$_.Directory.Parent.Name }
            catch { [version]"0.0" }
        } } -Descending |
        Select-Object -First 1
}

$resolved = Resolve-Path -LiteralPath $FilePath -ErrorAction Stop
$fullPath = [IO.Path]::GetFullPath($resolved.Path)

if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    throw "Candidate file does not exist or is not a file: $fullPath"
}

$actualHash = Get-Sha256 $fullPath
$signature = Get-AuthenticodeSignature -LiteralPath $fullPath
$signer = $signature.SignerCertificate
$timestamp = $signature.TimeStamperCertificate

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $reportRoot = Join-Path $env:TEMP "AotR8P_Guardian"
    New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $ReportPath = Join-Path $reportRoot ("AUTHENTICODE_CANDIDATE_{0}.md" -f $stamp)
}
else {
    $ReportPath = [IO.Path]::GetFullPath($ReportPath)
    $parent = Split-Path -Parent $ReportPath
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
}

$lines = New-Object 'System.Collections.Generic.List[string]'
$lines.Add("# Authenticode candidate verification")
$lines.Add("")
$lines.Add(("- Timestamp: {0}" -f (Get-Date -Format o)))
$lines.Add(("- Candidate: {0}" -f $fullPath))
$lines.Add(("- SHA256: {0}" -f $actualHash))
$lines.Add("")
$lines.Add("## Results")
$lines.Add("")

$overallPass = $true

if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
    Add-Result $lines "Expected SHA256" $true "no expected hash supplied; actual hash recorded only."
}
else {
    $expectedNormalized = $ExpectedSha256.Replace(" ", "").ToUpperInvariant()
    $hashPass = $actualHash -eq $expectedNormalized
    Add-Result $lines "Expected SHA256" $hashPass ("expected {0}; actual {1}." -f $expectedNormalized, $actualHash)
    if (-not $hashPass) { $overallPass = $false }
}

$signaturePass = $signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid
Add-Result $lines "Authenticode status" $signaturePass ("status={0}; message={1}" -f $signature.Status, $signature.StatusMessage)
if (-not $signaturePass) { $overallPass = $false }

if ($null -eq $signer) {
    Add-Result $lines "Signer certificate" $false "no signer certificate is present."
    $overallPass = $false
}
else {
    Add-Result $lines "Signer certificate" $true ("subject={0}; issuer={1}; thumbprint={2}; serial={3}." -f $signer.Subject, $signer.Issuer, $signer.Thumbprint, $signer.SerialNumber)

    $keyOid = ""
    $keyFriendlyName = ""
    try {
        $keyOid = [string]$signer.PublicKey.Oid.Value
        $keyFriendlyName = [string]$signer.PublicKey.Oid.FriendlyName
    }
    catch {
        $keyOid = "<unavailable>"
        $keyFriendlyName = "<unavailable>"
    }

    $rsaPass = ($keyOid -eq "1.2.840.113549.1.1.1") -or ($keyFriendlyName -match "RSA")
    Add-Result $lines "RSA signer key" $rsaPass ("public-key OID={0}; friendly-name={1}." -f $keyOid, $keyFriendlyName)
    if (-not $rsaPass) { $overallPass = $false }

    if ([string]::IsNullOrWhiteSpace($ExpectedSubjectContains)) {
        Add-Result $lines "Expected publisher subject" $true "no subject constraint supplied."
    }
    else {
        $subjectPass = $signer.Subject.IndexOf($ExpectedSubjectContains, [StringComparison]::OrdinalIgnoreCase) -ge 0
        Add-Result $lines "Expected publisher subject" $subjectPass ("expected subject to contain '{0}'; actual subject='{1}'." -f $ExpectedSubjectContains, $signer.Subject)
        if (-not $subjectPass) { $overallPass = $false }
    }
}

if ($null -eq $timestamp) {
    if ($AllowMissingTimestamp) {
        Add-Result $lines "Timestamp certificate" $true "missing, but explicitly allowed for this diagnostic run."
    }
    else {
        Add-Result $lines "Timestamp certificate" $false "no timestamp certificate is present; public release candidates require timestamping."
        $overallPass = $false
    }
}
else {
    Add-Result $lines "Timestamp certificate" $true ("subject={0}; issuer={1}; thumbprint={2}." -f $timestamp.Subject, $timestamp.Issuer, $timestamp.Thumbprint)
}

$signtool = Find-SignTool
if ($null -eq $signtool) {
    if ($RequireSignTool) {
        Add-Result $lines "SignTool verify /pa /v" $false "signtool.exe was not found in the installed Windows SDK paths."
        $overallPass = $false
    }
    else {
        Add-Result $lines "SignTool verify /pa /v" $true "signtool.exe not found; skipped because -RequireSignTool was not specified."
    }
}
else {
    $output = & $signtool.FullName verify /pa /v $fullPath 2>&1
    $exitCode = $LASTEXITCODE
    $signToolPass = $exitCode -eq 0
    $detail = "exit-code={0}; tool={1}." -f $exitCode, $signtool.FullName
    Add-Result $lines "SignTool verify /pa /v" $signToolPass $detail
    $lines.Add("")
    $lines.Add("### SignTool output")
    $lines.Add("")
    $lines.Add('```text')
    foreach ($line in $output) { $lines.Add([string]$line) }
    $lines.Add('```')
    if (-not $signToolPass) { $overallPass = $false }
}

$lines.Add("")
$lines.Add("## Evidence boundary")
$lines.Add("")
$lines.Add("This verifier checks the supplied file's post-sign SHA256, Windows Authenticode validation status, RSA signer-key requirement, timestamp presence, optional publisher identity constraint, and SignTool policy verification when available/required.")
$lines.Add("")
$lines.Add("A PASS does not by itself prove Smart App Control, SmartScreen, Defender, ModDB-download, runtime, multiplayer, or game behavior. Those require the separate fresh-download and runtime acceptance gates documented in docs/release/CODE_SIGNING_SUCCESSOR_PLAN.md.")
$lines.Add("")
$lines.Add(("Overall: **{0}**" -f $(if ($overallPass) { "PASS" } else { "FAIL" })))

$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " AotR 8P WotR - Authenticode candidate verification" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ("Candidate: {0}" -f $fullPath)
Write-Host ("SHA256:    {0}" -f $actualHash)
Write-Host ("Signature: {0}" -f $signature.Status)
Write-Host ("Report:    {0}" -f $ReportPath)

if ($overallPass) {
    Write-Host "PASS: Authenticode candidate verification succeeded." -ForegroundColor Green
    exit 0
}

Write-Host "FAIL: one or more Authenticode candidate checks failed." -ForegroundColor Red
exit 1
