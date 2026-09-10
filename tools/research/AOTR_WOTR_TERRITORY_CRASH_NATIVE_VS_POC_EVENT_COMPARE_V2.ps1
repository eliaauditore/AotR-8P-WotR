param(
    [int]$LookbackHours = 4,
    [int]$MaxEvents = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '============================================================'
Write-Host ' AOTR TERRITORY CRASH NATIVE-vs-POC EVENT COMPARE V2'
Write-Host '============================================================'
Write-Host 'Mode  : READ ONLY / WINDOWS APPLICATION EVENT LOG'
Write-Host ("Since : {0}" -f (Get-Date).AddHours(-$LookbackHours))
Write-Host ''

$since = (Get-Date).AddHours(-$LookbackHours)
$events = @(Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=$since} -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -eq 'Application Error' -and $_.Message -match '(?im)Anwendungsname:\s*game\.dat|Faulting application name:\s*game\.dat' } |
    Sort-Object TimeCreated -Descending |
    Select-Object -First $MaxEvents)

Write-Host ("GAME_DAT_APPLICATION_ERROR_EVENTS={0}" -f $events.Count)
if ($events.Count -eq 0) {
    Write-Host 'NO_GAME_DAT_APPLICATION_ERROR_EVENTS=YES'
    Write-Host 'READ_ONLY_COMPLETE=YES'
    exit 0
}

$rows = @()
$index = 0
foreach ($ev in $events) {
    $index++
    $m = [string]$ev.Message
    $exception = ''
    $fault = ''
    $processIdHex = ''
    $module = ''
    $report = ''

    if ($m -match '(?im)(?:Ausnahmecode|Exception code):\s*(0x[0-9a-f]+)') { $exception = $Matches[1].ToLowerInvariant() }
    if ($m -match '(?im)(?:Fehleroffset|Fault offset):\s*(0x[0-9a-f]+)') { $fault = $Matches[1].ToLowerInvariant() }
    if ($m -match '(?im)(?:Fehlerhafte Prozess-ID|Faulting process id):\s*(0x[0-9a-f]+)') { $processIdHex = $Matches[1].ToLowerInvariant() }
    if ($m -match '(?im)(?:Fehlerhafter Modulname|Faulting module name):\s*([^\r\n]+)') { $module = $Matches[1].Trim() }
    if ($m -match '(?im)(?:Berichts-ID|Report Id):\s*([^\r\n]+)') { $report = $Matches[1].Trim() }

    $row = [pscustomobject]@{
        Index       = $index
        TimeCreated = $ev.TimeCreated
        RecordId    = $ev.RecordId
        Exception   = $exception
        FaultOffset = $fault
        ProcessId   = $processIdHex
        Module      = $module
        ReportId    = $report
    }
    $rows += $row

    Write-Host ("================ CRASH {0} ================" -f $index)
    Write-Host ("TimeCreated : {0}" -f $row.TimeCreated)
    Write-Host ("RecordId    : {0}" -f $row.RecordId)
    Write-Host ("Exception   : {0}" -f $row.Exception)
    Write-Host ("FaultOffset : {0}" -f $row.FaultOffset)
    Write-Host ("ProcessId   : {0}" -f $row.ProcessId)
    Write-Host ("Module      : {0}" -f $row.Module)
    Write-Host ("ReportId    : {0}" -f $row.ReportId)
    Write-Host ''
}

