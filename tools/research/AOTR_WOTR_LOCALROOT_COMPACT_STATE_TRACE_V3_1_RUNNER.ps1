param(
    [string]$Label = 'NODE',
    [string]$OutputDir = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# V3.3 compatibility fix, kept in the V3_1 runner path for continuity.
# V3 originally stored tailPattern in a double-quoted PowerShell string, so
# $null/$traceBytes were interpolated under Set-StrictMode. V3.1 prevented
# interpolation but accidentally removed the regex-level backslash before '$'.
# V3.2 corrected both escape layers. V3.3 additionally removes one dead C#
# constant (REC=20) from the generated source because Add-Type on the tested
# PowerShell treats compiler warning CS0219 as a terminating compilation error.
# No game.dat file is modified by this wrapper.

$SourceCommit = '818e1df7d5f3236251aa71effde61e93433ca0e1'
$SourceUri = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/tools/research/AOTR_WOTR_LOCALROOT_COMPACT_STATE_TRACE_V3_RUNNER.ps1"
$temp = Join-Path $env:TEMP ('AOTR_WOTR_LOCALROOT_COMPACT_STATE_TRACE_V3_3_' + [guid]::NewGuid().ToString('N') + '.ps1')

try {
    $text = (Invoke-WebRequest -UseBasicParsing -Uri $SourceUri).Content
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'Pinned V3 runner download returned empty content.' }

    $lines = $text -split "`r?`n"
    $hits = 0
    $replacement = @'
    $tailPattern = '(?s)if \(\$null -eq \$traceBytes\) \{ throw ''No trace buffer was captured\.'' \}.*?Write-Host ''The process hook was restored to the exact original 7 bytes\.'''
'@

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\$tailPattern\s*=\s*"') {
            $lines[$i] = $replacement.TrimEnd("`r","`n")
            $hits++
        }
    }

    if ($hits -ne 1) { throw "Expected exactly one tailPattern line in pinned V3; found $hits." }
    $fixed = $lines -join "`r`n"

    # Guard both layers: generated source must retain regex escapes before '$'.
    if (-not $fixed.Contains('\$null -eq \$traceBytes')) {
        throw 'V3.3 tailPattern regex-dollar escape verification failed.'
    }

    # Remove the unused generated C# constant that causes CS0219 under Add-Type.
    $deadConst = '        const UInt32 REC=20;'
    $deadConstCount = ([regex]::Matches($fixed,[regex]::Escape($deadConst))).Count
    if ($deadConstCount -ne 1) {
        throw "Expected exactly one generated REC constant; found $deadConstCount."
    }
    $fixed = $fixed.Replace($deadConst,'')
    if ($fixed.Contains($deadConst)) { throw 'V3.3 REC constant removal verification failed.' }

    Set-Content -LiteralPath $temp -Value $fixed -Encoding utf8NoBOM
    Write-Host 'V3.3 source fix      : regex escapes OK; unused C# REC constant removed'
    & $temp -Label $Label -OutputDir $OutputDir
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
