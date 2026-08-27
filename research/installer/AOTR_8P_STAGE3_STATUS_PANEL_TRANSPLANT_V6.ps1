#requires -version 5.1
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE3_HASHFIX_V2_20260827_012753\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_HASHFIX_V2_NONRELEASE.ps1',
    [string]$DonorGuiPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\STATUS_PANEL_EXE_RECOVERY_20260827_015504\GUI_4_46032AC5272E.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = 'B244D987A99533DD3A79978032F64C261FF7EBBDDA1AAFA6BB0142FFA9BC2572'
$ExpectedGuiSha256     = 'AA8893A160CF790644FF794F4E8E47B3D1E05E1022AD22FB784A071B91920D8E'
$ExpectedEngineSha256  = 'D045567058775DE4EBB56266DC5751D5A57BA7C236B8056DC41EC2CD7C5931E6'
$ExpectedDonorGuiSha256 = '46032AC5272ED491A9E3F497733148A4531E35DC7D1634DDC180CC48D6C9FA24'

function Get-Sha256File([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $stream.Dispose() }
    }
    finally { $sha.Dispose() }
}

function Get-Sha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Get-Sha256Text([string]$Text) {
    return Get-Sha256Bytes ([Text.Encoding]::UTF8.GetBytes($Text))
}

function Expand-GzipBase64Bytes([string]$Base64) {
    $compressed = [Convert]::FromBase64String(($Base64 -replace '\s',''))
    $input = New-Object IO.MemoryStream(,$compressed)
    try {
        $gzip = New-Object IO.Compression.GZipStream($input,[IO.Compression.CompressionMode]::Decompress)
        try {
            $output = New-Object IO.MemoryStream
            try {
                $gzip.CopyTo($output)
                return $output.ToArray()
            }
            finally { $output.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally { $input.Dispose() }
}

function Compress-BytesToGzipBase64([byte[]]$Bytes) {
    $output = New-Object IO.MemoryStream
    try {
        $gzip = New-Object IO.Compression.GZipStream($output,[IO.Compression.CompressionMode]::Compress,$true)
        try { $gzip.Write($Bytes,0,$Bytes.Length) }
        finally { $gzip.Dispose() }
        return [Convert]::ToBase64String($output.ToArray())
    }
    finally { $output.Dispose() }
}

function Wrap-Base64([string]$Text,[int]$Width=120) {
    $parts = New-Object System.Collections.Generic.List[string]
    for ($i=0; $i -lt $Text.Length; $i += $Width) {
        $len = [Math]::Min($Width,$Text.Length-$i)
        [void]$parts.Add($Text.Substring($i,$len))
    }
    return ($parts -join "`r`n")
}

function Test-PowerShellText([string]$Text,[string]$Label) {
    $parseText = $Text
    if ($parseText.Length -gt 0 -and [int][char]$parseText[0] -eq 0xFEFF) { $parseText = $parseText.Substring(1) }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($parseText,[ref]$tokens,[ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $msg = ($errors | ForEach-Object { "Line $($_.Extent.StartLineNumber), Col $($_.Extent.StartColumnNumber): $($_.Message)" }) -join [Environment]::NewLine
        throw "Parser validation failed for $Label`n$msg"
    }
}

function Get-OuterInfo([string]$BuilderText) {
    $pattern = '(?s)(?<before>\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\s*)(?<data>[A-Za-z0-9+/=\r\n]+?)(?<after>\s*''@\)\))'
    $m = [regex]::Match($BuilderText,$pattern)
    if (-not $m.Success) { throw 'Could not locate outer C# Base64 template.' }
    $clean = ($m.Groups['data'].Value -replace '\s','')
    return [PSCustomObject]@{ Match=$m; CSharp=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($clean)) }
}

function Get-PayloadInfo([string]$CSharp,[string]$Name) {
    $pattern = '(?s)(?:private\s+)?const\s+string\s+' + [regex]::Escape($Name) + '\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
    $m = [regex]::Match($CSharp,$pattern)
    if (-not $m.Success) { throw "Could not locate $Name in outer C# template." }
    $bytes = Expand-GzipBase64Bytes $m.Groups['data'].Value
    return [PSCustomObject]@{ Match=$m; Bytes=$bytes; Text=[Text.Encoding]::UTF8.GetString($bytes) }
}

function Replace-Payload([string]$CSharp,[string]$Name,[byte[]]$NewBytes) {
    $info = Get-PayloadInfo $CSharp $Name
    $newB64 = Wrap-Base64 (Compress-BytesToGzipBase64 $NewBytes)
    $g = $info.Match.Groups['data']
    return $CSharp.Substring(0,$g.Index) + $newB64 + $CSharp.Substring($g.Index+$g.Length)
}

function Get-FunctionText([string]$Text,[string]$Name) {
    $parseText = $Text
    $prefix = 0
    if ($parseText.Length -gt 0 -and [int][char]$parseText[0] -eq 0xFEFF) { $parseText=$parseText.Substring(1); $prefix=1 }
    $tokens=$null; $errors=$null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($parseText,[ref]$tokens,[ref]$errors)
    if ($errors -and $errors.Count -gt 0) { throw "Cannot parse source while locating function $Name." }
    $hits = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name },$true))
    if ($hits.Count -ne 1) { throw "Expected exactly one function $Name, found $($hits.Count)." }
    $start = $hits[0].Extent.StartOffset + $prefix
    $length = $hits[0].Extent.EndOffset - $hits[0].Extent.StartOffset
    return $Text.Substring($start,$length)
}

