param(
    [string]$DumpFolder = 'C:\AOTR_RESEARCH\LOCALDUMPS',
    [int]$TimeoutSeconds = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# game.dat is a 32-bit process on a 64-bit Windows guest. Microsoft documents
# the WOW64 WER LocalDumps location for collecting dumps from 32-bit apps.
$AppKey = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\Windows Error Reporting\LocalDumps\game.dat'
$AppKeyNative = 'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\Windows Error Reporting\LocalDumps\game.dat'
$ResearchRoot = Split-Path -Parent $DumpFolder
$BackupReg = Join-Path $ResearchRoot 'WER_LocalDumps_game.dat_before_capture.reg'
$Marker = Join-Path $ResearchRoot 'WER_LocalDumps_game.dat_before_capture.NONEXISTENT.txt'

function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restore-LocalDumps {
    Write-Host ''
    Write-Host '================ RESTORE WER LOCALDUMPS ================'
    if (Test-Path -LiteralPath $BackupReg -PathType Leaf) {
        & reg.exe delete $AppKeyNative /f | Out-Null
        & reg.exe import $BackupReg | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Failed to restore previous LocalDumps game.dat registry key.' }
        Write-Host 'WER_LOCALDUMPS_RESTORED_FROM_BACKUP=YES' -ForegroundColor Green
    }
    elseif (Test-Path -LiteralPath $Marker -PathType Leaf) {
        & reg.exe delete $AppKeyNative /f 2>$null | Out-Null
        Write-Host 'WER_LOCALDUMPS_CREATED_KEY_REMOVED=YES' -ForegroundColor Green
    }
    else {
        Write-Warning 'No restore backup/marker found. Registry state left unchanged.'
    }
}

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'Expected a 64-bit Windows guest. NOTHING CHANGED.'
}
if (-not [Environment]::Is64BitProcess) {
    throw 'Run this LocalDumps setup under normal 64-bit Windows PowerShell as Administrator. NOTHING CHANGED.'
}
if (-not (Is-Admin)) {
    throw 'ADMIN REQUIRED. Re-run Windows PowerShell as Administrator. NOTHING CHANGED.'
}
if ($TimeoutSeconds -lt 60 -or $TimeoutSeconds -gt 1800) {
    throw 'TimeoutSeconds must be 60..1800.'
}

New-Item -ItemType Directory -Path $ResearchRoot -Force | Out-Null
New-Item -ItemType Directory -Path $DumpFolder -Force | Out-Null
Remove-Item -LiteralPath $BackupReg,$Marker -Force -ErrorAction SilentlyContinue

$preExisting = Test-Path -LiteralPath $AppKey
if ($preExisting) {
    & reg.exe export $AppKeyNative $BackupReg /y | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $BackupReg -PathType Leaf)) {
        throw 'Failed to export existing LocalDumps game.dat registry key. NOTHING CHANGED.'
    }
    Write-Host 'PREEXISTING_LOCALDUMPS_APPKEY=YES'
}
else {
    Set-Content -LiteralPath $Marker -Value 'Per-app WOW64 LocalDumps key did not exist before this capture.' -Encoding ASCII
    Write-Host 'PREEXISTING_LOCALDUMPS_APPKEY=NO'
}

$start = Get-Date
$baseline = @{}
Get-ChildItem -LiteralPath $DumpFolder -Filter '*.dmp' -File -ErrorAction SilentlyContinue | ForEach-Object {
    $baseline[$_.FullName.ToLowerInvariant()] = $_.LastWriteTimeUtc
}

try {
    New-Item -Path $AppKey -Force | Out-Null
    New-ItemProperty -Path $AppKey -Name DumpFolder -Value $DumpFolder -PropertyType ExpandString -Force | Out-Null
    New-ItemProperty -Path $AppKey -Name DumpType -Value 2 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $AppKey -Name DumpCount -Value 5 -PropertyType DWord -Force | Out-Null

    $cfg = Get-ItemProperty -LiteralPath $AppKey
    if ([string]$cfg.DumpFolder -ne $DumpFolder -or [int]$cfg.DumpType -ne 2 -or [int]$cfg.DumpCount -ne 5) {
        throw 'LocalDumps verification failed.'
    }

    Write-Host '============================================================'
    Write-Host ' AOTR NATIVE TERRITORY WER LOCALDUMP CAPTURE V1'
    Write-Host '============================================================'
    Write-Host 'WER_REGISTRY_VIEW=WOW64_32BIT'
    Write-Host ('Registry   : {0}' -f $AppKeyNative)
    Write-Host ('DumpFolder : {0}' -f $DumpFolder)
    Write-Host 'DumpType   : 2 (full user-mode dump)'
    Write-Host 'DumpCount  : 5'
    Write-Host 'DEBUGGER_ATTACH=NO'
    Write-Host 'GAME_MEMORY_WRITE=NO'
    Write-Host 'GAME_FUNCTION_CALL=NO'
    Write-Host 'WER_LOCALDUMPS_READY=YES' -ForegroundColor Green
    Write-Host 'NEXT_ACTION=Use a fresh normal UI join, then click exactly one WotR territory. Do not use the PoC/debugger.' -ForegroundColor Yellow
    Write-Host ''

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $found = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $candidates = @(Get-ChildItem -LiteralPath $DumpFolder -Filter '*.dmp' -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.LastWriteTime -ge $start -and (
                    -not $baseline.ContainsKey($_.FullName.ToLowerInvariant()) -or
                    $_.LastWriteTimeUtc -gt $baseline[$_.FullName.ToLowerInvariant()]
                )
            } |
            Sort-Object LastWriteTime -Descending)
        if ($candidates.Count -gt 0) {
            $candidate = $candidates[0]
            $size1 = $candidate.Length
            Start-Sleep -Milliseconds 1000
            $candidate.Refresh()
            $size2 = $candidate.Length
            if ($size2 -gt 0 -and $size2 -eq $size1) {
                $found = $candidate
                break
            }
        }
    }

    if ($null -eq $found) {
        Write-Host 'LOCALDUMP_CAPTURED=NO'
        Write-Host 'LOCALDUMP_TIMEOUT=YES'
    }
    else {
        $sha = (Get-FileHash -LiteralPath $found.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
        Write-Host 'LOCALDUMP_CAPTURED=YES' -ForegroundColor Green
        Write-Host ('LOCALDUMP_PATH={0}' -f $found.FullName)
        Write-Host ('LOCALDUMP_SIZE={0}' -f $found.Length)
        Write-Host ('LOCALDUMP_SHA256={0}' -f $sha)
        Write-Host ('LOCALDUMP_TIME={0:O}' -f $found.LastWriteTime)
    }
}
finally {
    Restore-LocalDumps
    Write-Host 'CAPTURE_SESSION_COMPLETE=YES'
}
