param(
    [int]$LookbackMinutes = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY crash forensics for the post-join territory-selection failure.
# Reads Windows Application/WER logs and searches existing WER locations for dumps.
# Does NOT open/debug/modify game.dat and does NOT change registry/WER configuration.

if ($LookbackMinutes -lt 5 -or $LookbackMinutes -gt 240) {
    throw 'LookbackMinutes must be between 5 and 240.'
}

$since = (Get-Date).AddMinutes(-$LookbackMinutes)
Write-Host '============================================================'
Write-Host ' AOTR POSTJOIN 0x8472BF TERRITORY CRASH FORENSICS V1'
Write-Host '============================================================'
Write-Host ('Since : {0}' -f $since)
Write-Host 'Mode  : READ ONLY / EVENT LOG + EXISTING WER FILES'
Write-Host ''

$events = @(Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$since; Id=1000,1001} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match '(?i)game\.dat' } |
    Sort-Object TimeCreated -Descending)

Write-Host ('MATCHING_APPLICATION_EVENTS={0}' -f $events.Count)
if ($events.Count -eq 0) {
    Write-Host 'LATEST_CRASH_EVENT_FOUND=NO'
    Write-Host 'READ_ONLY_COMPLETE=YES'
    exit 0
}

$latest1000 = $events | Where-Object { $_.Id -eq 1000 } | Select-Object -First 1
$latest1001 = $events | Where-Object { $_.Id -eq 1001 } | Select-Object -First 1

$exceptionCode = $null
$faultOffset = $null
$faultModule = $null
$pidHex = $null

if ($null -ne $latest1000) {
    Write-Host '================ LATEST APPLICATION ERROR 1000 ================'
    Write-Host ('TimeCreated : {0}' -f $latest1000.TimeCreated)
    Write-Host ('RecordId    : {0}' -f $latest1000.RecordId)
    Write-Host $latest1000.Message
    Write-Host ''

    $m=[string]$latest1000.Message
    if ($m -match '(?im)Ausnahmecode:\s*(0x[0-9a-f]+)') { $exceptionCode=$Matches[1].ToLowerInvariant() }
    elseif ($m -match '(?im)Exception code:\s*(0x[0-9a-f]+)') { $exceptionCode=$Matches[1].ToLowerInvariant() }
    if ($m -match '(?im)Fehleroffset:\s*(0x[0-9a-f]+)') { $faultOffset=$Matches[1].ToLowerInvariant() }
    elseif ($m -match '(?im)Fault offset:\s*(0x[0-9a-f]+)') { $faultOffset=$Matches[1].ToLowerInvariant() }
    if ($m -match '(?im)Fehlerhafter Modulname:\s*([^\r\n]+)') { $faultModule=$Matches[1].Trim() }
    elseif ($m -match '(?im)Faulting module name:\s*([^\r\n]+)') { $faultModule=$Matches[1].Trim() }
    if ($m -match '(?im)Fehlerhafte Prozess-ID:\s*(0x[0-9a-f]+)') { $pidHex=$Matches[1].ToLowerInvariant() }
    elseif ($m -match '(?im)Faulting process id:\s*(0x[0-9a-f]+)') { $pidHex=$Matches[1].ToLowerInvariant() }
}

$archiveDirs = New-Object System.Collections.Generic.List[string]
if ($null -ne $latest1001) {
    Write-Host '================ LATEST WER 1001 ================'
    Write-Host ('TimeCreated : {0}' -f $latest1001.TimeCreated)
    Write-Host ('RecordId    : {0}' -f $latest1001.RecordId)
    Write-Host $latest1001.Message
    Write-Host ''
    foreach ($line in ([string]$latest1001.Message -split "`r?`n")) {
        if ($line -match '(?i)\\\?\\C:\\ProgramData\\Microsoft\\Windows\\WER\\ReportArchive\\[^\r\n]+') {
            $p=$Matches[0] -replace '^\\\\\?\\',''
            if (-not $archiveDirs.Contains($p)) { [void]$archiveDirs.Add($p) }
        }
    }
}

