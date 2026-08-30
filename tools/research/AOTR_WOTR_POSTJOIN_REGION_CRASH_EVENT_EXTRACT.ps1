param(
    [int]$MinutesBack = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($MinutesBack -lt 1 -or $MinutesBack -gt 240) { throw 'MinutesBack must be 1..240.' }

$since = (Get-Date).AddMinutes(-$MinutesBack)

Write-Host '============================================================'
Write-Host ' AOTR WOTR POSTJOIN REGION CRASH EVENT EXTRACT - READ ONLY'
Write-Host '============================================================'
Write-Host ("Since : {0}" -f $since)
Write-Host 'Mode  : READ ONLY / WINDOWS APPLICATION EVENT LOG'
Write-Host ''

$events = @(Get-WinEvent -FilterHashtable @{ LogName='Application'; StartTime=$since } -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Id -in 1000,1001,1002 -or
        $_.ProviderName -in 'Application Error','Windows Error Reporting','Application Hang'
    } |
    Where-Object {
        $_.Message -match '(?i)game\.dat|lotrbfme2ep1\.exe|AgeoftheRing'
    } |
    Sort-Object TimeCreated -Descending)

if ($events.Count -eq 0) {
    Write-Host 'MATCHING_APPLICATION_EVENTS=0'
    Write-Host 'No matching Application Error/WER event found in the requested window.'
    Write-Host 'READ_ONLY_COMPLETE=YES'
    return
}

Write-Host ("MATCHING_APPLICATION_EVENTS={0}" -f $events.Count)
Write-Host ''

$i = 0
foreach ($e in $events) {
    $i++
    Write-Host ('================ EVENT {0} ================' -f $i)
    Write-Host ('TimeCreated  : {0}' -f $e.TimeCreated)
    Write-Host ('Provider     : {0}' -f $e.ProviderName)
    Write-Host ('EventId      : {0}' -f $e.Id)
    Write-Host ('RecordId     : {0}' -f $e.RecordId)
    Write-Host 'Message:'
    Write-Host $e.Message
    Write-Host ''
}

$latest1000 = @($events | Where-Object { $_.Id -eq 1000 -and $_.ProviderName -eq 'Application Error' } | Select-Object -First 1)
if ($latest1000.Count -gt 0) {
    $m = [string]$latest1000[0].Message
    Write-Host '================ LATEST APPLICATION ERROR SUMMARY ================'

    $patterns = [ordered]@{
        FaultingApplication = '(?im)^Faulting application name:\s*([^,\r\n]+)'
        FaultingModule      = '(?im)^Faulting module name:\s*([^,\r\n]+)'
        ExceptionCode       = '(?im)^Exception code:\s*([^\r\n]+)'
        FaultOffset         = '(?im)^Fault offset:\s*([^\r\n]+)'
        ProcessId           = '(?im)^Faulting process id:\s*([^\r\n]+)'
        ApplicationPath     = '(?im)^Faulting application path:\s*([^\r\n]+)'
        ModulePath          = '(?im)^Faulting module path:\s*([^\r\n]+)'
    }

    foreach ($k in $patterns.Keys) {
        $mm = [regex]::Match($m,$patterns[$k])
        if ($mm.Success) {
            Write-Host ('{0,-20}: {1}' -f $k,$mm.Groups[1].Value.Trim())
        }
    }
}

Write-Host ''
Write-Host 'READ_ONLY_COMPLETE=YES'
Write-Host 'No process was opened, debugged, or modified.'
