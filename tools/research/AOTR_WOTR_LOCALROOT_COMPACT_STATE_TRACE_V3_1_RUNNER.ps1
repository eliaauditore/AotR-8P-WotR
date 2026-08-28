param(
    [string]$Label = 'NODE',
    [string]$OutputDir = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# V3.4 compatibility fix, kept in the V3_1 runner path for continuity.
# V3 originally stored tailPattern in a double-quoted PowerShell string, so
# $null/$traceBytes were interpolated under Set-StrictMode. V3.1 prevented
# interpolation but accidentally removed the regex-level backslash before '$'.
# V3.2 corrected both escape layers. V3.3 removed the dead generated C# REC=20
# constant because Add-Type treated CS0219 as a terminating compilation error.
# V3.4 additionally removes PowerShell-7-only Set-Content -Encoding utf8NoBOM
# from BOTH layers (this wrapper and the generated V3 script), using .NET's
# UTF8Encoding(false) instead. This works on Windows PowerShell 5.1 and PS7.
# No game.dat file is modified by this wrapper.

$SourceCommit = '818e1df7d5f3236251aa71effde61e93433ca0e1'
$SourceUri = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/tools/research/AOTR_WOTR_LOCALROOT_COMPACT_STATE_TRACE_V3_RUNNER.ps1"
$temp = Join-Path $env:TEMP ('AOTR_WOTR_LOCALROOT_COMPACT_STATE_TRACE_V3_4_' + [guid]::NewGuid().ToString('N') + '.ps1')
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

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
        throw 'V3.4 tailPattern regex-dollar escape verification failed.'
    }

    # Remove the unused generated C# constant that causes CS0219 under Add-Type.
    $deadConst = '        const UInt32 REC=20;'
    $deadConstCount = ([regex]::Matches($fixed,[regex]::Escape($deadConst))).Count
    if ($deadConstCount -ne 1) {
        throw "Expected exactly one generated REC constant; found $deadConstCount."
    }
    $fixed = $fixed.Replace($deadConst,'')
    if ($fixed.Contains($deadConst)) { throw 'V3.4 REC constant removal verification failed.' }

    # Windows PowerShell 5.1 does not support -Encoding utf8NoBOM. Patch the
    # inner generated V3 writer to a .NET call that behaves identically on PS5.1/PS7.
    $innerOld = '    Set-Content -LiteralPath $temp -Value $text -Encoding utf8NoBOM'
    $innerNew = '    [System.IO.File]::WriteAllText($temp,$text,(New-Object System.Text.UTF8Encoding($false)))'
    $innerCount = ([regex]::Matches($fixed,[regex]::Escape($innerOld))).Count
    if ($innerCount -ne 1) {
        throw "Expected exactly one inner utf8NoBOM writer; found $innerCount."
    }
    $fixed = $fixed.Replace($innerOld,$innerNew)
    if ($fixed.Contains('-Encoding utf8NoBOM')) {
        throw 'V3.4 inner utf8NoBOM replacement verification failed.'
    }

    # Outer temporary file writer: also PS5.1/PS7 compatible UTF-8 without BOM.
    [System.IO.File]::WriteAllText($temp,$fixed,$Utf8NoBom)
    Write-Host 'V3.4 source fix      : regex/C# fixes OK; PS5.1 UTF8-no-BOM compatibility ON'
    & $temp -Label $Label -OutputDir $OutputDir
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
