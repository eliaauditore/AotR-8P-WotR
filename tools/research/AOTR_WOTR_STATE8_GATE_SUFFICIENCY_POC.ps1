param(
    [string]$CombinedResult = '',
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [int]$ObserveMilliseconds = 3000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$Completion = [uint32]0x0084944F
$Publisher  = [uint32]0x00846827
$SessionGlobal = [uint32]0x00DE4394
$NetworkGlobal = [uint32]0x00DE892C
$SessionVtable = [uint32]0x00C54CE0
$GameInfoVtable = [uint32]0x00C54B78

if ([Environment]::Is64BitProcess) { throw 'Run under 32-bit Windows PowerShell (SysWOW64).' }
if ($ObserveMilliseconds -lt 500 -or $ObserveMilliseconds -gt 10000) { throw 'ObserveMilliseconds must be 500..10000.' }
if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash got $hash" }

if ([string]::IsNullOrWhiteSpace($CombinedResult)) {
    $latest = Get-ChildItem 'C:\AOTR_RESEARCH\LOWLEVEL_JOIN_COMPLETION_COMBINED_*.txt' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) { throw 'No LOWLEVEL_JOIN_COMPLETION_COMBINED_*.txt result found.' }
    $CombinedResult = $latest.FullName
}
if (-not (Test-Path -LiteralPath $CombinedResult -PathType Leaf)) { throw "Combined result not found: $CombinedResult" }
$log = Get-Content -LiteralPath $CombinedResult -Raw

$pidMatch = [regex]::Match($log, '(?m)^Game PID\s+:\s+(\d+)\s*$')
if (-not $pidMatch.Success) { throw 'Could not parse Game PID from combined result.' }
$GamePid = [int]$pidMatch.Groups[1].Value

$ownerMatch = [regex]::Match($log, '(?m)^ECX_OWNER=(0x[0-9A-Fa-f]{8}) OWNER_6A4=1 OWNER_304=1 CURRENT_IS_C54B78=YES\s*$')
if (-not $ownerMatch.Success) { throw 'Could not parse a proven owner record with 6A4=1, 304=1, Current=C54B78 from combined result.' }
$Owner = [uint32]::Parse($ownerMatch.Groups[1].Value.Substring(2), [Globalization.NumberStyles]::HexNumber)

$p = Get-CimInstance Win32_Process -Filter "ProcessId=$GamePid"
if (-not $p) { throw "Original game PID $GamePid is no longer running. This PoC intentionally refuses a different process." }
if ($p.ExecutablePath -ine $GameDat) { throw "PID $GamePid path mismatch: $($p.ExecutablePath)" }

