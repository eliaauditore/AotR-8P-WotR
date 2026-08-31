param(
    [int]$ProcessId = 0,
    [ValidateRange(1,100)]
    [int]$MaxCandidates = 20,
    [ValidateRange(1,32)]
    [int]$ChunkMB = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# READ ONLY.
# This tool never imports or calls WriteProcessMemory.
#
# Goal:
#   Locate staging-like arrays while the native WotR lobby is open BEFORE the
#   active GameInfo global is created.
#
# Static layout evidence for this exact AotR build:
#   PlayerInfo size / staging stride : 0x1B8
#   PlayerType                       : PlayerInfo + 0x04
#   Network identity DWORD           : PlayerInfo + 0x38
#   Network identity WORD            : PlayerInfo + 0x3C
#   Staging deserializer processes   : exactly 8 records
#
# Expected runtime test layout for this locator:
#   P1 = network human / Type 6
#   P2 = AI / Type 2..5
#   P3 = AI / Type 2..5
#   P4 = AI / Type 2..5
#
# The remaining four records may be any valid PlayerType 0..6.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$RvaGameInfoGlobal = [int64]0x009E7D6C
$PlayerInfoStride = 0x1B8

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class A8PLobbyStagingReadOnlyV1
{
    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORY_BASIC_INFORMATION
    {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public UInt32 AllocationProtect;
        public UIntPtr RegionSize;
        public UInt32 State;
        public UInt32 Protect;
        public UInt32 Type;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(
        UInt32 dwDesiredAccess,
        bool bInheritHandle,
        UInt32 dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ReadProcessMemory(
        IntPtr hProcess,
        IntPtr lpBaseAddress,
        byte[] lpBuffer,
        IntPtr nSize,
        out IntPtr lpNumberOfBytesRead);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern UIntPtr VirtualQueryEx(
        IntPtr hProcess,
        IntPtr lpAddress,
        out MEMORY_BASIC_INFORMATION lpBuffer,
        UIntPtr dwLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr hObject);

    public static MEMORY_BASIC_INFORMATION[] Enumerate32BitRegions(IntPtr process)
    {
        var regions = new List<MEMORY_BASIC_INFORMATION>();
        long address = 0x00010000;
        const long maxAddress = 0x7FFF0000;
        int mbiSize = Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION));

        while (address < maxAddress)
        {
            MEMORY_BASIC_INFORMATION mbi;
            UIntPtr result = VirtualQueryEx(
                process,
                new IntPtr(address),
                out mbi,
                new UIntPtr((uint)mbiSize));

            if (result == UIntPtr.Zero)
                break;

            long regionBase = mbi.BaseAddress.ToInt64();
            ulong regionSizeU = mbi.RegionSize.ToUInt64();
            if (regionSizeU == 0 || regionSizeU > 0x80000000UL)
                break;

            long regionSize = (long)regionSizeU;
            regions.Add(mbi);

            long next = regionBase + regionSize;
            if (next <= address)
                break;

            address = next;
        }

        return regions.ToArray();
    }

    public static int[] FindPlayerInfoArrayCandidates(byte[] buffer, int stride)
    {
        var hits = new List<int>();
        int required = (7 * stride) + 8;
        int maxStart = buffer.Length - required;
        if (maxStart < 0)
            return hits.ToArray();

        for (int start = 0; start <= maxStart; start += 4)
        {
            uint t0 = BitConverter.ToUInt32(buffer, start + 4);
            if (t0 != 6)
                continue;

            bool valid = true;
            uint[] types = new uint[8];
            for (int i = 0; i < 8; i++)
            {
                uint t = BitConverter.ToUInt32(buffer, start + (i * stride) + 4);
                types[i] = t;
                if (t > 6)
                {
                    valid = false;
                    break;
                }
            }

            if (!valid)
                continue;

            // Current controlled snapshot has three AIs immediately after host.
            for (int i = 1; i <= 3; i++)
            {
                if (types[i] < 2 || types[i] > 5)
                {
                    valid = false;
                    break;
                }
            }

            if (valid)
                hits.Add(start);
        }

        return hits.ToArray();
    }
}
"@

function Resolve-GameProcess {
    param([int]$RequestedId)

    if ($RequestedId -gt 0) {
        return Get-Process -Id $RequestedId -ErrorAction Stop
    }

    $candidates = @(
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object {
                try { $_.MainModule.FileName -match '\\game\.dat$' }
                catch { $false }
            }
    )

    if ($candidates.Count -eq 0) {
        throw 'No running game.dat process found.'
    }

    if ($candidates.Count -gt 1) {
        $text = $candidates | ForEach-Object {
            $path = $null
            try { $path = $_.MainModule.FileName } catch {}
            'PID={0} Path={1}' -f $_.Id, $path
        }
        throw "Multiple game.dat processes found. Re-run with -ProcessId <PID>.`n$($text -join "`n")"
    }

    return $candidates[0]
}

function Read-Bytes {
    param(
        [IntPtr]$Handle,
        [int64]$Address,
        [int]$Count
    )

    $buffer = New-Object byte[] $Count
    $read = [IntPtr]::Zero
    $ok = [A8PLobbyStagingReadOnlyV1]::ReadProcessMemory(
        $Handle,
        [IntPtr]$Address,
        $buffer,
        [IntPtr]$Count,
        [ref]$read)

    if (-not $ok -or $read.ToInt64() -ne $Count) {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ('ReadProcessMemory failed at 0x{0:X8} count={1} Win32={2}' -f $Address, $Count, $err)
    }

    return $buffer
}

function Try-ReadBytes {
    param(
        [IntPtr]$Handle,
        [int64]$Address,
        [int]$Count
    )

    try { return ,(Read-Bytes -Handle $Handle -Address $Address -Count $Count) }
    catch { return $null }
}

function Read-U16 {
    param([IntPtr]$Handle, [int64]$Address)
    return [BitConverter]::ToUInt16((Read-Bytes $Handle $Address 2), 0)
}

function Read-U32 {
    param([IntPtr]$Handle, [int64]$Address)
    return [BitConverter]::ToUInt32((Read-Bytes $Handle $Address 4), 0)
}

function Format-IPv4 {
    param([uint32]$Value)
    return '{0}.{1}.{2}.{3}' -f `
        (($Value -shr 24) -band 0xFF), `
        (($Value -shr 16) -band 0xFF), `
        (($Value -shr 8) -band 0xFF), `
        ($Value -band 0xFF)
}

function Get-TypeName {
    param([uint32]$Type)
    switch ($Type) {
        0 { 'OPEN' }
        1 { 'CLOSED' }
        2 { 'EASY_AI' }
        3 { 'MEDIUM_AI' }
        4 { 'HARD_AI' }
        5 { 'BRUTAL_AI' }
        6 { 'NETWORK_HUMAN' }
        default { 'UNKNOWN' }
    }
}

$proc = Resolve-GameProcess -RequestedId $ProcessId
$exePath = $proc.MainModule.FileName
$moduleBase = $proc.MainModule.BaseAddress.ToInt64()
$hash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToUpperInvariant()

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR LOBBY STAGING LOCATOR'
Write-Host ' READ ONLY - no memory writes'
Write-Host '============================================================'
Write-Host ('PID              : {0}' -f $proc.Id)
Write-Host ('Image            : {0}' -f $exePath)
Write-Host ('Module base      : 0x{0:X8}' -f $moduleBase)
Write-Host ('SHA256           : {0}' -f $hash)
Write-Host ('PlayerInfo stride: 0x{0:X}' -f $PlayerInfoStride)

if ($hash -ne $ExpectedHash) {
    throw "Unsupported game.dat build. Expected $ExpectedHash, got $hash"
}

$PROCESS_VM_READ = [uint32]0x0010
$PROCESS_QUERY_INFORMATION = [uint32]0x0400
$handle = [A8PLobbyStagingReadOnlyV1]::OpenProcess(
    ($PROCESS_VM_READ -bor $PROCESS_QUERY_INFORMATION),
    $false,
    [uint32]$proc.Id)

if ($handle -eq [IntPtr]::Zero) {
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "OpenProcess failed, Win32=$err"
}

try {
    $gameInfo = Read-U32 $handle ($moduleBase + $RvaGameInfoGlobal)
    Write-Host ('Active GameInfo  : 0x{0:X8}' -f $gameInfo)
    if ($gameInfo -eq 0) {
        Write-Host 'GameInfo state   : NULL (expected for the observed pre-start native WotR lobby)'
    }

    Write-Host ''
    Write-Host 'Scanning committed writable private memory...'

    $MEM_COMMIT = [uint32]0x1000
    $MEM_PRIVATE = [uint32]0x20000
    $PAGE_GUARD = [uint32]0x100
    $PAGE_NOACCESS = [uint32]0x01
    $writableBaseProtections = @(0x04, 0x08, 0x40, 0x80)

    $chunkCore = [int]($ChunkMB * 1MB)
    $overlap = 0x2000
    $seen = @{}
    $candidateCount = 0
    $regionsScanned = 0
    $bytesScanned = [uint64]0

    $regions = [A8PLobbyStagingReadOnlyV1]::Enumerate32BitRegions($handle)

    foreach ($region in $regions) {
        if ($candidateCount -ge $MaxCandidates) { break }

        if ($region.State -ne $MEM_COMMIT) { continue }
        if ($region.Type -ne $MEM_PRIVATE) { continue }
        if (($region.Protect -band $PAGE_GUARD) -ne 0) { continue }
        if (($region.Protect -band $PAGE_NOACCESS) -ne 0) { continue }

        $baseProtect = [int]($region.Protect -band 0xFF)
        if ($writableBaseProtections -notcontains $baseProtect) { continue }

        $regionBase = [uint64]$region.BaseAddress.ToInt64()
        $regionSize = [uint64]$region.RegionSize.ToUInt64()
        if ($regionSize -eq 0) { continue }

        $regionEnd = $regionBase + $regionSize
        $scanAddress = $regionBase
        $regionsScanned++

        while ($scanAddress -lt $regionEnd) {
            if ($candidateCount -ge $MaxCandidates) { break }

            $remaining = $regionEnd - $scanAddress
            $coreLen = [int][Math]::Min([uint64]$chunkCore, $remaining)
            $readLen64 = [Math]::Min([uint64]($chunkCore + $overlap), $remaining)
            $readLen = [int]$readLen64

            $buffer = Try-ReadBytes -Handle $handle -Address ([int64]$scanAddress) -Count $readLen
            if ($null -ne $buffer) {
                $bytesScanned += [uint64]$readLen
                $hits = [A8PLobbyStagingReadOnlyV1]::FindPlayerInfoArrayCandidates($buffer, $PlayerInfoStride)

                foreach ($offset in $hits) {
                    # Ignore candidates found only in the overlap; the next core chunk owns them.
                    if ($offset -ge $coreLen -and ($scanAddress + [uint64]$coreLen) -lt $regionEnd) {
                        continue
                    }

                    $candidateAddress = $scanAddress + [uint64]$offset
                    $key = ('{0:X8}' -f $candidateAddress)
                    if ($seen.ContainsKey($key)) { continue }
                    $seen[$key] = $true
                    $candidateCount++

                    Write-Host ''
                    Write-Host ('CANDIDATE #{0} @ 0x{1:X8}' -f $candidateCount, $candidateAddress)
                    Write-Host ('Region          : 0x{0:X8} + 0x{1:X}' -f $regionBase, $regionSize)
                    Write-Host 'Slots:'

                    for ($i = 0; $i -lt 8; $i++) {
                        $record = $candidateAddress + [uint64]($i * $PlayerInfoStride)
                        try {
                            $head = Read-U32 $handle ([int64]$record)
                            $type = Read-U32 $handle ([int64]$record + 0x04)
                            $ip = Read-U32 $handle ([int64]$record + 0x38)
                            $port = Read-U16 $handle ([int64]$record + 0x3C)
                            $typeName = Get-TypeName $type

                            if ($type -eq 6) {
                                Write-Host ('  P{0}/slot{1}: rec=0x{2:X8} head=0x{3:X8} Type={4} {5} EP={6}:{7}' -f `
                                    ($i + 1), $i, $record, $head, $type, $typeName, (Format-IPv4 $ip), $port)
                            }
                            else {
                                Write-Host ('  P{0}/slot{1}: rec=0x{2:X8} head=0x{3:X8} Type={4} {5} rawEP=0x{6:X8}:{7}' -f `
                                    ($i + 1), $i, $record, $head, $type, $typeName, $ip, $port)
                            }
                        }
                        catch {
                            Write-Host ('  P{0}/slot{1}: read failed: {2}' -f ($i + 1), $i, $_.Exception.Message)
                        }
                    }

                    if ($candidateCount -ge $MaxCandidates) { break }
                }
            }

            if ($coreLen -le 0) { break }
            $scanAddress += [uint64]$coreLen
        }
    }

    Write-Host ''
    Write-Host '============================================================'
    Write-Host ('Scan complete. Regions={0}, Bytes={1:N0}, Candidates={2}' -f $regionsScanned, $bytesScanned, $candidateCount)
    if ($candidateCount -eq 0) {
        Write-Host 'No exact contiguous 8xPlayerInfo candidate matched P1=T6 + P2-P4=AI.'
        Write-Host 'That would mean the live lobby representation differs from the deserializer temporary-array layout; no write should be attempted.'
    }
    else {
        Write-Host 'Candidates are LOCATOR HITS only. They are not yet proven writable bridge targets.'
        Write-Host 'Next proof is controlled lobby mutation (change one AI difficulty) and read-only rescan/diff.'
    }
    Write-Host '============================================================'
}
finally {
    [void][A8PLobbyStagingReadOnlyV1]::CloseHandle($handle)
}
