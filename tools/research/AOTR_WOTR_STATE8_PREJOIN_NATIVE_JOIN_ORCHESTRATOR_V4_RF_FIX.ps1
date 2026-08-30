param(
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [string]$ExpectedRemoteIp = '192.168.0.224',
    [int]$ExpectedRemotePort = 8086,
    [int]$ObserveSeconds = 8,
    [int]$WatcherTimeoutSeconds = 45,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# V4 bootstrap for the controlled State8-before-native-join experiment.
# It reuses the already-reviewed V2 orchestration body, but makes only these
# deterministic bootstrap substitutions before execution:
#   1) PS5.1 parser fix: exactly three literal $Stage: -> ${Stage}:
#   2) pin helper tools to the RF-safe watcher commit
#   3) replace watcher V5 filename with V6_RF filename
# Before the patched V2 is allowed to inspect the game process, this bootstrap
# independently downloads/parses/CompileOnly-tests V6 under 32-bit PS5.1 and
# requires both DEBUG_EVENT layout and EFLAGS.RF resume-policy selftests.

$PinnedV2Ref      = 'f138807b0b2eeed313a18b917465c8cd1f894210'
$PinnedToolRef    = '2d19e3a6cb3d422b08b0541b397798a847c264c6'
$OldToolRef       = 'b35d207898ea7e730a8e5d176e8e3e7754f7e923'
$V2Name           = 'AOTR_WOTR_STATE8_PREJOIN_NATIVE_JOIN_ORCHESTRATOR_V2.ps1'
$OldWatcherName   = 'AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V5.ps1'
$NewWatcherName   = 'AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V6_RF.ps1'
$RepoRaw          = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR'

if ([Environment]::Is64BitProcess) {
    throw 'Run under 32-bit Windows PowerShell: C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
}

New-Item -ItemType Directory -Path $ResearchRoot -Force | Out-Null
$ps32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $ps32 -PathType Leaf)) { throw "Missing $ps32" }