if (-not ('AotrState8Suff32' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public static class AotrState8Suff32 {
    const uint EX=1, CT=2, CP=3, XP=5;
    const uint SS=0x80000004, BP=0x80000003, CONT=0x00010002, NA=0x80010001;
    const uint TS=0x2, TG=0x8, TSET=0x10, TQ=0x40, TA=TS|TG|TSET|TQ;
    const uint PROCESS_ALL_ACCESS=0x001F0FFF;
    const uint CI=0x10000, CD=CI|0x10, CINT=CI|0x2, CC=CI|0x1, CAP=CD|CINT|CC;
    const uint DR01MASK=0x00FF000Fu;

    [StructLayout(LayoutKind.Sequential)] public struct FSA { public uint a,b,c,d,e,f,g; [MarshalAs(UnmanagedType.ByValArray,SizeConst=80)] public byte[] r; public uint h; }
    [StructLayout(LayoutKind.Sequential)] public struct CTX { public uint Flags,Dr0,Dr1,Dr2,Dr3,Dr6,Dr7; public FSA fs; public uint Gs,Fs,Es,Ds,Edi,Esi,Ebx,Edx,Ecx,Eax,Ebp,Eip,Cs,EFlags,Esp,Ss; [MarshalAs(UnmanagedType.ByValArray,SizeConst=512)] public byte[] x; }
    [StructLayout(LayoutKind.Explicit, Size=96)] public struct DE {
        [FieldOffset(0)]  public uint code;
        [FieldOffset(4)]  public uint pid;
        [FieldOffset(8)]  public uint tid;
        [FieldOffset(12)] public IntPtr union0;
        [FieldOffset(24)] public uint exceptionAddress;
    }

    [DllImport("kernel32.dll",SetLastError=true)] static extern bool DebugActiveProcess(uint p);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool DebugActiveProcessStop(uint p);
    [DllImport("kernel32.dll")] static extern bool DebugSetProcessKillOnExit(bool x);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool DebugBreakProcess(IntPtr h);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool WaitForDebugEvent(out DE e,uint ms);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool ContinueDebugEvent(uint p,uint t,uint s);
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenThread(uint a,bool i,uint t);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetThreadContext(IntPtr h,ref CTX c);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetThreadContext(IntPtr h,ref CTX c);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint a,bool i,uint p);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h,IntPtr a,byte[] b,UIntPtr n,out UIntPtr g);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool WriteProcessMemory(IntPtr h,IntPtr a,byte[] b,UIntPtr n,out UIntPtr w);

    static CTX New(uint f){ CTX c=new CTX(); c.Flags=f; c.fs.r=new byte[80]; c.x=new byte[512]; return c; }
    static uint R(IntPtr h,uint a){ if(a==0)return 0; byte[] b=new byte[4]; UIntPtr g; if(!ReadProcessMemory(h,new IntPtr(unchecked((int)a)),b,new UIntPtr(4u),out g)||g.ToUInt64()!=4)throw new Exception("ReadProcessMemory failed at 0x"+a.ToString("X8")+" win32="+Marshal.GetLastWin32Error()); return BitConverter.ToUInt32(b,0); }
    static void W(IntPtr h,uint a,uint v){ byte[] b=BitConverter.GetBytes(v); UIntPtr w; if(!WriteProcessMemory(h,new IntPtr(unchecked((int)a)),b,new UIntPtr(4u),out w)||w.ToUInt64()!=4)throw new Exception("WriteProcessMemory failed at 0x"+a.ToString("X8")+" win32="+Marshal.GetLastWin32Error()); }
    static string F(uint v){return "0x"+v.ToString("X8");}

    static int ArmHandle(IntPtr h,uint a0,uint a1){
        if(h==IntPtr.Zero)return 0;
        CTX c=New(CD); if(!GetThreadContext(h,ref c))return 0;
        bool ours=(c.Dr0==a0 && c.Dr1==a1 && (c.Dr7&DR01MASK)==0x05u);
        if(ours)return 2;
        if((c.Dr7&0xFFu)!=0u)return -1;
        c.Dr0=a0; c.Dr1=a1; c.Dr7&=~DR01MASK; c.Dr7|=0x05u; c.Dr6=0;
        return SetThreadContext(h,ref c)?1:0;
    }
    static bool DisarmHandle(IntPtr h){
        if(h==IntPtr.Zero)return false;
        CTX c=New(CD); if(!GetThreadContext(h,ref c))return false;
        c.Dr0=0; c.Dr1=0; c.Dr7&=~DR01MASK; c.Dr6=0;
        return SetThreadContext(h,ref c);
    }
    static int ArmTid(uint tid,uint a0,uint a1){ IntPtr h=OpenThread(TA,false,tid); if(h==IntPtr.Zero)return 0; try{return ArmHandle(h,a0,a1);}finally{CloseHandle(h);} }
    static bool DisarmTid(uint tid){ IntPtr h=OpenThread(TA,false,tid); if(h==IntPtr.Zero)return false; try{return DisarmHandle(h);}finally{CloseHandle(h);} }
    static int ThreadCount(int pid){ try{return Process.GetProcessById(pid).Threads.Count;}catch{return 0;} }
    static int ArmAll(int pid,uint a0,uint a1,out int conflicts){ int n=0; conflicts=0; foreach(ProcessThread t in Process.GetProcessById(pid).Threads){ int r=ArmTid((uint)t.Id,a0,a1); if(r>0)n++; else if(r<0)conflicts++; } return n; }
    static int DisarmAll(int pid){ int n=0; foreach(ProcessThread t in Process.GetProcessById(pid).Threads) if(DisarmTid((uint)t.Id))n++; return n; }
    static bool Get(uint tid,out CTX c){ c=New(CAP); IntPtr h=OpenThread(TA,false,tid); if(h==IntPtr.Zero)return false; try{return GetThreadContext(h,ref c);}finally{CloseHandle(h);} }
    static void Clear6(uint tid){ IntPtr h=OpenThread(TA,false,tid); if(h==IntPtr.Zero)return; try{ CTX c=New(CD); if(GetThreadContext(h,ref c)){c.Dr6=0;SetThreadContext(h,ref c);} }finally{CloseHandle(h);} }

    public static string LayoutSelfTest(){ return "DEBUG_EVENT_SIZE="+Marshal.SizeOf(typeof(DE))+" UNION0_OFFSET="+Marshal.OffsetOf(typeof(DE),"union0").ToInt32()+" EXADDR_OFFSET="+Marshal.OffsetOf(typeof(DE),"exceptionAddress").ToInt32(); }
    public static uint Read32(int pid,uint addr){ IntPtr h=OpenProcess(PROCESS_ALL_ACCESS,false,(uint)pid); if(h==IntPtr.Zero)throw new Exception("OpenProcess failed "+Marshal.GetLastWin32Error()); try{return R(h,addr);}finally{CloseHandle(h);} }

    public static string Run(int pid,uint owner,uint completion,uint publisher,uint sessionGlobal,uint networkGlobal,uint sessionVt,uint gameInfoVt,int observeMs){
        StringBuilder l=new StringBuilder(); IntPtr ph=OpenProcess(PROCESS_ALL_ACCESS,false,(uint)pid); if(ph==IntPtr.Zero)throw new Exception("OpenProcess failed "+Marshal.GetLastWin32Error());
        bool attached=false,pending=false,armed=false,stateWritten=false,stopRequested=false,done=false,clean=false,processExited=false; DE e=new DE(); Stopwatch sw=Stopwatch.StartNew(); int compHits=0,pubHits=0,newThreads=0;
        uint ownerStateAddr=owner+0x6A4u;
        try{
            uint session=R(ph,sessionGlobal); if(session==0)throw new Exception("Session global NULL");
            if(R(ph,session)!=sessionVt)throw new Exception("Session vtable mismatch");
            uint current=R(ph,session+0x44u); if(current==0)throw new Exception("session+0x44 NULL; expected already joined state");
            if(R(ph,current)!=gameInfoVt)throw new Exception("Current vtable mismatch");
            uint net=R(ph,networkGlobal); if(net!=0)throw new Exception("DE892C already non-NULL; test would not isolate publication");
            uint ownerState=R(ph,ownerStateAddr); uint owner304=R(ph,owner+0x304u);
            if(ownerState!=1u)throw new Exception("Owner+6A4 precondition failed: expected 1 got "+ownerState);
            if(owner304!=1u)throw new Exception("Owner+304 precondition failed: expected 1 got "+owner304);
            l.AppendLine("PRECONDITION_PASS=YES"); l.AppendLine("OWNER="+F(owner)); l.AppendLine("OWNER_6A4_BEFORE="+ownerState); l.AppendLine("OWNER_304_BEFORE="+owner304); l.AppendLine("CURRENT_BEFORE="+F(current)); l.AppendLine("DE892C_BEFORE="+F(net));

            DebugSetProcessKillOnExit(false);
            if(!DebugActiveProcess((uint)pid))throw new Exception("DebugActiveProcess failed "+Marshal.GetLastWin32Error());
            attached=true; l.AppendLine("DEBUG_ATTACH=OK");

            while(!done){
                if(stateWritten && !stopRequested && (sw.ElapsedMilliseconds>=observeMs || (compHits>0 && pubHits>0))){
                    if(!DebugBreakProcess(ph))throw new Exception("DebugBreakProcess failed "+Marshal.GetLastWin32Error());
                    stopRequested=true;
                }
                if(!WaitForDebugEvent(out e,50))continue; pending=true;

                if(!armed && (e.code==CP||e.code==CT)){
                    int total=ThreadCount(pid),conflicts=0,count=ArmAll(pid,completion,publisher,out conflicts);
                    l.AppendLine("ARMED_THREADS="+count); l.AppendLine("ARM_TARGET_THREADS="+total); l.AppendLine("ARM_CONFLICTS="+conflicts);
                    if(total<=0||count!=total||conflicts!=0)throw new Exception("Arm incomplete: armed="+count+" target="+total+" conflicts="+conflicts);
                    armed=true;
                    W(ph,ownerStateAddr,8u); stateWritten=true;
                    uint verify=R(ph,ownerStateAddr); if(verify!=8u)throw new Exception("State write verification failed");
                    l.AppendLine("STATE_WRITE_ATTEMPTED=YES"); l.AppendLine("OWNER_6A4_WRITTEN=8"); l.AppendLine("STATE_WRITE_VERIFIED=YES");
                    sw.Restart();
                }
                else if(armed && e.code==CT){
                    int r=ArmHandle(e.union0,completion,publisher); if(r<=0)throw new Exception("Failed to arm CREATE_THREAD event tid="+e.tid+" result="+r);
                    newThreads++;
                }

                uint cont=CONT;
                if(e.code==EX){
                    uint code=unchecked((uint)e.union0.ToInt32());
                    if(code==SS){
                        CTX c; if(Get(e.tid,out c)){
                            bool h0=(c.Dr6&1u)!=0u,h1=(c.Dr6&2u)!=0u;
                            if(h0||h1){
                                if(h0){compHits++;l.AppendLine("COMPLETION_84944F_HIT=YES");l.AppendLine("COMPLETION_HIT_COUNT="+compHits);}
                                if(h1){pubHits++;l.AppendLine("PUBLISH_WRITER_846827_HIT=YES");l.AppendLine("PUBLISH_HIT_COUNT="+pubHits);}
                                l.AppendLine("HIT_ELAPSED_MS="+sw.Elapsed.TotalMilliseconds.ToString("F3",System.Globalization.CultureInfo.InvariantCulture));
                                l.AppendLine("THREAD_ID="+e.tid+" EXCEPTION_ADDRESS="+F(e.exceptionAddress)+" EIP="+F(c.Eip));
                                l.AppendLine("OWNER_6A4_AT_HIT="+R(ph,ownerStateAddr)+" OWNER_304_AT_HIT="+R(ph,owner+0x304u));
                                l.AppendLine("CURRENT_AT_HIT="+F(R(ph,session+0x44u))+" DE892C_AT_HIT="+F(R(ph,networkGlobal)));
                                Clear6(e.tid);
                            }
                        }
                    } else if(code==BP && stopRequested){
                        int total=ThreadCount(pid),cleared=DisarmAll(pid); if(total>0&&cleared!=total){ total=ThreadCount(pid); cleared=DisarmAll(pid); }
                        l.AppendLine("DISARMED_THREADS="+cleared); l.AppendLine("DISARM_TARGET_THREADS="+total);
                        if(total<=0||cleared!=total)throw new Exception("Disarm incomplete: disarmed="+cleared+" target="+total);
                        done=true; clean=true;
                    } else if(code!=BP) cont=NA;
                }
                if(!ContinueDebugEvent(e.pid,e.tid,cont))throw new Exception("ContinueDebugEvent failed "+Marshal.GetLastWin32Error()); pending=false;
                if(e.code==XP){processExited=true;done=true;}
            }

            uint finalSession=R(ph,sessionGlobal), finalCurrent=finalSession==0?0:R(ph,finalSession+0x44u), finalNet=R(ph,networkGlobal), finalState=R(ph,ownerStateAddr), final304=R(ph,owner+0x304u);
            if(compHits==0 && pubHits==0 && finalNet==0 && finalState==8u){ W(ph,ownerStateAddr,1u); finalState=R(ph,ownerStateAddr); l.AppendLine("STATE_RESTORED_TO_1=YES"); }
            l.AppendLine("CREATE_THREAD_EVENTS_ARMED="+newThreads);
            if(compHits==0)l.AppendLine("COMPLETION_84944F_HIT=NO"); if(pubHits==0)l.AppendLine("PUBLISH_WRITER_846827_HIT=NO");
            l.AppendLine("OWNER_6A4_AFTER="+finalState); l.AppendLine("OWNER_304_AFTER="+final304); l.AppendLine("CURRENT_AFTER="+F(finalCurrent)); l.AppendLine("DE892C_AFTER="+F(finalNet));
            l.AppendLine("DE892C_EQUALS_CURRENT="+((finalCurrent!=0&&finalNet==finalCurrent)?"YES":"NO"));
            l.AppendLine("STATE8_SUFFICIENCY_PROVEN="+((compHits>0&&pubHits>0&&finalCurrent!=0&&finalNet==finalCurrent)?"YES":"NO"));
            l.AppendLine("WATCHER_CLEAN_EXIT="+((clean||processExited)?"YES":"NO"));
        }
        finally{
            try{if(pending)ContinueDebugEvent(e.pid,e.tid,CONT);}catch{}
            if(attached)try{DebugActiveProcessStop((uint)pid);}catch{}
            if(ph!=IntPtr.Zero)CloseHandle(ph);
        }
        return l.ToString();
    }
}
'@
}

