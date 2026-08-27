#requires -version 7.0
[CmdletBinding()]
param(
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE1_20260827_022948\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10_ROBUST_AUTODETECT_V2_NONRELEASE.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = 'D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0'
$ExpectedGuiSha256 = 'CFAF397833536769D726B0DD0960D940AAA6896ED62BFEFA0764185C2CEA90DC'
$ExpectedEngineSha256 = '94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA'

function Get-Sha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Get-Sha256File([string]$Path) {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
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

function Get-OuterInfo([string]$BuilderText) {
    $pattern = '(?s)\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\s*(?<data>[A-Za-z0-9+/=\r\n]+?)\s*''@\)\)'
    $m = [regex]::Match($BuilderText,$pattern)
    if (-not $m.Success) { throw 'Could not locate outer C# template.' }
    $bytes = [Convert]::FromBase64String(($m.Groups['data'].Value -replace '\s',''))
    return [PSCustomObject]@{ Bytes=$bytes; Text=(Get-Utf8Text $bytes) }
}

function Get-Payload([string]$CSharp,[string]$Name) {
    $pattern = '(?s)(?:private\s+)?const\s+string\s+' + [regex]::Escape($Name) + '\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
    $m = [regex]::Match($CSharp,$pattern)
    if (-not $m.Success) { throw ('Could not locate payload ' + $Name + '.') }
    $bytes = Expand-GzipBase64Bytes $m.Groups['data'].Value
    return [PSCustomObject]@{ Bytes=$bytes; Text=(Get-Utf8Text $bytes); Sha256=(Get-Sha256Bytes $bytes) }
}

function Show-Hits([string]$Label,[string[]]$Lines,[string]$Pattern,[int]$Context=2) {
    Write-Host ''
    Write-Host ('=== ' + $Label + ' ===') -ForegroundColor Cyan
    $hits = New-Object System.Collections.Generic.List[int]
    for ($i=0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match $Pattern) { [void]$hits.Add($i) }
    }
    if ($hits.Count -eq 0) {
        Write-Host '<none>' -ForegroundColor DarkGray
        return
    }
    $printed = @{}
    foreach ($idx in $hits) {
        $start = [Math]::Max(0,$idx-$Context)
        $end = [Math]::Min($Lines.Count-1,$idx+$Context)
        for ($j=$start; $j -le $end; $j++) {
            if ($printed.ContainsKey($j)) { continue }
            $printed[$j] = $true
            $mark = if ($j -eq $idx) { '>>' } else { '  ' }
            Write-Host ('{0} {1,5}: {2}' -f $mark,($j+1),$Lines[$j])
        }
        Write-Host '-----' -ForegroundColor DarkGray
    }
}

if (-not (Test-Path -LiteralPath $BuilderPath -PathType Leaf)) { throw ('Builder missing: ' + $BuilderPath) }
$builderSha = Get-Sha256File $BuilderPath
if ($builderSha -ne $ExpectedBuilderSha256) { throw ('Builder hash mismatch. Expected ' + $ExpectedBuilderSha256 + ', got ' + $builderSha) }

$builderText = Get-Utf8Text ([IO.File]::ReadAllBytes($BuilderPath))
$outer = Get-OuterInfo $builderText
$gui = Get-Payload $outer.Text 'GuiGzipBase64'
$engine = Get-Payload $outer.Text 'EngineGzipBase64'
if ($gui.Sha256 -ne $ExpectedGuiSha256) { throw ('GUI hash mismatch. Expected ' + $ExpectedGuiSha256 + ', got ' + $gui.Sha256) }
if ($engine.Sha256 -ne $ExpectedEngineSha256) { throw ('ENGINE hash mismatch. Expected ' + $ExpectedEngineSha256 + ', got ' + $engine.Sha256) }

$lines = @($gui.Text -split "`r?`n")

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P V18 STAGE 8 - WINDOW CHROME DIAGNOSTIC' -ForegroundColor Cyan
Write-Host ' READ ONLY / EXACT CURRENT GUI PAYLOAD' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ('Builder SHA : ' + $builderSha)
Write-Host ('GUI SHA     : ' + $gui.Sha256)
Write-Host ('ENGINE SHA  : ' + $engine.Sha256)
Write-Host ('GUI lines   : ' + $lines.Count)

Show-Hits 'FORM / WINDOW CONSTRUCTION' $lines '(?i)(New-Object\s+.*Windows\.Forms\.Form|Windows\.Forms\.Form\]::new|New-Object\s+.*Windows\.Window|Windows\.Window\]::new|XamlReader|<Window\b|Window\s+xmlns)'
Show-Hits 'TITLE / TEXT ASSIGNMENTS' $lines '(?i)\.(Text|Title)\s*='
Show-Hits 'WINDOW CHROME / RESIZE PROPERTIES' $lines '(?i)(MaximizeBox|MinimizeBox|FormBorderStyle|ResizeMode|WindowStyle|WindowState|AllowsTransparency|ResizeGrip|SizeToContent|Topmost)'
Show-Hits 'SHOW / SHOWDIALOG CALLS' $lines '(?i)\.(Show|ShowDialog)\s*\('
Show-Hits 'CUSTOM CAPTION BUTTON CLUES' $lines '(?i)(maximize|maximise|restore|windowstate|caption|titlebar|chrome|closebutton|minimize|minimise|btnmax|btnrestore|btnclose|btnmin)'
Show-Hits 'WPF BUTTON / XAML CLUES' $lines '(?i)(<Button\b|<Grid\b|<DockPanel\b|<Border\b|FindName\(|Add_Click|\.Add_Click)'

Write-Host ''
Write-Host '=== READ-ONLY ASSERTIONS ===' -ForegroundColor Cyan
Write-Host ('Builder unchanged : ' + ((Get-Sha256File $BuilderPath) -eq $ExpectedBuilderSha256)) -ForegroundColor Green
Write-Host ('Get-FileHash GUI  : ' + @([regex]::Matches($gui.Text,'\bGet-FileHash\b',[Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count)
Write-Host ('Get-FileHash ENGINE: ' + @([regex]::Matches($engine.Text,'\bGet-FileHash\b',[Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count)
Write-Host ''
Write-Host 'STAGE 8 DIAGNOSTIC COMPLETE - NO PATCH WRITTEN.' -ForegroundColor Green
