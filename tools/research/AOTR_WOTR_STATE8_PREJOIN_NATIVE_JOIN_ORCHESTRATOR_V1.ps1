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

# Controlled one-variable runtime experiment.
# Proven normal ordering:
#   frontendOwner+0x6A4 = 8 -> session->vtable+0x40 -> callback 0x8496C2
#   -> completion 0x84944F -> native publish helper -> DE892C=current.
#
# This tool mutates exactly one pre-existing DWORD before the proven native join call:
#   [ [0x00DE8D90] + 0x6A4 ] : 1 -> 8
#
# It does NOT write DE892C, DE8930, session+0x44, GameInfo, PlayerInfo, or game.dat.
# If the lifecycle does not consume State8 and the exact owner remains live with
# DE892C still NULL, the tool restores only that DWORD from 8 -> 1 after clean detach.

$ExpectedHash      = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$PinnedToolRef     = 'b35d207898ea7e730a8e5d176e8e3e7754f7e923'
$OwnerGlobal       = [uint32]0x00DE8D90
$SessionGlobal     = [uint32]0x00DE4394
$NetworkGlobal     = [uint32]0x00DE892C
$SessionVtable     = [uint32]0x00C54CE0
$GameInfoVtable    = [uint32]0x00C54B78
$OwnerStateOffset  = [uint32]0x000006A4
$Owner304Offset    = [uint32]0x00000304

if ([Environment]::Is64BitProcess) {
    throw 'Run this orchestrator under 32-bit Windows PowerShell: C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
}
if ($ExpectedRemotePort -lt 1 -or $ExpectedRemotePort -gt 65535) { throw 'ExpectedRemotePort must be 1..65535.' }
if ($ObserveSeconds -lt 2 -or $ObserveSeconds -gt 30) { throw 'ObserveSeconds must be 2..30.' }
if ($WatcherTimeoutSeconds -lt 20 -or $WatcherTimeoutSeconds -gt 120) { throw 'WatcherTimeoutSeconds must be 20..120.' }

New-Item -ItemType Directory -Force -Path $ResearchRoot | Out-Null
if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

function F32([uint32]$Value) { return ('0x{0:X8}' -f $Value) }
function Read-TextSafe {
    param([Parameter(Mandatory=$true)][string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { return '' }
    try { return [string](Get-Content -LiteralPath $FilePath -Raw -ErrorAction Stop) } catch { return '' }
}
function Quote-Arg {
    param([Parameter(Mandatory=$true)][string]$Value)
    if ($Value.Contains('"')) { throw "Quote-Arg does not accept embedded double quotes: $Value" }
    return ('"{0}"' -f $Value)
}
function Assert-PowerShellSyntax {
    param([Parameter(Mandatory=$true)][string]$FilePath)
    $tokens=$null
    $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($FilePath,[ref]$tokens,[ref]$parseErrors)
    if ($null -ne $parseErrors -and $parseErrors.Count -gt 0) {
        $text = ($parseErrors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join "`n"
        throw "PowerShell syntax validation failed for $FilePath`n$text"
    }
}
function Stop-ProcSafe {
    param($ProcessObject)
    if ($null -eq $ProcessObject) { return }
    try { if (-not $ProcessObject.HasExited) { $ProcessObject.Kill() } } catch {}
}

$games = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -ieq 'game.dat' -and $_.ExecutablePath -ieq $GameDat
})
if ($games.Count -ne 1) {
    throw "Expected exactly one running game.dat at '$GameDat'. Found $($games.Count)."
}
$GamePid = [int]$games[0].ProcessId

if (-not ('AotrState8PreJoinMem32V1' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class AotrState8PreJoinMem32V1 {
    const uint PROCESS_VM_OPERATION=0x0008;
    const uint PROCESS_VM_READ=0x0010;
    const uint PROCESS_VM_WRITE=0x0020;
    const uint PROCESS_QUERY_INFORMATION=0x0400;
    const uint ACCESS=PROCESS_VM_OPERATION|PROCESS_VM_READ|PROCESS_VM_WRITE|PROCESS_QUERY_INFORMATION;

    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint a,bool i,uint p);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h,IntPtr a,byte[] b,UIntPtr n,out UIntPtr g);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool WriteProcessMemory(IntPtr h,IntPtr a,byte[] b,UIntPtr n,out UIntPtr w);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

    static IntPtr A(uint a){ return new IntPtr(unchecked((int)a)); }
    static Exception E(string what,uint addr){ return new Win32Exception(Marshal.GetLastWin32Error(),what+" at 0x"+addr.ToString("X8")); }

    public static uint Read32(int pid,uint addr){
        IntPtr h=OpenProcess(ACCESS,false,(uint)pid);
        if(h==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error(),"OpenProcess failed");
        try{
            byte[] b=new byte[4]; UIntPtr g;
            if(!ReadProcessMemory(h,A(addr),b,new UIntPtr(4u),out g)||g.ToUInt64()!=4)throw E("ReadProcessMemory failed",addr);
            return BitConverter.ToUInt32(b,0);
        } finally { CloseHandle(h); }
    }

    public static void Write32(int pid,uint addr,uint value){
        IntPtr h=OpenProcess(ACCESS,false,(uint)pid);
        if(h==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error(),"OpenProcess failed");
        try{
            byte[] b=BitConverter.GetBytes(value); UIntPtr w;
            if(!WriteProcessMemory(h,A(addr),b,new UIntPtr(4u),out w)||w.ToUInt64()!=4)throw E("WriteProcessMemory failed",addr);
        } finally { CloseHandle(h); }
    }
}
'@
}

