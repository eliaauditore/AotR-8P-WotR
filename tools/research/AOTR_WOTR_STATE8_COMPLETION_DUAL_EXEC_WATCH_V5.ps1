param(
    [int]$ProcessId = 0,
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [int]$TimeoutSeconds = 60,
    [string]$ReadyFile = '',
    [string]$StopFile = '',
    [string]$StatusFile = '',
    [switch]$CompileOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$Callback   = [uint32]0x008496C2
$Completion = [uint32]0x0084944F

if ([Environment]::Is64BitProcess) { throw 'Run under 32-bit Windows PowerShell.' }
if ($TimeoutSeconds -lt 20 -or $TimeoutSeconds -gt 120) { throw 'TimeoutSeconds must be 20..120.' }

if (-not ('AotrDualExec32V5' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class AotrDualExec32V5 {
    const uint EX=1, CT=2, CP=3, XT=4, XP=5;
    const uint SS=0x80000004, BP=0x80000003, CONT=0x00010002, NA=0x80010001;
    const uint TS=0x2, TG=0x8, TSET=0x10, TQ=0x40, TA=TS|TG|TSET|TQ;
    const uint PROCESS_ALL_ACCESS=0x001F0FFF;
    const uint CI=0x10000, CD=CI|0x10, CINT=CI|0x2, CC=CI|0x1, CAP=CD|CINT|CC;
    const uint SG=0x00DE4394, NG=0x00DE892C, UI=0x00DEA114, C54=0x00C54B78;
    const uint DR01MASK=0x00FF000Fu;

    [StructLayout(LayoutKind.Sequential)] public struct FSA { public uint a,b,c,d,e,f,g; [MarshalAs(UnmanagedType.ByValArray,SizeConst=80)] public byte[] r; public uint h; }
    [StructLayout(LayoutKind.Sequential)] public struct CTX { public uint Flags,Dr0,Dr1,Dr2,Dr3,Dr6,Dr7; public FSA fs; public uint Gs,Fs,Es,Ds,Edi,Esi,Ebx,Edx,Ecx,Eax,Ebp,Eip,Cs,EFlags,Esp,Ss; [MarshalAs(UnmanagedType.ByValArray,SizeConst=512)] public byte[] x; }

    // x86 DEBUG_EVENT = 12-byte header + 84-byte union = 96 bytes.
    // Only fields used by this watcher are mapped. All overlapped fields are blittable.
    [StructLayout(LayoutKind.Explicit, Size=96)] public struct DE {
        [FieldOffset(0)]  public uint code;
        [FieldOffset(4)]  public uint pid;
        [FieldOffset(8)]  public uint tid;
        [FieldOffset(12)] public uint exceptionCode;
        [FieldOffset(12)] public IntPtr hThread;
        [FieldOffset(24)] public uint exceptionAddress;
    }

    public static string LayoutSelfTest(){
        int size=Marshal.SizeOf(typeof(DE));
        int h=Marshal.OffsetOf(typeof(DE),"hThread").ToInt32();
        int a=Marshal.OffsetOf(typeof(DE),"exceptionAddress").ToInt32();
        return "DEBUG_EVENT_SIZE="+size+" HTHREAD_OFFSET="+h+" EXADDR_OFFSET="+a;
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

    static CTX New(uint f){ CTX c=new CTX(); c.Flags=f; c.fs.r=new byte[80]; c.x=new byte[512]; return c; }
    static uint R(IntPtr h,uint a){ if(a==0)return 0; byte[] b=new byte[4]; UIntPtr g; if(!ReadProcessMemory(h,new IntPtr(unchecked((int)a)),b,new UIntPtr(4u),out g)||g.ToUInt64()!=4)return 0; return BitConverter.ToUInt32(b,0); }

    // Return: 1 newly armed, 2 already armed by us, 0 access/context failure, -1 conflicting active HW breakpoint.
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
    static int ArmAll(int pid,uint a0,uint a1,out int conflicts){ int n=0; conflicts=0; try{ foreach(ProcessThread t in Process.GetProcessById(pid).Threads){ int r=ArmTid((uint)t.Id,a0,a1); if(r>0)n++; else if(r<0)conflicts++; }}catch{} return n; }
    static int DisarmAll(int pid){ int n=0; try{ foreach(ProcessThread t in Process.GetProcessById(pid).Threads) if(DisarmTid((uint)t.Id))n++; }catch{} return n; }
    static bool Get(uint tid,out CTX c){ c=New(CAP); IntPtr h=OpenThread(TA,false,tid); if(h==IntPtr.Zero)return false; try{return GetThreadContext(h,ref c);}finally{CloseHandle(h);} }
    static void Clear6(uint tid){ IntPtr h=OpenThread(TA,false,tid); if(h==IntPtr.Zero)return; try{ CTX c=New(CD); if(GetThreadContext(h,ref c)){c.Dr6=0;SetThreadContext(h,ref c);} }finally{CloseHandle(h);} }
    static string F(uint v){return "0x"+v.ToString("X8");}
    static void State(StringBuilder l,IntPtr ph,CTX c){ uint s=R(ph,SG),st=s==0?0:R(ph,s+0x28),cur=s==0?0:R(ph,s+0x44),vt=cur==0?0:R(ph,cur),net=R(ph,NG),ui=R(ph,UI),os=c.Ecx==0?0:R(ph,c.Ecx+0x6A4),o304=c.Ecx==0?0:R(ph,c.Ecx+0x304); l.AppendLine("SESSION="+F(s)+" STATE28="+st+" CURRENT="+F(cur)+" CURRENT_VT="+F(vt)); l.AppendLine("DE892C="+F(net)+" DEA114="+ui); l.AppendLine("ECX_OWNER="+F(c.Ecx)+" OWNER_6A4="+os+" OWNER_304="+o304+" CURRENT_IS_C54B78="+(vt==C54?"YES":"NO")); }
    static void Signal(string p,string s){ if(String.IsNullOrEmpty(p))return; try{File.WriteAllText(p,s,Encoding.ASCII);}catch{} }
    static bool Exists(string p){ if(String.IsNullOrEmpty(p))return false; try{return File.Exists(p);}catch{return false;} }

    public static string Watch(int pid,uint cb,uint comp,int timeoutMs,string readyFile,string stopFile,string statusFile){
        StringBuilder l=new StringBuilder(); IntPtr ph=OpenProcess(PROCESS_ALL_ACCESS,false,(uint)pid); if(ph==IntPtr.Zero)throw new Exception("OpenProcess(PROCESS_ALL_ACCESS) failed "+Marshal.GetLastWin32Error());
        bool attached=false,pending=false,armed=false,stopRequested=false,done=false,cleanDetach=false,processExited=false; DE e=new DE(); Stopwatch sw=Stopwatch.StartNew(); int cbHits=0,compHits=0,newThreads=0;
        try{
            Signal(statusFile,"STAGE=ATTACHING\r\nCLEAN_DETACH=NO\r\n"); DebugSetProcessKillOnExit(false);
            if(!DebugActiveProcess((uint)pid)){ Signal(readyFile,"STATUS=FAIL\r\nSTAGE=DEBUG_ATTACH\r\nWIN32="+Marshal.GetLastWin32Error()+"\r\n"); throw new Exception("DebugActiveProcess failed "+Marshal.GetLastWin32Error()); }
            attached=true; l.AppendLine("DEBUG_ATTACH=OK"); Signal(statusFile,"STAGE=ATTACHED\r\nCLEAN_DETACH=NO\r\n");

            while(!done){
                if((Exists(stopFile)||sw.ElapsedMilliseconds>=timeoutMs) && !stopRequested){ Signal(statusFile,"STAGE=BREAK_REQUESTED\r\nCLEAN_DETACH=NO\r\n"); if(!DebugBreakProcess(ph))throw new Exception("DebugBreakProcess failed "+Marshal.GetLastWin32Error()); stopRequested=true; }
                if(!WaitForDebugEvent(out e,50))continue; pending=true;

                if(!armed && (e.code==CP||e.code==CT)){
                    int total=ThreadCount(pid), conflicts=0, count=ArmAll(pid,cb,comp,out conflicts);
                    l.AppendLine("ARMED_THREADS="+count); l.AppendLine("ARM_TARGET_THREADS="+total); l.AppendLine("ARM_CONFLICTS="+conflicts);
                    if(total<=0 || count!=total || conflicts!=0){ Signal(readyFile,"STATUS=FAIL\r\nSTAGE=ARM_INCOMPLETE\r\nARMED_THREADS="+count+"\r\nTARGET_THREADS="+total+"\r\nCONFLICTS="+conflicts+"\r\n"); throw new Exception("Hardware breakpoint arm incomplete: armed="+count+" target="+total+" conflicts="+conflicts); }
                    armed=true; Signal(readyFile,"STATUS=READY\r\nARMED_THREADS="+count+"\r\nTARGET_THREADS="+total+"\r\nPID="+pid+"\r\n"); Signal(statusFile,"STAGE=ARMED\r\nARMED_THREADS="+count+"\r\nTARGET_THREADS="+total+"\r\nCLEAN_DETACH=NO\r\n");
                }
                else if(armed && e.code==CT){
                    int r=ArmHandle(e.hThread,cb,comp);
                    if(r<=0)throw new Exception("Failed to arm CREATE_THREAD_DEBUG_EVENT tid="+e.tid+" result="+r+" win32="+Marshal.GetLastWin32Error());
                    newThreads++; l.AppendLine("CREATE_THREAD_ARMED=YES TID="+e.tid+" MODE="+(r==2?"ALREADY":"EVENT_HANDLE"));
                }

                uint cont=CONT;
                if(e.code==EX){
                    uint code=e.exceptionCode;
                    if(code==SS){ CTX c; if(Get(e.tid,out c)){ bool h0=(c.Dr6&1)!=0,h1=(c.Dr6&2)!=0; if(h0||h1){ if(h0){cbHits++;l.AppendLine("CALLBACK_8496C2_HIT=YES");l.AppendLine("CALLBACK_HIT_COUNT="+cbHits);} if(h1){compHits++;l.AppendLine("COMPLETION_84944F_HIT=YES");l.AppendLine("COMPLETION_HIT_COUNT="+compHits);} l.AppendLine("ELAPSED_MS="+sw.Elapsed.TotalMilliseconds.ToString("F3",System.Globalization.CultureInfo.InvariantCulture)); l.AppendLine("THREAD_ID="+e.tid+" EXCEPTION_ADDRESS="+F(e.exceptionAddress)+" EIP="+F(c.Eip)); l.AppendLine("EAX="+F(c.Eax)+" EBX="+F(c.Ebx)+" ECX="+F(c.Ecx)+" EDX="+F(c.Edx)+" ESI="+F(c.Esi)+" EDI="+F(c.Edi)); State(l,ph,c); Clear6(e.tid); } } }
                    else if(code==BP && stopRequested){ Signal(statusFile,"STAGE=DISARMING\r\nCLEAN_DETACH=NO\r\n"); int total=ThreadCount(pid),cleared=DisarmAll(pid); if(total>0&&cleared!=total){ total=ThreadCount(pid); cleared=DisarmAll(pid); } l.AppendLine("DISARMED_THREADS="+cleared); l.AppendLine("DISARM_TARGET_THREADS="+total); if(total<=0||cleared!=total){ Signal(statusFile,"STAGE=DISARM_FAILED\r\nDISARMED_THREADS="+cleared+"\r\nTARGET_THREADS="+total+"\r\nCLEAN_DETACH=NO\r\n"); throw new Exception("Hardware breakpoint disarm incomplete: disarmed="+cleared+" target="+total); } cleanDetach=true; done=true; }
                    else if(code!=BP)cont=NA;
                }

                if(!ContinueDebugEvent(e.pid,e.tid,cont))throw new Exception("ContinueDebugEvent failed "+Marshal.GetLastWin32Error()); pending=false;
                if(e.code==XP){ l.AppendLine("PROCESS_EXITED=YES"); processExited=true; done=true; }
            }

            l.AppendLine("CREATE_THREAD_EVENTS_ARMED="+newThreads);
            if(cbHits==0)l.AppendLine("CALLBACK_8496C2_HIT=NO"); if(compHits==0)l.AppendLine("COMPLETION_84944F_HIT=NO"); if(!processExited){ CTX z=New(CAP); State(l,ph,z); }
        }
        finally{
            try{if(pending)ContinueDebugEvent(e.pid,e.tid,CONT);}catch{}
            if(attached)try{DebugActiveProcessStop((uint)pid);}catch{}
            if(ph!=IntPtr.Zero)CloseHandle(ph);
            if(cleanDetach||processExited)Signal(statusFile,"STAGE=DONE\r\nCLEAN_DETACH=YES\r\n"); else Signal(statusFile,"STAGE=FAILED\r\nCLEAN_DETACH=NO\r\n");
        }
        return l.ToString();
    }
}
'@
}

$layout = [AotrDualExec32V5]::LayoutSelfTest()
$expectedLayout = 'DEBUG_EVENT_SIZE=96 HTHREAD_OFFSET=12 EXADDR_OFFSET=24'
if ($layout -ne $expectedLayout) {
    throw "CLR DEBUG_EVENT layout mismatch. Expected [$expectedLayout], got [$layout]"
}
Write-Output ("CLR_LAYOUT_SELFTEST_PASS {0}" -f $layout)
if ($CompileOnly) {
    Write-Output 'COMPILE_ONLY_COMPLETE - no game process was opened or debugged.'
    return
}

if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash got $hash" }

if ($ProcessId -eq 0) {
    $m = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'game.dat' -and $_.ExecutablePath -eq $GameDat })
    if ($m.Count -ne 1) { throw "Expected exactly one game.dat at $GameDat, found $($m.Count)" }
    $ProcessId = [int]$m[0].ProcessId
}
$p = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId"
if (-not $p) { throw "PID $ProcessId not found" }
if ($p.ExecutablePath -ne $GameDat) { throw "PID path mismatch: $($p.ExecutablePath)" }

foreach ($f in @($ReadyFile,$StopFile,$StatusFile)) {
    if (-not [string]::IsNullOrWhiteSpace($f)) {
        $d = Split-Path -Parent $f
        if ($d) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    }
}

Write-Output '============================================================'
Write-Output ' AOTR WOTR STATE8 COMPLETION DUAL EXEC WATCH V5'
Write-Output '============================================================'
Write-Output ("PID             : {0}" -f $ProcessId)
Write-Output ("Image           : {0}" -f $GameDat)
Write-Output ("SHA256          : {0}" -f $hash)
Write-Output ("DR0 callback    : 0x{0:X8}" -f $Callback)
Write-Output ("DR1 completion  : 0x{0:X8}" -f $Completion)
Write-Output ("Timeout         : {0}s" -f $TimeoutSeconds)
Write-Output ''
$result=[AotrDualExec32V5]::Watch($ProcessId,$Callback,$Completion,$TimeoutSeconds*1000,$ReadyFile,$StopFile,$StatusFile)
Write-Output $result
Write-Output 'WATCH COMPLETE. No game-memory bytes were patched and no game function was called by this watcher.'