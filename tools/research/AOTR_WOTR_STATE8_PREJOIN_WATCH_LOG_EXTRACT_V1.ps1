param(
    [string]$WatchLog = '',
    [string]$JoinLog = '',
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH',
    [uint32]$ExpectedOwner = 0x0994D8F0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY. Parses already-written watcher/join text files only.
# No process APIs, no debugger APIs, no WriteProcessMemory.

function F32([uint32]$v) { '0x{0:X8}' -f $v }
function Parse-Hex32([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s) -or $s -notmatch '^0x[0-9A-Fa-f]{8}$') { return [uint32]0 }
    return [uint32]::Parse($s.Substring(2), [Globalization.NumberStyles]::HexNumber)
}

if ([string]::IsNullOrWhiteSpace($WatchLog)) {
    $w = Get-ChildItem -LiteralPath $ResearchRoot -Filter 'STATE8_PREJOIN_WATCH_*.out.txt' -File -ErrorAction Stop |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $w) { throw 'No STATE8_PREJOIN_WATCH_*.out.txt found.' }
    $WatchLog = $w.FullName
}
if (-not (Test-Path -LiteralPath $WatchLog -PathType Leaf)) { throw "Watch log not found: $WatchLog" }

if ([string]::IsNullOrWhiteSpace($JoinLog)) {
    $j = Get-ChildItem -LiteralPath $ResearchRoot -Filter 'STATE8_PREJOIN_JOIN_*.txt' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($j) { $JoinLog = $j.FullName }
}

$lines = Get-Content -LiteralPath $WatchLog
$events = New-Object System.Collections.Generic.List[object]
$pending = $null

function New-Event([string]$Kind) {
    [ordered]@{
        Kind=$Kind; HitIndex=0; Elapsed=''; ThreadId=''; ExceptionAddress=''; Eip='';
        Eax='';Ebx='';Ecx='';Edx='';Esi='';Edi='';
        Session='';State28='';Current='';CurrentVt='';DE892C='';DEA114='';
        EcxOwner='';Owner6A4='';Owner304='';CurrentIsC54=''
    }
}

$cbIndex = 0
$coIndex = 0
foreach ($line in $lines) {
    if ($line -eq 'CALLBACK_8496C2_HIT=YES') {
        if ($null -ne $pending) { $events.Add([pscustomobject]$pending) }
        $pending = New-Event 'CALLBACK'
        $cbIndex++
        $pending.HitIndex = $cbIndex
        continue
    }
    if ($line -eq 'COMPLETION_84944F_HIT=YES') {
        if ($null -ne $pending) { $events.Add([pscustomobject]$pending) }
        $pending = New-Event 'COMPLETION'
        $coIndex++
        $pending.HitIndex = $coIndex
        continue
    }
    if ($null -eq $pending) { continue }

    $m = [regex]::Match($line,'^ELAPSED_MS=(.+)$')
    if ($m.Success) { $pending.Elapsed=$m.Groups[1].Value; continue }

    $m = [regex]::Match($line,'^THREAD_ID=(\d+) EXCEPTION_ADDRESS=(0x[0-9A-Fa-f]{8}) EIP=(0x[0-9A-Fa-f]{8})$')
    if ($m.Success) {
        $pending.ThreadId=$m.Groups[1].Value
        $pending.ExceptionAddress=$m.Groups[2].Value.ToUpperInvariant()
        $pending.Eip=$m.Groups[3].Value.ToUpperInvariant()
        continue
    }

    $m = [regex]::Match($line,'^EAX=(0x[0-9A-Fa-f]{8}) EBX=(0x[0-9A-Fa-f]{8}) ECX=(0x[0-9A-Fa-f]{8}) EDX=(0x[0-9A-Fa-f]{8}) ESI=(0x[0-9A-Fa-f]{8}) EDI=(0x[0-9A-Fa-f]{8})$')
    if ($m.Success) {
        $pending.Eax=$m.Groups[1].Value.ToUpperInvariant()
        $pending.Ebx=$m.Groups[2].Value.ToUpperInvariant()
        $pending.Ecx=$m.Groups[3].Value.ToUpperInvariant()
        $pending.Edx=$m.Groups[4].Value.ToUpperInvariant()
        $pending.Esi=$m.Groups[5].Value.ToUpperInvariant()
        $pending.Edi=$m.Groups[6].Value.ToUpperInvariant()
        continue
    }

    $m = [regex]::Match($line,'^SESSION=(0x[0-9A-Fa-f]{8}) STATE28=(\d+) CURRENT=(0x[0-9A-Fa-f]{8}) CURRENT_VT=(0x[0-9A-Fa-f]{8})$')
    if ($m.Success) {
        $pending.Session=$m.Groups[1].Value.ToUpperInvariant()
        $pending.State28=$m.Groups[2].Value
        $pending.Current=$m.Groups[3].Value.ToUpperInvariant()
        $pending.CurrentVt=$m.Groups[4].Value.ToUpperInvariant()
        continue
    }

    $m = [regex]::Match($line,'^DE892C=(0x[0-9A-Fa-f]{8}) DEA114=(\d+)$')
    if ($m.Success) {
        $pending.DE892C=$m.Groups[1].Value.ToUpperInvariant()
        $pending.DEA114=$m.Groups[2].Value
        continue
    }

    $m = [regex]::Match($line,'^ECX_OWNER=(0x[0-9A-Fa-f]{8}) OWNER_6A4=(\d+) OWNER_304=(\d+) CURRENT_IS_C54B78=(YES|NO)$')
    if ($m.Success) {
        $pending.EcxOwner=$m.Groups[1].Value.ToUpperInvariant()
        $pending.Owner6A4=$m.Groups[2].Value
        $pending.Owner304=$m.Groups[3].Value
        $pending.CurrentIsC54=$m.Groups[4].Value
        $events.Add([pscustomobject]$pending)
        $pending = $null
        continue
    }
}
if ($null -ne $pending) { $events.Add([pscustomobject]$pending) }