if ($rows.Count -ge 2) {
    $a = $rows[0]
    $b = $rows[1]
    $sameException = (-not [string]::IsNullOrWhiteSpace($a.Exception)) -and ($a.Exception -eq $b.Exception)
    $sameFault = (-not [string]::IsNullOrWhiteSpace($a.FaultOffset)) -and ($a.FaultOffset -eq $b.FaultOffset)
    $sameModule = (-not [string]::IsNullOrWhiteSpace($a.Module)) -and ($a.Module -eq $b.Module)
    Write-Host '================ LATEST TWO A/B ================'
    Write-Host ("LATEST_TWO_SAME_EXCEPTION={0}" -f ($(if($sameException){'YES'}else{'NO'})))
    Write-Host ("LATEST_TWO_SAME_FAULT_OFFSET={0}" -f ($(if($sameFault){'YES'}else{'NO'})))
    Write-Host ("LATEST_TWO_SAME_MODULE={0}" -f ($(if($sameModule){'YES'}else{'NO'})))
    if ($sameException -and $a.Exception -eq '0xc000001d' -and $sameModule) {
        Write-Host 'LATEST_TWO_SHARE_ILLEGAL_INSTRUCTION_SIGNATURE=YES'
    }
    Write-Host ''
}

function Get-WerField([string]$Text,[string]$Name){
    $pattern='(?im)^'+[regex]::Escape($Name)+':\s*([^\r\n]+)'
    if($Text -match $pattern){return $Matches[1].Trim()}
    return ''
}
function Get-WerBucket([string]$Text){
    $m=[regex]::Match($Text,'(?im)^(?:Bucket mit Hash|Bucket hash):\s*([^\r\n]+)')
    if($m.Success){return $m.Groups[1].Value.Trim()}
    return ''
}

$wer = @(Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1001; StartTime=$since} -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -eq 'Windows Error Reporting' -and $_.Message -match '(?im)^P1:\s*game\.dat\s*$' } |
    Sort-Object TimeCreated -Descending |
    Select-Object -First $MaxEvents)
Write-Host ("GAME_DAT_WER_EVENTS={0}" -f $wer.Count)
$werRows=@()
$wi = 0
foreach ($ev in $wer) {
    $wi++
    $m=[string]$ev.Message
    $wr=[pscustomobject]@{
        Index=$wi
        TimeCreated=$ev.TimeCreated
        RecordId=$ev.RecordId
        P4=(Get-WerField $m 'P4')
        P7=(Get-WerField $m 'P7')
        P8=(Get-WerField $m 'P8')
        BucketHash=(Get-WerBucket $m)
    }
    $werRows += $wr
    Write-Host ("WER[{0}] Time={1} RecordId={2} P4={3} P7={4} P8={5} BucketHash={6}" -f $wr.Index,$wr.TimeCreated,$wr.RecordId,$wr.P4,$wr.P7,$wr.P8,$wr.BucketHash)
}

if($werRows.Count -ge 2){
    $w0=$werRows[0]; $w1=$werRows[1]
    $sameP4=(-not [string]::IsNullOrWhiteSpace($w0.P4)) -and ($w0.P4 -eq $w1.P4)
    $sameP7=(-not [string]::IsNullOrWhiteSpace($w0.P7)) -and ($w0.P7 -eq $w1.P7)
    $sameP8=(-not [string]::IsNullOrWhiteSpace($w0.P8)) -and ($w0.P8 -eq $w1.P8)
    $sameBucket=(-not [string]::IsNullOrWhiteSpace($w0.BucketHash)) -and ($w0.BucketHash -eq $w1.BucketHash)
    Write-Host ("LATEST_TWO_WER_SAME_P4={0}" -f ($(if($sameP4){'YES'}else{'NO'})))
    Write-Host ("LATEST_TWO_WER_SAME_P7={0}" -f ($(if($sameP7){'YES'}else{'NO'})))
    Write-Host ("LATEST_TWO_WER_SAME_P8={0}" -f ($(if($sameP8){'YES'}else{'NO'})))
    Write-Host ("LATEST_TWO_WER_SAME_BUCKET={0}" -f ($(if($sameBucket){'YES'}else{'NO'})))
    if($sameP4 -and $sameP7 -and $sameP8 -and $sameBucket){
        Write-Host 'LATEST_TWO_WER_FINGERPRINT_MATCH=YES'
    } else {
        Write-Host 'LATEST_TWO_WER_FINGERPRINT_MATCH=NO'
    }
}

Write-Host ''
Write-Host 'READ_ONLY_COMPLETE=YES'
Write-Host 'No process was opened/debugged/modified.'