# Also discover recently modified game.dat WER archives in case the event message path is localized/omitted.
$archiveRoot='C:\ProgramData\Microsoft\Windows\WER\ReportArchive'
if (Test-Path -LiteralPath $archiveRoot) {
    foreach ($d in @(Get-ChildItem -LiteralPath $archiveRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $since -and $_.Name -match '(?i)game\.dat' })) {
        if (-not $archiveDirs.Contains($d.FullName)) { [void]$archiveDirs.Add($d.FullName) }
    }
}

Write-Host '================ NORMALIZED CRASH SUMMARY ================'
Write-Host ('EXCEPTION_CODE={0}' -f $(if($null-ne$exceptionCode){$exceptionCode}else{'UNKNOWN'}))
Write-Host ('FAULT_OFFSET={0}' -f $(if($null-ne$faultOffset){$faultOffset}else{'UNKNOWN'}))
Write-Host ('FAULT_MODULE={0}' -f $(if($null-ne$faultModule){$faultModule}else{'UNKNOWN'}))
Write-Host ('PROCESS_ID_HEX={0}' -f $(if($null-ne$pidHex){$pidHex}else{'UNKNOWN'}))
$matchesPrior = ($exceptionCode -eq '0xc000001d' -and $faultOffset -eq '0x042e04f8')
Write-Host ('MATCHES_PRIOR_CRASH_C000001D_042E04F8={0}' -f $(if($matchesPrior){'YES'}else{'NO'}))
Write-Host ''

Write-Host ('WER_ARCHIVE_DIRS={0}' -f $archiveDirs.Count)
$dumps = New-Object System.Collections.Generic.List[object]
foreach ($dir in $archiveDirs) {
    Write-Host ('ARCHIVE_DIR : {0}' -f $dir)
    if (-not (Test-Path -LiteralPath $dir)) { Write-Host '  EXISTS=NO'; continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
        Write-Host ('  FILE {0,12} {1}  {2}' -f $f.Length,$f.LastWriteTime,$f.Name)
        if ($f.Extension -ieq '.dmp') { [void]$dumps.Add($f) }
    }
    $rw=Join-Path $dir 'Report.wer'
    if (Test-Path -LiteralPath $rw) {
        Write-Host '--- REPORT.WER KEY LINES ---'
        Get-Content -LiteralPath $rw -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '^(EventType|ReportIdentifier|AppName|AppPath|Sig\[|DynamicSig\[)' } |
            Select-Object -First 80 |
            ForEach-Object { Write-Host $_ }
    }
}

# Search still-existing WER temp dumps created in the lookback window.
$tempRoot='C:\ProgramData\Microsoft\Windows\WER\Temp'
if (Test-Path -LiteralPath $tempRoot) {
    foreach ($f in @(Get-ChildItem -LiteralPath $tempRoot -Filter '*.dmp' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $since })) {
        if (-not ($dumps | Where-Object { $_.FullName -eq $f.FullName })) { [void]$dumps.Add($f) }
    }
}

Write-Host ''
Write-Host ('DUMP_CANDIDATES={0}' -f $dumps.Count)
foreach ($d in $dumps) {
    $sha=(Get-FileHash -LiteralPath $d.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
    Write-Host ('DUMP : {0}' -f $d.FullName)
    Write-Host ('  Size   : {0}' -f $d.Length)
    Write-Host ('  Modified: {0}' -f $d.LastWriteTime)
    Write-Host ('  SHA256 : {0}' -f $sha)
}

if ($dumps.Count -gt 0) { Write-Host 'DUMP_AVAILABLE_FOR_OFFLINE_ANALYSIS=YES' -ForegroundColor Green }
else { Write-Host 'DUMP_AVAILABLE_FOR_OFFLINE_ANALYSIS=NO' -ForegroundColor Yellow }

Write-Host ''
Write-Host 'READ_ONLY_COMPLETE=YES'
Write-Host 'No process was opened/debugged/modified and no WER configuration was changed.'
