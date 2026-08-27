#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE1_20260827_022948\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10_ROBUST_AUTODETECT_V2_NONRELEASE.ps1',
    [string]$UsbDrive = 'I:\',
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
    if (-not $m.Success) { throw ('Could not locate payload ' + $Name + '.') }
    $bytes = Expand-GzipBase64Bytes $m.Groups['data'].Value
    return [PSCustomObject]@{ Bytes=$bytes; Text=(Get-Utf8Text $bytes); Sha256=(Get-Sha256Bytes $bytes) }
}

function Test-PowerShellText([string]$Text,[string]$Label) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) {
        $msg = ($errors | ForEach-Object { 'Line ' + $_.Extent.StartLineNumber + ', Col ' + $_.Extent.StartColumnNumber + ': ' + $_.Message }) -join [Environment]::NewLine
        throw ('Parser failure for ' + $Label + [Environment]::NewLine + $msg)
    }
}

function Canon([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function New-EmptyFile([string]$Path) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($Path,[byte[]](0x00))
}

function New-FullSyntheticAotR([string]$Root) {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $runtime = Join-Path $Root 'rotwk'
    $aotr = Join-Path $Root 'aotr'
    New-Item -ItemType Directory -Force -Path $runtime | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $aotr 'data\ini') | Out-Null
    New-EmptyFile (Join-Path $runtime 'lotrbfme2ep1.exe')
    New-EmptyFile (Join-Path $runtime 'game.dat')
    New-EmptyFile (Join-Path $Root 'AotR_Launcher.exe')
    New-EmptyFile (Join-Path $aotr 'Changelist.txt')
    return (Canon $Root)
}

$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Case,[bool]$Pass,[string]$Detail) {
    [void]$results.Add([PSCustomObject]@{ Case=$Case; Pass=$Pass; Detail=$Detail })
    $color = if ($Pass) { 'Green' } else { 'Red' }
    $status = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ('[{0}] {1} -- {2}' -f $status,$Case,$Detail) -ForegroundColor $color
}

if (-not (Test-Path -LiteralPath $BuilderPath -PathType Leaf)) { throw ('Builder missing: ' + $BuilderPath) }
$builderSha = Get-Sha256File $BuilderPath
if ($builderSha -ne $ExpectedBuilderSha256) { throw ('Builder hash mismatch. Expected ' + $ExpectedBuilderSha256 + ', got ' + $builderSha) }

$builderText = Get-Utf8Text ([IO.File]::ReadAllBytes($BuilderPath))
$csharp = Get-OuterCSharp $builderText
$gui = Get-Payload $csharp 'GuiGzipBase64'
$engine = Get-Payload $csharp 'EngineGzipBase64'
if ($gui.Sha256 -ne $ExpectedGuiSha256) { throw ('GUI hash mismatch. Expected ' + $ExpectedGuiSha256 + ', got ' + $gui.Sha256) }
if ($engine.Sha256 -ne $ExpectedEngineSha256) { throw ('ENGINE hash mismatch. Expected ' + $ExpectedEngineSha256 + ', got ' + $engine.Sha256) }

$startMarker = 'function Get-CanonicalAotRPath([string]$Path) {'
$endMarker = '$Install = Resolve-AotRInstall -PromptIfMissing'
$start = $gui.Text.IndexOf($startMarker,[StringComparison]::Ordinal)
$end = $gui.Text.IndexOf($endMarker,$start,[StringComparison]::Ordinal)
if ($start -lt 0 -or $end -le $start) { throw 'Could not isolate current GUI resolver source.' }
$resolverText = $gui.Text.Substring($start,$end-$start)
Test-PowerShellText $resolverText 'current V18 GUI resolver'
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
. ([ScriptBlock]::Create($resolverText))

$usbRoot = Canon $UsbDrive
if (-not (Test-Path -LiteralPath $usbRoot -PathType Container)) { throw ('USB drive root missing: ' + $usbRoot) }
if ($usbRoot -match '^(?i)[CD]:$') { throw ('Refusing to use fixed system/research drive as USB test target: ' + $usbRoot) }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ('AUTODETECT_V2_V18_STAGE7_USB_' + $stamp)
$stateRoot = Join-Path $workRoot 'STATE'
$ConfigPath = Join-Path $stateRoot 'launcher_config.json'
$reportPath = Join-Path $workRoot 'V18_STAGE7_PHYSICAL_USB_SELECTION_REPORT.txt'
New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null