function Get-ResolverRegion([string]$Text) {
    $pattern = '(?s)function\s+Get-AotRInstallFromPath\b.*?(?=\$Install\s*=\s*Resolve-AotRInstall\s+-PromptIfMissing)'
    $m = [regex]::Match($Text,$pattern)
    if (-not $m.Success) { throw 'Could not locate current autodetect resolver region.' }
    return $m.Value
}

function Get-NamedBorderBlock([string]$Text,[string]$Name) {
    $startPattern = '<Border\s+x:Name="' + [regex]::Escape($Name) + '"\b'
    $startMatch = [regex]::Match($Text,$startPattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $startMatch.Success) { throw "Could not locate donor Border $Name." }
    $sub = $Text.Substring($startMatch.Index)
    $tokens = [regex]::Matches($sub,'(?is)<Border\b[^>]*?/?>|</Border>')
    $depth = 0
    foreach ($t in $tokens) {
        if ($t.Value -match '^</Border') {
            $depth--
            if ($depth -eq 0) {
                return $sub.Substring(0,$t.Index+$t.Length)
            }
        } else {
            if ($t.Value -notmatch '/>\s*$') { $depth++ }
        }
    }
    throw "Could not find matching closing Border for $Name."
}

function Get-FindNameLine([string]$Text,[string]$Name) {
    $pattern = '(?m)^\s*\$' + [regex]::Escape($Name) + '\s*=\s*\$Window\.FindName\(["'']' + [regex]::Escape($Name) + '["'']\)\s*$'
    $hits = @([regex]::Matches($Text,$pattern))
    if ($hits.Count -ne 1) { throw "Expected exactly one donor FindName assignment for $Name, found $($hits.Count)." }
    return $hits[0].Value.TrimEnd()
}

