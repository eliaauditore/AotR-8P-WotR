param(
    [string]$Label = 'NODE',
    [string]$OutputDir = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# STANDALONE DIRECT CAPTURE.
# No generator, no source transform, no nested runner.
# Windows PowerShell 5.1 + PowerShell 7 compatible.
# game.dat on disk is never modified.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$HookRva = [int64]0x006211DF
$MgrGlobalRva = [int64]0x009E3380
$ExpectedOriginal = [byte[]](0x55,0x8B,0xEC,0x83,0x7D,0x0C,0x00)
$AllocSize = 0x04000000
$StubOffset = 0x100
$DataOffset = 0x1000
$DataCapacity = $AllocSize - $DataOffset

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

if (-not ('A8PCompactFinalNative' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PCompactFinalNative {
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr n, out IntPtr got);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr n, out IntPtr wrote);
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr addr, UIntPtr size, UInt32 type, UInt32 protect);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool VirtualFreeEx(IntPtr h, IntPtr addr, UIntPtr size, UInt32 type);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool VirtualProtectEx(IntPtr h, IntPtr addr, UIntPtr size, UInt32 newProtect, out UInt32 oldProtect);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool FlushInstructionCache(IntPtr h, IntPtr addr, UIntPtr size);

    const UInt32 PROCESS_QUERY_INFORMATION=0x0400, PROCESS_VM_OPERATION=0x0008, PROCESS_VM_READ=0x0010, PROCESS_VM_WRITE=0x0020;
    const UInt32 MEM_COMMIT=0x1000, MEM_RESERVE=0x2000, MEM_RELEASE=0x8000;
    const UInt32 PAGE_EXECUTE_READWRITE=0x40;

    public static IntPtr Open(UInt32 pid) {
        IntPtr h=OpenProcess(PROCESS_QUERY_INFORMATION|PROCESS_VM_OPERATION|PROCESS_VM_READ|PROCESS_VM_WRITE,false,pid);
        if(h==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"OpenProcess failed");
        return h;
    }
    public static void Close(IntPtr h) { if(h!=IntPtr.Zero) CloseHandle(h); }
    public static byte[] Read(IntPtr h, Int64 addr, Int32 count) {
        byte[] b=new byte[count]; IntPtr got;
        if(!ReadProcessMemory(h,new IntPtr(addr),b,new IntPtr(count),out got) || got.ToInt64()!=count)
            throw new Win32Exception(Marshal.GetLastWin32Error(),"ReadProcessMemory failed at 0x"+addr.ToString("X8"));
        return b;
    }
    public static void Write(IntPtr h, Int64 addr, byte[] b) {
        IntPtr wrote;
        if(!WriteProcessMemory(h,new IntPtr(addr),b,new IntPtr(b.Length),out wrote) || wrote.ToInt64()!=b.Length)
            throw new Win32Exception(Marshal.GetLastWin32Error(),"WriteProcessMemory failed at 0x"+addr.ToString("X8"));
    }
    public static IntPtr Alloc(IntPtr h, Int32 size) {
        IntPtr p=VirtualAllocEx(h,IntPtr.Zero,new UIntPtr((UInt32)size),MEM_COMMIT|MEM_RESERVE,PAGE_EXECUTE_READWRITE);
        if(p==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"VirtualAllocEx failed");
        return p;
    }
    public static void Free(IntPtr h, IntPtr p) {
        if(p!=IntPtr.Zero && !VirtualFreeEx(h,p,UIntPtr.Zero,MEM_RELEASE))
            throw new Win32Exception(Marshal.GetLastWin32Error(),"VirtualFreeEx failed");
    }
    public static UInt32 ProtectRWX(IntPtr h, Int64 addr, Int32 len) {
        UInt32 oldp;
        if(!VirtualProtectEx(h,new IntPtr(addr),new UIntPtr((UInt32)len),PAGE_EXECUTE_READWRITE,out oldp))
            throw new Win32Exception(Marshal.GetLastWin32Error(),"VirtualProtectEx failed");
        return oldp;
    }
    public static void Protect(IntPtr h, Int64 addr, Int32 len, UInt32 prot) {
        UInt32 oldp;
        if(!VirtualProtectEx(h,new IntPtr(addr),new UIntPtr((UInt32)len),prot,out oldp))
            throw new Win32Exception(Marshal.GetLastWin32Error(),"VirtualProtectEx restore failed");
    }
    public static void Flush(IntPtr h, Int64 addr, Int32 len) {
        if(!FlushInstructionCache(h,new IntPtr(addr),new UIntPtr((UInt32)len)))
            throw new Win32Exception(Marshal.GetLastWin32Error(),"FlushInstructionCache failed");
    }

    static void U32(List<byte> b, UInt32 v) { b.Add((byte)v); b.Add((byte)(v>>8)); b.Add((byte)(v>>16)); b.Add((byte)(v>>24)); }
    static void I32At(List<byte> b, int pos, Int32 v) {
        byte[] q=BitConverter.GetBytes(v); for(int i=0;i<4;i++) b[pos+i]=q[i];
    }
    static int Jcc(List<byte> b, byte cc) { b.Add(0x0F); b.Add(cc); int p=b.Count; U32(b,0); return p; }
    static int Jmp(List<byte> b) { b.Add(0xE9); int p=b.Count; U32(b,0); return p; }
    static void Patch(List<byte> b, int dispPos, int targetPos) { I32At(b,dispPos,targetPos-(dispPos+4)); }

    public static byte[] BuildStub(UInt32 remoteBase, UInt32 continueVa, UInt32 capacity, UInt32 rootMgrGlobalVa) {
        UInt32 offAddr=remoteBase+0x00, countAddr=remoteBase+0x04, overflowAddr=remoteBase+0x08, dataBase=remoteBase+0x1000;
        var b=new List<byte>();
        b.Add(0x9C);
        b.Add(0x60);

        b.Add(0xA1); U32(b,rootMgrGlobalVa);
        b.AddRange(new byte[]{0x85,0xC0});
        int jDoneNoMgr=Jcc(b,0x84);
        b.AddRange(new byte[]{0x8B,0x40,0x24});
        b.AddRange(new byte[]{0x85,0xC0});
        int jDoneNoRoot=Jcc(b,0x84);
        b.AddRange(new byte[]{0x3B,0x44,0x24,0x18});
        int jDoneOther=Jcc(b,0x85);

        b.AddRange(new byte[]{0x8B,0x1D}); U32(b,offAddr);
        b.AddRange(new byte[]{0x8B,0xC3});
        b.AddRange(new byte[]{0x83,0xC0,0x14});
        b.Add(0x3D); U32(b,capacity);
        int jOverflow=Jcc(b,0x87);

        b.Add(0xA1); U32(b,countAddr);
        b.Add(0x40);
        b.Add(0xA3); U32(b,countAddr);
        b.Add(0xBF); U32(b,dataBase);
        b.AddRange(new byte[]{0x03,0xFB});
        b.AddRange(new byte[]{0x89,0x07});

        b.AddRange(new byte[]{0x8B,0x44,0x24,0x18});
        b.AddRange(new byte[]{0x89,0x47,0x04});
        b.AddRange(new byte[]{0x8B,0x54,0x24,0x28});
        b.AddRange(new byte[]{0x89,0x57,0x08});
        b.AddRange(new byte[]{0x8B,0x54,0x24,0x30});
        b.AddRange(new byte[]{0x89,0x57,0x0C});
        b.AddRange(new byte[]{0x8B,0x40,0x44});
        b.AddRange(new byte[]{0x89,0x47,0x10});

        b.AddRange(new byte[]{0x8B,0xC3});
        b.AddRange(new byte[]{0x83,0xC0,0x14});
        b.Add(0xA3); U32(b,offAddr);
        int jDoneLogged=Jmp(b);

        int overflow=b.Count;
        Patch(b,jOverflow,overflow);
        b.AddRange(new byte[]{0xC7,0x05}); U32(b,overflowAddr); U32(b,1);

        int done=b.Count;
        Patch(b,jDoneNoMgr,done); Patch(b,jDoneNoRoot,done); Patch(b,jDoneOther,done); Patch(b,jDoneLogged,done);
        b.Add(0x61);
        b.Add(0x9D);

        b.Add(0x55);
        b.AddRange(new byte[]{0x8B,0xEC});
        b.AddRange(new byte[]{0x83,0x7D,0x0C,0x00});
        b.Add(0xE9);
        UInt32 stubVa=remoteBase+0x100;
        UInt32 next=(UInt32)(stubVa+b.Count+4);
        Int32 rel=unchecked((Int32)(continueVa-next));
        U32(b,unchecked((UInt32)rel));
        return b.ToArray();
    }

    public static byte[] BuildHook(UInt32 hookVa, UInt32 stubVa) {
        byte[] p=new byte[7]; p[0]=0xE9;
        Int32 rel=unchecked((Int32)(stubVa-(hookVa+5)));
        byte[] q=BitConverter.GetBytes(rel); Array.Copy(q,0,p,1,4); p[5]=0x90; p[6]=0x90;
        return p;
    }
}
"@
}

