param(
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY. Fresh-process runtime validation for frontend owner global 0x00DE8D90.
# No WriteProcessMemory import exists.

$ExpectedHash   = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$OwnerGlobal    = [uint32]0x00DE8D90
$SessionGlobal  = [uint32]0x00DE4394
$NetworkGlobal  = [uint32]0x00DE892C
$SessionVtable  = [uint32]0x00C54CE0
$GameInfoVtable = [uint32]0x00C54B78

if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash=(Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if($hash -ne $ExpectedHash){throw "HASH MISMATCH. Expected $ExpectedHash got $hash"}

$games=@(Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'game.dat' -and $_.ExecutablePath -ieq $GameDat })
if($games.Count -ne 1){throw "Expected exactly one game.dat at '$GameDat', found $($games.Count)."}
$GamePid=[int]$games[0].ProcessId

if (-not ('AotrOwnerGlobalReadOnly' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class AotrOwnerGlobalReadOnly {
    const uint PROCESS_VM_READ=0x0010, PROCESS_QUERY_INFORMATION=0x0400;
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint a,bool i,uint p);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h,IntPtr a,byte[] b,UIntPtr n,out UIntPtr g);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    static IntPtr A(uint a){return new IntPtr((long)a);}
    public static uint Read32(int pid,uint addr){
        IntPtr h=OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION,false,(uint)pid);
        if(h==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error());
        try{byte[] b=new byte[4];UIntPtr g;if(!ReadProcessMemory(h,A(addr),b,new UIntPtr(4u),out g)||g.ToUInt64()!=4)throw new Exception("ReadProcessMemory failed at 0x"+addr.ToString("X8")+" win32="+Marshal.GetLastWin32Error());return BitConverter.ToUInt32(b,0);}finally{CloseHandle(h);}
    }
}
'@
}
function Read32([uint32]$Address){ return [uint32][AotrOwnerGlobalReadOnly]::Read32($GamePid,$Address) }

$owner=Read32 $OwnerGlobal
$session=Read32 $SessionGlobal
$network=Read32 $NetworkGlobal
$sessionVt=if($session -ne 0){Read32 $session}else{0}
$sessionState=if($session -ne 0){Read32 ([uint32]($session+0x28))}else{0xFFFFFFFF}
$current=if($session -ne 0){Read32 ([uint32]($session+0x44))}else{0}
$currentVt=if($current -ne 0){Read32 $current}else{0}
$ownerState=if($owner -ne 0){Read32 ([uint32]($owner+0x6A4))}else{0xFFFFFFFF}
$owner304=if($owner -ne 0){Read32 ([uint32]($owner+0x304))}else{0xFFFFFFFF}
$owner288=if($owner -ne 0){[uint32]($owner+0x288)}else{0}

Write-Host '============================================================'
Write-Host ' AOTR WOTR FRONTEND OWNER GLOBAL RUNTIME VALIDATE - READ ONLY'
Write-Host '============================================================'
Write-Host ("PID                  : {0}" -f $GamePid)
Write-Host ("Image                : {0}" -f $GameDat)
Write-Host ("SHA256               : {0}" -f $hash)
Write-Host ("Owner global         : [0x{0:X8}] = 0x{1:X8}" -f $OwnerGlobal,$owner)
Write-Host ("Owner +0x288 address : 0x{0:X8}" -f $owner288)
if($owner -ne 0){
    Write-Host ("Owner +0x6A4         : {0}" -f $ownerState)
    Write-Host ("Owner +0x304         : {0}" -f $owner304)
}
Write-Host ("Session              : 0x{0:X8}" -f $session)
Write-Host ("Session vtable       : 0x{0:X8} expected=0x{1:X8} match={2}" -f $sessionVt,$SessionVtable,($sessionVt -eq $SessionVtable))
Write-Host ("Session state +0x28  : {0}" -f $sessionState)
Write-Host ("Session current +0x44: 0x{0:X8}" -f $current)
Write-Host ("Current vtable       : 0x{0:X8} expected=0x{1:X8} match={2}" -f $currentVt,$GameInfoVtable,($currentVt -eq $GameInfoVtable))
Write-Host ("DE892C               : 0x{0:X8}" -f $network)
Write-Host ''

$ownerPass=($owner -ne 0)
$freshBrowserShape=($ownerPass -and $session -ne 0 -and $sessionVt -eq $SessionVtable -and $current -eq 0 -and $network -eq 0)
Write-Host ("OWNER_GLOBAL_NON_NULL            = {0}" -f $(if($ownerPass){'YES'}else{'NO'}))
Write-Host ("FRESH_BROWSER_SESSION_SHAPE      = {0}" -f $(if($freshBrowserShape){'YES'}else{'NO'}))
if($ownerPass){
    Write-Host ("OWNER_STATE_6A4                 = {0}" -f $ownerState)
    Write-Host ("OWNER_FIELD_304                 = {0}" -f $owner304)
}
Write-Host 'READ_ONLY_COMPLETE=YES'
Write-Host 'No WriteProcessMemory import exists in this tool.'
