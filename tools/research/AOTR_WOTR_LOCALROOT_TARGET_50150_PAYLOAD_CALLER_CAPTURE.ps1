param(
    [string]$Label = 'NODE',
    [string]$OutputDir = 'C:\AOTR_RESEARCH',
    [uint32]$StartIndex = 50150,
    [uint32]$EndIndex = 50160
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# TARGETED process-only capture for the first proven Host/VM localRoot divergence.
# Captures only localRoot calls StartIndex..EndIndex and records:
#   index / this / caller-return-VA / tag / len / preA / copiedLen / payload
# No game.dat file on disk is modified. Exact SHA256 + exact 7-byte hook guards.
# Windows PowerShell 5.1 / PowerShell 7 compatible. No generated/nested scripts.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$HookRva = [int64]0x006211DF
$MgrGlobalRva = [int64]0x009E3380
$ExpectedOriginal = [byte[]](0x55,0x8B,0xEC,0x83,0x7D,0x0C,0x00)
$AllocSize = 0x00400000                  # 4 MiB; target window is only 11 calls by default
$StubOffset = 0x100
$DataOffset = 0x1000
$DataCapacity = $AllocSize - $DataOffset
$MaxPayload = [uint32]0x00010000         # 64 KiB per targeted call safety cap
$HeaderSize = 28

if ($EndIndex -lt $StartIndex) { throw 'EndIndex must be >= StartIndex.' }
$ExpectedTargetCount = [uint32]($EndIndex - $StartIndex + 1)

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

if (-not ('A8PTarget50150Native' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class A8PTarget50150Native {
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr n, out IntPtr got);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr n, out IntPtr wrote);
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr addr, UIntPtr size, UInt32 type, UInt32 protect);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool VirtualProtectEx(IntPtr h, IntPtr addr, UIntPtr size, UInt32 newProtect, out UInt32 oldProtect);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool FlushInstructionCache(IntPtr h, IntPtr addr, UIntPtr size);

    const UInt32 PROCESS_QUERY_INFORMATION=0x0400, PROCESS_VM_OPERATION=0x0008, PROCESS_VM_READ=0x0010, PROCESS_VM_WRITE=0x0020;
    const UInt32 MEM_COMMIT=0x1000, MEM_RESERVE=0x2000;
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

    public static byte[] BuildStub(UInt32 remoteBase, UInt32 continueVa, UInt32 capacity, UInt32 rootMgrGlobalVa,
                                   UInt32 startIndex, UInt32 endIndex, UInt32 maxPayload) {
        UInt32 offAddr=remoteBase+0x00;
        UInt32 countAddr=remoteBase+0x04;
        UInt32 overflowAddr=remoteBase+0x08;
        UInt32 capturedAddr=remoteBase+0x0C;
        UInt32 truncatedAddr=remoteBase+0x10;
        UInt32 dataBase=remoteBase+0x1000;

        var b=new List<byte>();
        b.Add(0x9C);                                            // pushfd
        b.Add(0x60);                                            // pushad

        // Exact same localRoot filter as the compact trace:
        // manager=[DE3380], root=[manager+0x24], root == saved original ECX(this).
        b.Add(0xA1); U32(b,rootMgrGlobalVa);                     // mov eax,[rootMgrGlobalVa]
        b.AddRange(new byte[]{0x85,0xC0});                       // test eax,eax
        int jDoneNoMgr=Jcc(b,0x84);                              // je done
        b.AddRange(new byte[]{0x8B,0x40,0x24});                  // mov eax,[eax+24]
        b.AddRange(new byte[]{0x85,0xC0});                       // test eax,eax
        int jDoneNoRoot=Jcc(b,0x84);                             // je done
        b.AddRange(new byte[]{0x3B,0x44,0x24,0x18});             // cmp eax,[esp+18] saved ECX
        int jDoneOther=Jcc(b,0x85);                              // jne done

        // 1-based localRoot call index, matching the previously stored compact trace index field.
        b.Add(0xA1); U32(b,countAddr);                           // mov eax,[count]
        b.Add(0x40);                                             // inc eax
        b.Add(0xA3); U32(b,countAddr);                           // mov [count],eax
        b.AddRange(new byte[]{0x8B,0xD8});                       // mov ebx,eax (index)
        b.Add(0x3D); U32(b,startIndex);                          // cmp eax,startIndex
        int jDoneBefore=Jcc(b,0x82);                             // jb done
        b.Add(0x3D); U32(b,endIndex);                            // cmp eax,endIndex
        int jDoneAfter=Jcc(b,0x87);                              // ja done

        // Original function args at hook entry after pushfd+pushad:
        // [esp+24]=return address, [esp+28]=tag, [esp+2C]=data, [esp+30]=len.
        b.AddRange(new byte[]{0x8B,0x6C,0x24,0x30});             // mov ebp,[esp+30] actual len
        b.AddRange(new byte[]{0x8B,0x74,0x24,0x2C});             // mov esi,[esp+2C] data
        b.AddRange(new byte[]{0x8B,0xCD});                       // mov ecx,ebp copyLen=len
        b.AddRange(new byte[]{0x85,0xF6});                       // test esi,esi
        int jHasPtr=Jcc(b,0x85);                                 // jne hasPtr
        b.AddRange(new byte[]{0x31,0xC9});                       // xor ecx,ecx
        int hasPtr=b.Count; Patch(b,jHasPtr,hasPtr);

        b.AddRange(new byte[]{0x81,0xF9}); U32(b,maxPayload);    // cmp ecx,maxPayload
        int jCopyLenOk=Jcc(b,0x86);                              // jbe copyLenOk
        b.Add(0xB9); U32(b,maxPayload);                          // mov ecx,maxPayload
        b.AddRange(new byte[]{0xFF,0x05}); U32(b,truncatedAddr); // inc dword [truncated]
        int copyLenOk=b.Count; Patch(b,jCopyLenOk,copyLenOk);

        // Reserve header(28)+payload bytes in target buffer.
        b.AddRange(new byte[]{0x8B,0x15}); U32(b,offAddr);       // mov edx,[off]
        b.AddRange(new byte[]{0x8B,0xC2});                       // mov eax,edx
        b.AddRange(new byte[]{0x83,0xC0,0x1C});                  // add eax,28
        b.AddRange(new byte[]{0x03,0xC1});                       // add eax,ecx
        b.Add(0x3D); U32(b,capacity);                            // cmp eax,capacity
        int jBufferOverflow=Jcc(b,0x87);                         // ja overflow
        b.Add(0xA3); U32(b,offAddr);                             // [off]=new end

        b.Add(0xBF); U32(b,dataBase);                            // mov edi,dataBase
        b.AddRange(new byte[]{0x03,0xFA});                       // add edi,edx
        b.AddRange(new byte[]{0x89,0x1F});                       // [edi+00]=index
        b.AddRange(new byte[]{0x8B,0x44,0x24,0x18});             // eax=this
        b.AddRange(new byte[]{0x89,0x47,0x04});                  // [edi+04]=this
        b.AddRange(new byte[]{0x8B,0x44,0x24,0x24});             // eax=caller return VA
        b.AddRange(new byte[]{0x89,0x47,0x08});                  // [edi+08]=caller
        b.AddRange(new byte[]{0x8B,0x44,0x24,0x28});             // eax=tag
        b.AddRange(new byte[]{0x89,0x47,0x0C});                  // [edi+0C]=tag
        b.AddRange(new byte[]{0x89,0x6F,0x10});                  // [edi+10]=actual len
        b.AddRange(new byte[]{0x8B,0x44,0x24,0x18});             // eax=this
        b.AddRange(new byte[]{0x8B,0x40,0x44});                  // eax=[this+44] preA
        b.AddRange(new byte[]{0x89,0x47,0x14});                  // [edi+14]=preA
        b.AddRange(new byte[]{0x89,0x4F,0x18});                  // [edi+18]=copiedLen
        b.AddRange(new byte[]{0x83,0xC7,0x1C});                  // edi+=28
        b.AddRange(new byte[]{0x85,0xC9});                       // test ecx,ecx
        int jAfterCopy=Jcc(b,0x84);                              // je afterCopy
        b.AddRange(new byte[]{0xF3,0xA4});                       // rep movsb
        int afterCopy=b.Count; Patch(b,jAfterCopy,afterCopy);
        b.AddRange(new byte[]{0xFF,0x05}); U32(b,capturedAddr);  // inc dword [captured] LAST
        int jDoneCaptured=Jmp(b);

        int overflow=b.Count;
        Patch(b,jBufferOverflow,overflow);
        b.AddRange(new byte[]{0xC7,0x05}); U32(b,overflowAddr); U32(b,1);

        int done=b.Count;
        Patch(b,jDoneNoMgr,done); Patch(b,jDoneNoRoot,done); Patch(b,jDoneOther,done);
        Patch(b,jDoneBefore,done); Patch(b,jDoneAfter,done); Patch(b,jDoneCaptured,done);
        b.Add(0x61);                                             // popad
        b.Add(0x9D);                                             // popfd

        // Exact stolen original 7 bytes at 0xA211DF.
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
function RBytes([IntPtr]$h,[int64]$a,[int]$n) { [A8PTarget50150Native]::Read($h,$a,$n) }
function RU32([IntPtr]$h,[int64]$a) { U32 (RBytes $h $a 4) 0 }
function HexBytes([byte[]]$b) {
    if ($null -eq $b -or $b.Length -eq 0) { return '' }
    return ([BitConverter]::ToString($b)).Replace('-','')
}
function AsciiBytes([byte[]]$b) {
    if ($null -eq $b -or $b.Length -eq 0) { return '' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($x in $b) {
        if ($x -ge 32 -and $x -le 126) { [void]$sb.Append([char]$x) }
        else { [void]$sb.Append('.') }
    }
    return $sb.ToString()
}

$existing = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'game.dat' })
if ($existing.Count -gt 0) {
    throw "A game.dat is already running (PID(s): $($existing.ProcessId -join ',')). Close it first. Start this capture before launching AotR."
}

Write-Host '============================================================'
Write-Host ' AOTR WOTR LOCALROOT TARGET 50150 PAYLOAD/CALLER CAPTURE'
Write-Host '============================================================'
Write-Host ("Label                : {0}" -f $Label)
Write-Host ("Target indices       : {0}..{1} ({2} calls)" -f $StartIndex,$EndIndex,$ExpectedTargetCount)
Write-Host 'Records              : index/this/caller/tag/len/preA/copiedLen/payload'
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
$root = [uint32]0
$rootVT = [uint32]0
$traceBytes = $null
$writeOff = [uint32]0
$totalCalls = [uint32]0
$capturedCount = [uint32]0
$overflow = [uint32]0
$truncated = [uint32]0

try {
    $h = [A8PTarget50150Native]::Open([uint32]$gamePid)
    $actual = RBytes $h $hook 7
    if ((HexBytes $actual) -ne (HexBytes $ExpectedOriginal)) {
        throw "HOOK BYTE MISMATCH at 0x$('{0:X8}' -f $hook). Expected $(HexBytes $ExpectedOriginal), got $(HexBytes $actual)"
    }

    $remote = [A8PTarget50150Native]::Alloc($h,$AllocSize)
    $remoteBase = [uint32]$remote.ToInt64()
    $stubVa = $remoteBase + [uint32]$StubOffset
    $stub = [A8PTarget50150Native]::BuildStub(
        $remoteBase,[uint32]$continue,[uint32]$DataCapacity,[uint32]($base + $MgrGlobalRva),
        $StartIndex,$EndIndex,$MaxPayload)
    [A8PTarget50150Native]::Write($h,[int64]$stubVa,$stub)

    $hookBytes = [A8PTarget50150Native]::BuildHook([uint32]$hook,$stubVa)
    $oldProtect = [A8PTarget50150Native]::ProtectRWX($h,$hook,7)
    [A8PTarget50150Native]::Write($h,$hook,$hookBytes)
    [A8PTarget50150Native]::Flush($h,$hook,7)
    $patched = $true

    Write-Host ("Remote scratch       : 0x{0:X8}" -f $remoteBase)
    Write-Host ("Stub VA              : 0x{0:X8}" -f $stubVa)
    Write-Host 'Hook installed       : YES (exact-byte guarded)'
    Write-Host 'Waiting for target window...'

    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not (Get-Process -Id $gamePid -ErrorAction SilentlyContinue)) {
            throw 'game.dat exited before targeted capture completed.'
        }

        if ($root -eq 0) {
            $mgr = RU32 $h ($base + $MgrGlobalRva)
            if ($mgr -ne 0) {
                $cur = RU32 $h ([int64]$mgr + 0x24)
                if ($cur -ne 0) {
                    $root = [uint32]$cur
                    $rootVT = RU32 $h ([int64]$root)
                    Write-Host ("localRoot published  : 0x{0:X8}" -f $root)
                    Write-Host ("localRoot vtable     : 0x{0:X8}" -f $rootVT)
                }
            }
        }

        $capturedNow = RU32 $h ($remoteBase + 0x0C)
        if ($capturedNow -ge $ExpectedTargetCount) {
            # The captured counter is written only after the last payload byte.
            # A short guard delay allows the instrumented call to leave the stub
            # before restoring the entry bytes. Any already-running stub remains valid.
            Start-Sleep -Milliseconds 100
            break
        }
        Start-Sleep -Milliseconds 1
    }

    $capturedCount = RU32 $h ($remoteBase + 0x0C)
    if ($capturedCount -lt $ExpectedTargetCount) {
        throw "Target window incomplete: captured $capturedCount / $ExpectedTargetCount calls within timeout."
    }

    [A8PTarget50150Native]::Write($h,$hook,$ExpectedOriginal)
    [A8PTarget50150Native]::Flush($h,$hook,7)
    [A8PTarget50150Native]::Protect($h,$hook,7,$oldProtect)
    $patched = $false
    Write-Host 'Hook restored        : YES'

    $writeOff = RU32 $h ($remoteBase + 0x00)
    $totalCalls = RU32 $h ($remoteBase + 0x04)
    $overflow = RU32 $h ($remoteBase + 0x08)
    $capturedCount = RU32 $h ($remoteBase + 0x0C)
    $truncated = RU32 $h ($remoteBase + 0x10)
    if ($writeOff -gt $DataCapacity) { throw "Remote write offset invalid: $writeOff" }
    $traceBytes = if ($writeOff -gt 0) { RBytes $h ($remoteBase + $DataOffset) ([int]$writeOff) } else { [byte[]]@() }

    Write-Host ("localRoot calls seen : {0}" -f $totalCalls)
    Write-Host ("Target calls captured: {0}" -f $capturedCount)
    Write-Host ("Captured bytes       : {0}" -f $writeOff)
    Write-Host ("Buffer overflow      : {0}" -f $overflow)
    Write-Host ("Payload truncations  : {0}" -f $truncated)
}
finally {
    if ($h -ne [IntPtr]::Zero -and $patched) {
        try {
            [A8PTarget50150Native]::Write($h,$hook,$ExpectedOriginal)
            [A8PTarget50150Native]::Flush($h,$hook,7)
            if ($oldProtect -ne 0) { [A8PTarget50150Native]::Protect($h,$hook,7,$oldProtect) }
            Write-Host 'Emergency rollback   : original hook bytes restored'
        }
        catch { Write-Warning "Emergency rollback failed: $($_.Exception.Message)" }
    }
}

