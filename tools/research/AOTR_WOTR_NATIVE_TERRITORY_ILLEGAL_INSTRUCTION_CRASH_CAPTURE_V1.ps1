param(
    [int]$ProcessId = 0,
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [int]$TimeoutSeconds = 90,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH',
    [switch]$CompileOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# NORMAL-NATIVE-UI CRASH CAPTURE ONLY.
# Intended flow: join the WotR lobby manually through the normal UI, then run this
# observer, wait for CRASH_OBSERVER_READY, and click exactly one territory.
#
# This tool:
# - does NOT set hardware breakpoints;
# - does NOT call WriteProcessMemory / SetThreadContext;
# - does NOT call any game function;
# - does NOT modify game.dat on disk;
# - attaches as a debugger only to capture the native 0xC000001D exception context;
# - resumes the exception as NOT_HANDLED so the native crash semantics are preserved.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'

if ([Environment]::Is64BitProcess) {
    throw 'Run under 32-bit Windows PowerShell: C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
}
if ($TimeoutSeconds -lt 20 -or $TimeoutSeconds -gt 180) { throw 'TimeoutSeconds must be 20..180.' }

if (-not ('AotrTerritoryCrashCapture32V1' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public static class AotrTerritoryCrashCapture32V1
{
    const uint EX=1, CT=2, CP=3, XT=4, XP=5;
    const uint DBG_CONTINUE=0x00010002, DBG_EXCEPTION_NOT_HANDLED=0x80010001;
    const uint EXCEPTION_BREAKPOINT=0x80000003, EXCEPTION_ILLEGAL_INSTRUCTION=0xC000001D;
    const uint THREAD_GET_CONTEXT=0x0008, THREAD_QUERY_INFORMATION=0x0040;
    const uint CONTEXT_I386=0x00010000, CONTEXT_CONTROL=CONTEXT_I386|0x1, CONTEXT_INTEGER=CONTEXT_I386|0x2, CONTEXT_DEBUG_REGISTERS=CONTEXT_I386|0x10;
    const uint CONTEXT_CAPTURE=CONTEXT_CONTROL|CONTEXT_INTEGER|CONTEXT_DEBUG_REGISTERS;
    const uint PROCESS_VM_READ=0x0010, PROCESS_QUERY_INFORMATION=0x0400;

    [StructLayout(LayoutKind.Sequential)] public struct FSA {
        public uint a,b,c,d,e,f,g;
        [MarshalAs(UnmanagedType.ByValArray,SizeConst=80)] public byte[] r;
        public uint h;
    }
    [StructLayout(LayoutKind.Sequential)] public struct CTX {
        public uint Flags,Dr0,Dr1,Dr2,Dr3,Dr6,Dr7;
        public FSA fs;
        public uint Gs,Fs,Es,Ds,Edi,Esi,Ebx,Edx,Ecx,Eax,Ebp,Eip,Cs,EFlags,Esp,Ss;
        [MarshalAs(UnmanagedType.ByValArray,SizeConst=512)] public byte[] x;
    }
    [StructLayout(LayoutKind.Explicit, Size=96)] public struct DE {
        [FieldOffset(0)]  public uint code;
        [FieldOffset(4)]  public uint pid;
        [FieldOffset(8)]  public uint tid;
        [FieldOffset(12)] public IntPtr exceptionCode;
        [FieldOffset(24)] public uint exceptionAddress;
        [FieldOffset(92)] public uint firstChance;
    }
    [StructLayout(LayoutKind.Sequential)] public struct MBI {
        public UIntPtr BaseAddress;
        public UIntPtr AllocationBase;
        public uint AllocationProtect;
        public UIntPtr RegionSize;
        public uint State;
        public uint Protect;
        public uint Type;
    }

    [DllImport("kernel32.dll",SetLastError=true)] static extern bool DebugActiveProcess(uint pid);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool DebugActiveProcessStop(uint pid);
    [DllImport("kernel32.dll")] static extern bool DebugSetProcessKillOnExit(bool killOnExit);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool WaitForDebugEvent(out DE e,uint ms);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool ContinueDebugEvent(uint pid,uint tid,uint status);
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenThread(uint access,bool inherit,uint tid);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetThreadContext(IntPtr hThread,ref CTX c);
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr hProcess,IntPtr addr,byte[] buffer,UIntPtr size,out UIntPtr got);
    [DllImport("kernel32.dll",SetLastError=true)] static extern UIntPtr VirtualQueryEx(IntPtr hProcess,IntPtr addr,out MBI mbi,UIntPtr len);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

    static CTX NewContext(){
        CTX c=new CTX(); c.Flags=CONTEXT_CAPTURE; c.fs.r=new byte[80]; c.x=new byte[512]; return c;
    }
    static string F(uint v){ return "0x"+v.ToString("X8"); }
    static string Hex(byte[] b){
        if(b==null)return "<UNREADABLE>";
        StringBuilder s=new StringBuilder();
        for(int i=0;i<b.Length;i++){ if(i>0)s.Append(' '); s.Append(b[i].ToString("X2")); }
        return s.ToString();
    }
    static byte[] ReadBytes(IntPtr ph,uint addr,int count){
        if(addr==0 || count<=0)return null;
        byte[] b=new byte[count]; UIntPtr got;
        if(!ReadProcessMemory(ph,new IntPtr(unchecked((int)addr)),b,new UIntPtr((uint)count),out got) || got.ToUInt64()!=(ulong)count)return null;
        return b;
    }
    static uint U32(byte[] b,int o){ return BitConverter.ToUInt32(b,o); }
    static bool GetContext(uint tid,out CTX c){
        c=NewContext(); IntPtr th=OpenThread(THREAD_GET_CONTEXT|THREAD_QUERY_INFORMATION,false,tid);
        if(th==IntPtr.Zero)return false;
        try{return GetThreadContext(th,ref c);}finally{CloseHandle(th);}
    }
    static void LogRegion(StringBuilder l,IntPtr ph,uint eip){
        MBI m; UIntPtr q=VirtualQueryEx(ph,new IntPtr(unchecked((int)eip)),out m,new UIntPtr((uint)Marshal.SizeOf(typeof(MBI))));
        if(q==UIntPtr.Zero){ l.AppendLine("FAULT_REGION_QUERY=FAILED WIN32="+Marshal.GetLastWin32Error()); return; }
        uint b=unchecked((uint)m.BaseAddress.ToUInt64()), ab=unchecked((uint)m.AllocationBase.ToUInt64()), rs=unchecked((uint)m.RegionSize.ToUInt64());
        l.AppendLine("FAULT_REGION_BASE="+F(b)+" ALLOCATION_BASE="+F(ab)+" REGION_SIZE="+F(rs));
        l.AppendLine("FAULT_REGION_STATE="+F(m.State)+" PROTECT="+F(m.Protect)+" ALLOC_PROTECT="+F(m.AllocationProtect)+" TYPE="+F(m.Type));
        l.AppendLine("FAULT_MINUS_REGION_BASE="+F(unchecked(eip-b)));
        l.AppendLine("FAULT_MINUS_ALLOCATION_BASE="+F(unchecked(eip-ab)));
    }
    static void LogStack(StringBuilder l,IntPtr ph,CTX c,uint imageBase,uint imageSize){
        byte[] st=ReadBytes(ph,c.Esp,256);
        l.AppendLine("STACK_256_BYTES="+Hex(st));
        if(st==null)return;
        uint imageEnd=unchecked(imageBase+imageSize); int hits=0;
        for(int i=0;i+4<=st.Length;i+=4){
            uint v=U32(st,i);
            if(v>=imageBase && v<imageEnd){
                hits++;
                uint pre=v>=16?v-16:0;
                byte[] p=pre==0?null:ReadBytes(ph,pre,16);
                l.AppendLine("STACK_GAME_PTR["+hits+"] ESP_PLUS=0x"+i.ToString("X2")+" VALUE="+F(v)+" PREV16="+Hex(p));
            }
        }
        l.AppendLine("STACK_GAME_PTR_COUNT="+hits);
    }
    static void Capture(StringBuilder l,IntPtr ph,DE e,uint imageBase,uint imageSize,int ordinal){
        CTX c;
        l.AppendLine("================ ILLEGAL INSTRUCTION CAPTURE "+ordinal+" ================");
        l.AppendLine("THREAD_ID="+e.tid+" FIRST_CHANCE="+e.firstChance+" EXCEPTION_ADDRESS="+F(e.exceptionAddress));
        if(!GetContext(e.tid,out c)){ l.AppendLine("GET_THREAD_CONTEXT=FAILED WIN32="+Marshal.GetLastWin32Error()); return; }
        l.AppendLine("EIP="+F(c.Eip)+" ESP="+F(c.Esp)+" EBP="+F(c.Ebp)+" EFLAGS="+F(c.EFlags));
        l.AppendLine("EAX="+F(c.Eax)+" EBX="+F(c.Ebx)+" ECX="+F(c.Ecx)+" EDX="+F(c.Edx)+" ESI="+F(c.Esi)+" EDI="+F(c.Edi));
        l.AppendLine("FAULT_BYTES_64="+Hex(ReadBytes(ph,c.Eip,64)));
        if(c.Eip>=32)l.AppendLine("FAULT_PREV32="+Hex(ReadBytes(ph,c.Eip-32,32)));
        LogRegion(l,ph,c.Eip);
        LogStack(l,ph,c,imageBase,imageSize);
    }

    public static string SelfTest(){
        return "PTR_SIZE="+IntPtr.Size+
            " DEBUG_EVENT_SIZE="+Marshal.SizeOf(typeof(DE))+
            " EXADDR_OFFSET="+Marshal.OffsetOf(typeof(DE),"exceptionAddress").ToInt32()+
            " FIRSTCHANCE_OFFSET="+Marshal.OffsetOf(typeof(DE),"firstChance").ToInt32()+
            " MBI_SIZE="+Marshal.SizeOf(typeof(MBI));
    }

    public static string Watch(int pid,uint imageBase,uint imageSize,int timeoutMs){
        StringBuilder l=new StringBuilder();
        IntPtr ph=OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION,false,(uint)pid);
        if(ph==IntPtr.Zero)throw new Exception("OpenProcess failed "+Marshal.GetLastWin32Error());
        bool attached=false, pending=false, ready=false, exited=false; int captures=0; Stopwatch sw=Stopwatch.StartNew(); DE e=new DE();
        try{
            DebugSetProcessKillOnExit(false);
            if(!DebugActiveProcess((uint)pid))throw new Exception("DebugActiveProcess failed "+Marshal.GetLastWin32Error());
            attached=true; l.AppendLine("DEBUG_ATTACH=OK PID="+pid);
            Console.WriteLine("CRASH_OBSERVER_ATTACHED=YES");

            while(sw.ElapsedMilliseconds<timeoutMs){
                if(!WaitForDebugEvent(out e,50))continue;
                pending=true; uint status=DBG_CONTINUE;

                if(e.code==EX){
                    uint code=unchecked((uint)e.exceptionCode.ToInt32());
                    if(code==EXCEPTION_BREAKPOINT){
                        status=DBG_CONTINUE;
                        if(!ready){
                            ready=true;
                            Console.WriteLine("CRASH_OBSERVER_READY=YES");
                            Console.WriteLine("NEXT_ACTION=Click exactly one WotR territory in the normal UI-joined client.");
                            l.AppendLine("CRASH_OBSERVER_READY=YES");
                        }
                    }
                    else if(code==EXCEPTION_ILLEGAL_INSTRUCTION){
                        captures++;
                        Capture(l,ph,e,imageBase,imageSize,captures);
                        Console.WriteLine("ILLEGAL_INSTRUCTION_CAPTURED=YES FIRST_CHANCE="+e.firstChance+" EIP="+F(e.exceptionAddress));
                        status=DBG_EXCEPTION_NOT_HANDLED;
                    }
                    else {
                        status=DBG_EXCEPTION_NOT_HANDLED;
                    }
                }
                else if(e.code==XP){
                    l.AppendLine("EXIT_PROCESS_DEBUG_EVENT=YES"); exited=true;
                }

                if(!ContinueDebugEvent(e.pid,e.tid,status))throw new Exception("ContinueDebugEvent failed "+Marshal.GetLastWin32Error());
                pending=false;
                if(exited)break;
            }

            if(captures==0)l.AppendLine("ILLEGAL_INSTRUCTION_CAPTURED=NO");
            l.AppendLine("ILLEGAL_INSTRUCTION_CAPTURE_COUNT="+captures);
            l.AppendLine("PROCESS_EXIT_OBSERVED="+(exited?"YES":"NO"));
            l.AppendLine("OBSERVER_COMPLETE=YES");
            return l.ToString();
        }
        finally{
            if(pending){ try{ContinueDebugEvent(e.pid,e.tid,DBG_EXCEPTION_NOT_HANDLED);}catch{} }
            if(attached && !exited){ try{DebugActiveProcessStop((uint)pid);}catch{} }
            CloseHandle(ph);
        }
    }
}
'@
}