function U32([byte[]]$b,[int]$o=0) { [BitConverter]::ToUInt32($b,$o) }
function RBytes([IntPtr]$h,[int64]$a,[int]$n) { [A8PCompactFinalNative]::Read($h,$a,$n) }
function RU32([IntPtr]$h,[int64]$a) { U32 (RBytes $h $a 4) 0 }
function HexBytes([byte[]]$b) { ([BitConverter]::ToString($b)).Replace('-','') }

$existing = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'game.dat' })
if ($existing.Count -gt 0) {
    throw "A game.dat is already running (PID(s): $($existing.ProcessId -join ',')). Close it first. Start this capture before launching AotR."
}

Write-Host '============================================================'
Write-Host ' AOTR WOTR LOCALROOT COMPACT FINAL DIRECT'
Write-Host '============================================================'
Write-Host ("Label                : {0}" -f $Label)
Write-Host 'Mode                 : standalone direct compact trace -> raw BIN'
Write-Host 'Compatibility        : Windows PowerShell 5.1 / PowerShell 7'
Write-Host 'Waiting for fresh game.dat...'

$procInfo = $null
while (-not $procInfo) {
    Start-Sleep -Milliseconds 25
    $cand = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'game.dat' -and $_.ExecutablePath })
    if ($cand.Count -eq 1) { $procInfo = $cand[0] }
    elseif ($cand.Count -gt 1) { throw 'More than one game.dat appeared; aborting.' }
}