function Read32([uint32]$Address) {
    return [uint32][AotrState8PreJoinMem32V1]::Read32($GamePid,$Address)
}
function Write32([uint32]$Address,[uint32]$Value) {
    [AotrState8PreJoinMem32V1]::Write32($GamePid,$Address,$Value)
}
function Get-LiveState {
    $owner = Read32 $OwnerGlobal
    $state6A4 = if ($owner -ne 0) { Read32 ([uint32]($owner + $OwnerStateOffset)) } else { [uint32]0xFFFFFFFF }
    $owner304 = if ($owner -ne 0) { Read32 ([uint32]($owner + $Owner304Offset)) } else { [uint32]0xFFFFFFFF }
    $session = Read32 $SessionGlobal
    $sessionVt = if ($session -ne 0) { Read32 $session } else { [uint32]0 }
    $state28 = if ($session -ne 0) { Read32 ([uint32]($session + 0x28)) } else { [uint32]0xFFFFFFFF }
    $current = if ($session -ne 0) { Read32 ([uint32]($session + 0x44)) } else { [uint32]0 }
    $currentVt = if ($current -ne 0) { Read32 $current } else { [uint32]0 }
    $net = Read32 $NetworkGlobal
    return [pscustomobject]@{
        Owner=$owner; State6A4=$state6A4; Owner304=$owner304;
        Session=$session; SessionVt=$sessionVt; State28=$state28;
        Current=$current; CurrentVt=$currentVt; Net=$net
    }
}
function Assert-FreshPreJoinState {
    param(
        [Parameter(Mandatory=$true)]$State,
        [uint32]$ExpectedOwner = 0,
        [string]$Stage = 'PREJOIN'
    )
    if ($State.Owner -eq 0) { throw "$Stage failed: [DE8D90] is NULL." }
    if ($ExpectedOwner -ne 0 -and $State.Owner -ne $ExpectedOwner) {
        throw ("{0} failed: frontend owner changed {1} -> {2}." -f $Stage,(F32 $ExpectedOwner),(F32 $State.Owner))
    }
    if ($State.State6A4 -ne 1 -or $State.Owner304 -ne 1) {
        throw "$Stage failed: owner+6A4=$($State.State6A4), owner+304=$($State.Owner304), expected 1/1."
    }
    if ($State.Session -eq 0 -or $State.SessionVt -ne $SessionVtable) {
        throw ("{0} failed: session={1}, vtable={2}, expected vtable={3}." -f $Stage,(F32 $State.Session),(F32 $State.SessionVt),(F32 $SessionVtable))
    }
    if ($State.State28 -ne 0 -and $State.State28 -ne 2) {
        throw "$Stage failed: session+0x28=$($State.State28), expected 0 or 2."
    }
    if ($State.Current -ne 0) { throw ("{0} failed: session+0x44 already non-NULL ({1})." -f $Stage,(F32 $State.Current)) }
    if ($State.Net -ne 0) { throw ("{0} failed: DE892C already non-NULL ({1})." -f $Stage,(F32 $State.Net)) }
}

