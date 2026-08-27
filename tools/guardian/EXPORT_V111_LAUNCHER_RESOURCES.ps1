#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DonorRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedDonorExeSha256 = "2141EA9690708EA7A61B7298AD90E0C76CC417FED996AC0CF3685276BA2A4024"
$ExpectedUiSha256 = "827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376"
$ExpectedPaperSha256 = "3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43"
$ExpectedSkinSha256 = "BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6"
$ExpectedGuiSha256 = "23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C"
$ExpectedEngineSha256 = "94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA"
$ExpectedFinalStableV7Sha256 = "FEAF40B3B231646CD8F7C7099D1E8544090D5010F1C6DB06E5B2F3EF8C0C5F44"
$ExpectedV7ShellcodeSha256 = "60EECE4660C3BA0AD183EB82B82DCDACF3ECA6DC892C8FAFCD629A92170ED45A"
$ExpectedV7ShellcodeLength = 1577

$ExpectedRowPatches = @(
    @{ Variable = "Row1CleanPatchBase64"; File = "row1cleanpatch.png"; Sha256 = "D4DC9A47F0E2FD9715D92F8DD4C3831B9AB95F8CA34E98937F019B7574294177" },
    @{ Variable = "Row2CleanPatchBase64"; File = "row2cleanpatch.png"; Sha256 = "58B9A7173CE1C9C30C85EE76D15D54E3D40B3E7E14E25D0C1FE5D8EFD89E6D8E" },
    @{ Variable = "Row3CleanPatchBase64"; File = "row3cleanpatch.png"; Sha256 = "7F86C02BC02D2E57D66202AF9C526D6FAE13CFC9B7CB1EFF1BB61C165B25278C" },
    @{ Variable = "ReadyCleanPatchBase64"; File = "readycleanpatch.png"; Sha256 = "35DCBCBE6E625C5C06EC36BAB3CA51A6F4EE29DA3DFF4CAEEDD69BC87D873DF3" }
)

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

function Assert-Hash([string]$Path, [string]$Expected, [string]$Role) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Role missing: $Path"
    }
    $actual = Get-Sha256 $Path
    if ($actual -ne $Expected) {
        throw "$Role SHA256 mismatch. Expected $Expected, got $actual"
    }
    Write-Host "$Role OK: $actual" -ForegroundColor Green
    return $actual
}

function Inflate-Base64Gzip([string]$Value, [string]$OutPath) {
    $packed = [Convert]::FromBase64String($Value)
    $input = New-Object IO.MemoryStream(,$packed)
    try {
        $gzip = New-Object IO.Compression.GZipStream($input, [IO.Compression.CompressionMode]::Decompress)
        try {
            $output = [IO.File]::Create($OutPath)
            try {
                $gzip.CopyTo($output)
            }
            finally {
                $output.Dispose()
            }
        }
        finally {
            $gzip.Dispose()
        }
    }
    finally {
        $input.Dispose()
    }
}

