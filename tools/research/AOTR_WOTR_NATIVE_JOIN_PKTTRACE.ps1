param(
    [ValidateSet('Start','Stop')]
    [string]$Mode,
    [ValidateSet('HOST','VM')]
    [string]$Label,
    [string]$OutDir = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# NETWORK-ONLY TRACE HELPER.
# Uses the built-in Windows pktmon utility. Does not read or write game memory.
# Captures UDP traffic on native AotR session ports 8086..8093.

function Require-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this PowerShell as Administrator.'
    }
}

Require-Admin
if (-not (Get-Command pktmon.exe -ErrorAction SilentlyContinue)) {
    throw 'pktmon.exe was not found on this Windows installation.'
}
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$stateFile = Join-Path $OutDir ("AOTR_JOIN_PKTTRACE_{0}.state.txt" -f $Label)
$etl = Join-Path $OutDir ("AOTR_JOIN_PKTTRACE_{0}.etl" -f $Label)
$txt = Join-Path $OutDir ("AOTR_JOIN_PKTTRACE_{0}.txt" -f $Label)

if ($Mode -eq 'Start') {
    # Clean up only pktmon state from an earlier run.
    & pktmon stop 2>$null | Out-Null
    & pktmon filter remove 2>$null | Out-Null

    foreach ($port in 8086..8093) {
        $name = "AOTR_$port"
        & pktmon filter add $name -t UDP -p $port | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "pktmon filter add failed for UDP port $port" }
    }

    Remove-Item -LiteralPath $etl,$txt,$stateFile -Force -ErrorAction SilentlyContinue
    & pktmon start --capture --comp nics --pkt-size 0 --file-name $etl --file-size 64 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'pktmon start failed.' }

    @(
        "Label=$Label"
        "ETL=$etl"
        "TXT=$txt"
        "StartedUtc=$([DateTime]::UtcNow.ToString('o'))"
    ) | Set-Content -LiteralPath $stateFile -Encoding ASCII

    Write-Host '============================================================'
    Write-Host ' AOTR WOTR NATIVE JOIN PACKET TRACE'
    Write-Host '============================================================'
    Write-Host ("Label        : {0}" -f $Label)
    Write-Host 'Mode         : START'
    Write-Host 'Filter       : UDP ports 8086..8093'
    Write-Host ("ETL          : {0}" -f $etl)
    Write-Host ''
    Write-Host 'TRACE ARMED.' -ForegroundColor Green
    Write-Host 'Reproduce exactly ONE client native +0x40 call, then run this script again with -Mode Stop on BOTH machines.'
    exit 0
}

& pktmon stop | Out-Null
if (-not (Test-Path -LiteralPath $etl)) {
    throw "Expected ETL not found: $etl"
}
& pktmon etl2txt $etl --out $txt --brief --hex | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'pktmon etl2txt failed.' }
& pktmon filter remove 2>$null | Out-Null

Write-Host '============================================================'
Write-Host ' AOTR WOTR NATIVE JOIN PACKET TRACE'
Write-Host '============================================================'
Write-Host ("Label        : {0}" -f $Label)
Write-Host 'Mode         : STOP'
Write-Host ("ETL          : {0}" -f $etl)
Write-Host ("TXT          : {0}" -f $txt)
Write-Host ''

$lines = @(Get-Content -LiteralPath $txt -ErrorAction Stop)
$interesting = @($lines | Where-Object {
    $_ -match '8086|8087|8088|8089|8090|8091|8092|8093|192\.168\.0\.57|192\.168\.0\.224|255\.255\.255\.255'
})

Write-Host ("Interesting text lines : {0}" -f $interesting.Count)
if ($interesting.Count -gt 0) {
    Write-Host '--- compact trace excerpt ---'
    $interesting | Select-Object -First 120 | ForEach-Object { Write-Host $_ }
    if ($interesting.Count -gt 120) { Write-Host '<excerpt truncated; inspect TXT file for full trace>' }
} else {
    Write-Host '<no matching decoded lines>'
}

Write-Host ''
Write-Host 'NETWORK TRACE COMPLETE. No game memory was modified.'
