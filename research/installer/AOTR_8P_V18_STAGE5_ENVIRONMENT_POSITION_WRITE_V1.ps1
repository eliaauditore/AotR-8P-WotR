#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE1_20260827_022948\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10_ROBUST_AUTODETECT_V2_NONRELEASE.ps1',
    [string]$ExpectedAotRRoot = 'D:\Games\AotR\AgeoftheRing'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = 'D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0'
$ExpectedGuiSha256 = 'CFAF397833536769D726B0DD0960D940AAA6896ED62BFEFA0764185C2CEA90DC'
$ExpectedEngineSha256 = '94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA'
$ExpectedValidation = 'aotr-standalone-v2'

function Get-Sha256File([string]$Path) {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Get-Sha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Get-Utf8Text([byte[]]$Bytes) {
    $offset = 0
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { $offset = 3 }
    return [Text.UTF8Encoding]::new($false,$true).GetString($Bytes,$offset,$Bytes.Length-$offset)
}

function Expand-GzipBase64Bytes([string]$Base64) {
    $compressed = [Convert]::FromBase64String(($Base64 -replace '\s',''))
    $input = [IO.MemoryStream]::new($compressed)
    try {
        $gzip = [IO.Compression.GZipStream]::new($input,[IO.Compression.CompressionMode]::Decompress)
        try {
            $output = [IO.MemoryStream]::new()
            try { $gzip.CopyTo($output); return $output.ToArray() }
            finally { $output.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally { $input.Dispose() }
}

function Get-OuterCSharp([string]$BuilderText) {
    $pattern = '(?s)\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\s*(?<data>[A-Za-z0-9+/=\r\n]+?)\s*''@\)\)'
    $m = [regex]::Match($BuilderText,$pattern)
    if (-not $m.Success) { throw 'Could not locate outer C# template.' }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($m.Groups['data'].Value -replace '\s','')))
}

function Get-Payload([string]$CSharp,[string]$Name) {
    $pattern = '(?s)(?:private\s+)?const\s+string\s+' + [regex]::Escape($Name) + '\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
    $m = [regex]::Match($CSharp,$pattern)
    if (-not $m.Success) { throw "Could not locate payload $Name." }
    $bytes = Expand-GzipBase64Bytes $m.Groups['data'].Value
    return [PSCustomObject]@{ Bytes=$bytes; Text=(Get-Utf8Text $bytes); Sha256=(Get-Sha256Bytes $bytes) }
}

function Test-PowerShellText([string]$Text,[string]$Label) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) {
        $msg = ($errors | ForEach-Object { "Line $($_.Extent.StartLineNumber), Col $($_.Extent.StartColumnNumber): $($_.Message)" }) -join [Environment]::NewLine
        throw "Parser failure for $Label`n$msg"
    }
}

