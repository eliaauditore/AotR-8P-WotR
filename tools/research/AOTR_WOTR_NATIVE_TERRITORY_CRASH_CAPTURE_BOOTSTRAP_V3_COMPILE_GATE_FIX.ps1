param(
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [int]$TimeoutSeconds = 90,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PinnedV2Ref = '0a3602285cb8c2eef44cfc37d16ad9cf79fdd8d9'
$V2Name = 'AOTR_WOTR_NATIVE_TERRITORY_CRASH_CAPTURE_BOOTSTRAP_V2.ps1'
$RepoRaw = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR'

if ([Environment]::Is64BitProcess) {
    throw 'Run under 32-bit Windows PowerShell: C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
}

New-Item -ItemType Directory -Path $ResearchRoot -Force | Out-Null
$temp = Join-Path $env:TEMP ('AOTR_NATIVE_TERRITORY_CAPTURE_V3_' + [guid]::NewGuid().ToString('N') + '.ps1')

function Assert-PowerShellSyntax([string]$Path) {
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if($errors.Count -gt 0){
        $errors | Format-List
        throw 'V3 PATCHED BOOTSTRAP PARSER FAILED - NOTHING EXECUTED'
    }
}

try {
    Write-Host '============================================================'
    Write-Host ' AOTR NATIVE TERRITORY CRASH CAPTURE - V3 COMPILE GATE FIX'
    Write-Host '============================================================'
    Write-Host ("Pinned V2 : {0}" -f $PinnedV2Ref)
    Write-Host ''

    Invoke-WebRequest -UseBasicParsing -Uri "$RepoRaw/$PinnedV2Ref/tools/research/$V2Name" -OutFile $temp
    if((Get-Item -LiteralPath $temp).Length -lt 5000){ throw 'Pinned V2 download looks invalid. NOTHING EXECUTED.' }

    $src = [string](Get-Content -LiteralPath $temp -Raw)
    $old = @'
    $co = (@(& $temp -CompileOnly 2>&1) | Out-String)
    Write-Host $co
    if($co -notmatch 'CRASH_CAPTURE_CLR_SELFTEST_PASS' -or $co -notmatch 'COMPILE_ONLY_COMPLETE - no game process was opened or debugged\.'){
        throw 'CAPTURE COMPILEONLY FAILED - NOTHING EXECUTED'
    }
    Write-Host 'CAPTURE_COMPILEONLY_PASS' -ForegroundColor Green
'@
    $new = @'
    try {
        & $temp -CompileOnly
    }
    catch {
        throw ("CAPTURE COMPILEONLY FAILED - NOTHING EXECUTED. INNER: {0}" -f $_.Exception.Message)
    }
    Write-Host 'CAPTURE_COMPILEONLY_PASS' -ForegroundColor Green
'@

    $matches = [regex]::Matches($src,[regex]::Escape($old)).Count
    if($matches -ne 1){ throw "V3 PATCH CONTRACT FAILED: expected exactly one compile-gate block, found $matches. NOTHING EXECUTED." }
    $patched = $src.Replace($old,$new)

    if($patched -match '\$co\s*=\s*\(@\(& \$temp -CompileOnly 2>&1\)'){
        throw 'V3 STATIC CONTRACT FAILED: stale 2>&1 marker-capture gate remains. NOTHING EXECUTED.'
    }
    if($patched -notmatch "& \$temp -CompileOnly" -or $patched -notmatch 'CAPTURE_COMPILEONLY_PASS'){
        throw 'V3 STATIC CONTRACT FAILED: replacement compile gate missing. NOTHING EXECUTED.'
    }

    Set-Content -LiteralPath $temp -Value $patched -Encoding UTF8
    Assert-PowerShellSyntax $temp

    Write-Host 'V3_COMPILE_GATE_PATCH_PASS' -ForegroundColor Green
    Write-Host 'No game process has been opened/debugged by V3.' -ForegroundColor Green
    Write-Host 'Executing patched gated bootstrap now...' -ForegroundColor Yellow
    Write-Host ''

    & $temp -GameDat $GameDat -TimeoutSeconds $TimeoutSeconds -ResearchRoot $ResearchRoot
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
