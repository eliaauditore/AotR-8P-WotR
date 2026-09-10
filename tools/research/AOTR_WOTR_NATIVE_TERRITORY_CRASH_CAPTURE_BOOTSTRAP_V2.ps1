param(
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [int]$TimeoutSeconds = 90,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PinnedCaptureRef = 'e794e6b86d5f04a58673ff32394b1d6bccdcd3ef'
$CaptureName = 'AOTR_WOTR_NATIVE_TERRITORY_ILLEGAL_INSTRUCTION_CRASH_CAPTURE_V1.ps1'
$RepoRaw = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR'
$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'

$OwnerGlobal   = [uint32]0x00DE8D90
$SessionGlobal = [uint32]0x00DE4394
$NetworkGlobal = [uint32]0x00DE892C
$SessionVtable = [uint32]0x00C54CE0
$GameInfoVt    = [uint32]0x00C54B78

if ([Environment]::Is64BitProcess) {
    throw 'Run under 32-bit Windows PowerShell: C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
}

New-Item -ItemType Directory -Path $ResearchRoot -Force | Out-Null
$temp = Join-Path $env:TEMP ('AOTR_NATIVE_TERRITORY_CAPTURE_' + [guid]::NewGuid().ToString('N') + '.ps1')

function Assert-PowerShellSyntax([string]$Path) {
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if($errors.Count -gt 0){
        $errors | Format-List
        throw 'CAPTURE PARSER FAILED - NOTHING EXECUTED'
    }
}

try {
    Write-Host '============================================================'
    Write-Host ' AOTR NATIVE TERRITORY CRASH CAPTURE - GATED BOOTSTRAP V2'
    Write-Host '============================================================'
    Write-Host ("Pinned capture : {0}" -f $PinnedCaptureRef)
    Write-Host ''

    Invoke-WebRequest -UseBasicParsing -Uri "$RepoRaw/$PinnedCaptureRef/tools/research/$CaptureName" -OutFile $temp
    if((Get-Item -LiteralPath $temp).Length -lt 8000){throw 'Capture download looks invalid. NOTHING EXECUTED.'}
    Assert-PowerShellSyntax $temp

    $src=[string](Get-Content -LiteralPath $temp -Raw)
    foreach($forbidden in @(
        'static extern bool WriteProcessMemory',
        'static extern bool SetThreadContext',
        'CreateRemoteThread',
        'VirtualAllocEx',
        'Dr0=',
        'Dr1='
    )){
        if($src.Contains($forbidden)){throw "STATIC SAFETY CONTRACT FAILED: forbidden token [$forbidden]. NOTHING EXECUTED."}
    }
    foreach($required in @(
        'DebugActiveProcess',
        'EXCEPTION_ILLEGAL_INSTRUCTION=0xC000001D',
        'DBG_EXCEPTION_NOT_HANDLED',
        'FAULT_REGION_BASE=',
        'STACK_GAME_PTR_COUNT='
    )){
        if(-not $src.Contains($required)){throw "STATIC CAPTURE CONTRACT FAILED: missing [$required]. NOTHING EXECUTED."}
    }
    Write-Host 'STATIC_NO_GAME_WRITE_NO_HW_BREAKPOINT_CONTRACT_PASS' -ForegroundColor Green

    $co = (@(& $temp -CompileOnly 2>&1) | Out-String)
    Write-Host $co
    if($co -notmatch 'CRASH_CAPTURE_CLR_SELFTEST_PASS' -or $co -notmatch 'COMPILE_ONLY_COMPLETE - no game process was opened or debugged\.'){
        throw 'CAPTURE COMPILEONLY FAILED - NOTHING EXECUTED'
    }
    Write-Host 'CAPTURE_COMPILEONLY_PASS' -ForegroundColor Green
    Write-Host 'No game process has been opened/debugged by the capture tool yet.' -ForegroundColor Green
    Write-Host ''

    if(-not(Test-Path -LiteralPath $GameDat -PathType Leaf)){throw "game.dat not found: $GameDat"}
    $hash=(Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
    if($hash-ne$ExpectedHash){throw "HASH MISMATCH. Expected $ExpectedHash, got $hash"}

    $games=@(Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'game.dat' -and $_.ExecutablePath -ieq $GameDat })
    if($games.Count-ne 1){throw "Expected exactly one game.dat at '$GameDat'. Found $($games.Count)."}
    $GamePid=[int]$games[0].ProcessId

    if(-not('AotrTerritoryCapturePreflightV2' -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class AotrTerritoryCapturePreflightV2 {
    const uint PROCESS_VM_READ=0x0010, PROCESS_QUERY_INFORMATION=0x0400;
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint a,bool i,uint p);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h,IntPtr a,byte[] b,UIntPtr n,out UIntPtr g);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    public static uint R(int pid,uint addr){
        IntPtr h=OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION,false,(uint)pid);
        if(h==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error(),"OpenProcess failed");
        try{
            byte[] b=new byte[4]; UIntPtr g;
            if(!ReadProcessMemory(h,new IntPtr(unchecked((int)addr)),b,new UIntPtr(4u),out g)||g.ToUInt64()!=4)throw new Win32Exception(Marshal.GetLastWin32Error(),"ReadProcessMemory failed at 0x"+addr.ToString("X8"));
            return BitConverter.ToUInt32(b,0);
        }finally{CloseHandle(h);}
    }
}
'@
    }
    function R32([uint32]$a){[uint32][AotrTerritoryCapturePreflightV2]::R($GamePid,$a)}
    function F32([uint32]$v){'0x{0:X8}' -f $v}

    $owner=R32 $OwnerGlobal
    $session=R32 $SessionGlobal
    $net=R32 $NetworkGlobal
    if($owner-eq 0){throw 'NATIVE_JOIN_PREFLIGHT_FAIL: frontend owner NULL.'}
    if($session-eq 0){throw 'NATIVE_JOIN_PREFLIGHT_FAIL: session NULL.'}
    $sessionVt=R32 $session
    $current=R32 ([uint32]($session+0x44))
    $currentVt=if($current-ne 0){R32 $current}else{[uint32]0}
    $state=R32 ([uint32]($owner+0x6A4))
    $flags=R32 ([uint32]($owner+0x6BC))
    $owner304=R32 ([uint32]($owner+0x304))

    Write-Host '================ NORMAL UI-JOIN PREFLIGHT ================'
    Write-Host ("PID              : {0}" -f $GamePid)
    Write-Host ("owner            : {0}" -f (F32 $owner))
    Write-Host ("owner+0x6A4     : {0}" -f $state)
    Write-Host ("owner+0x304     : {0}" -f $owner304)
    Write-Host ("owner+0x6BC     : {0} lowerBits={1}" -f (F32 $flags),($flags-band 3))
    Write-Host ("session          : {0} vt={1}" -f (F32 $session),(F32 $sessionVt))
    Write-Host ("current          : {0} vt={1}" -f (F32 $current),(F32 $currentVt))
    Write-Host ("DE892C           : {0}" -f (F32 $net))

    if($sessionVt-ne$SessionVtable){throw 'NATIVE_JOIN_PREFLIGHT_FAIL: session vtable mismatch.'}
    if($current-eq 0 -or $currentVt-ne$GameInfoVt){throw 'NATIVE_JOIN_PREFLIGHT_FAIL: current is not C54B78 GameInfo.'}
    if($net-ne$current){throw 'NATIVE_JOIN_PREFLIGHT_FAIL: DE892C != current.'}
    if($state-ne 9){throw "NATIVE_JOIN_PREFLIGHT_FAIL: owner+0x6A4=$state, expected 9."}
    if(($flags-band 3)-ne 0){throw 'NATIVE_JOIN_PREFLIGHT_FAIL: Create/Join enable bits are not cleared.'}
    if($owner304-ne 1){throw "NATIVE_JOIN_PREFLIGHT_FAIL: owner+0x304=$owner304, expected 1."}

    Write-Host 'NORMAL_UI_JOIN_SHAPE_PASS' -ForegroundColor Green
    Write-Host 'Entering exception observer now; still no game-state writes.' -ForegroundColor Yellow
    Write-Host ''

    & $temp -ProcessId $GamePid -GameDat $GameDat -TimeoutSeconds $TimeoutSeconds -ResearchRoot $ResearchRoot
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