$self = [AotrTerritoryCrashCapture32V1]::SelfTest()
Write-Host ('CRASH_CAPTURE_CLR_SELFTEST {0}' -f $self)
if ($self -notmatch 'PTR_SIZE=4 DEBUG_EVENT_SIZE=96 EXADDR_OFFSET=24 FIRSTCHANCE_OFFSET=92') {
    throw "CLR layout selftest failed. NOTHING EXECUTED. $self"
}
Write-Host 'CRASH_CAPTURE_CLR_SELFTEST_PASS' -ForegroundColor Green

if ($CompileOnly) {
    Write-Host 'COMPILE_ONLY_COMPLETE - no game process was opened or debugged.' -ForegroundColor Green
    return
}

if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }

if ($ProcessId -le 0) {
    $games = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -ieq 'game.dat' -and $_.ExecutablePath -ieq $GameDat
    })
    if ($games.Count -ne 1) { throw "Expected exactly one game.dat at '$GameDat'. Found $($games.Count)." }
    $ProcessId = [int]$games[0].ProcessId
}

$proc = Get-Process -Id $ProcessId -ErrorAction Stop
$exe = $proc.MainModule.FileName
if ($exe -ine $GameDat) { throw "PID $ProcessId path mismatch: $exe" }
$imageBase64 = $proc.MainModule.BaseAddress.ToInt64()
$imageSize64 = $proc.MainModule.ModuleMemorySize
if ($imageBase64 -lt 0 -or $imageBase64 -gt [uint32]::MaxValue) { throw 'game.dat module base outside 32-bit range.' }
$imageBase = [uint32]$imageBase64
$imageSize = [uint32]$imageSize64

