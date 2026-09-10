param(
    [int]$ProcessId = 0,
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# RUNTIME DEBUGGER / NO GAME-MEMORY PATCH.
# Purpose: prove whether frontend completion handler 0x0084944F executes after
# the low-level native join PoC. Uses an x86 hardware EXECUTION breakpoint.
# It does NOT WriteProcessMemory, VirtualProtect, VirtualAllocEx, or call game functions.
# Run under 32-bit Windows PowerShell (SysWOW64) because game.dat is 32-bit.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$BreakAddress = [uint32]0x0084944F

if ([Environment]::Is64BitProcess) {
    throw 'This watcher must run under 32-bit Windows PowerShell: C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
}
if (-not (Test-Path -LiteralPath $GameDat)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash, got $hash" }
if ($TimeoutSeconds -lt 1) { throw 'TimeoutSeconds must be >= 1.' }

if ($ProcessId -eq 0) {
    $matches = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -ieq 'game.dat' -and $_.ExecutablePath -eq $GameDat
    })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one game.dat at '$GameDat', found $($matches.Count). Pass -ProcessId explicitly if needed."
    }
    $ProcessId = [int]$matches[0].ProcessId
}

$proc = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId"
if (-not $proc) { throw "PID $ProcessId not found." }
if ($proc.ExecutablePath -ne $GameDat) {
    throw "PID path mismatch. PID $ProcessId image='$($proc.ExecutablePath)' expected='$GameDat'"
}

