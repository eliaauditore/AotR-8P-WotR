param(
    [string]$Label = 'NODE',
    [string]$OutputDir = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# V3.5 compatibility fix, kept in the V3_1 runner path for continuity.
# V3 originally stored tailPattern in a double-quoted PowerShell string, so
# $null/$traceBytes were interpolated under Set-StrictMode. V3.1 prevented
# interpolation but accidentally removed the regex-level backslash before '$'.
# V3.2 corrected both escape layers. V3.3 removed the dead generated C# REC=20
# constant because Add-Type treated CS0219 as a terminating compilation error.
# V3.4 removed PowerShell-7-only Set-Content -Encoding utf8NoBOM from both layers.
# V3.5 additionally replaces .NET-5+ Convert.ToHexString usage with the
# .NET-Framework-compatible BitConverter form required by Windows PowerShell 5.1.
# No game.dat file is modified by this wrapper.

$SourceCommit = '818e1df7d5f3236251aa71effde61e93433ca0e1'
$SourceUri = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/tools/research/AOTR_WOTR_LOCALROOT_COMPACT_STATE_TRACE_V3_RUNNER.ps1"
$temp = Join-Path $env:TEMP ('AOTR_WOTR_LOCALROOT_COMPACT_STATE_TRACE_V3_5_' + [guid]::NewGuid().ToString('N') + '.ps1')
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

    if (-not $fixed.Contains('\$null -eq \$traceBytes')) {
        throw 'V3.5 tailPattern regex-dollar escape verification failed.'
    }

    $deadConst = '        const UInt32 REC=20;'
    $deadConstCount = ([regex]::Matches($fixed,[regex]::Escape($deadConst))).Count
    if ($deadConstCount -ne 1) {
        throw "Expected exactly one generated REC constant; found $deadConstCount."
    }
    $fixed = $fixed.Replace($deadConst,'')
    if ($fixed.Contains($deadConst)) { throw 'V3.5 REC constant removal verification failed.' }

    # Windows PowerShell 5.1 runs on .NET Framework, which has no
    # System.Convert.ToHexString(). Replace the exact pre-hook helper used by
    # the generated capture. Also replace the two legacy tail occurrences so
    # no ToHexString call can survive the transform if tail layout changes.
    $hexHelperOld = 'function HexBytes([byte[]]$b) { [Convert]::ToHexString($b) }'
    $hexHelperNew = 'function HexBytes([byte[]]$b) { ([BitConverter]::ToString($b)).Replace(''-'','''') }'
    $hexHelperCount = ([regex]::Matches($fixed,[regex]::Escape($hexHelperOld))).Count
    if ($hexHelperCount -ne 1) {
        throw "Expected exactly one HexBytes ToHexString helper; found $hexHelperCount."
    }
    $fixed = $fixed.Replace($hexHelperOld,$hexHelperNew)
    $fixed = $fixed.Replace('$ph = [Convert]::ToHexString($sha.ComputeHash($payload))', '$ph = ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace(''-'','''')')
    $fixed = $fixed.Replace('$px = [Convert]::ToHexString($payload)', '$px = ([BitConverter]::ToString($payload)).Replace(''-'','''')')
    if ($fixed.Contains('[Convert]::ToHexString')) {
        throw 'V3.5 Convert.ToHexString replacement verification failed.'
    }

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
        throw 'V3.5 inner utf8NoBOM replacement verification failed.'
    }

    [System.IO.File]::WriteAllText($temp,$fixed,$Utf8NoBom)
    Write-Host 'V3.5 source fix      : regex/C#/UTF8 fixes OK; PS5.1 ToHexString compatibility ON'
    & $temp -Label $Label -OutputDir $OutputDir
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