Write-Host '============================================================'
Write-Host ' AOTR WOTR STATE8 PRE-JOIN -> NATIVE +0x40 ORCHESTRATOR V1'
Write-Host '============================================================'
Write-Host ("PID              : {0}" -f $GamePid)
Write-Host ("Image            : {0}" -f $GameDat)
Write-Host ("SHA256           : {0}" -f $hash)
Write-Host ("Expected host    : {0}:{1}" -f $ExpectedRemoteIp,$ExpectedRemotePort)
Write-Host ("Pinned tool ref  : {0}" -f $PinnedToolRef)
Write-Host 'Authorized write : exactly frontendOwner+0x6A4, 1 -> 8'
Write-Host 'Forbidden writes : DE892C, DE8930, session+0x44, GameInfo, PlayerInfo'
Write-Host ''

$initial = Get-LiveState
Assert-FreshPreJoinState -State $initial -Stage 'INITIAL_PREJOIN'
$Owner = [uint32]$initial.Owner
$StateAddr = [uint32]($Owner + $OwnerStateOffset)
Write-Host ("OWNER_LOCATOR_PASS [DE8D90]={0}" -f (F32 $Owner)) -ForegroundColor Green
Write-Host ("Owner+0x6A4      : {0} = 1" -f (F32 $StateAddr))
Write-Host ("Owner+0x304      : 1")
Write-Host ("Session          : {0} vt={1}" -f (F32 $initial.Session),(F32 $initial.SessionVt))
Write-Host 'Current          : NULL'
Write-Host 'DE892C           : NULL'
Write-Host ''

$baseRaw = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/' + $PinnedToolRef + '/tools/research/'
$watchPath   = Join-Path $ResearchRoot 'AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V5.ps1'
$joinPath    = Join-Path $ResearchRoot 'AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1'
$wrapperPath = Join-Path $ResearchRoot 'AOTR_WOTR_NATIVE_JOIN_CALL_POC_PS51_WRAPPER.ps1'

function Download-Tool {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$Destination)
    Invoke-WebRequest -UseBasicParsing -Uri ($baseRaw + $Name) -OutFile $Destination
    $item = Get-Item -LiteralPath $Destination -ErrorAction Stop
    if ($item.Length -lt 100) { throw "Downloaded tool looks invalid: $Name len=$($item.Length)" }
    Assert-PowerShellSyntax -FilePath $Destination
}

