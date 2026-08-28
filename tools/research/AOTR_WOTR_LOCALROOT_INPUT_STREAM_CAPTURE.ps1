param(
    [string]$Label = 'NODE',
    [string]$OutputDir = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# CONTROLLED PROCESS-ONLY INSTRUMENTATION.
# Exact-hash + exact-byte guarded. Hooks only native serializer method 0xA211DF
# in a fresh game.dat process, records (this, tag, len, payload) into remote
# scratch memory, then restores the exact original bytes before exit.
# No game.dat file is modified.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$HookRva = [int64]0x006211DF            # VA 0x00A211DF at image base 0x00400000
$MgrGlobalRva = [int64]0x009E3380       # VA 0x00DE3380
$B04MgrGlobalRva = [int64]0x009E4364    # VA 0x00DE4364
$CompBGlobalRva = [int64]0x009E3D84     # VA 0x00DE3D84
$ExpectedOriginal = [byte[]](0x55,0x8B,0xEC,0x83,0x7D,0x0C,0x00)
$AllocSize = 0x01000000                  # 16 MiB
$StubOffset = 0x100
$DataOffset = 0x1000
$DataCapacity = $AllocSize - $DataOffset

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

if (-not ('A8PInputTraceNative' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PInputTraceNative {
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

    public static byte[] BuildStub(UInt32 remoteBase, UInt32 continueVa, UInt32 capacity) {
        UInt32 offAddr=remoteBase+0x00, countAddr=remoteBase+0x04, overflowAddr=remoteBase+0x08, dataBase=remoteBase+0x1000;
        var b=new List<byte>();
        b.Add(0x9C);                    // pushfd
        b.Add(0x60);                    // pushad
        b.AddRange(new byte[]{0x8B,0x1D}); U32(b,offAddr);        // mov ebx,[off]
        b.AddRange(new byte[]{0x8B,0x6C,0x24,0x30});              // mov ebp,[esp+30] len
        b.AddRange(new byte[]{0x8B,0x74,0x24,0x2C});              // mov esi,[esp+2C] data
        b.AddRange(new byte[]{0x8B,0x54,0x24,0x28});              // mov edx,[esp+28] tag
        b.AddRange(new byte[]{0x85,0xF6});                        // test esi,esi
        int jHasPtr1=Jcc(b,0x85);                                 // jne hasPtr
        b.AddRange(new byte[]{0x85,0xED});                        // test ebp,ebp
        int jHasPtr2=Jcc(b,0x84);                                 // je hasPtr (zero len)
        b.AddRange(new byte[]{0x31,0xED});                        // xor ebp,ebp (NULL data => logged len 0)
        int hasPtr=b.Count;
        Patch(b,jHasPtr1,hasPtr); Patch(b,jHasPtr2,hasPtr);
        b.AddRange(new byte[]{0x81,0xFD}); U32(b,0x00100000);     // cmp ebp,1 MiB
        int jOverflow1=Jcc(b,0x87);                               // ja overflow
        b.AddRange(new byte[]{0x8B,0xC3});                        // mov eax,ebx
        b.AddRange(new byte[]{0x03,0xC5});                        // add eax,ebp
        b.AddRange(new byte[]{0x83,0xC0,0x10});                   // add eax,16
        b.Add(0x3D); U32(b,capacity);                             // cmp eax,capacity
        int jOverflow2=Jcc(b,0x87);                               // ja overflow
        b.Add(0xA1); U32(b,countAddr);                            // mov eax,[count]
        b.Add(0x40);                                              // inc eax
        b.Add(0xA3); U32(b,countAddr);                            // mov [count],eax
        b.Add(0xBF); U32(b,dataBase);                             // mov edi,dataBase
        b.AddRange(new byte[]{0x03,0xFB});                        // add edi,ebx
        b.AddRange(new byte[]{0x89,0x07});                        // [edi]=index
        b.AddRange(new byte[]{0x8B,0x4C,0x24,0x18});              // ecx=saved original ECX (this)
        b.AddRange(new byte[]{0x89,0x4F,0x04});                   // [edi+4]=this
        b.AddRange(new byte[]{0x89,0x57,0x08});                   // [edi+8]=tag
        b.AddRange(new byte[]{0x89,0x6F,0x0C});                   // [edi+12]=len
        b.AddRange(new byte[]{0x83,0xC7,0x10});                   // edi+=16
        b.AddRange(new byte[]{0x8B,0xCD});                        // ecx=ebp
        b.AddRange(new byte[]{0x85,0xC9});                        // test ecx,ecx
        int jAfterCopy=Jcc(b,0x84);                               // je afterCopy
        b.AddRange(new byte[]{0xF3,0xA4});                        // rep movsb
        int afterCopy=b.Count; Patch(b,jAfterCopy,afterCopy);
        b.AddRange(new byte[]{0x8B,0xC3});                        // eax=old off
        b.AddRange(new byte[]{0x03,0xC5});                        // +len
        b.AddRange(new byte[]{0x83,0xC0,0x10});                   // +header
        b.Add(0xA3); U32(b,offAddr);                              // [off]=eax
        int jDone=Jmp(b);
        int overflow=b.Count;
        Patch(b,jOverflow1,overflow); Patch(b,jOverflow2,overflow);
        b.AddRange(new byte[]{0xC7,0x05}); U32(b,overflowAddr); U32(b,1); // overflow=1
        int done=b.Count; Patch(b,jDone,done);
        b.Add(0x61);                                              // popad
        b.Add(0x9D);                                              // popfd
        b.Add(0x55);                                              // stolen push ebp
        b.AddRange(new byte[]{0x8B,0xEC});                        // stolen mov ebp,esp
        b.AddRange(new byte[]{0x83,0x7D,0x0C,0x00});              // stolen cmp [ebp+0C],0
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
function RBytes([IntPtr]$h,[int64]$a,[int]$n) { [A8PInputTraceNative]::Read($h,$a,$n) }
function RU32([IntPtr]$h,[int64]$a) { U32 (RBytes $h $a 4) 0 }
function HexBytes([byte[]]$b) { [Convert]::ToHexString($b) }
function TagAscii([uint32]$v) {
    $c = @(
        [char](($v -shr 24) -band 0xFF),
        [char](($v -shr 16) -band 0xFF),
        [char](($v -shr 8) -band 0xFF),
        [char]($v -band 0xFF)
    )
    $s = -join $c
    if ($s.ToCharArray() | Where-Object { [int]$_ -lt 32 -or [int]$_ -gt 126 }) { return '....' }
    return $s
}
function Rol1([uint32]$v) { return [uint32]((([uint64]$v -shl 1) -bor ([uint64]$v -shr 31)) -band 0xFFFFFFFF) }

$existing = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'game.dat' })
if ($existing.Count -gt 0) {
    throw "A game.dat is already running (PID(s): $($existing.ProcessId -join ',')). Close it first. Start this capture before launching AotR."
}

Write-Host '============================================================'
Write-Host ' AOTR WOTR LOCALROOT INPUT-STREAM CAPTURE'
Write-Host '============================================================'
Write-Host ("Label                : {0}" -f $Label)
Write-Host 'Mode                 : controlled process-only instrumentation'
Write-Host 'Waiting for fresh game.dat...'

$procInfo = $null
while (-not $procInfo) {
    Start-Sleep -Milliseconds 25
    $cand = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'game.dat' -and $_.ExecutablePath })
    if ($cand.Count -eq 1) { $procInfo = $cand[0] }
    elseif ($cand.Count -gt 1) { throw 'More than one game.dat appeared; aborting.' }
}

$pid = [int]$procInfo.ProcessId
$exe = [string]$procInfo.ExecutablePath
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH - expected $ExpectedHash, got $hash" }
$proc = Get-Process -Id $pid -ErrorAction Stop
$base = $proc.MainModule.BaseAddress.ToInt64()
$hook = $base + $HookRva
$continue = $hook + 7

Write-Host ("PID                  : {0}" -f $pid)
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
$globalDerivedA = $null
$b04 = $null
$componentB = $null

try {
    $h = [A8PInputTraceNative]::Open([uint32]$pid)
    $actual = RBytes $h $hook 7
    if ((HexBytes $actual) -ne (HexBytes $ExpectedOriginal)) {
        throw "HOOK BYTE MISMATCH at 0x$('{0:X8}' -f $hook). Expected $(HexBytes $ExpectedOriginal), got $(HexBytes $actual)"
    }

    $remote = [A8PInputTraceNative]::Alloc($h,$AllocSize)
    $remoteBase = [uint32]$remote.ToInt64()
    $stubVa = $remoteBase + [uint32]$StubOffset
    $stub = [A8PInputTraceNative]::BuildStub($remoteBase,[uint32]$continue,[uint32]$DataCapacity)
    [A8PInputTraceNative]::Write($h,[int64]$stubVa,$stub)
    $hookBytes = [A8PInputTraceNative]::BuildHook([uint32]$hook,$stubVa)
    $oldProtect = [A8PInputTraceNative]::ProtectRWX($h,$hook,7)
    [A8PInputTraceNative]::Write($h,$hook,$hookBytes)
    [A8PInputTraceNative]::Flush($h,$hook,7)
    $patched = $true

    Write-Host ("Remote scratch       : 0x{0:X8}" -f $remoteBase)
    Write-Host ("Stub VA              : 0x{0:X8}" -f $stubVa)
    Write-Host 'Hook installed       : YES (exact-byte guarded)'
    Write-Host 'Waiting for localRoot publication...'

    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not (Get-Process -Id $pid -ErrorAction SilentlyContinue)) { throw 'game.dat exited before localRoot capture completed.' }
        $mgr = RU32 $h ($base + $MgrGlobalRva)
        if ($mgr -ne 0) {
            $cur = RU32 $h ([int64]$mgr + 0x24)
            if ($cur -ne 0 -and -not $rootSeen) {
                $rootSeen = $true; $root = [uint32]$cur
                $rootVT = RU32 $h ([int64]$root)
                Write-Host ("localRoot published  : 0x{0:X8}" -f $root)
                Write-Host ("localRoot vtable     : 0x{0:X8}" -f $rootVT)
            } elseif ($rootSeen -and $cur -eq 0) {
                break
            }
        }
        Start-Sleep -Milliseconds 1
    }
    if (-not $rootSeen) { throw 'localRoot was never observed within timeout.' }

    Start-Sleep -Milliseconds 100

    # Restore hook BEFORE parsing/copying any trace.
    [A8PInputTraceNative]::Write($h,$hook,$ExpectedOriginal)
    [A8PInputTraceNative]::Flush($h,$hook,7)
    [A8PInputTraceNative]::Protect($h,$hook,7,$oldProtect)
    $patched = $false
    Write-Host 'Hook restored        : YES'

    $writeOff = RU32 $h ($remoteBase + 0)
    $callCount = RU32 $h ($remoteBase + 4)
    $overflow = RU32 $h ($remoteBase + 8)
    if ($writeOff -gt $DataCapacity) { throw "Remote write offset invalid: $writeOff" }
    $traceBytes = if ($writeOff -gt 0) { RBytes $h ($remoteBase + $DataOffset) ([int]$writeOff) } else { [byte[]]@() }

    # Reliable post-build A derivation from the already-proven B04 = A+B formula.
    try {
        $b04Mgr = RU32 $h ($base + $B04MgrGlobalRva)
        $compObj = RU32 $h ($base + $CompBGlobalRva)
        if ($b04Mgr -ne 0 -and $compObj -ne 0) {
            $b04 = RU32 $h ([int64]$b04Mgr + 0xB04)
            $componentB = RU32 $h ([int64]$compObj + 0x200)
            $globalDerivedA = [uint32]((([uint64]$b04 + [uint64]4294967296 - [uint64]$componentB) % [uint64]4294967296))
        }
    } catch { }

    Write-Host ("Captured calls       : {0}" -f $callCount)
    Write-Host ("Captured bytes       : {0}" -f $writeOff)
    Write-Host ("Overflow             : {0}" -f $overflow)
}
finally {
    if ($h -ne [IntPtr]::Zero) {
        if ($patched) {
            try {
                [A8PInputTraceNative]::Write($h,$hook,$ExpectedOriginal)
                [A8PInputTraceNative]::Flush($h,$hook,7)
                if ($oldProtect -ne 0) { [A8PInputTraceNative]::Protect($h,$hook,7,$oldProtect) }
                Write-Host 'Emergency rollback   : original hook bytes restored'
            } catch {
                Write-Warning "Emergency rollback failed: $($_.Exception.Message)"
            }
        }
    }
}

