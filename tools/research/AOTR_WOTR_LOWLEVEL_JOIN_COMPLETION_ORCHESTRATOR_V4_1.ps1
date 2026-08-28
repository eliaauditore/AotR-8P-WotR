param(
    [string]$RepoRef,
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [string]$ExpectedRemoteIp = '192.168.0.224',
    [int]$ExpectedRemotePort = 8086,
    [int]$ObserveSeconds = 8,
    [int]$WatcherTimeoutSeconds = 60,
    [int]$WaitForGameSeconds = 120,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRef)) {
    throw 'Pass -RepoRef with the exact Git commit SHA.'
}
if ($WatcherTimeoutSeconds -lt 20 -or $WatcherTimeoutSeconds -gt 120) {
    throw 'WatcherTimeoutSeconds must be 20..120.'
}

# V4.1 patches only the already-proven V4 ExitCode problem class.
# It validates exact token counts, parses the patched result, and invokes it directly
# as a PowerShell script in this same process with NAMED splatting.

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

    $replacements = @(
        [pscustomobject]@{ Old='$selfProc.ExitCode -ne 0 -or '; New='' },
        [pscustomobject]@{ Old='$preProc.ExitCode -ne 0 -or '; New='' },
        [pscustomobject]@{ Old='($statusText -match ''STAGE=DONE'') -and ($watchProc.ExitCode -eq 0)'; New='($statusText -match ''STAGE=DONE'')' },
        [pscustomobject]@{ Old='Write-Host ("JOIN_EXIT_CODE={0}" -f $joinProc.ExitCode)'; New='Write-Host ''JOIN_PROCESS_EXITED=YES''' },
        [pscustomobject]@{ Old='Write-Host ("WATCHER_EXIT_CODE={0}" -f $watchProc.ExitCode)'; New='Write-Host ''WATCHER_PROCESS_EXITED=YES''' }
    )

    foreach ($r in $replacements) {
        $count = ([regex]::Matches($src,[regex]::Escape([string]$r.Old))).Count
        if ($count -ne 1) {
            throw "V4.1 source contract mismatch; token count for [$($r.Old)] is $count, expected 1."
        }
    }

    foreach ($r in $replacements) {
        $src = $src.Replace([string]$r.Old,[string]$r.New)
    }

    foreach ($r in $replacements) {
        if ($src.Contains([string]$r.Old)) {
            throw "V4.1 patch verification failed; token remains: $($r.Old)"
        }
    }

    if ($src -match '\.ExitCode') {
        throw 'V4.1 patch verification failed: an ExitCode reference still remains.'
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
    Write-Host 'NO_EXITCODE_REFERENCES_PASS'
    Write-Host 'PATCHED_SCRIPT_SYNTAX_PASS'
    Write-Host 'Success decisions use semantic markers only.'
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

    & $temp @invoke
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
