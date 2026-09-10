param(
    [int]$SinceMinutes = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($SinceMinutes -lt 5 -or $SinceMinutes -gt 1440) { throw 'SinceMinutes must be 5..1440.' }
$since = (Get-Date).AddMinutes(-$SinceMinutes)

Write-Host '============================================================'
Write-Host ' AOTR WOTR POSTJOIN REGION CRASH WER DUMP LOCATOR - READ ONLY'
Write-Host '============================================================'
Write-Host ("Since : {0}" -f $since)
Write-Host 'Mode  : READ ONLY / NO GAME PROCESS ACCESS / NO DEBUG ATTACH'
Write-Host ''

$eventCandidates = @()
try {
    $eventCandidates = @(Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$since; Id=1001} -ErrorAction Stop |
        Where-Object { $_.ProviderName -eq 'Windows Error Reporting' -and $_.Message -match '(?i)game\.dat' } |
        Sort-Object TimeCreated -Descending)
} catch {
    Write-Host ("WER_EVENT_QUERY_FAILED: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

$explicitDumpPaths = New-Object System.Collections.Generic.List[string]
$explicitArchiveDirs = New-Object System.Collections.Generic.List[string]
foreach ($ev in $eventCandidates) {
    Write-Host ('WER_EVENT Time={0} RecordId={1}' -f $ev.TimeCreated,$ev.RecordId)
    foreach ($m in [regex]::Matches([string]$ev.Message,'(?im)([A-Z]:\\[^\r\n]+?\.dmp)')) {
        $p = $m.Groups[1].Value.Trim()
        if (-not $explicitDumpPaths.Contains($p)) { [void]$explicitDumpPaths.Add($p) }
    }
    foreach ($m in [regex]::Matches([string]$ev.Message,'(?im)([A-Z]:\\ProgramData\\Microsoft\\Windows\\WER\\ReportArchive\\[^\r\n]+)')) {
        $p = $m.Groups[1].Value.Trim()
        if (-not $explicitArchiveDirs.Contains($p)) { [void]$explicitArchiveDirs.Add($p) }
    }
}

$roots = @(
    'C:\ProgramData\Microsoft\Windows\WER\Temp',
    'C:\ProgramData\Microsoft\Windows\WER\ReportArchive',
    'C:\ProgramData\Microsoft\Windows\WER\ReportQueue',
    (Join-Path $env:LOCALAPPDATA 'CrashDumps')
) | Select-Object -Unique

$dumps = New-Object System.Collections.Generic.List[object]
function Add-DumpCandidate([string]$Path,[string]$Source) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($fi.LastWriteTime -lt $since) { return }
    if ($dumps | Where-Object { $_.Path -eq $fi.FullName }) { return }
    $hash = ''
    try { $hash = (Get-FileHash -LiteralPath $fi.FullName -Algorithm SHA256).Hash.ToUpperInvariant() } catch { $hash = 'HASH_FAILED' }
    $dumps.Add([pscustomobject]@{
        Source=$Source; Path=$fi.FullName; Length=$fi.Length; LastWriteTime=$fi.LastWriteTime; SHA256=$hash
    }) | Out-Null
}

foreach ($p in $explicitDumpPaths) { Add-DumpCandidate $p 'WER_EVENT_EXPLICIT' }
foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    try {
        Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.dmp' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $since } |
            ForEach-Object { Add-DumpCandidate $_.FullName ('SCAN:'+ $root) }
    } catch {}
}

Write-Host ''
Write-Host ('DUMP_CANDIDATES={0}' -f $dumps.Count)
$ordered = @($dumps | Sort-Object LastWriteTime -Descending)
for ($i=0; $i -lt $ordered.Count; $i++) {
    $d = $ordered[$i]
    Write-Host ('[{0}] Source        : {1}' -f $i,$d.Source)
    Write-Host ('    Path          : {0}' -f $d.Path)
    Write-Host ('    Length        : {0}' -f $d.Length)
    Write-Host ('    LastWriteTime : {0}' -f $d.LastWriteTime)
    Write-Host ('    SHA256        : {0}' -f $d.SHA256)
}

Write-Host ''
Write-Host ('EXPLICIT_ARCHIVE_DIRS={0}' -f $explicitArchiveDirs.Count)
foreach ($dir in $explicitArchiveDirs) {
    Write-Host ('ARCHIVE_DIR : {0}' -f $dir)
    if (Test-Path -LiteralPath $dir -PathType Container) {
        Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue |
            Sort-Object Name |
            ForEach-Object { Write-Host ('  {0,-8} {1,12} {2}  {3}' -f $(if($_.PSIsContainer){'DIR'}else{'FILE'}),$(if($_.PSIsContainer){''}else{$_.Length}),$_.LastWriteTime,$_.Name) }
        $wer = Join-Path $dir 'Report.wer'
        if (Test-Path -LiteralPath $wer -PathType Leaf) {
            Write-Host '--- REPORT.WER KEY LINES ---'
            Get-Content -LiteralPath $wer -ErrorAction SilentlyContinue |
                Where-Object { $_ -match '^(AppName|AppPath|AppVersion|EventType|Sig\[[0-9]+\]|DynamicSig\[[0-9]+\]|Faulting|Exception|ReportIdentifier|CabGuid)=' } |
                ForEach-Object { Write-Host $_ }
        }
    } else {
        Write-Host '  ARCHIVE_DIR_NOT_PRESENT'
    }
}

$cdbCandidates = @(
    'C:\Program Files (x86)\Windows Kits\10\Debuggers\x86\cdb.exe',
    'C:\Program Files\Windows Kits\10\Debuggers\x86\cdb.exe',
    'C:\Program Files (x86)\Windows Kits\8.1\Debuggers\x86\cdb.exe'
)
$cdb = $cdbCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

Write-Host ''
Write-Host ('CDB_FOUND={0}' -f $(if($cdb){'YES'}else{'NO'}))
if ($cdb) { Write-Host ('CDB_PATH={0}' -f $cdb) }

if ($ordered.Count -gt 0 -and $cdb) {
    $dump = $ordered[0].Path
    Write-Host ''
    Write-Host '================ OFFLINE CDB ANALYSIS OF NEWEST DUMP ================'
    Write-Host ('DUMP={0}' -f $dump)
    Write-Host 'The debugger is opening the dump file only; it is not attaching to game.dat.'
    $cmd = '.ecxr; r; kv; u @eip-20 @eip+40; db @eip-20 L60; q'
    try {
        $out = (& $cdb -z $dump -c $cmd 2>&1 | Out-String)
        Write-Host $out
        Write-Host 'OFFLINE_CDB_COMPLETE=YES'
    } catch {
        Write-Host ('OFFLINE_CDB_FAILED: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
    }
} elseif ($ordered.Count -gt 0) {
    Write-Host 'DUMP_FOUND_NO_CDB=YES'
} else {
    Write-Host 'NO_DUMP_FOUND_IN_CURRENT_WER_LOCATIONS=YES'
}

Write-Host ''
Write-Host 'READ_ONLY_COMPLETE=YES'
Write-Host 'No game process was opened, debugged, or modified.'
