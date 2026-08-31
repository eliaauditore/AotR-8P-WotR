param(
    [int]$LookbackHours = 4,
    [int]$MaxEvents = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '============================================================'
Write-Host ' AOTR TERRITORY CRASH NATIVE-vs-POC EVENT COMPARE V1'
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
    $pid = ''
    $module = ''
    $report = ''

    if ($m -match '(?im)(?:Ausnahmecode|Exception code):\s*(0x[0-9a-f]+)') { $exception = $Matches[1].ToLowerInvariant() }
    if ($m -match '(?im)(?:Fehleroffset|Fault offset):\s*(0x[0-9a-f]+)') { $fault = $Matches[1].ToLowerInvariant() }
    if ($m -match '(?im)(?:Fehlerhafte Prozess-ID|Faulting process id):\s*(0x[0-9a-f]+)') { $pid = $Matches[1].ToLowerInvariant() }
    if ($m -match '(?im)(?:Fehlerhafter Modulname|Faulting module name):\s*([^\r\n]+)') { $module = $Matches[1].Trim() }
    if ($m -match '(?im)(?:Berichts-ID|Report Id):\s*([^\r\n]+)') { $report = $Matches[1].Trim() }

    $row = [pscustomobject]@{
        Index       = $index
        TimeCreated = $ev.TimeCreated
        RecordId    = $ev.RecordId
        Exception   = $exception
        FaultOffset = $fault
        ProcessId   = $pid
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

# Pair recent WER 1001 entries for game.dat and print their stable bucket/signature fields.
$wer = @(Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1001; StartTime=$since} -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -eq 'Windows Error Reporting' -and $_.Message -match '(?im)^P1:\s*game\.dat\s*$' } |
    Sort-Object TimeCreated -Descending |
    Select-Object -First $MaxEvents)
Write-Host ("GAME_DAT_WER_EVENTS={0}" -f $wer.Count)
$wi = 0
foreach ($ev in $wer) {
    $wi++
    $m=[string]$ev.Message
    $p4='';$p7='';$p8='';$bucket=''
    if($m -match '(?im)^P4:\s*([^\r\n]+)'){ $p4=$Matches[1].Trim() }
    if($m -match '(?im)^P7:\s*([^\r\n]+)'){ $p7=$Matches[1].Trim() }
    if($m -match '(?im)^P8:\s*([^\r\n]+)'){ $p8=$Matches[1].Trim() }
    if($m -match '(?im)^Bucket mit Hash:\s*([^\r\n]+)|^Bucket hash:\s*([^\r\n]+)'){
        $bucket = if($Matches[1]){$Matches[1].Trim()}else{$Matches[2].Trim()}
    }
    Write-Host ("WER[{0}] Time={1} RecordId={2} P4={3} P7={4} P8={5} BucketHash={6}" -f $wi,$ev.TimeCreated,$ev.RecordId,$p4,$p7,$p8,$bucket)
}

if($wer.Count -ge 2){
    $m0=[string]$wer[0].Message; $m1=[string]$wer[1].Message
    function Get-WerField([string]$Text,[string]$Name){
        $pattern='(?im)^'+[regex]::Escape($Name)+':\s*([^\r\n]+)'
        if($Text -match $pattern){return $Matches[1].Trim()}
        return ''
    }
    $sameP4=(Get-WerField $m0 'P4') -eq (Get-WerField $m1 'P4')
    $sameP7=(Get-WerField $m0 'P7') -eq (Get-WerField $m1 'P7')
    $sameP8=(Get-WerField $m0 'P8') -eq (Get-WerField $m1 'P8')
    Write-Host ("LATEST_TWO_WER_SAME_P4={0}" -f ($(if($sameP4){'YES'}else{'NO'})))
    Write-Host ("LATEST_TWO_WER_SAME_P7={0}" -f ($(if($sameP7){'YES'}else{'NO'})))
    Write-Host ("LATEST_TWO_WER_SAME_P8={0}" -f ($(if($sameP8){'YES'}else{'NO'})))
}

Write-Host ''
Write-Host 'READ_ONLY_COMPLETE=YES'
Write-Host 'No process was opened/debugged/modified.'
