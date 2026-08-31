param(
    [string]$WerTemp = 'C:\ProgramData\Microsoft\Windows\WER\Temp',
    [string]$OutDir = 'C:\AOTR_RESEARCH\WER_SALVAGED_DUMPS',
    [int]$TimeoutSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Is-Admin)) { throw 'ADMIN REQUIRED. NOTHING EXECUTED.' }
if ($TimeoutSeconds -lt 30 -or $TimeoutSeconds -gt 1800) { throw 'TimeoutSeconds must be 30..1800.' }
if (-not (Test-Path -LiteralPath $WerTemp -PathType Container)) { throw "WER temp folder not found: $WerTemp" }

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$start = Get-Date
$deadline = $start.AddSeconds($TimeoutSeconds)
$baseline = @{}
Get-ChildItem -LiteralPath $WerTemp -Filter '*.tmp.dmp' -File -ErrorAction SilentlyContinue | ForEach-Object {
    $baseline[$_.FullName.ToLowerInvariant()] = $_.LastWriteTimeUtc
}

Write-Host '============================================================'
Write-Host ' AOTR WER TEMP LIVE DUMP CAPTURE V1'
Write-Host '============================================================'
Write-Host 'MODE=READ/COPY ONLY'
Write-Host 'DEBUGGER_ATTACH=NO'
Write-Host 'GAME_PROCESS_ACCESS=NO'
Write-Host 'REGISTRY_WRITE=NO'
Write-Host ('WER_TEMP={0}' -f $WerTemp)
Write-Host ('OUT_DIR={0}' -f $OutDir)
Write-Host 'WER_TEMP_WATCH_READY=YES' -ForegroundColor Green
Write-Host 'NEXT_ACTION=Fresh normal UI join, then click exactly one WotR territory.' -ForegroundColor Yellow
Write-Host ''

$seen = @{}
$captured = $null
while ((Get-Date) -lt $deadline -and $null -eq $captured) {
    $files = @(Get-ChildItem -LiteralPath $WerTemp -Filter '*.tmp.dmp' -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.LastWriteTime -ge $start -and (
                -not $baseline.ContainsKey($_.FullName.ToLowerInvariant()) -or
                $_.LastWriteTimeUtc -gt $baseline[$_.FullName.ToLowerInvariant()]
            )
        } |
        Sort-Object LastWriteTime)

    foreach ($f in $files) {
        $key = $f.FullName.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        Write-Host ('WER_DUMP_APPEARED={0}' -f $f.FullName) -ForegroundColor Cyan

        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
        $dest = Join-Path $OutDir ("game.dat_WER_$stamp.dmp")
        $success = $false
        for ($i=1; $i -le 200 -and -not $success; $i++) {
            try {
                if (-not (Test-Path -LiteralPath $f.FullName -PathType Leaf)) { break }
                Copy-Item -LiteralPath $f.FullName -Destination $dest -Force -ErrorAction Stop
                $d = Get-Item -LiteralPath $dest -ErrorAction Stop
                if ($d.Length -gt 0) {
                    $success = $true
                    $captured = $d
                    break
                }
            }
            catch {
                Start-Sleep -Milliseconds 25
            }
        }

        if (-not $success) {
            Write-Host ('COPY_FAILED_OR_SOURCE_GONE={0}' -f $f.FullName) -ForegroundColor Yellow
        }
        if ($success) { break }
    }

    if ($null -eq $captured) { Start-Sleep -Milliseconds 25 }
}

if ($null -eq $captured) {
    Write-Host 'LIVE_WER_DUMP_CAPTURED=NO'
    Write-Host 'LIVE_WER_DUMP_TIMEOUT=YES'
    exit 2
}

$captured.Refresh()
$sha = (Get-FileHash -LiteralPath $captured.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
Write-Host ''
Write-Host 'LIVE_WER_DUMP_CAPTURED=YES' -ForegroundColor Green
Write-Host ('SAVED_PATH={0}' -f $captured.FullName)
Write-Host ('SAVED_SIZE={0}' -f $captured.Length)
Write-Host ('SAVED_SHA256={0}' -f $sha)
Write-Host ('SAVED_TIME={0:O}' -f $captured.LastWriteTime)
Write-Host 'CAPTURE_COMPLETE=YES' -ForegroundColor Green