function Assert-PowerShellSyntax {
    param([Parameter(Mandatory=$true)][string]$FilePath)
    $tokens=$null
    $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($FilePath,[ref]$tokens,[ref]$errors)
    if ($null -ne $errors -and $errors.Count -gt 0) {
        $detail = ($errors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join "`n"
        throw "PARSER_FAILED for $FilePath - NOTHING EXECUTED.`n$detail"
    }
}
function Read-TextSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    try { return [string](Get-Content -LiteralPath $Path -Raw -ErrorAction Stop) } catch { return '' }
}
function Quote-Arg([string]$Value) {
    if ($Value.Contains('"')) { throw "Quote-Arg rejects embedded quotes: $Value" }
    return ('"{0}"' -f $Value)
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$tempV2 = Join-Path $env:TEMP ("AOTR_STATE8_PREJOIN_V4_BODY_$stamp.ps1")
$tempWatcher = Join-Path $env:TEMP ("AOTR_STATE8_WATCH_V6_RF_$stamp.ps1")
$co = Join-Path $ResearchRoot ("STATE8_V6_RF_COMPILEONLY_$stamp.out.txt")
$ce = Join-Path $ResearchRoot ("STATE8_V6_RF_COMPILEONLY_$stamp.err.txt")

try {
    Write-Host '============================================================'
    Write-Host ' AOTR STATE8 PREJOIN V4 - RF-SAFE WATCHER BOOTSTRAP'
    Write-Host '============================================================'
    Write-Host ("Pinned V2 body : {0}" -f $PinnedV2Ref)
    Write-Host ("Pinned tools   : {0}" -f $PinnedToolRef)
    Write-Host ("Watcher        : {0}" -f $NewWatcherName)
    Write-Host ''

    # Gate 0: obtain and validate V6 without touching any game process.
    $watchUrl = "$RepoRaw/$PinnedToolRef/tools/research/$NewWatcherName"
    Invoke-WebRequest -UseBasicParsing -Uri $watchUrl -OutFile $tempWatcher
    if ((Get-Item -LiteralPath $tempWatcher).Length -lt 5000) { throw 'V6 watcher download looks invalid. NOTHING EXECUTED.' }
    Assert-PowerShellSyntax $tempWatcher

    $watchSrc = [string](Get-Content -LiteralPath $tempWatcher -Raw)
    foreach ($marker in @(
        'const uint RF=0x00010000u;',
        'c.EFlags|=RF;',
        'HW_RESUME_RF_SELFTEST_PASS',
        'AotrDualExec32V6RF'
    )) {
        if (-not $watchSrc.Contains($marker)) { throw "V6_STATIC_RF_CONTRACT_FAILED missing [$marker]. NOTHING EXECUTED." }
    }
    Write-Host 'V6_STATIC_RF_CONTRACT_PASS' -ForegroundColor Green

    Remove-Item -LiteralPath $co,$ce -Force -ErrorAction SilentlyContinue
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-Arg $tempWatcher),'-CompileOnly')
    $p = Start-Process -FilePath $ps32 -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $co -RedirectStandardError $ce -PassThru
    if (-not $p.WaitForExit(15000)) { try{$p.Kill()}catch{}; throw 'V6_COMPILEONLY_TIMEOUT. NOTHING EXECUTED.' }
    $cot = Read-TextSafe $co
    $cet = Read-TextSafe $ce
    if ($p.ExitCode -ne 0 -or
        $cot -notmatch 'CLR_LAYOUT_SELFTEST_PASS DEBUG_EVENT_SIZE=96 HTHREAD_OFFSET=12 EXADDR_OFFSET=24' -or
        $cot -notmatch 'HW_RESUME_RF_SELFTEST_PASS DR6=0 RF=YES EFLAGS=0x[0-9A-F]{8}' -or
        $cot -notmatch 'COMPILE_ONLY_COMPLETE') {
        throw ("V6_COMPILEONLY_FAILED. NOTHING EXECUTED.`nOUT:`n{0}`nERR:`n{1}" -f $cot,$cet)
    }
    Write-Host 'V6_COMPILEONLY_PASS - DEBUG_EVENT + RF RESUME POLICY' -ForegroundColor Green
    Write-Host 'No game process has been opened/debugged by this bootstrap.' -ForegroundColor Green
    Write-Host ''

    # Prepare exact reviewed V2 body with narrowly-scoped deterministic substitutions.
    $v2Url = "$RepoRaw/$PinnedV2Ref/tools/research/$V2Name"
    $src = [string](Invoke-WebRequest -UseBasicParsing -Uri $v2Url).Content
    if ([string]::IsNullOrWhiteSpace($src) -or $src.Length -lt 10000) { throw "Pinned V2 download looks invalid. Length=$($src.Length)" }

    $stageCount = ([regex]::Matches($src,[regex]::Escape('$Stage:'))).Count
    if ($stageCount -ne 3) { throw "V2 parser source contract failed: expected 3 literal `$Stage:, found $stageCount." }
    $src = $src.Replace('$Stage:','${Stage}:')

    $refNeedle = "`$PinnedToolRef     = '$OldToolRef'"
    $refReplace = "`$PinnedToolRef     = '$PinnedToolRef'"
    $refCount = ([regex]::Matches($src,[regex]::Escape($refNeedle))).Count
    if ($refCount -ne 1) { throw "V2 tool-ref contract failed: expected 1 old pin, found $refCount." }
    $src = $src.Replace($refNeedle,$refReplace)

    $watchCount = ([regex]::Matches($src,[regex]::Escape($OldWatcherName))).Count
    if ($watchCount -ne 2) { throw "V2 watcher-name contract failed: expected 2 V5 tokens, found $watchCount." }
    $src = $src.Replace($OldWatcherName,$NewWatcherName)

    if ($src.Contains('$Stage:')) { throw 'V2 parser fix incomplete.' }
    if ($src.Contains($OldToolRef)) { throw 'V2 still contains old tool pin.' }
    if ($src.Contains($OldWatcherName)) { throw 'V2 still contains V5 watcher name.' }
    foreach ($required in @(
        $PinnedToolRef,
        $NewWatcherName,
        'Write32 $StateAddr ([uint32]8)',
        'SAFE_FAILURE_RESTORE_VERIFIED 8->1',
        'DE892C_EQUALS_CURRENT'
    )) {
        if (-not $src.Contains($required)) { throw "PATCHED_V2_STATIC_CONTRACT_FAILED missing [$required]." }
    }
    foreach ($forbidden in @('Write32 $NetworkGlobal','Write32 $SessionGlobal','Write32 $OwnerGlobal')) {
        if ($src.Contains($forbidden)) { throw "PATCHED_V2_STATIC_CONTRACT_FAILED forbidden write [$forbidden]." }
    }

    Set-Content -LiteralPath $tempV2 -Value $src -Encoding UTF8
    Assert-PowerShellSyntax $tempV2
    Write-Host 'PATCHED_V2_PARSER_AND_STATIC_CONTRACT_PASS' -ForegroundColor Green
    Write-Host 'Entering controlled runtime experiment only now...' -ForegroundColor Yellow
    Write-Host ''

    $invoke = @{
        GameDat               = [string]$GameDat
        ExpectedRemoteIp      = [string]$ExpectedRemoteIp
        ExpectedRemotePort    = [int]$ExpectedRemotePort
        ObserveSeconds        = [int]$ObserveSeconds
        WatcherTimeoutSeconds = [int]$WatcherTimeoutSeconds
        ResearchRoot          = [string]$ResearchRoot
    }
    & $tempV2 @invoke
}
finally {
    Remove-Item -LiteralPath $tempV2,$tempWatcher -Force -ErrorAction SilentlyContinue
}
