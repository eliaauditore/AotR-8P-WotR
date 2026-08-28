param(
    [string]$RepoRef,
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [string]$ExpectedRemoteIp = '192.168.0.224',
    [int]$ExpectedRemotePort = 8086,
    [int]$ObserveSeconds = 8,
    [int]$WatcherTimeoutSeconds = 30,
    [int]$WaitForGameSeconds = 120,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRef)) {
    throw 'Pass -RepoRef with the exact Git commit SHA.'
}

# V4.1 deliberately patches only the three proven false-negative ExitCode gates
# in V4, validates that exact source contract, parses the patched script, and then
# invokes the patched script directly in the SAME PowerShell process with NAMED
# splatting. No native powershell.exe argument boundary is used here.

$sourceUrl = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $RepoRef + '/tools/research/AOTR_WOTR_LOWLEVEL_JOIN_COMPLETION_ORCHESTRATOR_V4.ps1'
$temp = Join-Path $env:TEMP ('AOTR_WOTR_ORCH_V4_1_' + [guid]::NewGuid().ToString('N') + '.ps1')

try {
    Invoke-WebRequest -UseBasicParsing -Uri $sourceUrl -OutFile $temp
    if (-not (Test-Path -LiteralPath $temp)) {
        throw 'V4.1 failed to download V4 source.'
    }

    $src = Get-Content -LiteralPath $temp -Raw
    if ([string]::IsNullOrWhiteSpace($src)) {
        throw 'V4.1 downloaded an empty V4 source.'
    }

    $old1 = '$selfProc.ExitCode -ne 0 -or '
    $old2 = '$preProc.ExitCode -ne 0 -or '
    $old3 = '($statusText -match ''STAGE=DONE'') -and ($watchProc.ExitCode -eq 0)'
    $new3 = '($statusText -match ''STAGE=DONE'')'

    foreach ($required in @($old1,$old2,$old3)) {
        if (-not $src.Contains($required)) {
            throw "V4.1 source contract mismatch; required token not found: $required"
        }
    }

    # Each token is expected exactly once. Refuse to patch an unexpected source.
    foreach ($required in @($old1,$old2,$old3)) {
        $count = ([regex]::Matches($src,[regex]::Escape($required))).Count
        if ($count -ne 1) {
            throw "V4.1 source contract mismatch; token count for [$required] is $count, expected 1."
        }
    }

    $src = $src.Replace($old1,'')
    $src = $src.Replace($old2,'')
    $src = $src.Replace($old3,$new3)

    if ($src.Contains($old1) -or $src.Contains($old2) -or $src.Contains($old3)) {
        throw 'V4.1 patch verification failed: one or more ExitCode decision gates remain.'
    }

    Set-Content -LiteralPath $temp -Value $src -Encoding UTF8

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($temp,[ref]$tokens,[ref]$parseErrors)
    if ($null -ne $parseErrors -and $parseErrors.Count -gt 0) {
        $text = ($parseErrors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join "`n"
        throw "V4.1 patched orchestrator syntax validation failed:`n$text"
    }

    Write-Host '============================================================'
    Write-Host ' AOTR WOTR ORCHESTRATOR V4.1'
    Write-Host '============================================================'
    Write-Host 'PATCH_CONTRACT_PASS'
    Write-Host 'PATCHED_SCRIPT_SYNTAX_PASS'
    Write-Host 'Removed decision gates: selftest ExitCode, preflight ExitCode, watcher ExitCode.'
    Write-Host 'Success is determined by semantic markers only.'
    Write-Host ''

    $invoke = @{
        RepoRef               = [string]$RepoRef
        GameDat               = [string]$GameDat
        ExpectedRemoteIp      = [string]$ExpectedRemoteIp
        ExpectedRemotePort    = [int]$ExpectedRemotePort
        ObserveSeconds        = [int]$ObserveSeconds
        WatcherTimeoutSeconds = [int]$WatcherTimeoutSeconds
        WaitForGameSeconds    = [int]$WaitForGameSeconds
        ResearchRoot          = [string]$ResearchRoot
    }

    # Direct PowerShell script invocation. Exceptions from V4 propagate naturally.
    & $temp @invoke
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