Download-Tool -Name 'AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V5.ps1' -Destination $watchPath
Download-Tool -Name 'AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1' -Destination $joinPath
Download-Tool -Name 'AOTR_WOTR_NATIVE_JOIN_CALL_POC_PS51_WRAPPER.ps1' -Destination $wrapperPath
Write-Host 'PINNED_TOOLS_DOWNLOAD_AND_SYNTAX_PASS' -ForegroundColor Green

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$clrOut    = Join-Path $ResearchRoot "STATE8_PREJOIN_CLR_$stamp.out.txt"
$clrErr    = Join-Path $ResearchRoot "STATE8_PREJOIN_CLR_$stamp.err.txt"
$readyFile = Join-Path $ResearchRoot "STATE8_PREJOIN_READY_$stamp.txt"
$stopFile  = Join-Path $ResearchRoot "STATE8_PREJOIN_STOP_$stamp.txt"
$statusFile= Join-Path $ResearchRoot "STATE8_PREJOIN_STATUS_$stamp.txt"
$watchOut  = Join-Path $ResearchRoot "STATE8_PREJOIN_WATCH_$stamp.out.txt"
$watchErr  = Join-Path $ResearchRoot "STATE8_PREJOIN_WATCH_$stamp.err.txt"
$preOut    = Join-Path $ResearchRoot "STATE8_PREJOIN_PREFLIGHT_$stamp.txt"
$pre2Out   = Join-Path $ResearchRoot "STATE8_PREJOIN_PREFLIGHT2_$stamp.txt"
$joinOut   = Join-Path $ResearchRoot "STATE8_PREJOIN_JOIN_$stamp.txt"
$resultFile= Join-Path $ResearchRoot "STATE8_PREJOIN_RESULT_$stamp.txt"
foreach ($f in @($clrOut,$clrErr,$readyFile,$stopFile,$statusFile,$watchOut,$watchErr,$preOut,$pre2Out,$joinOut,$resultFile)) {
    Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
}

$ps32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $ps32)) { throw "32-bit Windows PowerShell not found: $ps32" }

Write-Host 'PHASE 1/6 - watcher CLR compile/layout selftest...'
$clrArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-Arg $watchPath),'-CompileOnly')
$clrProc = Start-Process -FilePath $ps32 -ArgumentList $clrArgs -WindowStyle Hidden -RedirectStandardOutput $clrOut -RedirectStandardError $clrErr -PassThru
if (-not $clrProc.WaitForExit(15000)) {
    Stop-ProcSafe $clrProc
    throw 'WATCHER_CLR_SELFTEST_TIMEOUT. No debugger/join/state write was attempted.'
}
$clrText = Read-TextSafe $clrOut
$clrErrText = Read-TextSafe $clrErr
$layoutExpected = 'CLR_LAYOUT_SELFTEST_PASS DEBUG_EVENT_SIZE=96 HTHREAD_OFFSET=12 EXADDR_OFFSET=24'
if ($clrText -notmatch [regex]::Escape($layoutExpected) -or $clrText -notmatch 'COMPILE_ONLY_COMPLETE') {
    throw ("WATCHER_CLR_SELFTEST_FAILED. No debugger/join/state write was attempted.`n--- OUT ---`n{0}`n--- ERR ---`n{1}" -f $clrText,$clrErrText)
}
Write-Host $layoutExpected -ForegroundColor Green

Write-Host 'PHASE 2/6 - native join DRY-RUN preflight...'
$preInvoke = @{
    SourcePath=$joinPath; ProcessId=$GamePid; ExpectedRemoteIp=$ExpectedRemoteIp;
    ExpectedRemotePort=$ExpectedRemotePort; ObserveSeconds=$ObserveSeconds
}
$preLines = @(& $wrapperPath @preInvoke 6>&1 2>&1)
$preText = ($preLines | Out-String)
Set-Content -LiteralPath $preOut -Value $preText -Encoding UTF8
if ($preText -notmatch 'CALL_POC_READY = YES') {
    throw ("NATIVE_JOIN_PREFLIGHT_FAILED. No debugger/join/state write was attempted.`n{0}" -f $preText)
}
Write-Host 'NATIVE_JOIN_PREFLIGHT_PASS' -ForegroundColor Green

