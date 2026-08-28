param(
    [string]$Label = 'NODE',
    [string]$OutputDir = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# V3.1 compatibility runner.
# V3's transform regex was stored in a double-quoted PowerShell string and
# therefore attempted to expand $traceBytes under Set-StrictMode before the
# generated capture script existed. This wrapper pins V3, escapes only those
# two dollar signs in the regex source line, then executes the corrected
# temporary runner. No game.dat file is modified here.

$SourceCommit = '818e1df7d5f3236251aa71effde61e93433ca0e1'
$SourceUri = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/tools/research/AOTR_WOTR_LOCALROOT_COMPACT_STATE_TRACE_V3_RUNNER.ps1"
$temp = Join-Path $env:TEMP ('AOTR_WOTR_LOCALROOT_COMPACT_STATE_TRACE_V3_1_' + [guid]::NewGuid().ToString('N') + '.ps1')

try {
    $text = (Invoke-WebRequest -UseBasicParsing -Uri $SourceUri).Content
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'Pinned V3 runner download returned empty content.' }

    $lines = $text -split "`r?`n"
    $hits = 0
    $replacement = @'
    $tailPattern = "(?s)if \(`$null -eq `$traceBytes\) \{ throw 'No trace buffer was captured\.' \}.*?Write-Host 'The process hook was restored to the exact original 7 bytes\.'"
'@

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\$tailPattern\s*=\s*"') {
            $lines[$i] = $replacement.TrimEnd("`r","`n")
            $hits++
        }
    }

    if ($hits -ne 1) { throw "Expected exactly one tailPattern line in pinned V3; found $hits." }
    $fixed = $lines -join "`r`n"

    # Guard: the corrected source must contain escaped literal variable names.
    if (-not $fixed.Contains('`$null -eq `$traceBytes')) {
        throw 'V3.1 tailPattern escape verification failed.'
    }

    Set-Content -LiteralPath $temp -Value $fixed -Encoding utf8NoBOM
    Write-Host 'V3.1 source fix      : tailPattern variable interpolation disabled'
    & $temp -Label $Label -OutputDir $OutputDir
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