function Replace-Once([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $count = @([regex]::Matches($Text,[regex]::Escape($Old))).Count
    if ($count -ne 1) { throw "$Label checkpoint mismatch. Expected 1 exact match, found $count." }
    return $Text.Replace($Old,$New)
}

function Add-After-Line([string]$Text,[string]$Line,[string]$Insert,[string]$Label) {
    $pattern = '(?m)^(?<indent>\s*)' + [regex]::Escape($Line) + '\s*$'
    $hits = @([regex]::Matches($Text,$pattern))
    if ($hits.Count -ne 1) { throw "$Label checkpoint mismatch. Expected 1 line match, found $($hits.Count)." }
    $m = $hits[0]
    $indent = $m.Groups['indent'].Value
    $replacement = $m.Value.TrimEnd() + "`r`n" + $indent + $Insert
    return $Text.Substring(0,$m.Index) + $replacement + $Text.Substring($m.Index+$m.Length)
}

if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw "Base missing: $Base" }
if (-not (Test-Path -LiteralPath $BuilderPath -PathType Leaf)) { throw "Builder missing: $BuilderPath" }
if (-not (Test-Path -LiteralPath $DonorGuiPath -PathType Leaf)) { throw "Donor GUI missing: $DonorGuiPath" }

$builderHash = Get-Sha256File $BuilderPath
$donorHash = Get-Sha256File $DonorGuiPath
if ($builderHash -ne $ExpectedBuilderSha256) { throw "Builder hash mismatch. Expected $ExpectedBuilderSha256, got $builderHash" }
if ($donorHash -ne $ExpectedDonorGuiSha256) { throw "Donor GUI hash mismatch. Expected $ExpectedDonorGuiSha256, got $donorHash" }

$builderText = [IO.File]::ReadAllText($BuilderPath)
$outer = Get-OuterInfo $builderText
$guiInfo = Get-PayloadInfo $outer.CSharp 'GuiGzipBase64'
$engineInfo = Get-PayloadInfo $outer.CSharp 'EngineGzipBase64'
$guiHash = Get-Sha256Bytes $guiInfo.Bytes
$engineHash = Get-Sha256Bytes $engineInfo.Bytes
if ($guiHash -ne $ExpectedGuiSha256) { throw "GUI hash mismatch. Expected $ExpectedGuiSha256, got $guiHash" }
if ($engineHash -ne $ExpectedEngineSha256) { throw "ENGINE hash mismatch. Expected $ExpectedEngineSha256, got $engineHash" }

$current = $guiInfo.Text
$donor = [IO.File]::ReadAllText($DonorGuiPath)
Test-PowerShellText $current 'current GUI before transplant'
Test-PowerShellText $donor 'recovered donor GUI'

$resolverBefore = Get-ResolverRegion $current
$resolverBeforeHash = Get-Sha256Text $resolverBefore
$shaFunctionBefore = Get-FunctionText $current 'Get-Sha256'
$shaFunctionBeforeHash = Get-Sha256Text $shaFunctionBefore

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P STAGE 3 STATUS PANEL TRANSPLANT V6' -ForegroundColor Cyan
Write-Host ' HASH-PINNED DONOR / CURRENT GUI ONLY / NON-RELEASE' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Builder SHA : $builderHash" -ForegroundColor Green
Write-Host "Current GUI : $guiHash" -ForegroundColor Green
Write-Host "Engine SHA  : $engineHash" -ForegroundColor Green
Write-Host "Donor GUI   : $donorHash" -ForegroundColor Green
Write-Host ''

# Current GUI must not already contain the dynamic panel controls/functions.
foreach ($name in @('StatusRowsHost','StatusGameText','StatusCampaignText','StatusUiText','OverallStatusText')) {
    $count = @([regex]::Matches($current,'\b' + [regex]::Escape($name) + '\b')).Count
    if ($count -ne 0) { throw "Current GUI unexpectedly already contains $name ($count refs). Refusing double transplant." }
}
foreach ($fn in @('Set-StatusCheck','Set-StatusChecking','Set-OverallStatus')) {
    $count = @([regex]::Matches($current,'(?m)^function\s+' + [regex]::Escape($fn) + '\b')).Count
    if ($count -ne 0) { throw "Current GUI unexpectedly already contains function $fn. Refusing double transplant." }
}

