#Requires -Version 5.1
[CmdletBinding()]
param([string]$GameRoot = '')
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'aotr10_ui_diagnose.py'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw "Diagnoseskript fehlt: $script" }
if (Get-Command py -ErrorAction SilentlyContinue) {
    $cmd = 'py'; $args = @('-3', $script)
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $cmd = 'python'; $args = @($script)
} else { throw 'Python 3 nicht gefunden.' }
if ($GameRoot) { $args += @('--root', $GameRoot) }
& $cmd @args
if ($LASTEXITCODE -ne 0) { throw "AOTR-UI-Diagnose fehlgeschlagen ($LASTEXITCODE). GameRoot ggf. explizit angeben." }
