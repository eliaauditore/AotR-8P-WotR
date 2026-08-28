param(
    [string]$CombinedResult = '',
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [int]$MaxHits = 256,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
if ($MaxHits -lt 1 -or $MaxHits -gt 2048) { throw 'MaxHits must be 1..2048.' }
if (-not (Test-Path -LiteralPath $GameDat -PathType Leaf)) { throw "game.dat not found: $GameDat" }
$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) { throw "HASH MISMATCH. Expected $ExpectedHash got $hash" }
New-Item -ItemType Directory -Path $ResearchRoot -Force | Out-Null

if ([string]::IsNullOrWhiteSpace($CombinedResult)) {
    $latest = Get-ChildItem (Join-Path $ResearchRoot 'LOWLEVEL_JOIN_COMPLETION_COMBINED_*.txt') -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) { throw 'No LOWLEVEL_JOIN_COMPLETION_COMBINED_*.txt result found.' }
    $CombinedResult = $latest.FullName
}
if (-not (Test-Path -LiteralPath $CombinedResult -PathType Leaf)) { throw "Combined result not found: $CombinedResult" }

$lines = @(Get-Content -LiteralPath $CombinedResult)
$raw = [string]::Join("`r`n", $lines)
foreach ($required in @('TEST_VALID_FOR_STATE8','WATCHER_CLEAN_EXIT','JOIN_STATE_OBSERVED','CURRENT_C54B78','DE892C_STAYED_NULL')) {
    if ($raw -notmatch ('(?m)^' + [regex]::Escape($required) + '\s+:\s+YES\s*$')) {
        throw "Source log is not marked $required=YES."
    }
}
$pidMatch = [regex]::Match($raw, '(?m)^Game PID\s+:\s+(\d+)\s*$')
if (-not $pidMatch.Success) { throw 'Could not parse Game PID from source log.' }
$GamePid = [int]$pidMatch.Groups[1].Value

# Parse only callback-bound owner records. Do not consume unrelated ECX_OWNER snapshots.
$records = New-Object System.Collections.Generic.List[object]
for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -ne 'CALLBACK_8496C2_HIT=YES') { continue }
    for ($j=$i+1; $j -le [Math]::Min($i+8,$lines.Count-1); $j++) {
        $m=[regex]::Match($lines[$j].Trim(), '^ECX_OWNER=(0x[0-9A-Fa-f]{8}) OWNER_6A4=(\d+) OWNER_304=(\d+) CURRENT_IS_C54B78=(YES|NO)$')
        if ($m.Success) {
            $records.Add([pscustomobject]@{
                Owner=$m.Groups[1].Value.ToUpperInvariant();
                State=[int]$m.Groups[2].Value;
                Owner304=[int]$m.Groups[3].Value;
                Current=$m.Groups[4].Value
            })
            break
        }
    }
}
if ($records.Count -le 0) { throw 'No callback-bound owner records found.' }
$owners=@($records|ForEach-Object{$_.Owner}|Select-Object -Unique)
if ($owners.Count -ne 1 -or $owners[0] -eq '0X00000000') { throw "Callback owner is not unique/non-NULL: $($owners -join ', ')" }
$bad=@($records|Where-Object{$_.State -ne 1 -or $_.Owner304 -ne 1 -or $_.Current -ne 'YES'})
if ($bad.Count -ne 0) { throw "Callback owner contract is not uniform; bad records=$($bad.Count)." }
$Owner=[uint32]::Parse($owners[0].Substring(2),[Globalization.NumberStyles]::HexNumber)

$p=Get-CimInstance Win32_Process -Filter "ProcessId=$GamePid"
if (-not $p) { throw "Original game PID $GamePid is no longer running. Run this read-only provenance scan before restarting AotR." }
if ($p.ExecutablePath -ine $GameDat) { throw "PID $GamePid path mismatch: $($p.ExecutablePath)" }
$proc=Get-Process -Id $GamePid -ErrorAction Stop
$moduleBase=[uint32]$proc.MainModule.BaseAddress.ToInt64()
$moduleSize=[uint32]$proc.MainModule.ModuleMemorySize
$moduleEnd=[uint64]$moduleBase+[uint64]$moduleSize