$testParent = Join-Path ($usbRoot + '\') ('A8P_STAGE7_USB_' + [Guid]::NewGuid().ToString('N'))
$testRoot = Join-Path $testParent 'AgeoftheRing'
$expectedRoot = Canon $ExpectedAotRRoot

$realConfig = Join-Path $env:LOCALAPPDATA 'AotR 8P WotR Mod\launcher_config.json'
$realConfigExisted = Test-Path -LiteralPath $realConfig -PathType Leaf
$realConfigHashBefore = if ($realConfigExisted) { Get-Sha256File $realConfig } else { '' }
$oldAotrHomeExists = Test-Path Env:AOTR_HOME
$oldAotrHome = if ($oldAotrHomeExists) { $env:AOTR_HOME } else { $null }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P V18 STAGE 7 - PHYSICAL USB/EXFAT SELECTION' -ForegroundColor Cyan
Write-Host ' EXACT CURRENT RESOLVER / ISOLATED CONFIG / NO GAME START' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('Builder SHA : ' + $builderSha)
Write-Host ('GUI SHA     : ' + $gui.Sha256)
Write-Host ('ENGINE SHA  : ' + $engine.Sha256)
Write-Host ('USB target  : ' + $usbRoot)
Write-Host ('Temp root   : ' + $testRoot)
Write-Host ('Work root   : ' + $workRoot)
Write-Host ''

try {
    Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue

    # 1) Physical classification from exact resolver.
    $drives = @(Get-AotRLocalDrives)
    $usbDriveRow = @($drives | Where-Object { (Canon ([string]$_.Root)) -eq $usbRoot } | Select-Object -First 1)
    $usbClassPass = [bool](
        $usbDriveRow.Count -eq 1 -and
        [int]$usbDriveRow[0].Rank -eq 1 -and
        [string]$usbDriveRow[0].Type -eq 'RemovableUsbOrExFat'
    )
    $usbDetail = if ($usbDriveRow.Count -eq 1) {
        'type=' + [string]$usbDriveRow[0].Type + ', rank=' + [string]$usbDriveRow[0].Rank + ', driveType=' + [string]$usbDriveRow[0].DriveType + ', fs=' + [string]$usbDriveRow[0].FileSystem + ', bus=' + [string]$usbDriveRow[0].BusType
    } else { 'drive row not returned by resolver' }
    Add-Result 'physical I: classified RemovableUsbOrExFat rank 1' $usbClassPass $usbDetail
    if (-not $usbClassPass) { throw 'Physical USB classification did not meet Stage7 requirements.' }

    $fixedBeforeSecondary = $true
    $seenSecondary = $false
    foreach ($d in $drives) {
        if ([int]$d.Rank -eq 1) { $seenSecondary = $true }
        elseif ($seenSecondary -and [int]$d.Rank -eq 0) { $fixedBeforeSecondary = $false }
    }
    Add-Result 'Fixed drives remain ordered before physical USB/exFAT' $fixedBeforeSecondary ('driveCount=' + $drives.Count)

    # 2) Create only one unique temporary structural AotR root on the USB drive.
    $testRoot = New-FullSyntheticAotR $testRoot
    $usbInstall = Test-AotRStandaloneRoot $testRoot
    $structuralPass = [bool]($usbInstall -and $usbInstall.HardValid -and $usbInstall.AutoEligible -and [int]$usbInstall.Score -eq 120)
    Add-Result 'temporary USB standalone root validates score 120' $structuralPass ('root=' + $testRoot + ', score=' + [string]$usbInstall.Score)
    if (-not $structuralPass) { throw 'Temporary USB candidate did not validate.' }

    # 3) Prove bounded physical-drive discovery sees the temporary root from I:\ itself.
    $bounded = @(Find-AotRRootsBounded -DriveRoot ($usbRoot + '\'))
    $boundedCanonical = @($bounded | ForEach-Object { Canon ([string]$_) })
    $boundedPass = $boundedCanonical -contains $testRoot
    Add-Result 'bounded physical USB search discovers temporary root' $boundedPass ('found=' + ($boundedCanonical -join '; '))
    if (-not $boundedPass) { throw 'Bounded USB discovery did not find the temporary root.' }

    # 4) Full resolver must now produce a real equal-top picker. Use a neutral package hint so
    # the USB candidate is admitted through physical-drive discovery, not launcher vicinity.
    Remove-Item -LiteralPath $ConfigPath -Force -ErrorAction SilentlyContinue
    $packageRoot = Join-Path $workRoot 'NONINSTALL_PACKAGE_HINT'
    $script:LastErrorCode = ''
    $script:LastErrorDetail = ''

    Write-Host ''
    Write-Host 'A picker should open now. Select the TEMPORARY USB installation on I:\' -ForegroundColor Yellow
    Write-Host ('Select exactly: ' + $testRoot) -ForegroundColor Yellow
    Write-Host ('Do NOT select the real install: ' + $expectedRoot) -ForegroundColor Yellow
    Write-Host ''

    $selected = Resolve-AotRInstall -PromptIfMissing
    $saved = if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) { Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json } else { $null }
    $selectedRootText = if ($selected) { Canon ([string]$selected.Root) } else { '<null>' }
    $pickerPass = [bool](
        $selected -and
        $selectedRootText -eq $testRoot -and
        $saved -and
        [int]$saved.schema -eq 2 -and
        [string]$saved.validation -eq $ExpectedValidation -and
        (Canon ([string]$saved.aotr_root)) -eq $testRoot -and
        $script:LastErrorCode -eq 'A8P-INSTALL-002'
    )
    Add-Result 'physical USB equal-top picker selection revalidated and saved' $pickerPass ('selected=' + $selectedRootText + ', resolverCode=' + [string]$script:LastErrorCode)
}
finally {
    if ($oldAotrHomeExists) { $env:AOTR_HOME = $oldAotrHome }
    else { Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue }

    if (Test-Path -LiteralPath $testParent -PathType Container) {
        Remove-Item -LiteralPath $testParent -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$usbTempRemoved = -not (Test-Path -LiteralPath $testParent)
Add-Result 'temporary USB test tree removed' $usbTempRemoved $testParent

$realConfigHashAfter = if ($realConfigExisted -and (Test-Path -LiteralPath $realConfig -PathType Leaf)) { Get-Sha256File $realConfig } else { '' }
$realConfigUnchanged = if ($realConfigExisted) { $realConfigHashBefore -eq $realConfigHashAfter } else { -not (Test-Path -LiteralPath $realConfig -PathType Leaf) }
$realConfigDetail = if ($realConfigExisted) { 'hash before/after compared' } else { 'remained absent' }
Add-Result 'real launcher config unchanged' ([bool]$realConfigUnchanged) $realConfigDetail

$builderUnchanged = (Get-Sha256File $BuilderPath) -eq $ExpectedBuilderSha256
Add-Result 'Stage1 builder unchanged' ([bool]$builderUnchanged) $ExpectedBuilderSha256

$failures = @($results | Where-Object { -not $_.Pass })
$reportLines = New-Object System.Collections.Generic.List[string]
[void]$reportLines.Add('AOTR 8P V18 STAGE7 PHYSICAL USB/EXFAT SELECTION')
[void]$reportLines.Add('Generated UTC: ' + [DateTime]::UtcNow.ToString('o'))
[void]$reportLines.Add('Builder SHA256: ' + $builderSha)
[void]$reportLines.Add('GUI SHA256: ' + $gui.Sha256)
[void]$reportLines.Add('ENGINE SHA256: ' + $engine.Sha256)
[void]$reportLines.Add('USB target: ' + $usbRoot)
[void]$reportLines.Add('Cases: ' + $results.Count)
[void]$reportLines.Add('Failures: ' + $failures.Count)
[void]$reportLines.Add('')
foreach ($r in $results) { [void]$reportLines.Add(('[{0}] {1} -- {2}' -f ($(if ($r.Pass) {'PASS'} else {'FAIL'})),$r.Case,$r.Detail)) }
[IO.File]::WriteAllLines($reportPath,$reportLines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' V18 STAGE 7 RESULT' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('Cases   : ' + $results.Count)
Write-Host ('Failures: ' + $failures.Count)
Write-Host ('Report  : ' + $reportPath)
Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host 'STAGE 7: FAIL' -ForegroundColor Red
    foreach ($f in $failures) { Write-Host ('  - ' + $f.Case + ': ' + $f.Detail) -ForegroundColor Red }
    exit 7
}
Write-Host 'STAGE 7: PASS' -ForegroundColor Green
Write-Host 'Physical secondary-drive proof complete. Temporary USB tree was removed.' -ForegroundColor Green
Write-Host 'No game start, release change, or real launcher-config change was performed.' -ForegroundColor Green
