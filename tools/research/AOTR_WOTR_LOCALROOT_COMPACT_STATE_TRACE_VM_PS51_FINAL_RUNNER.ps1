param(
    [string]$Label = 'VM',
    [string]$OutputDir = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Consolidated Windows PowerShell 5.1 compatibility runner for the V3 compact trace.
# It materializes one corrected temporary V3 runner before execution.
# No game.dat file is modified by this wrapper.

$SourceCommit = '818e1df7d5f3236251aa71effde61e93433ca0e1'
$SourceUri = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/tools/research/AOTR_WOTR_LOCALROOT_COMPACT_STATE_TRACE_V3_RUNNER.ps1"
$temp = Join-Path $env:TEMP ('AOTR_WOTR_LOCALROOT_COMPACT_STATE_TRACE_VM_PS51_FINAL_' + [guid]::NewGuid().ToString('N') + '.ps1')
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

try {
    $fixed = (Invoke-WebRequest -UseBasicParsing -Uri $SourceUri).Content
    if ([string]::IsNullOrWhiteSpace($fixed)) { throw 'Pinned V3 runner download returned empty content.' }

    # 1) Prevent StrictMode expansion in V3's tail regex while preserving regex-level literal-dollar escapes.
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

    # 2) Remove the dead C# constant that causes Add-Type CS0219 on Windows PowerShell 5.1.
    $deadConst = '        const UInt32 REC=20;'
    $deadCount = ([regex]::Matches($fixed,[regex]::Escape($deadConst))).Count
    if ($deadCount -ne 1) { throw "Expected exactly one generated REC constant; found $deadCount." }
    $fixed = $fixed.Replace($deadConst,'')

    # 3) Inject the .NET Framework HexBytes compatibility fix INTO V3 immediately after
    #    it downloads the pinned original capture. That is the layer where HexBytes exists.
    $sourceGuard = '    if ([string]::IsNullOrWhiteSpace($text)) { throw ''Pinned capture source download returned empty content.'' }'
    $guardCount = ([regex]::Matches($fixed,[regex]::Escape($sourceGuard))).Count
    if ($guardCount -ne 1) { throw "Expected exactly one pinned-source guard; found $guardCount." }
    $hexInjection = @'

    # Windows PowerShell 5.1 / .NET Framework has no Convert.ToHexString().
    # Only the pre-hook HexBytes helper survives into the compact V3 path; the legacy TSV tail is replaced later.
    $hexHelperOld = 'function HexBytes([byte[]]$b) { [Convert]::ToHexString($b) }'
    $hexHelperNew = 'function HexBytes([byte[]]$b) { ([BitConverter]::ToString($b)).Replace(''-'','''') }'
    $hexHelperCount = ([regex]::Matches($text,[regex]::Escape($hexHelperOld))).Count
    if ($hexHelperCount -ne 1) { throw "Expected exactly one pinned HexBytes helper; found $hexHelperCount." }
    $text = $text.Replace($hexHelperOld,$hexHelperNew)
'@
    $fixed = $fixed.Replace($sourceGuard,$sourceGuard + $hexInjection)

    # 4) Replace PS7-only utf8NoBOM writer in V3 with a .NET Framework-compatible writer.
    $innerOld = '    Set-Content -LiteralPath $temp -Value $text -Encoding utf8NoBOM'
    $innerNew = '    [System.IO.File]::WriteAllText($temp,$text,(New-Object System.Text.UTF8Encoding($false)))'
    $innerCount = ([regex]::Matches($fixed,[regex]::Escape($innerOld))).Count
    if ($innerCount -ne 1) { throw "Expected exactly one V3 utf8NoBOM writer; found $innerCount." }
    $fixed = $fixed.Replace($innerOld,$innerNew)

    # 5) Remove the unnecessary LASTEXITCODE check. Terminating inner-script errors already propagate
    #    through &, and this avoids depending on native-process state in a fresh PS5.1 session.
    $lastExitLine = '    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }'
    if ($fixed.Contains($lastExitLine)) { $fixed = $fixed.Replace($lastExitLine,'') }

    # Final materialization guard: the V3 generator itself must no longer contain known PS5.1 blockers.
    if ($fixed.Contains('-Encoding utf8NoBOM')) { throw 'utf8NoBOM blocker survived materialization.' }
    if ($fixed.Contains('const UInt32 REC=20;')) { throw 'Dead REC constant survived materialization.' }

    [System.IO.File]::WriteAllText($temp,$fixed,$Utf8NoBom)
    Write-Host 'VM FINAL source fix  : tail/PID/C#/UTF8/.NET5 compatibility materialized'
    Write-Host 'VM FINAL execution   : one corrected V3 runner; no nested compatibility runner'
    & $temp -Label $Label -OutputDir $OutputDir
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