if (-not ('AotrOwnerProvRead' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class AotrOwnerProvRead {
    [StructLayout(LayoutKind.Sequential)]
    public struct MBI {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public UInt32 AllocationProtect;
        public UIntPtr RegionSize;
        public UInt32 State;
        public UInt32 Protect;
        public UInt32 Type;
    }
    public struct Hit {
        public UInt32 Address;
        public UInt32 RegionBase;
        public UInt32 AllocationBase;
        public UInt32 Type;
        public UInt32 Protect;
    }

    const UInt32 PROCESS_VM_READ=0x0010, PROCESS_QUERY_INFORMATION=0x0400;
    const UInt32 MEM_COMMIT=0x1000, PAGE_NOACCESS=0x01, PAGE_GUARD=0x100;
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(UInt32 a,bool i,UInt32 p);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr VirtualQueryEx(IntPtr h,IntPtr a,out MBI m,IntPtr n);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h,IntPtr a,byte[] b,IntPtr n,out IntPtr g);

    static bool Readable(MBI m) {
        if(m.State!=MEM_COMMIT) return false;
        UInt32 p=m.Protect&0xFFu;
        if((m.Protect&PAGE_GUARD)!=0 || p==0 || p==PAGE_NOACCESS) return false;
        return true;
    }
    public static UInt32 ReadU32(UInt32 pid,UInt32 addr) {
        IntPtr h=OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION,false,pid);
        if(h==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try { byte[] b=new byte[4]; IntPtr g; if(!ReadProcessMemory(h,new IntPtr((long)addr),b,new IntPtr(4),out g)||g.ToInt64()!=4) throw new Exception("ReadU32 failed at 0x"+addr.ToString("X8")); return BitConverter.ToUInt32(b,0); }
        finally { CloseHandle(h); }
    }
    public static byte[] ReadBytes(UInt32 pid,UInt32 addr,Int32 count) {
        IntPtr h=OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION,false,pid);
        if(h==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try { byte[] b=new byte[count]; IntPtr g; if(!ReadProcessMemory(h,new IntPtr((long)addr),b,new IntPtr(count),out g)) return new byte[0]; int n=(int)g.ToInt64(); if(n<=0)return new byte[0]; if(n==count)return b; byte[] s=new byte[n]; Array.Copy(b,s,n); return s; }
        finally { CloseHandle(h); }
    }
    public static Hit[] Scan(UInt32 pid,UInt32 needle,UInt32 minAddr,UInt32 maxAddr,Int32 maxHits) {
        IntPtr h=OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION,false,pid);
        if(h==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            List<Hit> hits=new List<Hit>(); byte[] pat=BitConverter.GetBytes(needle);
            UInt64 addr=minAddr, ceiling=maxAddr==0 ? 0x7FFFFFFFUL : (UInt64)maxAddr;
            int mbiSize=Marshal.SizeOf(typeof(MBI)); const int CHUNK=2*1024*1024;
            while(addr<ceiling && hits.Count<maxHits) {
                MBI m; if(VirtualQueryEx(h,new IntPtr((long)addr),out m,new IntPtr(mbiSize))==IntPtr.Zero) break;
                UInt64 rb=(UInt64)m.BaseAddress.ToInt64(), rs=m.RegionSize.ToUInt64(); if(rs==0){addr+=0x1000;continue;}
                UInt64 lo=Math.Max(rb,(UInt64)minAddr), hi=Math.Min(rb+rs,ceiling);
                if(Readable(m) && hi>lo) {
                    UInt64 off=lo-rb; byte[] carry=new byte[0];
                    while(rb+off<hi && hits.Count<maxHits) {
                        int want=(int)Math.Min((UInt64)CHUNK,hi-(rb+off)); byte[] buf=new byte[want]; IntPtr g;
                        bool ok=ReadProcessMemory(h,new IntPtr((long)(rb+off)),buf,new IntPtr(want),out g); int n=ok?(int)g.ToInt64():0;
                        if(n<=0){off+=(UInt64)want;carry=new byte[0];continue;}
                        byte[] scan=new byte[carry.Length+n]; if(carry.Length>0)Array.Copy(carry,0,scan,0,carry.Length); Array.Copy(buf,0,scan,carry.Length,n);
                        UInt64 sb=rb+off-(UInt64)carry.Length;
                        for(int i=0;i<=scan.Length-4 && hits.Count<maxHits;i++) if(scan[i]==pat[0]&&scan[i+1]==pat[1]&&scan[i+2]==pat[2]&&scan[i+3]==pat[3]) {
                            UInt64 a=sb+(UInt64)i; if(a>=minAddr&&a<ceiling) hits.Add(new Hit{Address=(UInt32)a,RegionBase=(UInt32)rb,AllocationBase=(UInt32)m.AllocationBase.ToInt64(),Type=m.Type,Protect=m.Protect});
                        }
                        int keep=Math.Min(3,scan.Length); carry=new byte[keep]; if(keep>0)Array.Copy(scan,scan.Length-keep,carry,0,keep);
                        off+=(UInt64)n; if(n<want)off+=(UInt64)(want-n);
                    }
                }
                UInt64 next=rb+rs; if(next<=addr)break; addr=next;
            }
            return hits.ToArray();
        } finally { CloseHandle(h); }
    }
}
'@
}

