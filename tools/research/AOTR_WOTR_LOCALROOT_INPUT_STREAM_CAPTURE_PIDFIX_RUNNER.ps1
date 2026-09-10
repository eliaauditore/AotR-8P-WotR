param(
    [string]$Label = 'NODE',
    [string]$OutputDir = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Compatibility runner for PowerShell's built-in read-only $PID automatic variable.
# The original capture used $pid as a normal variable; PowerShell variable names are
# case-insensitive, so that collides with $PID. This runner downloads the pinned
# capture source, renames only PowerShell variable tokens $pid -> $gamePid, then
# executes the corrected temporary copy. The pinned source and game.dat on disk are
# not modified.

$SourceCommit = 'd9c786a74a305f15dac2c6ebb2d9785196c55f0c'
$SourceUri = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/tools/research/AOTR_WOTR_LOCALROOT_INPUT_STREAM_CAPTURE.ps1"
$temp = Join-Path $env:TEMP ('AOTR_WOTR_LOCALROOT_INPUT_STREAM_CAPTURE_PIDFIX_' + [guid]::NewGuid().ToString('N') + '.ps1')

try {
    $text = (Invoke-WebRequest -UseBasicParsing -Uri $SourceUri).Content
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'Pinned capture source download returned empty content.' }

    $before = ([regex]::Matches($text, '(?i)\$pid\b')).Count
    if ($before -lt 1) { throw 'Expected at least one $pid token in pinned capture source.' }

    $fixed = [regex]::Replace($text, '(?i)\$pid\b', '$gamePid')
    $after = ([regex]::Matches($fixed, '(?i)\$pid\b')).Count
    if ($after -ne 0) { throw "PID token replacement incomplete: $after token(s) remain." }

    Set-Content -LiteralPath $temp -Value $fixed -Encoding utf8NoBOM
    Write-Host ("PID compatibility fix : {0} token(s) renamed to `$gamePid" -f $before)
    & $temp -Label $Label -OutputDir $OutputDir
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