if ($null -eq $traceBytes) { throw 'No trace buffer was captured.' }

$records = New-Object System.Collections.Generic.List[object]
$pos = 0
while ($pos -lt $traceBytes.Length) {
    if ($pos + 16 -gt $traceBytes.Length) { throw "Truncated record header at offset $pos" }
    $idx = [BitConverter]::ToUInt32($traceBytes,$pos)
    $thisPtr = [BitConverter]::ToUInt32($traceBytes,$pos+4)
    $tag = [BitConverter]::ToUInt32($traceBytes,$pos+8)
    $len = [BitConverter]::ToUInt32($traceBytes,$pos+12)
    $pos += 16
    if ([uint64]$pos + [uint64]$len -gt [uint64]$traceBytes.Length) { throw "Truncated payload at record $idx" }
    $payload = New-Object byte[] ([int]$len)
    if ($len -gt 0) { [Array]::Copy($traceBytes,$pos,$payload,0,[int]$len) }
    $pos += [int]$len
    $records.Add([pscustomobject]@{ Index=[uint32]$idx; This=[uint32]$thisPtr; Tag=[uint32]$tag; Len=[uint32]$len; Payload=$payload })
}

$local = @($records | Where-Object { $_.This -eq $root })
$acc = [uint32]0
$totalPayload = [uint64]0
foreach ($r in $local) {
    $p = [byte[]]$r.Payload
    $totalPayload += [uint64]$p.Length
    $i = 0
    while ($i + 4 -le $p.Length) {
        $u = [BitConverter]::ToUInt32($p,$i)
        $acc = [uint32](([uint64](Rol1 $acc) + [uint64]$u) -band 0xFFFFFFFF)
        $i += 4
    }
    while ($i -lt $p.Length) {
        $acc = [uint32](([uint64](Rol1 $acc) + [uint64]$p[$i]) -band 0xFFFFFFFF)
        $i++
    }
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$safeLabel = ($Label -replace '[^A-Za-z0-9_.-]','_')
$tsv = Join-Path $OutputDir ("AOTR_WOTR_LOCALROOT_STREAM_{0}_{1}.tsv" -f $safeLabel,$stamp)
$sw = [System.IO.StreamWriter]::new($tsv,$false,[System.Text.UTF8Encoding]::new($false))
try {
    $sw.WriteLine("index`tthis_hex`ttag_hex`ttag_ascii`tlen`tpayload_sha256`tpayload_hex")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        foreach ($r in $local) {
            $payload = [byte[]]$r.Payload
            $ph = [Convert]::ToHexString($sha.ComputeHash($payload))
            $px = [Convert]::ToHexString($payload)
            $sw.WriteLine(("{0}`t{1:X8}`t{2:X8}`t{3}`t{4}`t{5}`t{6}" -f $r.Index,$r.This,$r.Tag,(TagAscii $r.Tag),$r.Len,$ph,$px))
        }
    } finally { $sha.Dispose() }
} finally { $sw.Dispose() }