$callbacks = @($events | Where-Object { $_.Kind -eq 'CALLBACK' })
$completions = @($events | Where-Object { $_.Kind -eq 'COMPLETION' })
$ownerText = F32 $ExpectedOwner
$ecxOwnerCount = @($callbacks | Where-Object { $_.Ecx -eq $ownerText }).Count
$esiOwnerCount = @($callbacks | Where-Object { $_.Esi -eq $ownerText }).Count
$ecxEsiSameCount = @($callbacks | Where-Object { $_.Ecx -ne '' -and $_.Ecx -eq $_.Esi }).Count
$currentNonNull = @($callbacks | Where-Object { $_.Current -ne '' -and $_.Current -ne '0x00000000' })
$netNonNull = @($callbacks | Where-Object { $_.DE892C -ne '' -and $_.DE892C -ne '0x00000000' })

Write-Host '============================================================'
Write-Host ' AOTR STATE8 PREJOIN WATCH LOG EXTRACT V1 - READ ONLY'
Write-Host '============================================================'
Write-Host ("WATCH_LOG                  : {0}" -f $WatchLog)
if (-not [string]::IsNullOrWhiteSpace($JoinLog)) { Write-Host ("JOIN_LOG                   : {0}" -f $JoinLog) }
Write-Host ("EXPECTED_OWNER             : {0}" -f $ownerText)
Write-Host ("PARSED_CALLBACK_EVENTS     : {0}" -f $callbacks.Count)
Write-Host ("PARSED_COMPLETION_EVENTS   : {0}" -f $completions.Count)
Write-Host ("CALLBACK_ECX_EQ_OWNER      : {0}" -f $ecxOwnerCount)
Write-Host ("CALLBACK_ESI_EQ_OWNER      : {0}" -f $esiOwnerCount)
Write-Host ("CALLBACK_ECX_EQ_ESI        : {0}" -f $ecxEsiSameCount)
Write-Host ("CALLBACK_CURRENT_NON_NULL  : {0}" -f $currentNonNull.Count)
Write-Host ("CALLBACK_DE892C_NON_NULL   : {0}" -f $netNonNull.Count)
Write-Host ''

Write-Host '=== DISTINCT CALLBACK ECX / ESI / THREAD ==='
$callbacks |
    Group-Object Ecx,Esi,ThreadId |
    Sort-Object Count -Descending |
    Select-Object Count,@{n='ECX';e={$_.Group[0].Ecx}},@{n='ESI';e={$_.Group[0].Esi}},@{n='ThreadId';e={$_.Group[0].ThreadId}} |
    Format-Table -AutoSize

Write-Host '=== FIRST 5 CALLBACK EVENTS ==='
$callbacks | Select-Object -First 5 HitIndex,Elapsed,ThreadId,Eip,Ecx,Esi,Edi,Owner6A4,Owner304,Current,DE892C | Format-Table -AutoSize
Write-Host '=== LAST 5 CALLBACK EVENTS ==='
$callbacks | Select-Object -Last 5 HitIndex,Elapsed,ThreadId,Eip,Ecx,Esi,Edi,Owner6A4,Owner304,Current,DE892C | Format-Table -AutoSize

if ($currentNonNull.Count -gt 0) {
    Write-Host '=== FIRST CALLBACK WITH CURRENT != NULL ==='
    $currentNonNull | Select-Object -First 1 HitIndex,Elapsed,ThreadId,Eip,Ecx,Esi,Owner6A4,Current,CurrentVt,DE892C | Format-List
}
if ($netNonNull.Count -gt 0) {
    Write-Host '=== FIRST CALLBACK WITH DE892C != NULL ==='
    $netNonNull | Select-Object -First 1 HitIndex,Elapsed,ThreadId,Eip,Ecx,Esi,Owner6A4,Current,CurrentVt,DE892C | Format-List
}

Write-Host '=== COMPLETION EVENTS ==='
if ($completions.Count -eq 0) {
    Write-Host 'NONE'
} else {
    $completions | Select-Object HitIndex,Elapsed,ThreadId,Eip,Ecx,Esi,Edi,Owner6A4,Current,DE892C | Format-Table -AutoSize
}

if (-not [string]::IsNullOrWhiteSpace($JoinLog) -and (Test-Path -LiteralPath $JoinLog -PathType Leaf)) {
    $joinText = Get-Content -LiteralPath $JoinLog -Raw
    Write-Host '=== JOIN MARKERS ==='
    foreach ($marker in @('NATIVE +0x40 CALL RETURNED = YES','NATIVE_JOIN_STATE_OBSERVED = YES','session +0x44 after','DE892C after','current vtable')) {
        $hits = @($joinText -split "`r?`n" | Where-Object { $_ -like "*$marker*" })
        foreach ($h in $hits) { Write-Host $h }
    }
}

Write-Host ''
if ($callbacks.Count -gt 0 -and $esiOwnerCount -eq $callbacks.Count) {
    Write-Host 'GUARD_BASE_RESULT = ESI_EQUALS_EXPECTED_OWNER_ON_ALL_PARSED_CALLBACKS'
} elseif ($callbacks.Count -gt 0 -and $esiOwnerCount -eq 0) {
    Write-Host 'GUARD_BASE_RESULT = ESI_NEVER_EQUALS_EXPECTED_OWNER'
} else {
    Write-Host ("GUARD_BASE_RESULT = MIXED_ESI_OWNER_MATCH {0}/{1}" -f $esiOwnerCount,$callbacks.Count)
}
Write-Host 'READ_ONLY_COMPLETE=YES'
