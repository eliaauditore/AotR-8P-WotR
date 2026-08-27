#requires -version 5.1
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-Sha256File([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $stream.Dispose() }
    }
    finally { $sha.Dispose() }
}

function Expand-GzipBase64([string]$Base64) {
    $compressed = [Convert]::FromBase64String(($Base64 -replace '\s',''))
    $input = New-Object IO.MemoryStream(,$compressed)
    try {
        $gzip = New-Object IO.Compression.GZipStream($input,[IO.Compression.CompressionMode]::Decompress)
        try {
            $output = New-Object IO.MemoryStream
            try {
                $gzip.CopyTo($output)
                return [Text.Encoding]::UTF8.GetString($output.ToArray())
            }
            finally { $output.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally { $input.Dispose() }
}

function Get-GuiFromAssembly([string]$ExePath) {
    try {
        $asm = [Reflection.Assembly]::ReflectionOnlyLoadFrom($ExePath)
    }
    catch {
        try { $asm = [Reflection.Assembly]::LoadFile($ExePath) }
        catch { return $null }
    }

    foreach ($type in $asm.GetTypes()) {
        $flags = [Reflection.BindingFlags]'Public,NonPublic,Static,Instance'
        foreach ($field in $type.GetFields($flags)) {
            if ($field.Name -eq 'GuiGzipBase64') {
                $value = $null
                try {
                    if ($field.IsLiteral) { $value = [string]$field.GetRawConstantValue() }
                    elseif ($field.IsStatic) { $value = [string]$field.GetValue($null) }
                } catch {}
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    try { return (Expand-GzipBase64 $value) } catch {}
                }
            }
        }
    }
    return $null
}

function Show-Hits([string]$Label,[string]$Gui) {
    $lines = $Gui -split "`r?`n"
    $patterns = @(
        'HealthHeaderText','HealthStatusText','StatusPanel','StatusHeader','StatusText',
        'Row1','Row2','Row3','ReadyCleanPatch','Invoke-Preflight',
        'game\.dat','campaign payload','roster UI','compatible','ready to launch','verified','detected'
    )
    Write-Host ''
    Write-Host ("=== {0} / STATUS HITS ===" -f $Label) -ForegroundColor Cyan
    $hitLines = New-Object System.Collections.Generic.List[int]
    for ($i=0; $i -lt $lines.Count; $i++) {
        foreach ($p in $patterns) {
            if ($lines[$i] -match $p) {
                Write-Host ('{0,5}: {1}' -f ($i+1),$lines[$i])
                [void]$hitLines.Add($i+1)
                break
            }
        }
    }

    $focus = @($hitLines | Select-Object -First 20)
    $shown = @{}
    foreach ($ln in $focus) {
        $start = [Math]::Max(1,$ln-10)
        $end = [Math]::Min($lines.Count,$ln+18)
        $key = "$start-$end"
        if ($shown.ContainsKey($key)) { continue }
        $shown[$key] = $true
        Write-Host ''
        Write-Host ("--- context {0}-{1} / hit {2} ---" -f $start,$end,$ln) -ForegroundColor DarkCyan
        for ($n=$start; $n -le $end; $n++) {
            $mark = if ($n -eq $ln) { '>>' } else { '  ' }
            Write-Host ('{0} {1,5}: {2}' -f $mark,$n,$lines[$n-1])
        }
    }
}

if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw "Base missing: $Base" }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P STAGE 3 STATUS PANEL EXE RECOVERY AUDIT V3' -ForegroundColor Cyan
Write-Host ' OLD V18 RC EXE EMBEDDED GUI / READ ONLY' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Base: $Base"

$dirs = @(Get-ChildItem -LiteralPath $Base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^V18_RC[1-4]_TEST_' })
Write-Host "V18 RC test dirs: $($dirs.Count)"
if ($dirs.Count -eq 0) { throw 'No V18_RC*_TEST_* directories found.' }

$results = New-Object System.Collections.Generic.List[object]
foreach ($dir in $dirs) {
    $exes = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Filter 'AotR 8P WotR Mod.exe' -ErrorAction SilentlyContinue)
    foreach ($exe in $exes) {
        $gui = Get-GuiFromAssembly $exe.FullName
        [void]$results.Add([PSCustomObject]@{
            Dir = $dir.Name
            Exe = $exe.FullName
            Sha256 = (Get-Sha256File $exe.FullName)
            GuiRecovered = [bool]$gui
            Gui = $gui
        })
    }
}

Write-Host ''
Write-Host '=== EXE INVENTORY ===' -ForegroundColor Cyan
$results | Select-Object Dir,Exe,Sha256,GuiRecovered | Format-Table -AutoSize | Out-Host

$recovered = @($results | Where-Object GuiRecovered)
if ($recovered.Count -eq 0) {
    throw 'No embedded GUI could be recovered from the V18 RC EXEs via .NET reflection.'
}

$work = Join-Path $Base ('STATUS_PANEL_EXE_RECOVERY_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

$seen = @{}
$idx = 0
foreach ($r in $recovered) {
    $guiBytes = [Text.Encoding]::UTF8.GetBytes([string]$r.Gui)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $guiSha = ([BitConverter]::ToString($sha.ComputeHash($guiBytes))).Replace('-','') }
    finally { $sha.Dispose() }
    if ($seen.ContainsKey($guiSha)) { continue }
    $seen[$guiSha] = $true
    $idx++
    $path = Join-Path $work ("GUI_{0}_{1}.ps1" -f $idx,$guiSha.Substring(0,12))
    [IO.File]::WriteAllText($path,[string]$r.Gui,(New-Object Text.UTF8Encoding($false)))
    Write-Host ''
    Write-Host "Recovered GUI #$idx" -ForegroundColor Green
    Write-Host "  Source EXE : $($r.Exe)"
    Write-Host "  EXE SHA    : $($r.Sha256)"
    Write-Host "  GUI SHA    : $guiSha"
    Write-Host "  Saved      : $path"
    Show-Hits -Label ("GUI #$idx") -Gui ([string]$r.Gui)
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' EXE RECOVERY AUDIT COMPLETE' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host "Recovered unique GUIs: $idx"
Write-Host "Evidence root          : $work"
Write-Host 'No EXE, builder, game, config, cache, or release files were modified.' -ForegroundColor Green
