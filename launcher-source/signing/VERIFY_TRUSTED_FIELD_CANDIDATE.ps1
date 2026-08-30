param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExePath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Fa-f0-9]{64}$')]
    [string]$ExpectedSha256,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedProductVersion,

    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Stop-Gate {
    param([Parameter(Mandatory = $true)][string]$Message)
    throw ('TRUSTED_FIELD_CANDIDATE_GATE_FAIL: ' + $Message)
}

$resolved = (Resolve-Path -LiteralPath $ExePath -ErrorAction Stop).Path
$item = Get-Item -LiteralPath $resolved -ErrorAction Stop

if (-not $item.PSIsContainer -and ([IO.Path]::GetExtension($item.Name) -ieq '.exe')) {
    # Expected path shape.
}
else {
    Stop-Gate ('Candidate is not an EXE file: ' + $resolved)
}

$actualSha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToUpperInvariant()
$expectedSha256Normalized = $ExpectedSha256.ToUpperInvariant()
if ($actualSha256 -ne $expectedSha256Normalized) {
    Stop-Gate ('Post-sign SHA256 mismatch. Expected=' + $expectedSha256Normalized + ' Actual=' + $actualSha256)
}

$fvi = [Diagnostics.FileVersionInfo]::GetVersionInfo($resolved)
$productVersion = [string]$fvi.ProductVersion
if ($productVersion -ne $ExpectedProductVersion) {
    Stop-Gate ('ProductVersion mismatch. Expected=' + $ExpectedProductVersion + ' Actual=' + $productVersion)
}

$signature = Get-AuthenticodeSignature -LiteralPath $resolved
if ($null -eq $signature) {
    Stop-Gate 'Get-AuthenticodeSignature returned no result.'
}
if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    Stop-Gate ('Authenticode status is not Valid: ' + [string]$signature.Status + ' :: ' + [string]$signature.StatusMessage)
}
if ($null -eq $signature.SignerCertificate) {
    Stop-Gate 'SignerCertificate is missing.'
}
if ($null -eq $signature.TimeStamperCertificate) {
    Stop-Gate 'Timestamp certificate is missing. Field candidates require a timestamped signature.'
}

$signer = $signature.SignerCertificate
$timestampSigner = $signature.TimeStamperCertificate

$rsaEncryptionOid = '1.2.840.113549.1.1.1'
$signerKeyOid = [string]$signer.PublicKey.Oid.Value
if ($signerKeyOid -ne $rsaEncryptionOid) {
    Stop-Gate ('Signer public key is not RSA. OID=' + $signerKeyOid)
}

$codeSigningEkuOid = '1.3.6.1.5.5.7.3.3'
$codeSigningEkuPresent = $false
foreach ($extension in $signer.Extensions) {
    if ($null -ne $extension.Oid -and $extension.Oid.Value -eq '2.5.29.37') {
        $ekuExtension = New-Object System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension($extension, $extension.Critical)
        foreach ($usage in $ekuExtension.EnhancedKeyUsages) {
            if ($usage.Value -eq $codeSigningEkuOid) {
                $codeSigningEkuPresent = $true
                break
            }
        }
    }
    if ($codeSigningEkuPresent) { break }
}
if (-not $codeSigningEkuPresent) {
    Stop-Gate 'Signer certificate does not expose the Code Signing EKU (1.3.6.1.5.5.7.3.3).'
}

$signtool = Get-Command 'signtool.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $signtool) {
    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $kitsRoot -PathType Container) {
        $signtool = Get-ChildItem -LiteralPath $kitsRoot -Filter 'signtool.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
    }
}
if ($null -eq $signtool) {
    Stop-Gate 'signtool.exe is unavailable; trusted field verification cannot be completed.'
}

$signtoolPath = if ($signtool.PSObject.Properties['Source']) { [string]$signtool.Source } else { [string]$signtool.FullName }
if ([string]::IsNullOrWhiteSpace($signtoolPath)) {
    Stop-Gate 'Could not resolve signtool.exe path.'
}

$signtoolOutput = @(& $signtoolPath verify /pa /v $resolved 2>&1 | ForEach-Object { [string]$_ })
$signtoolExit = $LASTEXITCODE
if ($signtoolExit -ne 0) {
    Stop-Gate ('signtool verify /pa /v failed with exit code ' + $signtoolExit + '. Output: ' + ($signtoolOutput -join ' | '))
}

$report = [ordered]@{
    state = 'TRUSTED_FIELD_CANDIDATE_GATE_PASS'
    verified_utc = [DateTime]::UtcNow.ToString('o')
    exe_path = $resolved
    file_name = $item.Name
    file_size = [int64]$item.Length
    product_version = $productVersion
    post_sign_sha256 = $actualSha256
    authenticode_status = [string]$signature.Status
    signer_subject = [string]$signer.Subject
    signer_issuer = [string]$signer.Issuer
    signer_thumbprint = [string]$signer.Thumbprint
    signer_serial_number = [string]$signer.SerialNumber
    signer_public_key_oid = $signerKeyOid
    code_signing_eku_present = $codeSigningEkuPresent
    timestamp_subject = [string]$timestampSigner.Subject
    timestamp_issuer = [string]$timestampSigner.Issuer
    timestamp_thumbprint = [string]$timestampSigner.Thumbprint
    signtool_path = $signtoolPath
    signtool_verify_exit_code = $signtoolExit
}

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $reportFull = [IO.Path]::GetFullPath($ReportPath)
    $reportParent = Split-Path -Parent $reportFull
    if (-not [string]::IsNullOrWhiteSpace($reportParent)) {
        New-Item -ItemType Directory -Force -Path $reportParent | Out-Null
    }
    $json = $report | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($reportFull, $json, (New-Object Text.UTF8Encoding($false)))
    Write-Host ('TRUSTED_FIELD_CANDIDATE_REPORT=' + $reportFull)
}

Write-Host 'TRUSTED_FIELD_CANDIDATE_GATE=PASS' -ForegroundColor Green
Write-Host ('POST_SIGN_SHA256=' + $actualSha256)
Write-Host ('PRODUCT_VERSION=' + $productVersion)
Write-Host ('SIGNER_SUBJECT=' + [string]$signer.Subject)
Write-Host ('SIGNER_ISSUER=' + [string]$signer.Issuer)
Write-Host ('SIGNER_THUMBPRINT=' + [string]$signer.Thumbprint)
Write-Host ('TIMESTAMP_SUBJECT=' + [string]$timestampSigner.Subject)
