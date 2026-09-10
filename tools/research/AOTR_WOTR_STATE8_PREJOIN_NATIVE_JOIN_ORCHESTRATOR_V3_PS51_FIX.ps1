param(
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [string]$ExpectedRemoteIp = '192.168.0.224',
    [int]$ExpectedRemotePort = 8086,
    [int]$ObserveSeconds = 8,
    [int]$WatcherTimeoutSeconds = 45,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# PS5.1 parser-fix bootstrap for V2 only.
# V2 was correctly blocked before execution because three interpolated strings used
# "$Stage:" instead of "${Stage}:". PowerShell parses $Stage: as a drive-qualified
# variable reference. This wrapper downloads the exact pinned V2 commit, performs only
# that parser-safe textual substitution, validates the corrected file with the local
# PowerShell parser, checks the mutation contract markers, then invokes it in-process.
# No game process is opened or modified by this wrapper before the corrected V2 parser
# and static contract gates pass.

$PinnedV2Ref  = 'f138807b0b2eeed313a18b917465c8cd1f894210'
$PinnedV2Name = 'AOTR_WOTR_STATE8_PREJOIN_NATIVE_JOIN_ORCHESTRATOR_V2.ps1'
$RawUrl       = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$PinnedV2Ref/tools/research/$PinnedV2Name"

if ([Environment]::Is64BitProcess) {
    throw 'Run under 32-bit Windows PowerShell: C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
}

New-Item -ItemType Directory -Path $ResearchRoot -Force | Out-Null
$temp = Join-Path $env:TEMP ('AOTR_STATE8_PREJOIN_V2_PS51FIX_' + [guid]::NewGuid().ToString('N') + '.ps1')

try {
    Write-Host '============================================================'
    Write-Host ' AOTR STATE8 PREJOIN V3 - PS5.1 PARSER FIX BOOTSTRAP'
    Write-Host '============================================================'
    Write-Host ("Pinned V2 ref : {0}" -f $PinnedV2Ref)
    Write-Host 'Fix contract  : replace exactly three literal $Stage: tokens with ${Stage}:'
    Write-Host ''

    $src = [string](Invoke-WebRequest -UseBasicParsing -Uri $RawUrl).Content
    if ([string]::IsNullOrWhiteSpace($src) -or $src.Length -lt 5000) {
        throw "Pinned V2 download looks invalid. Length=$($src.Length)"
    }

    $beforeCount = ([regex]::Matches($src, [regex]::Escape('$Stage:'))).Count
    if ($beforeCount -ne 3) {
        throw "PINNED_V2_SOURCE_CONTRACT_FAILED: expected exactly 3 literal `$Stage: tokens, found $beforeCount. Nothing executed."
    }

    $fixed = $src.Replace('$Stage:', '${Stage}:')
    $afterBadCount = ([regex]::Matches($fixed, [regex]::Escape('$Stage:'))).Count
    $afterGoodCount = ([regex]::Matches($fixed, [regex]::Escape('${Stage}:'))).Count
    if ($afterBadCount -ne 0 -or $afterGoodCount -ne 3) {
        throw "PARSER_FIX_CONTRACT_FAILED: bad=$afterBadCount good=$afterGoodCount. Nothing executed."
    }

    Set-Content -LiteralPath $temp -Value $fixed -Encoding UTF8

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($temp, [ref]$tokens, [ref]$parseErrors)
    if ($null -ne $parseErrors -and $parseErrors.Count -gt 0) {
        $details = ($parseErrors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join "`n"
        throw "CORRECTED_V2_PARSER_FAILED - NOTHING EXECUTED.`n$details"
    }
    Write-Host 'CORRECTED_V2_PARSER_PASS' -ForegroundColor Green

    # Static one-variable mutation contract checks before invoking corrected V2.
    $required = @(
        'Write32 $StateAddr ([uint32]8)',
        'SAFE_FAILURE_RESTORE_VERIFIED 8->1',
        'CLEAN_DETACH=YES',
        'DE892C_EQUALS_CURRENT'
    )
    foreach ($marker in $required) {
        if (-not $fixed.Contains($marker)) {
            throw "CORRECTED_V2_STATIC_CONTRACT_FAILED: missing marker [$marker]. Nothing executed."
        }
    }
    foreach ($forbidden in @(
        'Write32 $NetworkGlobal',
        'Write32 $SessionGlobal',
        'Write32 $OwnerGlobal'
    )) {
        if ($fixed.Contains($forbidden)) {
            throw "CORRECTED_V2_STATIC_CONTRACT_FAILED: forbidden write marker [$forbidden]. Nothing executed."
        }
    }
    Write-Host 'CORRECTED_V2_STATIC_CONTRACT_PASS' -ForegroundColor Green
    Write-Host 'Invoking corrected V2 in this same 32-bit PowerShell process...'
    Write-Host ''

    $invoke = @{
        GameDat               = [string]$GameDat
        ExpectedRemoteIp      = [string]$ExpectedRemoteIp
        ExpectedRemotePort    = [int]$ExpectedRemotePort
        ObserveSeconds        = [int]$ObserveSeconds
        WatcherTimeoutSeconds = [int]$WatcherTimeoutSeconds
        ResearchRoot          = [string]$ResearchRoot
    }
    & $temp @invoke
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