# 1) XAML: recover exact donor StatusRowsHost Border and insert immediately after current LaunchHit.
$statusBorder = Get-NamedBorderBlock $donor 'StatusRowsHost'
$launchHitPattern = '(?is)<Border\s+x:Name="LaunchHit"\b.*?/>'
$launchHits = @([regex]::Matches($current,$launchHitPattern))
if ($launchHits.Count -ne 1) { throw "Current LaunchHit XAML checkpoint mismatch. Expected 1, found $($launchHits.Count)." }
$lh = $launchHits[0]
$current = $current.Substring(0,$lh.Index+$lh.Length) + "`r`n`r`n        <!-- Recovered V18 dynamic status panel; donor GUI SHA256 $ExpectedDonorGuiSha256 -->`r`n" + $statusBorder + $current.Substring($lh.Index+$lh.Length)

# 2) FindName bindings: recover exact donor binding lines and insert after current LaunchHit binding.
$bindingNames = @('StatusRowsHost','StatusGameText','StatusCampaignText','StatusUiText','OverallStatusText')
$bindingLines = @($bindingNames | ForEach-Object { Get-FindNameLine $donor $_ })
$launchBindingPattern = '(?m)^\s*\$LaunchHit\s*=\s*\$Window\.FindName\(["'']LaunchHit["'']\)\s*$'
$launchBindingHits = @([regex]::Matches($current,$launchBindingPattern))
if ($launchBindingHits.Count -ne 1) { throw "Current LaunchHit FindName checkpoint mismatch. Expected 1, found $($launchBindingHits.Count)." }
$lb = $launchBindingHits[0]
$current = $current.Substring(0,$lb.Index+$lb.Length) + "`r`n" + ($bindingLines -join "`r`n") + $current.Substring($lb.Index+$lb.Length)

# 3) Runtime helpers: recover exact donor functions and insert before current Set-LaunchState.
$helperTexts = @(
    Get-FunctionText $donor 'Set-StatusCheck'
    Get-FunctionText $donor 'Set-StatusChecking'
    Get-FunctionText $donor 'Set-OverallStatus'
)
$launchFn = Get-FunctionText $current 'Set-LaunchState'
$helperBlock = ($helperTexts -join "`r`n`r`n") + "`r`n`r`n"
$current = Replace-Once $current $launchFn ($helperBlock + $launchFn) 'Set-LaunchState insertion anchor'

# 4) Preflight: modify only the existing current Invoke-Preflight function, not resolver/hash logic.
$preflight = Get-FunctionText $current 'Invoke-Preflight'
$patchedPreflight = $preflight
$headerOld = "function Invoke-Preflight {"
$patchedPreflight = Replace-Once $patchedPreflight $headerOld ($headerOld + "`r`n    Set-StatusChecking") 'Invoke-Preflight header'

$patchedPreflight = Add-After-Line $patchedPreflight '$Row1Fail.Visibility = [Windows.Visibility]::Collapsed' 'Set-StatusCheck $StatusGameText $true "OK" "NOT FOUND"' 'Row1 success status'
$patchedPreflight = Add-After-Line $patchedPreflight '$Row1Fail.Visibility = [Windows.Visibility]::Visible' 'Set-StatusCheck $StatusGameText $false "OK" "NOT FOUND"' 'Row1 fail status'
$patchedPreflight = Add-After-Line $patchedPreflight '$Row2Fail.Visibility = [Windows.Visibility]::Collapsed' 'Set-StatusCheck $StatusCampaignText $true "OK" "MISSING / INVALID"' 'Row2 success status'
$patchedPreflight = Add-After-Line $patchedPreflight '$Row2Fail.Visibility = [Windows.Visibility]::Visible' 'Set-StatusCheck $StatusCampaignText $false "OK" "MISSING / INVALID"' 'Row2 fail status'
$patchedPreflight = Add-After-Line $patchedPreflight '$Row3Fail.Visibility = [Windows.Visibility]::Collapsed' 'Set-StatusCheck $StatusUiText $true "OK" "MISSING / INVALID"' 'Row3 success status'
$patchedPreflight = Add-After-Line $patchedPreflight '$Row3Fail.Visibility = [Windows.Visibility]::Visible' 'Set-StatusCheck $StatusUiText $false "OK" "MISSING / INVALID"' 'Row3 fail status'
$patchedPreflight = Add-After-Line $patchedPreflight 'Set-LaunchState "LAUNCH + COMPAT CHECK"' 'Set-OverallStatus "READY — COMPAT CHECK ON LAUNCH" $RepairText' 'Compat-ready overall status'
$patchedPreflight = Add-After-Line $patchedPreflight 'Set-LaunchState "LAUNCH AOTR 8P WOTR"' 'Set-OverallStatus "ALL CHECKS PASSED — READY" $RunningText' 'Ready overall status'