function Canon([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Case,[bool]$Pass,[string]$Detail) {
    [void]$results.Add([PSCustomObject]@{ Case=$Case; Pass=$Pass; Detail=$Detail })
    $color = if ($Pass) { 'Green' } else { 'Red' }
    Write-Host ('[{0}] {1} -- {2}' -f ($(if ($Pass) {'PASS'} else {'FAIL'})),$Case,$Detail) -ForegroundColor $color
}

if (-not (Test-Path -LiteralPath $BuilderPath -PathType Leaf)) { throw "Builder missing: $BuilderPath" }
$builderSha = Get-Sha256File $BuilderPath
if ($builderSha -ne $ExpectedBuilderSha256) { throw "Builder hash mismatch. Expected $ExpectedBuilderSha256, got $builderSha" }

$builderText = Get-Utf8Text ([IO.File]::ReadAllBytes($BuilderPath))
$csharp = Get-OuterCSharp $builderText
$gui = Get-Payload $csharp 'GuiGzipBase64'
$engine = Get-Payload $csharp 'EngineGzipBase64'
if ($gui.Sha256 -ne $ExpectedGuiSha256) { throw "GUI hash mismatch. Expected $ExpectedGuiSha256, got $($gui.Sha256)" }
if ($engine.Sha256 -ne $ExpectedEngineSha256) { throw "ENGINE hash mismatch. Expected $ExpectedEngineSha256, got $($engine.Sha256)" }

$startMarker = 'function Get-CanonicalAotRPath([string]$Path) {'
$endMarker = '$Install = Resolve-AotRInstall -PromptIfMissing'
$start = $gui.Text.IndexOf($startMarker,[StringComparison]::Ordinal)
$end = $gui.Text.IndexOf($endMarker,$start,[StringComparison]::Ordinal)
if ($start -lt 0 -or $end -le $start) { throw 'Could not isolate current GUI resolver source.' }
$resolverText = $gui.Text.Substring($start,$end-$start)
Test-PowerShellText $resolverText 'current V18 GUI resolver'
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ("AUTODETECT_V2_V18_STAGE5_ENV_" + $stamp)
$stateRoot = Join-Path $workRoot 'STATE'
$ConfigPath = Join-Path $stateRoot 'launcher_config.json'
$reportPath = Join-Path $workRoot 'V18_STAGE5_ENVIRONMENT_POSITION_WRITE_REPORT.txt'
New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null

$realConfig = Join-Path $env:LOCALAPPDATA 'AotR 8P WotR Mod\launcher_config.json'
$realConfigExisted = Test-Path -LiteralPath $realConfig -PathType Leaf
$realConfigHashBefore = if ($realConfigExisted) { Get-Sha256File $realConfig } else { '' }
$oldAotrHomeExists = Test-Path Env:AOTR_HOME
$oldAotrHome = if ($oldAotrHomeExists) { $env:AOTR_HOME } else { $null }

. ([ScriptBlock]::Create($resolverText))

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P V18 STAGE 5 - ENVIRONMENT POSITION + WRITE' -ForegroundColor Cyan
Write-Host ' EXACT CURRENT RESOLVER / NO BUILD / NO GAME START' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Builder SHA : $builderSha"
Write-Host "GUI SHA     : $($gui.Sha256)"
Write-Host "ENGINE SHA  : $($engine.Sha256)"
Write-Host "Work root   : $workRoot"
Write-Host ''

$expectedRoot = Canon $ExpectedAotRRoot
if (-not (Test-Path -LiteralPath $expectedRoot -PathType Container)) { throw "Expected AotR root missing: $expectedRoot" }
$expectedInstall = Test-AotRStandaloneRoot $expectedRoot
if (-not $expectedInstall -or -not $expectedInstall.HardValid -or $expectedInstall.HardReject) { throw 'Expected real AotR root does not validate.' }

try {
    Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue

    # CASE 1: launcher/package is elsewhere (Downloads-style). Discovery must remain independent of launcher location.
    Remove-Item -LiteralPath $ConfigPath -Force -ErrorAction SilentlyContinue
    $packageRoot = Join-Path $env:USERPROFILE 'Downloads\A8P_STAGE5_NONINSTALL_PACKAGE'
    $script:LastErrorCode = ''
    $script:LastErrorDetail = ''
    $fromDownloads = Resolve-AotRInstall
    $downloadsConfig = if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) { Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json } else { $null }
    $downloadsPass = [bool](
        $fromDownloads -and
        (Canon ([string]$fromDownloads.Root)) -eq $expectedRoot -and
        $downloadsConfig -and
        [int]$downloadsConfig.schema -eq 2 -and
        [string]$downloadsConfig.validation -eq $ExpectedValidation -and
        (Canon ([string]$downloadsConfig.aotr_root)) -eq $expectedRoot
    )
    Add-Result 'launcher/package in Downloads-style location' $downloadsPass ("resolved=" + [string]$fromDownloads.Root + ', error=' + [string]$script:LastErrorCode)

    # CASE 2: launcher/package sits directly in the standalone AotR root.
    Remove-Item -LiteralPath $ConfigPath -Force -ErrorAction SilentlyContinue
    $packageRoot = $expectedRoot
    $script:LastErrorCode = ''
    $script:LastErrorDetail = ''
    $fromInstall = Resolve-AotRInstall
    $insideConfig = if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) { Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json } else { $null }
    $insidePass = [bool](
        $fromInstall -and
        (Canon ([string]$fromInstall.Root)) -eq $expectedRoot -and
        $insideConfig -and
        [int]$insideConfig.schema -eq 2 -and
        [string]$insideConfig.validation -eq $ExpectedValidation -and
        (Canon ([string]$insideConfig.aotr_root)) -eq $expectedRoot
    )
    Add-Result 'launcher/package directly inside AotR root' $insidePass ("resolved=" + [string]$fromInstall.Root + ', error=' + [string]$script:LastErrorCode)

    # CASE 3: deterministic config write/verify failure must map to A8P-INSTALL-004.
    # Make ConfigPath point at an existing directory. Set-Content cannot write a file over a directory,
    # which exercises the same Save-AotRInstall failure path without changing machine ACLs.
    $badConfigTarget = Join-Path $workRoot 'CONFIG_TARGET_IS_DIRECTORY'
    New-Item -ItemType Directory -Force -Path $badConfigTarget | Out-Null
    $stateRoot = $workRoot
    $ConfigPath = $badConfigTarget
    $script:LastErrorCode = ''
    $script:LastErrorDetail = ''
    $writeFailResult = Use-AotRInstall $expectedInstall
    $writeFailPass = [bool](
        $null -eq $writeFailResult -and
        $script:LastErrorCode -eq 'A8P-INSTALL-004' -and
        $script:LastErrorDetail -match 'could not be written and verified'
    )
    Add-Result 'config write/verify failure maps to A8P-INSTALL-004' $writeFailPass ("error=" + [string]$script:LastErrorCode + ', detail=' + [string]$script:LastErrorDetail)

    # CASE 4: actual ACL-denied write on NTFS/current state folder, with ACL restored immediately afterward.
    $denyRoot = Join-Path $workRoot 'ACL_DENY_STATE'
    New-Item -ItemType Directory -Force -Path $denyRoot | Out-Null
    $originalAcl = Get-Acl -LiteralPath $denyRoot
    $originalSddl = $originalAcl.Sddl
    $aclCasePass = $false
    $aclDetail = ''
    try {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $rights = [Security.AccessControl.FileSystemRights]::Write -bor
                  [Security.AccessControl.FileSystemRights]::CreateFiles -bor
                  [Security.AccessControl.FileSystemRights]::CreateDirectories -bor
                  [Security.AccessControl.FileSystemRights]::AppendData
        $inherit = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $sid,
            $rights,
            $inherit,
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Deny
        )
        $denyAcl = Get-Acl -LiteralPath $denyRoot
        [void]$denyAcl.AddAccessRule($rule)
        Set-Acl -LiteralPath $denyRoot -AclObject $denyAcl

        $stateRoot = $denyRoot
        $ConfigPath = Join-Path $denyRoot 'launcher_config.json'
        $script:LastErrorCode = ''
        $script:LastErrorDetail = ''
        $aclResult = Use-AotRInstall $expectedInstall
        $aclCasePass = [bool]($null -eq $aclResult -and $script:LastErrorCode -eq 'A8P-INSTALL-004' -and -not (Test-Path -LiteralPath $ConfigPath -PathType Leaf))
        $aclDetail = 'error=' + [string]$script:LastErrorCode
    }
    catch {
        $aclDetail = 'ACL test exception: ' + $_.Exception.Message
    }
    finally {
        try {
            $restoreAcl = [Security.AccessControl.DirectorySecurity]::new()
            $restoreAcl.SetSecurityDescriptorSddlForm($originalSddl)
            Set-Acl -LiteralPath $denyRoot -AclObject $restoreAcl
        } catch {
            throw ('STOP: failed to restore temporary ACL on ' + $denyRoot + ': ' + $_.Exception.Message)
        }
    }
    Add-Result 'actual ACL no-write-rights maps to A8P-INSTALL-004' $aclCasePass $aclDetail
}
finally {
    if ($oldAotrHomeExists) { $env:AOTR_HOME = $oldAotrHome }
    else { Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue }
}