Write-Host 'PHASE 3/6 - attach proven V5 watcher and arm all threads...'
$watchArgs = @(
    '-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-Arg $watchPath),
    '-ProcessId',[string]$GamePid,
    '-GameDat',(Quote-Arg $GameDat),
    '-TimeoutSeconds',[string]$WatcherTimeoutSeconds,
    '-ReadyFile',(Quote-Arg $readyFile),
    '-StopFile',(Quote-Arg $stopFile),
    '-StatusFile',(Quote-Arg $statusFile)
)
$watchProc = $null
$watchClean = $false
$stateIssued = $false
$stateRestored = $false
$joinReturned = $false
try {
    $watchProc = Start-Process -FilePath $ps32 -ArgumentList $watchArgs -WindowStyle Hidden -RedirectStandardOutput $watchOut -RedirectStandardError $watchErr -PassThru
    Write-Host ("WATCHER_STARTED PID={0}" -f $watchProc.Id)

    $readyDeadline = [DateTime]::UtcNow.AddSeconds(10)
    $armed = 0
    $readyText = ''
    while ([DateTime]::UtcNow -lt $readyDeadline) {
        Start-Sleep -Milliseconds 25
        $readyText = Read-TextSafe $readyFile
        if ($readyText -match 'STATUS=READY' -and $readyText -match 'ARMED_THREADS=(\d+)') {
            $armed = [int]$Matches[1]
            if ($armed -gt 0) { break }
        }
        if ($readyText -match 'STATUS=FAIL' -or $watchProc.HasExited) { break }
    }
    if ($armed -le 0) {
        throw ("WATCHER_READY_FAILED. No state write/join attempted.`nREADY={0}`nSTATUS={1}`nOUT={2}`nERR={3}" -f $readyText,(Read-TextSafe $statusFile),(Read-TextSafe $watchOut),(Read-TextSafe $watchErr))
    }
    Write-Host ("WATCHER_READY ARMED_THREADS={0}" -f $armed) -ForegroundColor Green

    Write-Host 'PHASE 4/6 - revalidate full pre-join contract after watcher READY...'
    $pre2Lines = @(& $wrapperPath @preInvoke 6>&1 2>&1)
    $pre2Text = ($pre2Lines | Out-String)
    Set-Content -LiteralPath $pre2Out -Value $pre2Text -Encoding UTF8
    if ($pre2Text -notmatch 'CALL_POC_READY = YES') {
        throw ("SECOND_NATIVE_JOIN_PREFLIGHT_FAILED. No state write/join attempted.`n{0}" -f $pre2Text)
    }
    $preWrite = Get-LiveState
    Assert-FreshPreJoinState -State $preWrite -ExpectedOwner $Owner -Stage 'PREWRITE_REVALIDATION'
    Write-Host 'PREWRITE_CONTRACT_PASS' -ForegroundColor Green

    Write-Host 'PHASE 5/6 - write State8 and immediately execute exactly one native +0x40 join...'
    Write32 $StateAddr ([uint32]8)
    $stateIssued = $true
    $postWrite = Read32 $StateAddr
    if ($postWrite -ne 8) {
        throw "STATE8_WRITE_READBACK_FAILED: readback=$postWrite"
    }
    Write-Host 'STATE8_WRITE_API_PASS 1 -> 8; readback=8' -ForegroundColor Green

    # Do not start another shell here: execute in this already-running 32-bit PS5.1 process
    # to minimize the interval between the one authorized state write and session->+0x40.
    $joinInvoke = @{
        SourcePath=$joinPath; ProcessId=$GamePid; ExpectedRemoteIp=$ExpectedRemoteIp;
        ExpectedRemotePort=$ExpectedRemotePort; ObserveSeconds=$ObserveSeconds; Execute=$true
    }
    $joinLines = @(& $wrapperPath @joinInvoke 6>&1 2>&1)
    $joinText = ($joinLines | Out-String)
    Set-Content -LiteralPath $joinOut -Value $joinText -Encoding UTF8
    Write-Host $joinText
    if ($joinText -notmatch 'NATIVE \+0x40 CALL RETURNED = YES') {
        throw 'Native +0x40 wrapper returned without the expected CALL RETURNED marker.'
    }
    $joinReturned = $true

    Start-Sleep -Milliseconds 1000

    Write-Host 'PHASE 6/6 - clean watcher disarm/detach...'
    Set-Content -LiteralPath $stopFile -Value 'STOP=1' -Encoding ASCII
    if (-not $watchProc.WaitForExit(10000)) {
        throw ("WATCHER_TEARDOWN_TIMEOUT. Restart game.dat before another debugger test. STATUS={0}" -f (Read-TextSafe $statusFile))
    }
    $statusText = Read-TextSafe $statusFile
    if ($statusText -notmatch 'CLEAN_DETACH=YES') {
        throw ("WATCHER_DID_NOT_CONFIRM_CLEAN_DETACH. Restart game.dat before another debugger test.`n{0}" -f $statusText)
    }
    $watchClean = $true
    Write-Host 'WATCHER_CLEAN_EXIT=YES' -ForegroundColor Green
}
finally {
    if ($null -ne $watchProc -and -not $watchProc.HasExited) {
        try { Set-Content -LiteralPath $stopFile -Value 'STOP=1' -Encoding ASCII -ErrorAction SilentlyContinue } catch {}
        try { [void]$watchProc.WaitForExit(7000) } catch {}
    }

    # Safe rollback is deliberately narrow. Only restore if:
    # - our State8 write happened,
    # - the exact same frontend owner is still published,
    # - native publication did not happen,
    # - lifecycle left the field stuck at exactly 8.
    if ($stateIssued) {
        try {
            $ownerNow = Read32 $OwnerGlobal
            $netNow = Read32 $NetworkGlobal
            if ($ownerNow -eq $Owner) {
                $stateNow = Read32 $StateAddr
                if ($stateNow -eq 8 -and $netNow -eq 0) {
                    Write32 $StateAddr ([uint32]1)
                    $restoreReadback = Read32 $StateAddr
                    if ($restoreReadback -eq 1) {
                        $stateRestored = $true
                        Write-Host 'SAFE_FAILURE_RESTORE_VERIFIED 8 -> 1' -ForegroundColor Yellow
                    }
                }
            }
        } catch {
            Write-Host ("SAFE_RESTORE_NOT_CONFIRMED: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        }
    }
}

$watchText = Read-TextSafe $watchOut
$watchErrText = Read-TextSafe $watchErr
$final = Get-LiveState

# Parse callback/completion records event-locally. Do not use global owner regexes over
# repeated diagnostic snapshots; a state line is bound only to its immediately pending hit.
$callbackRecords = @()
$completionRecords = @()
$pendingCallback = $false
$pendingCompletion = $false
foreach ($line in ($watchText -split "`r?`n")) {
    if ($line -eq 'CALLBACK_8496C2_HIT=YES') { $pendingCallback = $true; continue }
    if ($line -eq 'COMPLETION_84944F_HIT=YES') { $pendingCompletion = $true; continue }
    $m = [regex]::Match($line,'^ECX_OWNER=(0x[0-9A-Fa-f]{8}) OWNER_6A4=(\d+) OWNER_304=(\d+) CURRENT_IS_C54B78=(YES|NO)$')
    if ($m.Success) {
        $record = [pscustomobject]@{
            Owner=$m.Groups[1].Value.ToUpperInvariant()
            State=[int]$m.Groups[2].Value
            Owner304=[int]$m.Groups[3].Value
            CurrentIsC54=$m.Groups[4].Value
        }
        if ($pendingCallback) { $callbackRecords += $record }
        if ($pendingCompletion) { $completionRecords += $record }
        $pendingCallback = $false
        $pendingCompletion = $false
    }
}

$callbackHits = $callbackRecords.Count
$completionHits = $completionRecords.Count
$callbackState8 = @($callbackRecords | Where-Object {
    $_.Owner -eq (F32 $Owner) -and $_.State -eq 8 -and $_.Owner304 -eq 1
}).Count
$completionAtState8 = @($completionRecords | Where-Object {
    $_.Owner -eq (F32 $Owner) -and $_.State -eq 8
}).Count
$currentC54 = ($final.Current -ne 0 -and $final.CurrentVt -eq $GameInfoVtable)
$published = ($currentC54 -and $final.Net -eq $final.Current)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('============================================================')
$lines.Add(' AOTR WOTR STATE8 PRE-JOIN NATIVE JOIN - FINAL VERDICT')
$lines.Add('============================================================')
$lines.Add(('Game PID                    : {0}' -f $GamePid))
$lines.Add(('Frontend owner              : {0}' -f (F32 $Owner)))
$lines.Add(('STATE8_WRITE_ISSUED         : {0}' -f ($(if($stateIssued){'YES'}else{'NO'}))))
$lines.Add(('JOIN_RETURNED               : {0}' -f ($(if($joinReturned){'YES'}else{'NO'}))))
$lines.Add(('WATCHER_CLEAN_EXIT          : {0}' -f ($(if($watchClean){'YES'}else{'NO'}))))
$lines.Add(('CALLBACK_8496C2_HIT_COUNT   : {0}' -f $callbackHits))
$lines.Add(('CALLBACK_AT_OWNER_STATE8    : {0}' -f $callbackState8))
$lines.Add(('COMPLETION_84944F_HIT_COUNT : {0}' -f $completionHits))
$lines.Add(('COMPLETION_AT_OWNER_STATE8  : {0}' -f $completionAtState8))
$lines.Add(('CURRENT_AFTER               : {0}' -f (F32 $final.Current)))
$lines.Add(('CURRENT_VTABLE_AFTER        : {0}' -f (F32 $final.CurrentVt)))
$lines.Add(('DE892C_AFTER                : {0}' -f (F32 $final.Net)))
$lines.Add(('OWNER_6A4_AFTER             : {0}' -f $final.State6A4))
$lines.Add(('OWNER_304_AFTER             : {0}' -f $final.Owner304))
$lines.Add(('CURRENT_C54B78              : {0}' -f ($(if($currentC54){'YES'}else{'NO'}))))
$lines.Add(('DE892C_EQUALS_CURRENT       : {0}' -f ($(if($published){'YES'}else{'NO'}))))
$lines.Add(('FAILURE_STATE_RESTORED      : {0}' -f ($(if($stateRestored){'YES'}else{'NO'}))))
$lines.Add('')

if ($callbackState8 -gt 0 -and $completionHits -gt 0 -and $published) {
    $lines.Add('STATE8_PREJOIN_CAUSAL_RESULT = PASS')
    $lines.Add('CLASSIFICATION = State8-before-native-join was sufficient for callback completion and native DE892C publication in this run.')
}
elseif ($callbackState8 -gt 0 -and $completionHits -eq 0) {
    $lines.Add('STATE8_PREJOIN_CAUSAL_RESULT = PARTIAL_CALLBACK_STATE8_NO_COMPLETION')
    $lines.Add('CLASSIFICATION = State8 reached the callback, but another completion prerequisite remains.')
}
elseif ($callbackHits -gt 0 -and $callbackState8 -eq 0) {
    $lines.Add('STATE8_PREJOIN_CAUSAL_RESULT = CALLBACK_OVERWROTE_OR_MISSED_STATE8')
    $lines.Add('CLASSIFICATION = Join lifecycle callback ran, but no callback-bound record observed owner State8.')
}
elseif ($joinReturned -and $callbackHits -eq 0) {
    $lines.Add('STATE8_PREJOIN_CAUSAL_RESULT = JOIN_RETURNED_NO_CALLBACK')
    $lines.Add('CLASSIFICATION = Native +0x40 returned, but the expected frontend callback did not execute in the observation window.')
}
else {
    $lines.Add('STATE8_PREJOIN_CAUSAL_RESULT = INCONCLUSIVE')
    $lines.Add('CLASSIFICATION = Required runtime markers were incomplete; do not infer sufficiency.')
}

$resultText = $lines -join "`r`n"
Set-Content -LiteralPath $resultFile -Value $resultText -Encoding UTF8
Write-Host ''
Write-Host $resultText
Write-Host ''
Write-Host ("RESULT_FILE : {0}" -f $resultFile)
Write-Host ("WATCH_LOG   : {0}" -f $watchOut)
Write-Host ("JOIN_LOG    : {0}" -f $joinOut)
if (-not [string]::IsNullOrWhiteSpace($watchErrText)) {
    Write-Host 'WATCHER STDERR was non-empty:' -ForegroundColor Yellow
    Write-Host $watchErrText
}
