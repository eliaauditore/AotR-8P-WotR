param(
    [string]$CombinedResult = '',
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [int]$ObserveMilliseconds = 2000,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$V2Ref  = '1337b4462599faf79ef2bfb12905b07e7226c8b0'
$V2Name = 'AOTR_WOTR_STATE8_GATE_SUFFICIENCY_ORCHESTRATOR_V2.ps1'

New-Item -ItemType Directory -Path $ResearchRoot -Force | Out-Null

if ([string]::IsNullOrWhiteSpace($CombinedResult)) {
    $latest = Get-ChildItem (Join-Path $ResearchRoot 'LOWLEVEL_JOIN_COMPLETION_COMBINED_*.txt') -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) { throw 'No LOWLEVEL_JOIN_COMPLETION_COMBINED_*.txt result found.' }
    $CombinedResult = $latest.FullName
}
if (-not (Test-Path -LiteralPath $CombinedResult -PathType Leaf)) {
    throw "Combined result not found: $CombinedResult"
}

$lines = @(Get-Content -LiteralPath $CombinedResult)
$raw = [string]::Join("`r`n", $lines)

$required = @('TEST_VALID_FOR_STATE8','WATCHER_CLEAN_EXIT','JOIN_STATE_OBSERVED','CURRENT_C54B78','DE892C_STAYED_NULL')
foreach ($name in $required) {
    if ($raw -notmatch ('(?m)^' + [regex]::Escape($name) + '\s+:\s+YES\s*$')) {
        throw "Source log is not marked $name=YES. No state write was attempted."
    }
}

$pidMatches = [regex]::Matches($raw, '(?m)^Game PID\s+:\s+(\d+)\s*$')
if ($pidMatches.Count -ne 1) {
    throw "Expected exactly one Game PID line, found $($pidMatches.Count). No state write was attempted."
}
$gamePid = [int]$pidMatches[0].Groups[1].Value

$records = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -ne 'CALLBACK_8496C2_HIT=YES') { continue }

    $ownerMatch = $null
    for ($j = $i + 1; $j -le [Math]::Min($i + 8, $lines.Count - 1); $j++) {
        $m = [regex]::Match($lines[$j].Trim(), '^ECX_OWNER=(0x[0-9A-Fa-f]{8}) OWNER_6A4=(\d+) OWNER_304=(\d+) CURRENT_IS_C54B78=(YES|NO)$')
        if ($m.Success) {
            $ownerMatch = $m
            break
        }
    }
    if ($null -eq $ownerMatch) { continue }

    $records.Add([pscustomobject]@{
        Owner      = $ownerMatch.Groups[1].Value.ToUpperInvariant()
        Owner6A4   = [int]$ownerMatch.Groups[2].Value
        Owner304   = [int]$ownerMatch.Groups[3].Value
        CurrentC54 = $ownerMatch.Groups[4].Value
        OwnerLine  = $ownerMatch.Value
    })
}

if ($records.Count -le 0) {
    throw 'No callback-bound owner records were parsed. No state write was attempted.'
}

$owners = @($records | ForEach-Object { $_.Owner } | Select-Object -Unique)
if ($owners.Count -ne 1) {
    throw "Callback blocks contain multiple distinct owners: $($owners -join ', '). No state write was attempted."
}
if ($owners[0] -eq '0X00000000') {
    throw 'Callback-bound owner resolved to NULL. No state write was attempted.'
}

$bad = @($records | Where-Object { $_.Owner6A4 -ne 1 -or $_.Owner304 -ne 1 -or $_.CurrentC54 -ne 'YES' })
if ($bad.Count -ne 0) {
    throw "Callback-bound source contract is not uniform: $($bad.Count) records differ from 6A4=1 / 304=1 / Current=C54. No state write was attempted."
}

Write-Host '============================================================'
Write-Host ' AOTR WOTR STATE8 SUFFICIENCY SOURCE FILTER V3'
Write-Host '============================================================'
Write-Host ("Source             : {0}" -f $CombinedResult)
Write-Host ("Game PID           : {0}" -f $gamePid)
Write-Host ("Callback records   : {0}" -f $records.Count)
Write-Host ("Frontend owner     : {0}" -f $owners[0])
Write-Host 'Callback contract  : ALL 6A4=1 / 304=1 / Current=C54'
Write-Host 'CALLBACK_SOURCE_FILTER_PASS' -ForegroundColor Green

# Build a minimal source file containing only the validated verdict markers,
# the one game PID, and callback-bound owner records. This prevents unrelated
# ECX_OWNER snapshots elsewhere in the combined watcher output from entering V2.
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$filtered = Join-Path $ResearchRoot "STATE8_SUFF_FILTERED_SOURCE_$stamp.txt"
$out = New-Object System.Collections.Generic.List[string]
$out.Add('TEST_VALID_FOR_STATE8     : YES')
$out.Add('WATCHER_CLEAN_EXIT        : YES')
$out.Add('JOIN_STATE_OBSERVED       : YES')
$out.Add('CURRENT_C54B78            : YES')
$out.Add('DE892C_STAYED_NULL        : YES')
$out.Add(("Game PID                 : {0}" -f $gamePid))
foreach ($r in $records) { $out.Add($r.OwnerLine) }
$out | Set-Content -LiteralPath $filtered -Encoding UTF8

# Self-check the exact filtered file against the parser contract expected by V2.
$filteredRaw = Get-Content -LiteralPath $filtered -Raw
$filteredOwners = [regex]::Matches($filteredRaw, '(?m)^ECX_OWNER=(0x[0-9A-Fa-f]{8}) OWNER_6A4=(\d+) OWNER_304=(\d+) CURRENT_IS_C54B78=(YES|NO)\s*$')
$filteredUniqueOwners = @($filteredOwners | ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() } | Select-Object -Unique)
if ($filteredOwners.Count -ne $records.Count -or $filteredUniqueOwners.Count -ne 1 -or $filteredUniqueOwners[0] -ne $owners[0]) {
    throw 'FILTERED_SOURCE_SELFTEST_FAILED. No state write was attempted.'
}
$filteredBad = @($filteredOwners | Where-Object { $_.Groups[2].Value -ne '1' -or $_.Groups[3].Value -ne '1' -or $_.Groups[4].Value -ne 'YES' })
if ($filteredBad.Count -ne 0) {
    throw 'FILTERED_SOURCE_SELFTEST_BAD_RECORD. No state write was attempted.'
}
Write-Host ("FILTERED_SOURCE_SELFTEST_PASS records={0} owner={1}" -f $filteredOwners.Count,$filteredUniqueOwners[0]) -ForegroundColor Green

$v2Path = Join-Path $ResearchRoot $V2Name
$v2Url = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$V2Ref/tools/research/$V2Name"
Invoke-WebRequest -UseBasicParsing -Uri $v2Url -OutFile $v2Path
if ((Get-Item -LiteralPath $v2Path).Length -lt 1000) {
    throw 'Downloaded V2 orchestrator looks invalid. No state write was attempted.'
}
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($v2Path,[ref]$tokens,[ref]$parseErrors)
if ($null -ne $parseErrors -and $parseErrors.Count -gt 0) {
    $text = ($parseErrors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join "`n"
    throw "V2 syntax validation failed. No state write was attempted.`n$text"
}
Write-Host 'PINNED_V2_SYNTAX_PASS' -ForegroundColor Green
Write-Host ''

# Invoke the already-reviewed V2 in-process with the sanitized source log.
& $v2Path `
    -CombinedResult $filtered `
    -GameDat $GameDat `
    -ObserveMilliseconds $ObserveMilliseconds `
    -ResearchRoot $ResearchRoot