if ($null -eq $traceBytes) { throw 'No targeted trace buffer was captured.' }
if ($overflow -ne 0) { throw 'Target buffer overflowed; result is not accepted.' }
if ($truncated -ne 0) { throw 'At least one target payload exceeded MaxPayload; result is not accepted.' }

$records = New-Object System.Collections.Generic.List[object]
$pos = 0
while ($pos -lt $traceBytes.Length) {
    if ($pos + $HeaderSize -gt $traceBytes.Length) { throw "Truncated target record header at offset $pos" }
    $idx = [BitConverter]::ToUInt32($traceBytes,$pos+0)
    $thisPtr = [BitConverter]::ToUInt32($traceBytes,$pos+4)
    $caller = [BitConverter]::ToUInt32($traceBytes,$pos+8)
    $tag = [BitConverter]::ToUInt32($traceBytes,$pos+12)
    $len = [BitConverter]::ToUInt32($traceBytes,$pos+16)
    $preA = [BitConverter]::ToUInt32($traceBytes,$pos+20)
    $copied = [BitConverter]::ToUInt32($traceBytes,$pos+24)
    $pos += $HeaderSize
    if ([uint64]$pos + [uint64]$copied -gt [uint64]$traceBytes.Length) { throw "Truncated payload at target index $idx" }
    $payload = New-Object byte[] ([int]$copied)
    if ($copied -gt 0) { [Array]::Copy($traceBytes,$pos,$payload,0,[int]$copied) }
    $pos += [int]$copied
    $records.Add([pscustomobject]@{
        Index=[uint32]$idx; This=[uint32]$thisPtr; Caller=[uint32]$caller; Tag=[uint32]$tag;
        Len=[uint32]$len; PreA=[uint32]$preA; Copied=[uint32]$copied; Payload=$payload
    })
}

