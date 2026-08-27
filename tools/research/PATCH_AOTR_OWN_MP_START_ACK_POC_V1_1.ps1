param(
    [string]$Source = 'C:\AOTR_RESEARCH\AOTR_OWN_MP_START_ACK_POC.ps1',
    [string]$Destination = 'C:\AOTR_RESEARCH\AOTR_OWN_MP_START_ACK_POC_V1_1.ps1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
    throw "Source not found: $Source"
}

$text = [System.IO.File]::ReadAllText($Source, [System.Text.Encoding]::UTF8)

$oldTimeout = '$stream.ReadTimeout = 10000'
$newTimeout = '$stream.ReadTimeout = 300000'
$timeoutCount = ([regex]::Matches($text, [regex]::Escape($oldTimeout))).Count
if ($timeoutCount -ne 1) {
    throw "Expected exactly one stream ReadTimeout marker, found $timeoutCount"
}
$text = $text.Replace($oldTimeout, $newTimeout)

$oldCounter = '                Write-Host ("Connected        : {0}/{1}" -f $clients.Count, $ExpectedClients)'
$newCounter = @'
                Write-Host ("Remote barrier   : {0}/{1}" -f $clients.Count, $ExpectedClients)
                Write-Host ("Network lobby    : {0}/8" -f ($clients.Count + 1))
                Write-Host ("Strategic mapped : {0}/8" -f ($clients.Count + 2))
'@
$counterCount = ([regex]::Matches($text, [regex]::Escape($oldCounter))).Count
if ($counterCount -ne 1) {
    throw "Expected exactly one Connected counter marker, found $counterCount"
}
$text = $text.Replace($oldCounter, $newCounter.TrimEnd("`r", "`n"))

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($Destination, $text, $utf8Bom)

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $Destination,
    [ref]$tokens,
    [ref]$errors
)

if ($errors.Count -ne 0) {
    $errors | Format-List | Out-String | Write-Host
    throw "Parser errors in patched V1.1 file."
}

Write-Host 'PATCH PASS' -ForegroundColor Green
Write-Host ("Source      : {0}" -f $Source)
Write-Host ("Destination : {0}" -f $Destination)
Write-Host 'Read timeout : 300000 ms'
Write-Host 'Counters     : Remote barrier / Network lobby / Strategic mapped'
Write-Host ("SHA256       : {0}" -f (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash)