$layout = [AotrState8Suff32]::LayoutSelfTest()
if ($layout -ne 'DEBUG_EVENT_SIZE=96 UNION0_OFFSET=12 EXADDR_OFFSET=24') { throw "CLR layout selftest failed: $layout" }
Write-Host ("CLR_LAYOUT_SELFTEST_PASS {0}" -f $layout)

# Re-check live contract immediately before attaching.
$session = [AotrState8Suff32]::Read32($GamePid,$SessionGlobal)
if ($session -eq 0) { throw 'Session global is NULL.' }
$sessionVtLive = [AotrState8Suff32]::Read32($GamePid,$session)
$current = [AotrState8Suff32]::Read32($GamePid,$session + 0x44)
$currentVt = if ($current -ne 0) { [AotrState8Suff32]::Read32($GamePid,$current) } else { 0 }
$net = [AotrState8Suff32]::Read32($GamePid,$NetworkGlobal)
$ownerState = [AotrState8Suff32]::Read32($GamePid,$Owner + 0x6A4)
$owner304 = [AotrState8Suff32]::Read32($GamePid,$Owner + 0x304)

Write-Host '============================================================'
Write-Host ' AOTR WOTR STATE8 GATE SUFFICIENCY POC'
Write-Host '============================================================'
Write-Host ("Source log       : {0}" -f $CombinedResult)
Write-Host ("PID              : {0}" -f $GamePid)
Write-Host ("Owner            : 0x{0:X8}" -f $Owner)
Write-Host ("Owner+6A4        : {0}" -f $ownerState)
Write-Host ("Owner+304        : {0}" -f $owner304)
Write-Host ("Session          : 0x{0:X8}" -f $session)
Write-Host ("Session vtable   : 0x{0:X8}" -f $sessionVtLive)
Write-Host ("Current          : 0x{0:X8}" -f $current)
Write-Host ("Current vtable   : 0x{0:X8}" -f $currentVt)
Write-Host ("DE892C           : 0x{0:X8}" -f $net)

if ($sessionVtLive -ne $SessionVtable) { throw 'Session vtable precondition failed.' }
if ($current -eq 0 -or $currentVt -ne $GameInfoVtable) { throw 'Current C54B78 precondition failed.' }
if ($net -ne 0) { throw 'DE892C is already non-NULL. Refusing sufficiency test.' }
if ($ownerState -ne 1 -or $owner304 -ne 1) { throw 'Owner precondition failed. Expected +6A4=1 and +304=1.' }
Write-Host 'LIVE_PRECONDITION_PASS' -ForegroundColor Green
Write-Host 'CONTROLLED_MUTATION: exactly one DWORD owner+0x6A4 will be changed 1 -> 8.' -ForegroundColor Yellow
Write-Host 'No DE892C write and no direct game-function call is performed.'
Write-Host ''

$result = [AotrState8Suff32]::Run($GamePid,$Owner,$Completion,$Publisher,$SessionGlobal,$NetworkGlobal,$SessionVtable,$GameInfoVtable,$ObserveMilliseconds)
Write-Output $result