$DonorRoot = [IO.Path]::GetFullPath($DonorRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$DonorExe = Join-Path $DonorRoot "AotR 8P WotR Mod.exe"
$DonorUi = Join-Path $DonorRoot "payload_ui.big"
$DonorPaper = Join-Path $DonorRoot "payload_paper.inc"

Assert-Hash $DonorExe $ExpectedDonorExeSha256 "Frozen v1.1.1 EXE" | Out-Null
Assert-Hash $DonorUi $ExpectedUiSha256 "Frozen v1.1.1 UI payload" | Out-Null
Assert-Hash $DonorPaper $ExpectedPaperSha256 "Frozen v1.1.1 Paper payload" | Out-Null

if (Test-Path -LiteralPath $OutputRoot) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.Drawing

$assembly = [Reflection.Assembly]::LoadFile($DonorExe)
$type = $assembly.GetType("Program", $true)
$flags = [Reflection.BindingFlags]"NonPublic,Public,Static"

function Get-ConstString([string]$Name) {
    $field = $type.GetField($Name, $flags)
    if (-not $field) {
        throw "Frozen donor field missing: $Name"
    }
    $value = $field.GetRawConstantValue()
    if (-not ($value -is [string])) {
        throw "Frozen donor field is not a string: $Name"
    }
    return [string]$value
}

$skinPath = Join-Path $OutputRoot "launcher_skin.png"
$guiPath = Join-Path $OutputRoot "launcher_gui.ps1"
$enginePath = Join-Path $OutputRoot "launcher_engine.ps1"
$iconPath = Join-Path $OutputRoot "launcher.ico"
$finalPath = Join-Path $OutputRoot "final_stable_v7.ps1"
$shellcodePath = Join-Path $OutputRoot "v7_shellcode.bin"

Inflate-Base64Gzip (Get-ConstString "Issue33SkinGzipBase64") $skinPath
Inflate-Base64Gzip (Get-ConstString "GuiGzipBase64") $guiPath
Inflate-Base64Gzip (Get-ConstString "EngineGzipBase64") $enginePath

Assert-Hash $skinPath $ExpectedSkinSha256 "Launcher skin" | Out-Null
Assert-Hash $guiPath $ExpectedGuiSha256 "Frozen GUI source" | Out-Null
Assert-Hash $enginePath $ExpectedEngineSha256 "Frozen engine source" | Out-Null

$iconObject = [Drawing.Icon]::ExtractAssociatedIcon($DonorExe)
if (-not $iconObject) {
    throw "Could not extract launcher icon from frozen donor EXE."
}
$iconStream = [IO.File]::Create($iconPath)
try {
    $iconObject.Save($iconStream)
}
finally {
    $iconStream.Dispose()
    $iconObject.Dispose()
}

$guiText = Get-Content -LiteralPath $guiPath -Raw -Encoding UTF8
foreach ($entry in $ExpectedRowPatches) {
    $variable = [string]$entry.Variable
    $fileName = [string]$entry.File
    $expected = [string]$entry.Sha256
    $pattern = '(?m)^\$' + [regex]::Escape($variable) + '\s*=\s*"([^"]+)"\s*$'
    $matches = [regex]::Matches($guiText, $pattern)
    if ($matches.Count -ne 1) {
        throw "Expected exactly one $variable resource definition, found $($matches.Count)."
    }
    $path = Join-Path $OutputRoot $fileName
    [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String($matches[0].Groups[1].Value))
    Assert-Hash $path $expected $fileName | Out-Null
}

$engineText = Get-Content -LiteralPath $enginePath -Raw -Encoding UTF8
$finalPattern = '(?s)\$FinalStableV7Base64\s*=\s*@''\s*(.*?)\s*''@'
$finalMatches = [regex]::Matches($engineText, $finalPattern)
if ($finalMatches.Count -ne 1) {
    throw "Expected exactly one FinalStableV7Base64 block, found $($finalMatches.Count)."
}
$finalBytes = [Convert]::FromBase64String(($finalMatches[0].Groups[1].Value -replace '\s', ''))
[IO.File]::WriteAllBytes($finalPath, $finalBytes)
Assert-Hash $finalPath $ExpectedFinalStableV7Sha256 "Frozen FINAL_STABLE_V7 source" | Out-Null

$finalText = Get-Content -LiteralPath $finalPath -Raw -Encoding UTF8
$shellcodePattern = '(?s)\$ShellcodeBase64\s*=\s*@''\s*(.*?)\s*''@'
$shellcodeMatches = [regex]::Matches($finalText, $shellcodePattern)
if ($shellcodeMatches.Count -ne 1) {
    throw "Expected exactly one ShellcodeBase64 block, found $($shellcodeMatches.Count)."
}
$shellcodeBytes = [Convert]::FromBase64String(($shellcodeMatches[0].Groups[1].Value -replace '\s', ''))
if ($shellcodeBytes.Length -ne $ExpectedV7ShellcodeLength) {
    throw "V7 shellcode length mismatch. Expected $ExpectedV7ShellcodeLength, got $($shellcodeBytes.Length)."
}
[IO.File]::WriteAllBytes($shellcodePath, $shellcodeBytes)
Assert-Hash $shellcodePath $ExpectedV7ShellcodeSha256 "Frozen V7 shellcode" | Out-Null

$resources = @()
foreach ($file in @(Get-ChildItem -LiteralPath $OutputRoot -File | Sort-Object Name)) {
    if ($file.Name -eq "provenance.json") {
        continue
    }
    $resources += [ordered]@{
        name = $file.Name
        size = [int64]$file.Length
        sha256 = Get-Sha256 $file.FullName
    }
}

$manifest = [ordered]@{
    schema = 1
    purpose = "one-time provenance export for donor-free SignPath migration"
    source_ref = "v1.1.1"
    source_release_commit = "303c202ffd809dbe70fb6e2611d98ce4f9773128"
    donor_exe_sha256 = $ExpectedDonorExeSha256
    donor_ui_sha256 = $ExpectedUiSha256
    donor_paper_sha256 = $ExpectedPaperSha256
    generated_utc = [DateTime]::UtcNow.ToString("o")
    resources = $resources
    warning = "Exported bytes are provenance evidence only. Their copyright/license status must be reviewed before any OSS licensing or SignPath application."
}

$manifestPath = Join-Path $OutputRoot "provenance.json"
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " v1.1.1 launcher provenance export complete" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Output: $OutputRoot"
Write-Host "Manifest: $manifestPath"
Write-Host "Exported resources: $($resources.Count)"