$repairAnchorPattern = '(?ms)(\$LaunchHit\.IsHitTestVisible\s*=\s*\$true\s*\r?\n\s*}\s*else\s*\{\s*\r?\n)(\s*if\s*\(-not\s+\$gameOk\)\s*\{)'
$repairHits = @([regex]::Matches($patchedPreflight,$repairAnchorPattern))
if ($repairHits.Count -ne 1) { throw "Preflight repair-status anchor mismatch. Expected 1, found $($repairHits.Count)." }
$patchedPreflight = [regex]::Replace($patchedPreflight,$repairAnchorPattern,'$1        Set-OverallStatus "REPAIR REQUIRED" $RepairText' + "`r`n" + '$2',1)

$current = Replace-Once $current $preflight $patchedPreflight 'Invoke-Preflight transplant'

# Structural validation before repack.
Test-PowerShellText $current 'GUI after status panel transplant'
foreach ($name in @('StatusRowsHost','StatusGameText','StatusCampaignText','StatusUiText','OverallStatusText')) {
    $xamlCount = @([regex]::Matches($current,'x:Name\s*=\s*["'']' + [regex]::Escape($name) + '["'']')).Count
    $bindCount = @([regex]::Matches($current,'(?m)^\s*\$' + [regex]::Escape($name) + '\s*=\s*\$Window\.FindName\(["'']' + [regex]::Escape($name) + '["'']\)\s*$')).Count
    if ($xamlCount -ne 1) { throw "$name XAML validation failed: expected 1, got $xamlCount." }
    if ($bindCount -ne 1) { throw "$name binding validation failed: expected 1, got $bindCount." }
}
foreach ($fn in @('Set-StatusCheck','Set-StatusChecking','Set-OverallStatus')) {
    $count = @([regex]::Matches($current,'(?m)^function\s+' + [regex]::Escape($fn) + '\b')).Count
    if ($count -ne 1) { throw "$fn function validation failed: expected 1, got $count." }
}

$statusCallChecks = [ordered]@{
    'Status checking call' = 'Set-StatusChecking'
    'Game OK call' = 'Set-StatusCheck $StatusGameText $true "OK" "NOT FOUND"'
    'Game fail call' = 'Set-StatusCheck $StatusGameText $false "OK" "NOT FOUND"'
    'Campaign OK call' = 'Set-StatusCheck $StatusCampaignText $true "OK" "MISSING / INVALID"'
    'Campaign fail call' = 'Set-StatusCheck $StatusCampaignText $false "OK" "MISSING / INVALID"'
    'UI OK call' = 'Set-StatusCheck $StatusUiText $true "OK" "MISSING / INVALID"'
    'UI fail call' = 'Set-StatusCheck $StatusUiText $false "OK" "MISSING / INVALID"'
    'Compat overall' = 'Set-OverallStatus "READY — COMPAT CHECK ON LAUNCH" $RepairText'
    'Ready overall' = 'Set-OverallStatus "ALL CHECKS PASSED — READY" $RunningText'
    'Repair overall' = 'Set-OverallStatus "REPAIR REQUIRED" $RepairText'
}
foreach ($entry in $statusCallChecks.GetEnumerator()) {
    $count = @([regex]::Matches($current,[regex]::Escape([string]$entry.Value))).Count
    if ($count -ne 1) { throw "$($entry.Key) validation failed: expected 1 exact occurrence, got $count." }
}