Write-Host ''
Write-Host '================ LOCALROOT STREAM SUMMARY ================'
Write-Host ("localRoot            : 0x{0:X8}" -f $root)
Write-Host ("localRoot vtable     : 0x{0:X8}" -f $rootVT)
Write-Host ("localRoot calls      : {0}" -f $local.Count)
Write-Host ("localRoot payload B  : {0}" -f $totalPayload)
Write-Host ("replayed Component A : 0x{0:X8}" -f $acc)
if ($null -ne $globalDerivedA) {
    Write-Host ("B04 live             : 0x{0:X8}" -f $b04)
    Write-Host ("Component B          : 0x{0:X8}" -f $componentB)
    Write-Host ("derived Component A  : 0x{0:X8}" -f $globalDerivedA)
    Write-Host ("REPLAY_MATCH         : {0}" -f ($(if ($acc -eq $globalDerivedA) {'YES'} else {'NO'})))
}
Write-Host ("Trace TSV            : {0}" -f $tsv)
Write-Host ("TRACE_KEY             : LABEL={0};ROOTVT={1:X8};CALLS={2};BYTES={3};REPLAY_A={4:X8};DERIVED_A={5}" -f $Label,$rootVT,$local.Count,$totalPayload,$acc,$(if ($null -ne $globalDerivedA) {('{0:X8}' -f $globalDerivedA)} else {'NA'}))
Write-Host ''
Write-Host 'CONTROLLED CAPTURE COMPLETE. game.dat on disk was never modified.'
Write-Host 'The process hook was restored to the exact original 7 bytes.'

if ($remote -ne [IntPtr]::Zero -and $h -ne [IntPtr]::Zero) {
    try { [A8PInputTraceNative]::Free($h,$remote) } catch { Write-Warning $_.Exception.Message }
}
if ($h -ne [IntPtr]::Zero) { [A8PInputTraceNative]::Close($h) }