function Type-Name([uint32]$t) {
    switch ($t) {
        0x01000000 { 'MEM_IMAGE' }
        0x00020000 { 'MEM_PRIVATE' }
        0x00040000 { 'MEM_MAPPED' }
        default { ('0x{0:X8}' -f $t) }
    }
}
function Dump-HitContext($hit) {
    $before=0x20; $after=0x24
    $start=[uint32]([Math]::Max(0,[int64]$hit.Address-$before))
    $bytes=[AotrOwnerProvRead]::ReadBytes([uint32]$GamePid,$start,$before+$after)
    for($o=0;$o+4 -le $bytes.Length;$o+=4) {
        $a=[uint32]($start+$o); $v=[BitConverter]::ToUInt32($bytes,$o); $mark=if($a -eq $hit.Address){'>>'}else{'  '}
        Write-Host ("  {0} 0x{1:X8}: 0x{2:X8}" -f $mark,$a,$v)
    }
}

Write-Host '============================================================'
Write-Host ' AOTR WOTR FRONTEND OWNER POINTER PROVENANCE - READ ONLY'
Write-Host '============================================================'
Write-Host ("Source log       : {0}" -f $CombinedResult)
Write-Host ("Game PID         : {0}" -f $GamePid)
Write-Host ("Callback records : {0}" -f $records.Count)
Write-Host ("Proven owner     : 0x{0:X8}" -f $Owner)
Write-Host ("game.dat module  : 0x{0:X8} .. 0x{1:X8} size=0x{2:X}" -f $moduleBase,$moduleEnd,$moduleSize)
Write-Host ''

# First, the high-value search: exact owner pointer stored anywhere inside game.dat image memory.
$moduleHits=[AotrOwnerProvRead]::Scan([uint32]$GamePid,$Owner,$moduleBase,[uint32]$moduleEnd,$MaxHits)
Write-Host ("MODULE_DIRECT_OWNER_POINTER_HITS={0}" -f $moduleHits.Count)
$idx=0
foreach($h in $moduleHits) {
    $idx++
    Write-Host ("MODULE HIT #{0}: addr=0x{1:X8} RVA=0x{2:X8} region=0x{3:X8} type={4} protect=0x{5:X}" -f $idx,$h.Address,([uint32]($h.Address-$moduleBase)),$h.RegionBase,(Type-Name $h.Type),$h.Protect)
    Dump-HitContext $h
}
Write-Host ''

# Then scan all readable committed user-space regions. This classifies heap/manager fields if no static slot exists.
$allHits=[AotrOwnerProvRead]::Scan([uint32]$GamePid,$Owner,0,[uint32]0x7FFFFFFF,$MaxHits)
Write-Host ("ALL_DIRECT_OWNER_POINTER_HITS={0}" -f $allHits.Count)
$grouped=$allHits|Group-Object Type|Sort-Object Count -Descending
foreach($g in $grouped){Write-Host ("  {0}: {1}" -f (Type-Name ([uint32]$g.Name)),$g.Count)}
Write-Host ''

$show=@($allHits|Select-Object -First 48)
$idx=0
foreach($h in $show) {
    $idx++
    $inModule=([uint64]$h.Address -ge [uint64]$moduleBase -and [uint64]$h.Address -lt $moduleEnd)
    Write-Host ("HIT #{0}: addr=0x{1:X8} region=0x{2:X8} alloc=0x{3:X8} type={4} inGameModule={5}" -f $idx,$h.Address,$h.RegionBase,$h.AllocationBase,(Type-Name $h.Type),$inModule)
    Dump-HitContext $h
}
if($allHits.Count -gt $show.Count){Write-Host ("... {0} additional hits omitted from context dump" -f ($allHits.Count-$show.Count))}

Write-Host ''
if($moduleHits.Count -eq 1) {
    Write-Host ("STATIC_OWNER_LOCATOR_CANDIDATE=0x{0:X8} RVA=0x{1:X8}" -f $moduleHits[0].Address,([uint32]($moduleHits[0].Address-$moduleBase))) -ForegroundColor Green
    Write-Host 'CLASSIFICATION=STRONG_CANDIDATE_REQUIRES_FRESH_PROCESS_REVALIDATION'
} elseif($moduleHits.Count -gt 1) {
    Write-Host 'STATIC_OWNER_LOCATOR_CANDIDATE=AMBIGUOUS'
    Write-Host 'CLASSIFICATION=MULTIPLE_MODULE_POINTERS_REQUIRE_CONTEXT_CLASSIFICATION'
} else {
    Write-Host 'STATIC_OWNER_LOCATOR_CANDIDATE=NONE'
    Write-Host 'CLASSIFICATION=OWNER_NOT_DIRECTLY_STORED_IN_GAME_IMAGE; USE_PRIVATE_PARENT_CHAIN'
}
Write-Host ''
Write-Host 'READ_ONLY_COMPLETE=YES'
Write-Host 'No WriteProcessMemory import exists in this tool.'