$gamePid = [int]$procInfo.ProcessId
$exe = [string]$procInfo.ExecutablePath
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH - expected $ExpectedHash, got $hash" }
$proc = Get-Process -Id $gamePid -ErrorAction Stop
$base = $proc.MainModule.BaseAddress.ToInt64()
$hook = $base + $HookRva
$continue = $hook + 7

Write-Host ("PID                  : {0}" -f $gamePid)
Write-Host ("Image                : {0}" -f $exe)
Write-Host ("SHA256               : {0}" -f $hash)
Write-Host ("Runtime base         : 0x{0:X8}" -f $base)
Write-Host ("Hook VA              : 0x{0:X8}" -f $hook)

$h = [IntPtr]::Zero
$remote = [IntPtr]::Zero
$patched = $false
$oldProtect = [uint32]0
$rootSeen = $false
$root = [uint32]0
$rootVT = [uint32]0
$traceBytes = $null
$writeOff = [uint32]0
$callCount = [uint32]0
$overflow = [uint32]0

try {
    $h = [A8PCompactFinalNative]::Open([uint32]$gamePid)

    $actual = RBytes $h $hook 7
    if ((HexBytes $actual) -ne (HexBytes $ExpectedOriginal)) {
        throw "HOOK BYTE MISMATCH at 0x$('{0:X8}' -f $hook). Expected $(HexBytes $ExpectedOriginal), got $(HexBytes $actual)"
    }

    $remote = [A8PCompactFinalNative]::Alloc($h,$AllocSize)
    $remoteBase = [uint32]$remote.ToInt64()
    $stubVa = $remoteBase + [uint32]$StubOffset
    $stub = [A8PCompactFinalNative]::BuildStub($remoteBase,[uint32]$continue,[uint32]$DataCapacity,[uint32]($base + $MgrGlobalRva))
    [A8PCompactFinalNative]::Write($h,[int64]$stubVa,$stub)

    $hookBytes = [A8PCompactFinalNative]::BuildHook([uint32]$hook,$stubVa)
    $oldProtect = [A8PCompactFinalNative]::ProtectRWX($h,$hook,7)
    [A8PCompactFinalNative]::Write($h,$hook,$hookBytes)
    [A8PCompactFinalNative]::Flush($h,$hook,7)
    $patched = $true

    Write-Host ("Remote scratch       : 0x{0:X8}" -f $remoteBase)
    Write-Host ("Stub VA              : 0x{0:X8}" -f $stubVa)
    Write-Host 'Hook installed       : YES (exact-byte guarded)'
    Write-Host 'Waiting for localRoot publication...'

    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not (Get-Process -Id $gamePid -ErrorAction SilentlyContinue)) {
            throw 'game.dat exited before localRoot capture completed.'
        }
        $mgr = RU32 $h ($base + $MgrGlobalRva)
        if ($mgr -ne 0) {
            $cur = RU32 $h ([int64]$mgr + 0x24)
            if ($cur -ne 0 -and -not $rootSeen) {
                $rootSeen = $true
                $root = [uint32]$cur
                $rootVT = RU32 $h ([int64]$root)
                Write-Host ("localRoot published  : 0x{0:X8}" -f $root)
                Write-Host ("localRoot vtable     : 0x{0:X8}" -f $rootVT)
            }
            elseif ($rootSeen -and $cur -eq 0) {
                break
            }
        }
        Start-Sleep -Milliseconds 1
    }

    if (-not $rootSeen) { throw 'localRoot was never observed within timeout.' }

    Start-Sleep -Milliseconds 100

    [A8PCompactFinalNative]::Write($h,$hook,$ExpectedOriginal)
    [A8PCompactFinalNative]::Flush($h,$hook,7)
    [A8PCompactFinalNative]::Protect($h,$hook,7,$oldProtect)
    $patched = $false
    Write-Host 'Hook restored        : YES'

    $writeOff = RU32 $h ($remoteBase + 0)
    $callCount = RU32 $h ($remoteBase + 4)
    $overflow = RU32 $h ($remoteBase + 8)
    if ($writeOff -gt $DataCapacity) { throw "Remote write offset invalid: $writeOff" }

    $traceBytes = if ($writeOff -gt 0) {
        RBytes $h ($remoteBase + $DataOffset) ([int]$writeOff)
    }
    else {
        [byte[]]@()
    }

    Write-Host ("Captured calls       : {0}" -f $callCount)
    Write-Host ("Captured bytes       : {0}" -f $writeOff)
    Write-Host ("Overflow             : {0}" -f $overflow)

    if (($writeOff % 20) -ne 0) {
        throw "Raw compact trace byte count $writeOff is not divisible by 20."
    }
    if ([uint32]($writeOff / 20) -ne $callCount) {
        throw "Record-count mismatch: header calls=$callCount, bytes/20=$([uint32]($writeOff/20))."
    }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $safeLabel = ($Label -replace '[^A-Za-z0-9_.-]','_')
    $rawBin = Join-Path $OutputDir ("AOTR_WOTR_LOCALROOT_COMPACT_FINAL_{0}_{1}.bin" -f $safeLabel,$stamp)
    [System.IO.File]::WriteAllBytes($rawBin,$traceBytes)
    $rawItem = Get-Item -LiteralPath $rawBin
    $rawSha = (Get-FileHash -LiteralPath $rawBin -Algorithm SHA256).Hash.ToUpperInvariant()

    Write-Host ''
    Write-Host '================ FINAL DIRECT SUMMARY ==================='
    Write-Host ("Label                : {0}" -f $Label)
    Write-Host ("localRoot            : 0x{0:X8}" -f $root)
    Write-Host ("localRoot vtable     : 0x{0:X8}" -f $rootVT)
    Write-Host ("Records              : {0}" -f $callCount)
    Write-Host ("Bytes                : {0}" -f $writeOff)
    Write-Host ("Overflow             : {0}" -f $overflow)
    Write-Host ("RAW BIN              : {0}" -f $rawBin)
    Write-Host ("RAW BIN bytes        : {0}" -f $rawItem.Length)
    Write-Host ("RAW BIN SHA256       : {0}" -f $rawSha)
    Write-Host ("FINAL_DIRECT_KEY     : LABEL={0};ROOTVT={1:X8};RECORDS={2};BYTES={3};OVERFLOW={4};SHA256={5}" -f $Label,$rootVT,$callCount,$writeOff,$overflow,$rawSha)
    Write-Host 'FINAL_DIRECT_CAPTURE_COMPLETE=YES'
}
finally {
    if ($h -ne [IntPtr]::Zero -and $patched) {
        try {
            [A8PCompactFinalNative]::Write($h,$hook,$ExpectedOriginal)
            [A8PCompactFinalNative]::Flush($h,$hook,7)
            if ($oldProtect -ne 0) { [A8PCompactFinalNative]::Protect($h,$hook,7,$oldProtect) }
            Write-Host 'Emergency rollback   : original hook bytes restored'
        }
        catch {
            Write-Warning "Emergency rollback failed: $($_.Exception.Message)"
        }
    }

    if ($h -ne [IntPtr]::Zero -and $remote -ne [IntPtr]::Zero) {
        try { [A8PCompactFinalNative]::Free($h,$remote) } catch { Write-Warning $_.Exception.Message }
    }
    if ($h -ne [IntPtr]::Zero) {
        [A8PCompactFinalNative]::Close($h)
    }
}