# Critical invariants: resolver and .NET Get-Sha256 must remain byte-for-byte identical in decoded GUI.
$resolverAfter = Get-ResolverRegion $current
$resolverAfterHash = Get-Sha256Text $resolverAfter
$shaFunctionAfter = Get-FunctionText $current 'Get-Sha256'
$shaFunctionAfterHash = Get-Sha256Text $shaFunctionAfter
if ($resolverAfterHash -ne $resolverBeforeHash) { throw 'Autodetect resolver changed during status transplant. Refusing output.' }
if ($shaFunctionAfterHash -ne $shaFunctionBeforeHash) { throw 'Get-Sha256 function changed during status transplant. Refusing output.' }
if (@([regex]::Matches($current,'(?i)\bGet-FileHash\b')).Count -ne 0) { throw 'GUI regained Get-FileHash during status transplant.' }

$utf8NoBom = New-Object Text.UTF8Encoding($false)
$newGuiBytes = $utf8NoBom.GetBytes($current)
$newGuiHash = Get-Sha256Bytes $newGuiBytes
$newCSharp = Replace-Payload $outer.CSharp 'GuiGzipBase64' $newGuiBytes
$newOuterB64 = Wrap-Base64 ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($newCSharp)))
$gOuter = $outer.Match.Groups['data']
$newBuilderText = $builderText.Substring(0,$gOuter.Index) + $newOuterB64 + $builderText.Substring($gOuter.Index+$gOuter.Length)
Test-PowerShellText $newBuilderText 'builder after status panel transplant'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ("AUTODETECT_V2_STAGE3_STATUSPANEL_V6_" + $stamp)
if (Test-Path -LiteralPath $workRoot) { throw "Refusing to reuse work root: $workRoot" }
New-Item -ItemType Directory -Path $workRoot | Out-Null
$newBuilder = Join-Path $workRoot 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_HASHFIX_V2_STATUSPANEL_V6_NONRELEASE.ps1'
$patchedGuiPath = Join-Path $workRoot 'GUI_STATUSPANEL_V6.ps1'
[IO.File]::WriteAllText($newBuilder,$newBuilderText,$utf8NoBom)
[IO.File]::WriteAllText($patchedGuiPath,$current,$utf8NoBom)

$newBuilderHash = Get-Sha256File $newBuilder
$newGuiFileHash = Get-Sha256File $patchedGuiPath
if ($newGuiFileHash -ne $newGuiHash) { throw 'Written patched GUI hash mismatch.' }

# Full written-builder roundtrip proof.
$roundText = [IO.File]::ReadAllText($newBuilder)
$roundOuter = Get-OuterInfo $roundText
$roundGui = Get-PayloadInfo $roundOuter.CSharp 'GuiGzipBase64'
$roundEngine = Get-PayloadInfo $roundOuter.CSharp 'EngineGzipBase64'
$roundGuiHash = Get-Sha256Bytes $roundGui.Bytes
$roundEngineHash = Get-Sha256Bytes $roundEngine.Bytes
if ($roundGuiHash -ne $newGuiHash) { throw 'GUI roundtrip hash mismatch.' }
if ($roundEngineHash -ne $ExpectedEngineSha256) { throw 'ENGINE changed during GUI-only transplant.' }
if (@([regex]::Matches($roundGui.Text,'(?i)\bGet-FileHash\b')).Count -ne 0) { throw 'Roundtrip GUI contains Get-FileHash.' }
if ((Get-Sha256Text (Get-ResolverRegion $roundGui.Text)) -ne $resolverBeforeHash) { throw 'Roundtrip resolver hash mismatch.' }
if ((Get-Sha256Text (Get-FunctionText $roundGui.Text 'Get-Sha256')) -ne $shaFunctionBeforeHash) { throw 'Roundtrip Get-Sha256 hash mismatch.' }
Test-PowerShellText $roundGui.Text 'roundtrip GUI'
Test-PowerShellText $roundEngine.Text 'roundtrip ENGINE'

