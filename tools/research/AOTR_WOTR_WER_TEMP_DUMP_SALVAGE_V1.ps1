param(
    [string]$OutputDir = 'C:\AOTR_RESEARCH\WER_SALVAGED_DUMPS',
    [int]$LookbackMinutes = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

Write-Host '============================================================'
Write-Host ' AOTR WER TEMP DUMP SALVAGE V1'
Write-Host '============================================================'
Write-Host 'MODE=READ/COPY ONLY'
Write-Host 'DEBUGGER_ATTACH=NO'
Write-Host 'GAME_PROCESS_ACCESS=NO'
Write-Host 'REGISTRY_WRITE=NO'
Write-Host ''

$since=(Get-Date).AddMinutes(-$LookbackMinutes)
$wer=@(Get-WinEvent -FilterHashtable @{LogName='Application';Id=1001;StartTime=$since} -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -eq 'Windows Error Reporting' -and $_.Message -match '(?im)^P1:\s*game\.dat\s*$' } |
    Sort-Object TimeCreated -Descending)

if($wer.Count -eq 0){
    Write-Host 'GAME_DAT_WER_EVENTS=0'
    Write-Host 'SALVAGE_RESULT=NO_RECENT_WER_EVENT'
    exit 0
}

$ev=$wer[0]
$msg=[string]$ev.Message
Write-Host ('WER_TIME={0:O}' -f $ev.TimeCreated)
Write-Host ('WER_RECORD_ID={0}' -f $ev.RecordId)

$paths=New-Object System.Collections.Generic.List[string]
foreach($m in [regex]::Matches($msg,'(?im)(?:\\\\\?\\)?([A-Z]:\\ProgramData\\Microsoft\\Windows\\WER\\Temp\\[^\r\n]+?\.dmp)')){
    $p=$m.Groups[1].Value.Trim()
    if(-not $paths.Contains($p)){[void]$paths.Add($p)}
}

$werTemp='C:\ProgramData\Microsoft\Windows\WER\Temp'
if(Test-Path -LiteralPath $werTemp -PathType Container){
    Get-ChildItem -LiteralPath $werTemp -Filter '*.dmp' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $since } |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { if(-not $paths.Contains($_.FullName)){[void]$paths.Add($_.FullName)} }
}

Write-Host ('DUMP_CANDIDATE_COUNT={0}' -f $paths.Count)
if($paths.Count -eq 0){
    Write-Host 'SALVAGE_RESULT=NO_DUMP_PATH_FOUND'
    exit 0
}

$copied=0
foreach($p in $paths){
    $exists=Test-Path -LiteralPath $p -PathType Leaf
    Write-Host ('CANDIDATE={0}' -f $p)
    Write-Host ('  EXISTS={0}' -f ($(if($exists){'YES'}else{'NO'})))
    if(-not $exists){continue}
    $fi=Get-Item -LiteralPath $p
    Write-Host ('  SIZE={0}' -f $fi.Length)
    Write-Host ('  LASTWRITE={0:O}' -f $fi.LastWriteTime)
    $stamp=$ev.TimeCreated.ToString('yyyyMMdd_HHmmss')
    $dest=Join-Path $OutputDir ("game.dat_WER_${stamp}_$($fi.Name)")
    Copy-Item -LiteralPath $p -Destination $dest -Force
    $out=Get-Item -LiteralPath $dest
    if($out.Length -le 0){throw "Copied dump is empty: $dest"}
    $sha=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToUpperInvariant()
    Write-Host '  COPY_PASS=YES' -ForegroundColor Green
    Write-Host ('  SAVED={0}' -f $dest)
    Write-Host ('  SAVED_SIZE={0}' -f $out.Length)
    Write-Host ('  SAVED_SHA256={0}' -f $sha)
    $copied++
}

if($copied -gt 0){
    Write-Host ('SALVAGE_RESULT=PASS COPIED={0}' -f $copied) -ForegroundColor Green
}else{
    Write-Host 'SALVAGE_RESULT=WER_DUMP_ALREADY_GONE'
}