if ($records.Count -ne $ExpectedTargetCount) {
    throw "Parsed target record count mismatch: $($records.Count) != $ExpectedTargetCount"
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$safeLabel = ($Label -replace '[^A-Za-z0-9_.-]','_')
$rawBin = Join-Path $OutputDir ("AOTR_WOTR_LOCALROOT_TARGET_50150_{0}_{1}.bin" -f $safeLabel,$stamp)
$tsv = Join-Path $OutputDir ("AOTR_WOTR_LOCALROOT_TARGET_50150_{0}_{1}.tsv" -f $safeLabel,$stamp)
[System.IO.File]::WriteAllBytes($rawBin,$traceBytes)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$sw = New-Object System.IO.StreamWriter($tsv,$false,$utf8NoBom)
try {
    $sw.WriteLine("index`tthis_hex`tcaller_hex`tcaller_rva_hex`ttag_hex`tlen`tpreA_hex`tcopied`tpayload_hex`tpayload_ascii")
    foreach ($r in $records) {
        $callerRva = [uint32](($r.Caller - [uint32]$base) -band 0xFFFFFFFF)
        $sw.WriteLine(("{0}`t{1:X8}`t{2:X8}`t{3:X8}`t{4:X8}`t{5}`t{6:X8}`t{7}`t{8}`t{9}" -f
            $r.Index,$r.This,$r.Caller,$callerRva,$r.Tag,$r.Len,$r.PreA,$r.Copied,(HexBytes $r.Payload),(AsciiBytes $r.Payload)))
    }
}
finally { $sw.Dispose() }

Write-Host ''
Write-Host '================ TARGET 50150 SUMMARY ==================='
Write-Host ("Label                : {0}" -f $Label)
Write-Host ("Image                : {0}" -f $exe)
Write-Host ("localRoot            : 0x{0:X8}" -f $root)
Write-Host ("localRoot vtable     : 0x{0:X8}" -f $rootVT)
Write-Host ("Target records       : {0}" -f $records.Count)
Write-Host ("RAW BIN              : {0}" -f $rawBin)
Write-Host ("TSV                  : {0}" -f $tsv)
Write-Host ''

foreach ($r in $records) {
    $callerRva = [uint32](($r.Caller - [uint32]$base) -band 0xFFFFFFFF)
    Write-Host ("INDEX {0}: CALLER=0x{1:X8} RVA=0x{2:X8} TAG=0x{3:X8} LEN={4} PREA=0x{5:X8} COPIED={6}" -f
        $r.Index,$r.Caller,$callerRva,$r.Tag,$r.Len,$r.PreA,$r.Copied)
    Write-Host ("  PAYLOAD_HEX  : {0}" -f (HexBytes $r.Payload))
    Write-Host ("  PAYLOAD_ASCII: {0}" -f (AsciiBytes $r.Payload))
}

Write-Host ''
Write-Host ("TARGET_CAPTURE_KEY   : LABEL={0};START={1};END={2};RECORDS={3};ROOTVT={4:X8};OVERFLOW={5};TRUNCATED={6}" -f
    $Label,$StartIndex,$EndIndex,$records.Count,$rootVT,$overflow,$truncated)
Write-Host 'TARGET_50150_CAPTURE_COMPLETE=YES'
Write-Host 'Remote scratch is intentionally left allocated; Windows reclaims it when this game.dat process exits.'

if ($h -ne [IntPtr]::Zero) {
    [A8PTarget50150Native]::Close($h)
    $h = [IntPtr]::Zero
}