# Original input builder and donor stay untouched.
if ((Get-Sha256File $BuilderPath) -ne $ExpectedBuilderSha256) { throw 'Original input builder was modified unexpectedly.' }
if ((Get-Sha256File $DonorGuiPath) -ne $ExpectedDonorGuiSha256) { throw 'Recovered donor GUI was modified unexpectedly.' }

$report = Join-Path $workRoot 'STAGE3_STATUSPANEL_V6_REPORT.txt'
$reportLines = @(
    'AOTR 8P STAGE 3 STATUS PANEL TRANSPLANT V6',
    ('GeneratedUtc=' + [DateTime]::UtcNow.ToString('o')),
    ('InputBuilder=' + $BuilderPath),
    ('InputBuilderSha256=' + $ExpectedBuilderSha256),
    ('InputGuiSha256=' + $ExpectedGuiSha256),
    ('InputEngineSha256=' + $ExpectedEngineSha256),
    ('DonorGui=' + $DonorGuiPath),
    ('DonorGuiSha256=' + $ExpectedDonorGuiSha256),
    ('OutputBuilder=' + $newBuilder),
    ('OutputBuilderSha256=' + $newBuilderHash),
    ('OutputGuiSha256=' + $newGuiHash),
    ('OutputEngineSha256=' + $roundEngineHash),
    ('ResolverRegionSha256Before=' + $resolverBeforeHash),
    ('ResolverRegionSha256After=' + $resolverAfterHash),
    ('GetSha256FunctionShaBefore=' + $shaFunctionBeforeHash),
    ('GetSha256FunctionShaAfter=' + $shaFunctionAfterHash),
    'DynamicStatusControls=5',
    'DynamicStatusFunctions=3',
    'PreflightStatusCalls=10',
    'GetFileHashRemaining=0',
    'AutodetectResolverChanged=NO',
    'GetSha256Changed=NO',
    'EngineChanged=NO',
    'OriginalBuilderModified=NO',
    'DonorGuiModified=NO',
    'PublicReleaseModified=NO',
    'GameFilesModified=NO'
)
[IO.File]::WriteAllText($report,($reportLines -join [Environment]::NewLine),$utf8NoBom)

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' STAGE 3 STATUS PANEL TRANSPLANT V6 COMPLETE' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host "Work root      : $workRoot"
Write-Host "Patched builder: $newBuilder"
Write-Host "Builder SHA256 : $newBuilderHash"
Write-Host "GUI SHA256     : $newGuiHash"
Write-Host "ENGINE SHA256  : $roundEngineHash"
Write-Host "Report         : $report"
Write-Host ''
Write-Host 'Dynamic status controls : 5' -ForegroundColor Green
Write-Host 'Dynamic status functions: 3' -ForegroundColor Green
Write-Host 'Preflight status calls   : 10' -ForegroundColor Green
Write-Host 'Get-FileHash remaining   : 0' -ForegroundColor Green
Write-Host 'Autodetect resolver changed: NO' -ForegroundColor Green
Write-Host 'Get-Sha256 changed         : NO' -ForegroundColor Green
Write-Host 'Engine changed              : NO' -ForegroundColor Green
Write-Host 'Original builder modified   : NO' -ForegroundColor Green
Write-Host 'Public/release EXE modified : NO' -ForegroundColor Green
Write-Host 'Game files modified         : NO' -ForegroundColor Green