if (-not ('AotrExecWatch32' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public static class AotrExecWatch32 {
    const uint EXCEPTION_DEBUG_EVENT = 1;
    const uint CREATE_THREAD_DEBUG_EVENT = 2;
    const uint CREATE_PROCESS_DEBUG_EVENT = 3;
    const uint EXIT_PROCESS_DEBUG_EVENT = 5;

    const uint EXCEPTION_SINGLE_STEP = 0x80000004;
    const uint EXCEPTION_BREAKPOINT  = 0x80000003;
    const uint DBG_CONTINUE = 0x00010002;
    const uint DBG_EXCEPTION_NOT_HANDLED = 0x80010001;

    const uint THREAD_SUSPEND_RESUME = 0x0002;
    const uint THREAD_GET_CONTEXT = 0x0008;
    const uint THREAD_SET_CONTEXT = 0x0010;
    const uint THREAD_QUERY_INFORMATION = 0x0040;
    const uint THREAD_ACCESS = THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_SET_CONTEXT | THREAD_QUERY_INFORMATION;

    const uint PROCESS_VM_READ = 0x0010;
    const uint PROCESS_QUERY_INFORMATION = 0x0400;

    const uint CONTEXT_i386 = 0x00010000;
    const uint CONTEXT_DEBUG_REGISTERS = CONTEXT_i386 | 0x00000010;
    const uint CONTEXT_INTEGER = CONTEXT_i386 | 0x00000002;
    const uint CONTEXT_CONTROL = CONTEXT_i386 | 0x00000001;
    const uint CONTEXT_CAPTURE = CONTEXT_DEBUG_REGISTERS | CONTEXT_INTEGER | CONTEXT_CONTROL;

    const uint SESSION_GLOBAL = 0x00DE4394;
    const uint NETWORK_GI = 0x00DE892C;
    const uint UI_INDEX = 0x00DEA114;
    const uint C54B78 = 0x00C54B78;

    [StructLayout(LayoutKind.Sequential)]
    public struct FLOATING_SAVE_AREA {
        public uint ControlWord, StatusWord, TagWord, ErrorOffset, ErrorSelector, DataOffset, DataSelector;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=80)] public byte[] RegisterArea;
        public uint Cr0NpxState;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct CONTEXT32 {
        public uint ContextFlags;
        public uint Dr0, Dr1, Dr2, Dr3, Dr6, Dr7;
        public FLOATING_SAVE_AREA FloatSave;
        public uint SegGs, SegFs, SegEs, SegDs;
        public uint Edi, Esi, Ebx, Edx, Ecx, Eax;
        public uint Ebp, Eip, SegCs, EFlags, Esp, SegSs;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=512)] public byte[] ExtendedRegisters;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct EXCEPTION_RECORD32 {
        public uint ExceptionCode;
        public uint ExceptionFlags;
        public uint ExceptionRecord;
        public uint ExceptionAddress;
        public uint NumberParameters;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=15)] public uint[] ExceptionInformation;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct EXCEPTION_DEBUG_INFO32 {
        public EXCEPTION_RECORD32 ExceptionRecord;
        public uint dwFirstChance;
    }

    [StructLayout(LayoutKind.Explicit, Size=84)]
    public struct DEBUG_EVENT_UNION32 {
        [FieldOffset(0)] public EXCEPTION_DEBUG_INFO32 Exception;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DEBUG_EVENT32 {
        public uint dwDebugEventCode;
        public uint dwProcessId;
        public uint dwThreadId;
        public DEBUG_EVENT_UNION32 u;
    }

    [DllImport("kernel32.dll", SetLastError=true)] static extern bool DebugActiveProcess(uint dwProcessId);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool DebugActiveProcessStop(uint dwProcessId);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool DebugSetProcessKillOnExit(bool KillOnExit);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool WaitForDebugEvent(out DEBUG_EVENT32 lpDebugEvent, uint dwMilliseconds);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ContinueDebugEvent(uint dwProcessId, uint dwThreadId, uint dwContinueStatus);

    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenThread(uint dwDesiredAccess, bool bInheritHandle, uint dwThreadId);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetThreadContext(IntPtr hThread, ref CONTEXT32 lpContext);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetThreadContext(IntPtr hThread, ref CONTEXT32 lpContext);
    [DllImport("kernel32.dll", SetLastError=true)] static extern uint SuspendThread(IntPtr hThread);
    [DllImport("kernel32.dll", SetLastError=true)] static extern uint ResumeThread(IntPtr hThread);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr address, byte[] buffer, UIntPtr size, out UIntPtr got);

    static CONTEXT32 NewContext(uint flags) {
        CONTEXT32 c = new CONTEXT32();
        c.ContextFlags = flags;
        c.FloatSave.RegisterArea = new byte[80];
        c.ExtendedRegisters = new byte[512];
        return c;
    }

    static uint ReadU32(IntPtr process, uint address) {
        if (address==0) return 0;
        byte[] b = new byte[4];
        UIntPtr got;
        if (!ReadProcessMemory(process, new IntPtr(unchecked((int)address)), b, new UIntPtr(4u), out got) || got.ToUInt64()!=4UL)
            return 0;
        return BitConverter.ToUInt32(b,0);
    }

    static bool ConfigureThread(uint tid, uint target, bool enable, bool suspendFirst) {
        IntPtr h = OpenThread(THREAD_ACCESS, false, tid);
        if (h == IntPtr.Zero) return false;
        bool suspended = false;
        try {
            if (suspendFirst) {
                uint r = SuspendThread(h);
                if (r == 0xFFFFFFFF) return false;
                suspended = true;
            }
            CONTEXT32 c = NewContext(CONTEXT_DEBUG_REGISTERS);
            if (!GetThreadContext(h, ref c)) return false;
            if (enable) {
                c.Dr0 = target;
                // DR0 local enable, EXECUTE condition (RW=00), 1-byte length (LEN=00).
                c.Dr7 &= ~0x000F0003u;
                c.Dr7 |= 0x00000001u;
                c.Dr6 = 0;
            } else {
                c.Dr0 = 0;
                c.Dr7 &= ~0x000F0003u;
                c.Dr6 = 0;
            }
            return SetThreadContext(h, ref c);
        } finally {
            if (suspended) ResumeThread(h);
            CloseHandle(h);
        }
    }

    static int ConfigureAllThreads(int pid, uint target, bool enable, bool suspendFirst) {
        int n=0;
        try {
            Process p = Process.GetProcessById(pid);
            foreach (ProcessThread t in p.Threads) {
                if (ConfigureThread((uint)t.Id,target,enable,suspendFirst)) n++;
            }
        } catch {}
        return n;
    }

    static bool CaptureThread(uint tid, out CONTEXT32 c) {
        c = NewContext(CONTEXT_CAPTURE);
        IntPtr h = OpenThread(THREAD_ACCESS,false,tid);
        if (h==IntPtr.Zero) return false;
        try { return GetThreadContext(h,ref c); }
        finally { CloseHandle(h); }
    }

    static string F(uint v) { return "0x"+v.ToString("X8"); }

    static void AppendState(StringBuilder log, IntPtr ph, CONTEXT32 c) {
        uint session = ReadU32(ph,SESSION_GLOBAL);
        uint state28 = session==0 ? 0 : ReadU32(ph,session+0x28);
        uint current = session==0 ? 0 : ReadU32(ph,session+0x44);
        uint network = ReadU32(ph,NETWORK_GI);
        uint uiIndex = ReadU32(ph,UI_INDEX);
        uint currentVt = current==0 ? 0 : ReadU32(ph,current);
        uint ownerState = c.Ecx==0 ? 0 : ReadU32(ph,c.Ecx+0x6A4);
        uint owner304 = c.Ecx==0 ? 0 : ReadU32(ph,c.Ecx+0x304);
        log.AppendLine("SESSION="+F(session)+" STATE28="+state28+" CURRENT="+F(current)+" CURRENT_VT="+F(currentVt));
        log.AppendLine("DE892C="+F(network)+" DEA114="+uiIndex);
        log.AppendLine("ECX_OWNER="+F(c.Ecx)+" OWNER_6A4="+ownerState+" OWNER_304="+owner304);
        log.AppendLine("CURRENT_IS_C54B78="+(currentVt==C54B78 ? "YES" : "NO"));
    }

    public static string Watch(int pid, uint target, int timeoutMs) {
        StringBuilder log = new StringBuilder();
        IntPtr ph = OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION,false,(uint)pid);
        if (ph==IntPtr.Zero) throw new InvalidOperationException("OpenProcess failed Win32="+Marshal.GetLastWin32Error());

        bool attached=false;
        bool eventPending=false;
        DEBUG_EVENT32 ev = new DEBUG_EVENT32();
        Stopwatch sw = Stopwatch.StartNew();
        int hitCount=0;
        try {
            DebugSetProcessKillOnExit(false);
            if (!DebugActiveProcess((uint)pid))
                throw new InvalidOperationException("DebugActiveProcess failed Win32="+Marshal.GetLastWin32Error());
            attached=true;
            log.AppendLine("DEBUG_ATTACH=OK");

            bool armed=false;
            while (sw.ElapsedMilliseconds < timeoutMs) {
                if (!WaitForDebugEvent(out ev,50)) continue;
                eventPending=true;

                if (!armed && (ev.dwDebugEventCode==CREATE_PROCESS_DEBUG_EVENT || ev.dwDebugEventCode==CREATE_THREAD_DEBUG_EVENT)) {
                    int count=ConfigureAllThreads(pid,target,true,false);
                    log.AppendLine("ARMED_THREADS="+count);
                    armed=true;
                } else if (armed && ev.dwDebugEventCode==CREATE_THREAD_DEBUG_EVENT) {
                    ConfigureThread(ev.dwThreadId,target,true,false);
                }

                uint cont=DBG_CONTINUE;
                bool stop=false;

                if (ev.dwDebugEventCode==EXCEPTION_DEBUG_EVENT) {
                    uint code=ev.u.Exception.ExceptionRecord.ExceptionCode;
                    if (code==EXCEPTION_SINGLE_STEP) {
                        CONTEXT32 c;
                        if (CaptureThread(ev.dwThreadId,out c) && (c.Dr6 & 1u)!=0) {
                            hitCount++;
                            log.AppendLine("EXEC_HIT=YES");
                            log.AppendLine("HIT_COUNT="+hitCount);
                            log.AppendLine("ELAPSED_MS="+sw.Elapsed.TotalMilliseconds.ToString("F3",System.Globalization.CultureInfo.InvariantCulture));
                            log.AppendLine("THREAD_ID="+ev.dwThreadId);
                            log.AppendLine("EXCEPTION_ADDRESS="+F(ev.u.Exception.ExceptionRecord.ExceptionAddress));
                            log.AppendLine("EIP="+F(c.Eip));
                            log.AppendLine("DR6="+F(c.Dr6)+" DR7="+F(c.Dr7));
                            log.AppendLine("EAX="+F(c.Eax)+" EBX="+F(c.Ebx)+" ECX="+F(c.Ecx)+" EDX="+F(c.Edx));
                            log.AppendLine("ESI="+F(c.Esi)+" EDI="+F(c.Edi)+" EBP="+F(c.Ebp)+" ESP="+F(c.Esp));
                            AppendState(log,ph,c);
                            ConfigureAllThreads(pid,target,false,false);
                            stop=true;
                        }
                    } else if (code==EXCEPTION_BREAKPOINT) {
                        cont=DBG_CONTINUE;
                    } else {
                        cont=DBG_EXCEPTION_NOT_HANDLED;
                    }
                }

                if (!ContinueDebugEvent(ev.dwProcessId,ev.dwThreadId,cont))
                    throw new InvalidOperationException("ContinueDebugEvent failed Win32="+Marshal.GetLastWin32Error());
                eventPending=false;
                if (stop) break;
                if (ev.dwDebugEventCode==EXIT_PROCESS_DEBUG_EVENT) {
                    log.AppendLine("PROCESS_EXITED=YES");
                    break;
                }
            }

            if (hitCount==0) {
                log.AppendLine("EXEC_HIT=NO");
                CONTEXT32 z = NewContext(CONTEXT_CAPTURE);
                AppendState(log,ph,z);
            }
        }
        finally {
            try {
                if (eventPending) {
                    ConfigureAllThreads(pid,target,false,false);
                    ContinueDebugEvent(ev.dwProcessId,ev.dwThreadId,DBG_CONTINUE);
                    eventPending=false;
                } else if (attached) {
                    ConfigureAllThreads(pid,target,false,true);
                }
            } catch {}
            if (attached) {
                try { DebugActiveProcessStop((uint)pid); } catch {}
            }
            if (ph!=IntPtr.Zero) CloseHandle(ph);
        }
        return log.ToString();
    }
}
'@
}

Write-Output '============================================================'
Write-Output ' AOTR WOTR FRONTEND COMPLETION 0x84944F EXEC WATCH'
Write-Output '============================================================'
Write-Output ("PID          : {0}" -f $ProcessId)
Write-Output ("Image        : {0}" -f $GameDat)
Write-Output ("SHA256       : {0}" -f $hash)
Write-Output ("Break address: 0x{0:X8}" -f $BreakAddress)
Write-Output ("Timeout      : {0}s" -f $TimeoutSeconds)
Write-Output ''
Write-Output 'Run this while the VM is in the normal browser, then invoke the LOW-LEVEL native join PoC from a second console.'
Write-Output 'The debugger uses DR0/DR7 execution breakpoint only; it does not patch game memory or call game functions.'
Write-Output ''

$result = [AotrExecWatch32]::Watch($ProcessId,$BreakAddress,$TimeoutSeconds*1000)
Write-Output $result
Write-Output 'WATCH COMPLETE. No WriteProcessMemory or game-function call was used by this watcher.'
