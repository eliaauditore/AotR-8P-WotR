#requires -version 5.1
[CmdletBinding()]
param(
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE1_20260827_003823\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_NONRELEASE.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = '6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386'

function Get-VarNameFromAst($Ast) {
    try {
        if ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
            return $Ast.VariablePath.UserPath
        }
    } catch {}
    return $null
}

$full = [IO.Path]::GetFullPath($BuilderPath)
if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
    throw "Stage 1 non-release builder not found: $full"
}

$actual = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()
if ($actual -ne $ExpectedBuilderSha256) {
    throw "Builder checkpoint mismatch. Expected $ExpectedBuilderSha256, got $actual. Refusing preflight."
}

$text = [IO.File]::ReadAllText($full)
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if ($errors -and $errors.Count -gt 0) {
    $msg = ($errors | ForEach-Object { "Line $($_.Extent.StartLineNumber): $($_.Message)" }) -join [Environment]::NewLine
    throw "Builder parser validation failed:`n$msg"
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P ROBUST AUTODETECT V2 - STAGE 2 BUILD PREFLIGHT' -ForegroundColor Cyan
Write-Host ' READ ONLY / NO BUILD' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Builder : $full"
Write-Host "SHA256  : $actual" -ForegroundColor Green
Write-Host ''

Write-Host '=== PARAMETERS ===' -ForegroundColor Cyan
$paramRows = New-Object System.Collections.Generic.List[object]
if ($ast.ParamBlock) {
    foreach ($p in $ast.ParamBlock.Parameters) {
        $defaultText = ''
        try {
            if ($p.DefaultValue) { $defaultText = $p.DefaultValue.Extent.Text }
        } catch {}
        $typeText = ''
        try {
            if ($p.StaticType) { $typeText = $p.StaticType.FullName }
        } catch {}
        [void]$paramRows.Add([pscustomobject]@{
            Name = $p.Name.VariablePath.UserPath
            Type = $typeText
            Default = $defaultText
        })
    }
}
$paramRows | Format-Table -Wrap -AutoSize

Write-Host ''
Write-Host '=== OUTPUT / PATH ASSIGNMENTS ===' -ForegroundColor Cyan
$interestingVars = @(
    'PackageRoot','Launcher','tempRoot','newExe','bundleUpdate','backupRoot','backup',
    'OutputPath','OutputRoot','BuildRoot','ReleaseRoot','BundleRoot','RepoRoot'
)
$assignRows = New-Object System.Collections.Generic.List[object]
$assignments = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] },$true)
foreach ($a in $assignments) {
    $name = Get-VarNameFromAst $a.Left
    if (-not $name) { continue }
    if ($interestingVars -notcontains $name) { continue }
    [void]$assignRows.Add([pscustomobject]@{
        Line = $a.Extent.StartLineNumber
        Variable = $name
        Expression = $a.Right.Extent.Text
    })
}
$assignRows | Sort-Object Line | Format-Table -Wrap -AutoSize

Write-Host ''
Write-Host '=== WRITE / PROCESS COMMANDS ===' -ForegroundColor Cyan
$writeCommands = @(
    'Copy-Item','Move-Item','Remove-Item','Rename-Item','New-Item','Set-Content','Add-Content',
    'Out-File','Export-Clixml','ConvertTo-Json','Start-Process','Compress-Archive','Expand-Archive'
)
$cmdRows = New-Object System.Collections.Generic.List[object]
$commands = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] },$true)
foreach ($c in $commands) {
    $name = $c.GetCommandName()
    if (-not $name) { continue }
    if ($writeCommands -notcontains $name) { continue }
    [void]$cmdRows.Add([pscustomobject]@{
        Line = $c.Extent.StartLineNumber
        Command = $name
        Text = $c.Extent.Text
    })
}
$cmdRows | Sort-Object Line | Format-Table -Wrap -AutoSize

Write-Host ''
Write-Host '=== HIGH-VALUE SOURCE HITS ===' -ForegroundColor Cyan
$patterns = @(
    'PackageRoot','AotR 8P WotR Mod.exe','seed_backup','bundleUpdate','manifest.json',
    'repair-manifest','Copy-Item','Move-Item','Remove-Item','Start-Process','LauncherVersion',
    'Release','publish','GitHub','repoRaw'
)
$lines = @($text -split "`r?`n")
$hitRows = New-Object System.Collections.Generic.List[object]
for ($i=0; $i -lt $lines.Count; $i++) {
    foreach ($term in $patterns) {
        if ($lines[$i].IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
            [void]$hitRows.Add([pscustomobject]@{
                Line = $i + 1
                Term = $term
                Text = $lines[$i].Trim()
            })
            break
        }
    }
}
$hitRows | Format-Table -Wrap -AutoSize

$paramNames = @($paramRows | ForEach-Object { $_.Name })
$hasPackageRoot = $paramNames -contains 'PackageRoot'
$hasLauncherVersion = $paramNames -contains 'LauncherVersion'

Write-Host ''
Write-Host '=== STATIC VERDICT ===' -ForegroundColor Cyan
Write-Host ("PackageRoot parameter : {0}" -f $hasPackageRoot)
Write-Host ("LauncherVersion param : {0}" -f $hasLauncherVersion)

if ($hasPackageRoot) {
    Write-Host 'Potential isolation mechanism exists: -PackageRoot can be supplied.' -ForegroundColor Green
} else {
    Write-Host 'No PackageRoot parameter proven. Do NOT execute builder yet.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Preflight only. Builder was NOT executed.' -ForegroundColor Green
Write-Host 'No files, registry keys, game files, launcher files or Git state were modified by this audit.' -ForegroundColor Green
