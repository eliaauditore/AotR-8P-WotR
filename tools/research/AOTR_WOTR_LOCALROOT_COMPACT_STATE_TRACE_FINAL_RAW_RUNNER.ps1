param(
    [string]$Label = 'NODE',
    [string]$OutputDir = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# FINAL one-pass compact localRoot trace runner.
# Purpose: run the proven compact V3 capture, then write the captured raw 20-byte
# records directly to a .bin file and EXIT before the expensive 3.3M-record
# PowerShell parser. Compatible with Windows PowerShell 5.1 and PowerShell 7.
# No game.dat file on disk is modified. The process hook remains exact-byte
# guarded and is restored before the raw trace is written.

$SourceCommit = '818e1df7d5f3236251aa71effde61e93433ca0e1'
$SourceUri = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/tools/research/AOTR_WOTR_LOCALROOT_COMPACT_STATE_TRACE_V3_RUNNER.ps1"
$temp = Join-Path $env:TEMP ('AOTR_WOTR_LOCALROOT_COMPACT_STATE_TRACE_FINAL_RAW_' + [guid]::NewGuid().ToString('N') + '.ps1')
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

try {
    $fixed = (Invoke-WebRequest -UseBasicParsing -Uri $SourceUri).Content
    if ([string]::IsNullOrWhiteSpace($fixed)) { throw 'Pinned V3 runner download returned empty content.' }

    # 1) Fix V3 tail regex StrictMode interpolation while preserving regex literal '$'.
    $lines = $fixed -split "`r?`n"
    $tailHits = 0
    $tailReplacement = @'
    $tailPattern = '(?s)if \(\$null -eq \$traceBytes\) \{ throw ''No trace buffer was captured\.'' \}.*?Write-Host ''The process hook was restored to the exact original 7 bytes\.'''
'@
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\$tailPattern\s*=\s*"') {
            $lines[$i] = $tailReplacement.TrimEnd("`r","`n")
            $tailHits++
        }
    }
    if ($tailHits -ne 1) { throw "Expected exactly one V3 tailPattern line; found $tailHits." }
    $fixed = $lines -join "`r`n"
    if (-not $fixed.Contains('\$null -eq \$traceBytes')) { throw 'Tail regex literal-dollar verification failed.' }

    # 2) Remove dead C# constant that produces CS0219 under Windows PowerShell 5.1 Add-Type.
    $deadConst = '        const UInt32 REC=20;'
    $deadCount = ([regex]::Matches($fixed,[regex]::Escape($deadConst))).Count
    if ($deadCount -ne 1) { throw "Expected exactly one generated REC constant; found $deadCount." }
    $fixed = $fixed.Replace($deadConst,'')

    # 3) Inject .NET Framework-compatible HexBytes helper replacement at the correct layer:
    #    immediately after V3 downloads the original pinned capture source.
    $sourceGuard = '    if ([string]::IsNullOrWhiteSpace($text)) { throw ''Pinned capture source download returned empty content.'' }'
    $guardCount = ([regex]::Matches($fixed,[regex]::Escape($sourceGuard))).Count
    if ($guardCount -ne 1) { throw "Expected exactly one pinned-source guard; found $guardCount." }
    $hexInjection = @'

    # PS5.1/.NET Framework compatibility: Convert.ToHexString does not exist.
    $hexHelperOld = 'function HexBytes([byte[]]$b) { [Convert]::ToHexString($b) }'
    $hexHelperNew = 'function HexBytes([byte[]]$b) { ([BitConverter]::ToString($b)).Replace(''-'','''') }'
    $hexHelperCount = ([regex]::Matches($text,[regex]::Escape($hexHelperOld))).Count
    if ($hexHelperCount -ne 1) { throw "Expected exactly one pinned HexBytes helper; found $hexHelperCount." }
    $text = $text.Replace($hexHelperOld,$hexHelperNew)
'@
    $fixed = $fixed.Replace($sourceGuard,$sourceGuard + $hexInjection)

    # 4) Replace PS7-only utf8NoBOM writer in V3 with .NET UTF8Encoding(false).
    $innerOld = '    Set-Content -LiteralPath $temp -Value $text -Encoding utf8NoBOM'
    $innerNew = '    [System.IO.File]::WriteAllText($temp,$text,(New-Object System.Text.UTF8Encoding($false)))'
    $innerCount = ([regex]::Matches($fixed,[regex]::Escape($innerOld))).Count
    if ($innerCount -ne 1) { throw "Expected exactly one V3 utf8NoBOM writer; found $innerCount." }
    $fixed = $fixed.Replace($innerOld,$innerNew)

    # 5) Inject an EARLY RAW DUMP into the generated compact-tail. This runs immediately
    #    after traceBytes has already been copied locally and after 'Hook restored : YES'.
    #    It writes the raw fixed-size records, prints a SHA256, frees scratch/handle,
    #    and returns before the millions-of-records PowerShell parser starts.
    $rawAnchor = "if (`$null -eq `$traceBytes) { throw 'No trace buffer was captured.' }"
    $rawAnchorCount = ([regex]::Matches($fixed,[regex]::Escape($rawAnchor))).Count
    if ($rawAnchorCount -ne 1) { throw "Expected exactly one compact tail raw anchor; found $rawAnchorCount." }
    $rawInjection = @'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$safeLabel = ($Label -replace '[^A-Za-z0-9_.-]','_')
$rawBin = Join-Path $OutputDir ("AOTR_WOTR_LOCALROOT_COMPACT_V3_{0}_{1}_RAW.bin" -f $safeLabel,$stamp)
[System.IO.File]::WriteAllBytes($rawBin,$traceBytes)
$rawItem = Get-Item -LiteralPath $rawBin
$rawSha = (Get-FileHash -LiteralPath $rawBin -Algorithm SHA256).Hash.ToUpperInvariant()

Write-Host ''
Write-Host '================ FINAL RAW TRACE SUMMARY ================'
Write-Host ("Label                : {0}" -f $Label)
Write-Host ("localRoot            : 0x{0:X8}" -f $root)
Write-Host ("localRoot vtable     : 0x{0:X8}" -f $rootVT)
Write-Host ("Captured calls       : {0}" -f $callCount)
Write-Host ("Captured bytes       : {0}" -f $writeOff)
Write-Host ("Overflow             : {0}" -f $overflow)
Write-Host ("RAW BIN              : {0}" -f $rawBin)
Write-Host ("RAW BIN bytes        : {0}" -f $rawItem.Length)
Write-Host ("RAW BIN SHA256       : {0}" -f $rawSha)
Write-Host ("FINAL_RAW_KEY        : LABEL={0};ROOTVT={1:X8};CALLS={2};BYTES={3};OVERFLOW={4};SHA256={5}" -f $Label,$rootVT,$callCount,$writeOff,$overflow,$rawSha)

if ($remote -ne [IntPtr]::Zero -and $h -ne [IntPtr]::Zero) {
    try { [A8PInputTraceNativeV3]::Free($h,$remote) } catch { Write-Warning $_.Exception.Message }
    $remote = [IntPtr]::Zero
}
if ($h -ne [IntPtr]::Zero) {
    [A8PInputTraceNativeV3]::Close($h)
    $h = [IntPtr]::Zero
}

Write-Host 'FINAL_RAW_CAPTURE_COMPLETE=YES'
Write-Host 'game.dat on disk was never modified; hook was restored before raw dump.'
return
'@
    $fixed = $fixed.Replace($rawAnchor,$rawAnchor + $rawInjection)

    # 6) Remove unnecessary LASTEXITCODE dependency. Terminating PowerShell errors propagate through &.
    $lastExitLine = '    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }'
    if ($fixed.Contains($lastExitLine)) { $fixed = $fixed.Replace($lastExitLine,'') }

    # Final generator-level guards for known blockers.
    if ($fixed.Contains('-Encoding utf8NoBOM')) { throw 'utf8NoBOM blocker survived final materialization.' }
    if ($fixed.Contains('const UInt32 REC=20;')) { throw 'Dead REC constant survived final materialization.' }
    if (-not $fixed.Contains('FINAL_RAW_CAPTURE_COMPLETE=YES')) { throw 'Early raw-dump injection verification failed.' }

    [System.IO.File]::WriteAllText($temp,$fixed,$Utf8NoBom)
    Write-Host 'FINAL RAW source fix : PID/regex/C#/UTF8/PS5.1 compatibility materialized'
    Write-Host 'FINAL RAW behavior   : raw .bin written immediately after hook restore; parser bypassed'
    & $temp -Label $Label -OutputDir $OutputDir
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