$realConfigHashAfter = if ($realConfigExisted -and (Test-Path -LiteralPath $realConfig -PathType Leaf)) { Get-Sha256File $realConfig } else { '' }
$realConfigUnchanged = if ($realConfigExisted) { $realConfigHashBefore -eq $realConfigHashAfter } else { -not (Test-Path -LiteralPath $realConfig -PathType Leaf) }
$realConfigDetail = if ($realConfigExisted) { 'hash before/after compared' } else { 'remained absent' }
Add-Result 'real launcher config unchanged' ([bool]$realConfigUnchanged) $realConfigDetail

$builderUnchanged = (Get-Sha256File $BuilderPath) -eq $ExpectedBuilderSha256
Add-Result 'Stage1 builder unchanged' ([bool]$builderUnchanged) $ExpectedBuilderSha256

$failures = @($results | Where-Object { -not $_.Pass })
$reportLines = New-Object System.Collections.Generic.List[string]
[void]$reportLines.Add('AOTR 8P V18 STAGE5 ENVIRONMENT POSITION + WRITE')
[void]$reportLines.Add('Generated UTC: ' + [DateTime]::UtcNow.ToString('o'))
[void]$reportLines.Add('Builder SHA256: ' + $builderSha)
[void]$reportLines.Add('GUI SHA256: ' + $gui.Sha256)
[void]$reportLines.Add('ENGINE SHA256: ' + $engine.Sha256)
[void]$reportLines.Add('Expected AotR root: ' + $expectedRoot)
[void]$reportLines.Add('Cases: ' + $results.Count)
[void]$reportLines.Add('Failures: ' + $failures.Count)
[void]$reportLines.Add('')
foreach ($r in $results) { [void]$reportLines.Add(('[{0}] {1} -- {2}' -f ($(if ($r.Pass) {'PASS'} else {'FAIL'})),$r.Case,$r.Detail)) }
[void]$reportLines.Add('')
[void]$reportLines.Add('PENDING')
[void]$reportLines.Add('- actual removable/USB/exFAT drive ordering/selection')
[void]$reportLines.Add('- real two-installation equal-top picker interaction')
[IO.File]::WriteAllLines($reportPath,$reportLines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' V18 STAGE 5 ENVIRONMENT RESULT' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Cases   : $($results.Count)"
Write-Host "Failures: $($failures.Count)"
Write-Host "Report  : $reportPath"
Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host 'STAGE 5: FAIL' -ForegroundColor Red
    foreach ($f in $failures) { Write-Host ('  - ' + $f.Case + ': ' + $f.Detail) -ForegroundColor Red }
    exit 5
}
Write-Host 'STAGE 5: PASS' -ForegroundColor Green
Write-Host 'No build, game start, release change, or real launcher-config change was performed.' -ForegroundColor Green
