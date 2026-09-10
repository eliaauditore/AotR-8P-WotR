param(
    [string]$CombinedResult = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($CombinedResult)) {
    $latest = Get-ChildItem 'C:\AOTR_RESEARCH\LOWLEVEL_JOIN_COMPLETION_COMBINED_*.txt' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) { throw 'No LOWLEVEL_JOIN_COMPLETION_COMBINED_*.txt result found.' }
    $CombinedResult = $latest.FullName
}
if (-not (Test-Path -LiteralPath $CombinedResult -PathType Leaf)) {
    throw "Combined result not found: $CombinedResult"
}

$lines = @(Get-Content -LiteralPath $CombinedResult)
$hits = New-Object System.Collections.Generic.List[object]

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -eq 'CALLBACK_8496C2_HIT=YES') {
        $ownerLine = $null
        $threadLine = $null
        $elapsedLine = $null
        for ($j = $i + 1; $j -le [Math]::Min($i + 8, $lines.Count - 1); $j++) {
            if ($lines[$j] -like 'ELAPSED_MS=*') { $elapsedLine = $lines[$j] }
            elseif ($lines[$j] -like 'THREAD_ID=*') { $threadLine = $lines[$j] }
            elseif ($lines[$j] -like 'ECX_OWNER=*') { $ownerLine = $lines[$j]; break }
        }
        if ($ownerLine) {
            $m = [regex]::Match($ownerLine, '^ECX_OWNER=(0x[0-9A-Fa-f]{8}) OWNER_6A4=(\d+) OWNER_304=(\d+) CURRENT_IS_C54B78=(YES|NO)$')
            if ($m.Success) {
                $elapsed = if ($elapsedLine) { ($elapsedLine -replace '^ELAPSED_MS=','') } else { '' }
                $thread = if ($threadLine -and $threadLine -match '^THREAD_ID=(\d+)') { [int]$Matches[1] } else { 0 }
                $hits.Add([pscustomobject]@{
                    Index       = $hits.Count + 1
                    ElapsedMs   = $elapsed
                    ThreadId    = $thread
                    Owner       = $m.Groups[1].Value
                    Owner6A4    = [int]$m.Groups[2].Value
                    Owner304    = [int]$m.Groups[3].Value
                    CurrentC54  = $m.Groups[4].Value
                })
            }
        }
    }
}

Write-Host '============================================================'
Write-Host ' AOTR WOTR STATE8 CALLBACK OWNER VALUE EXTRACT'
Write-Host '============================================================'
Write-Host ("Source              : {0}" -f $CombinedResult)
Write-Host ("Parsed callback hits : {0}" -f $hits.Count)

if ($hits.Count -eq 0) {
    throw 'No callback hits with owner-state records were parsed.'
}

$distinct = $hits | Group-Object Owner,Owner6A4,Owner304 | Sort-Object Count -Descending
Write-Host ''
Write-Host 'DISTINCT OWNER STATES:'
$distinct | ForEach-Object { Write-Host ("  Count={0}  {1}" -f $_.Count,$_.Name) }

Write-Host ''
Write-Host 'FIRST 10 CALLBACK HITS:'
$hits | Select-Object -First 10 | Format-Table -AutoSize

$state8 = @($hits | Where-Object { $_.Owner6A4 -eq 8 })
Write-Host ''
Write-Host ("OWNER_6A4_EQ_8_COUNT={0}" -f $state8.Count)
Write-Host ("OWNER_6A4_NE_8_COUNT={0}" -f ($hits.Count - $state8.Count))
if ($state8.Count -eq 0) {
    Write-Host 'STATE8_GATE_RUNTIME_RESULT=ALL_CALLBACK_HITS_STATE_NE_8'
} else {
    Write-Host 'STATE8_GATE_RUNTIME_RESULT=STATE8_OBSERVED_AT_CALLBACK'
    $state8 | Select-Object -First 10 | Format-Table -AutoSize
}