New-Item -ItemType Directory -Path $ResearchRoot -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$resultFile = Join-Path $ResearchRoot ("NATIVE_TERRITORY_ILLEGAL_INSTRUCTION_CAPTURE_$stamp.txt")

Write-Host '============================================================'
Write-Host ' AOTR NATIVE TERRITORY ILLEGAL-INSTRUCTION CRASH CAPTURE V1'
Write-Host '============================================================'
Write-Host ("PID        : {0}" -f $ProcessId)
Write-Host ("Image      : {0}" -f $exe)
Write-Host ("SHA256     : {0}" -f $hash)
Write-Host ("Image base : 0x{0:X8}" -f $imageBase)
Write-Host ("Image size : 0x{0:X8}" -f $imageSize)
Write-Host 'MODE       : NORMAL UI JOIN / DEBUG EXCEPTION OBSERVER / NO HW BREAKPOINTS / NO GAME WRITES'
Write-Host ''

$text = [AotrTerritoryCrashCapture32V1]::Watch($ProcessId,$imageBase,$imageSize,$TimeoutSeconds*1000)
Set-Content -LiteralPath $resultFile -Value $text -Encoding UTF8
Write-Host ''
Write-Host $text
Write-Host ("RESULT_FILE : {0}" -f $resultFile)
