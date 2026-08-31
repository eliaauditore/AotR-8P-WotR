param(
    [string]$Label = 'NODE',
    [string]$OutputDir = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# V3 compact-state trace runner.
# Downloads the pinned first-generation controlled capture and transforms a
# temporary copy so the injected hook records only the CURRENT published
# localRoot and stores fixed 20-byte records:
#   uint32 index, this, tag, len, preA(this+0x44)
# No payload bytes are copied in this pass. This is enough to locate the first
# Host/VM divergence; a later targeted capture can collect only that payload.
# game.dat on disk is never modified. The hook remains exact-byte guarded and
# is restored before trace parsing.

$SourceCommit = 'd9c786a74a305f15dac2c6ebb2d9785196c55f0c'
$SourceUri = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/tools/research/AOTR_WOTR_LOCALROOT_INPUT_STREAM_CAPTURE.ps1"
$temp = Join-Path $env:TEMP ('AOTR_WOTR_LOCALROOT_COMPACT_STATE_TRACE_V3_' + [guid]::NewGuid().ToString('N') + '.ps1')

try {
    $text = (Invoke-WebRequest -UseBasicParsing -Uri $SourceUri).Content
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'Pinned capture source download returned empty content.' }

    # PowerShell $PID compatibility.
    $pidCount = ([regex]::Matches($text, '(?i)\$pid\b')).Count
    if ($pidCount -lt 1) { throw 'Expected at least one $pid token in pinned source.' }
    $text = [regex]::Replace($text, '(?i)\$pid\b', '$gamePid')
    if ([regex]::IsMatch($text, '(?i)\$pid\b')) { throw 'PID token replacement incomplete.' }

    # Unique Add-Type class so an already-loaded V1/V2 class in this PowerShell
    # process cannot shadow the V3 BuildStub signature.
    $text = $text.Replace('A8PInputTraceNative','A8PInputTraceNativeV3')

    # 64 MiB scratch. Fixed 20-byte records permit >3.3M localRoot calls.
    $oldAlloc = '$AllocSize = 0x01000000                  # 16 MiB'
    $newAlloc = '$AllocSize = 0x04000000                  # 64 MiB V3 compact trace'
    if (-not $text.Contains($oldAlloc)) { throw 'AllocSize source anchor not found.' }
    $text = $text.Replace($oldAlloc,$newAlloc)

    # Replace the original payload-copying stub with a compact filtered stub.
    $buildPattern = '(?s)    public static byte\[\] BuildStub\(UInt32 remoteBase, UInt32 continueVa, UInt32 capacity\) \{.*?\r?\n    \}\r?\n\r?\n    public static byte\[\] BuildHook'
    $newBuild = @'
    public static byte[] BuildStub(UInt32 remoteBase, UInt32 continueVa, UInt32 capacity, UInt32 rootMgrGlobalVa) {
        UInt32 offAddr=remoteBase+0x00, countAddr=remoteBase+0x04, overflowAddr=remoteBase+0x08, dataBase=remoteBase+0x1000;
        const UInt32 REC=20;
        var b=new List<byte>();
        b.Add(0x9C);                                            // pushfd
        b.Add(0x60);                                            // pushad

        // Filter: manager=[DE3380], root=[manager+0x24], root must equal saved original ECX(this).
        b.Add(0xA1); U32(b,rootMgrGlobalVa);                     // mov eax,[rootMgrGlobalVa]
        b.AddRange(new byte[]{0x85,0xC0});                       // test eax,eax
        int jDoneNoMgr=Jcc(b,0x84);                              // je done
        b.AddRange(new byte[]{0x8B,0x40,0x24});                  // mov eax,[eax+24]
        b.AddRange(new byte[]{0x85,0xC0});                       // test eax,eax
        int jDoneNoRoot=Jcc(b,0x84);                             // je done
        b.AddRange(new byte[]{0x3B,0x44,0x24,0x18});             // cmp eax,[esp+18] saved original ECX
        int jDoneOther=Jcc(b,0x85);                              // jne done

        b.AddRange(new byte[]{0x8B,0x1D}); U32(b,offAddr);       // mov ebx,[off]
        b.AddRange(new byte[]{0x8B,0xC3});                       // mov eax,ebx
        b.AddRange(new byte[]{0x83,0xC0,0x14});                  // add eax,20
        b.Add(0x3D); U32(b,capacity);                            // cmp eax,capacity
        int jOverflow=Jcc(b,0x87);                               // ja overflow

        b.Add(0xA1); U32(b,countAddr);                           // mov eax,[count]
        b.Add(0x40);                                             // inc eax
        b.Add(0xA3); U32(b,countAddr);                           // mov [count],eax
        b.Add(0xBF); U32(b,dataBase);                            // mov edi,dataBase
        b.AddRange(new byte[]{0x03,0xFB});                       // add edi,ebx
        b.AddRange(new byte[]{0x89,0x07});                       // [edi+00]=index

        b.AddRange(new byte[]{0x8B,0x44,0x24,0x18});             // eax=saved original ECX(this)
        b.AddRange(new byte[]{0x89,0x47,0x04});                  // [edi+04]=this
        b.AddRange(new byte[]{0x8B,0x54,0x24,0x28});             // edx=arg1 tag
        b.AddRange(new byte[]{0x89,0x57,0x08});                  // [edi+08]=tag
        b.AddRange(new byte[]{0x8B,0x54,0x24,0x30});             // edx=arg3 len
        b.AddRange(new byte[]{0x89,0x57,0x0C});                  // [edi+0C]=len
        b.AddRange(new byte[]{0x8B,0x40,0x44});                  // eax=[this+44] preA
        b.AddRange(new byte[]{0x89,0x47,0x10});                  // [edi+10]=preA

        b.AddRange(new byte[]{0x8B,0xC3});                       // eax=old off
        b.AddRange(new byte[]{0x83,0xC0,0x14});                  // +20
        b.Add(0xA3); U32(b,offAddr);                             // [off]=eax
        int jDoneLogged=Jmp(b);

        int overflow=b.Count;
        Patch(b,jOverflow,overflow);
        b.AddRange(new byte[]{0xC7,0x05}); U32(b,overflowAddr); U32(b,1); // overflow=1

        int done=b.Count;
        Patch(b,jDoneNoMgr,done); Patch(b,jDoneNoRoot,done); Patch(b,jDoneOther,done); Patch(b,jDoneLogged,done);
        b.Add(0x61);                                             // popad
        b.Add(0x9D);                                             // popfd

        // Stolen original 7 bytes at 0xA211DF.
        b.Add(0x55);                                             // push ebp
        b.AddRange(new byte[]{0x8B,0xEC});                       // mov ebp,esp
        b.AddRange(new byte[]{0x83,0x7D,0x0C,0x00});             // cmp [ebp+0C],0
        b.Add(0xE9);
        UInt32 stubVa=remoteBase+0x100;
        UInt32 next=(UInt32)(stubVa+b.Count+4);
        Int32 rel=unchecked((Int32)(continueVa-next));
        U32(b,unchecked((UInt32)rel));
        return b.ToArray();
    }

    public static byte[] BuildHook
'@
    $rx = [regex]::new($buildPattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $rx.IsMatch($text)) { throw 'BuildStub source block anchor not found.' }
    $text = $rx.Replace($text,$newBuild.TrimEnd("`r","`n"),1)

    $oldCall = '$stub = [A8PInputTraceNativeV3]::BuildStub($remoteBase,[uint32]$continue,[uint32]$DataCapacity)'
    $newCall = '$stub = [A8PInputTraceNativeV3]::BuildStub($remoteBase,[uint32]$continue,[uint32]$DataCapacity,[uint32]($base + $MgrGlobalRva))'
    if (-not $text.Contains($oldCall)) { throw 'V3 BuildStub invocation anchor not found.' }
    $text = $text.Replace($oldCall,$newCall)

    $banner = "Write-Host ' AOTR WOTR LOCALROOT INPUT-STREAM CAPTURE'"
    $text = $text.Replace($banner,"Write-Host ' AOTR WOTR LOCALROOT COMPACT STATE TRACE - V3'")
    $mode = "Write-Host 'Mode                 : controlled process-only instrumentation'"
    $text = $text.Replace($mode,"Write-Host 'Mode                 : compact localRoot-only index/this/tag/len/preA trace'")

    # Replace payload parser/replay/TSV output with fixed-record binary output.
    $tailPattern = "(?s)if \(\$null -eq \$traceBytes\) \{ throw 'No trace buffer was captured\.' \}.*?Write-Host 'The process hook was restored to the exact original 7 bytes\.'"
    $newTail = @'
if ($null -eq $traceBytes) { throw 'No trace buffer was captured.' }

$RecordSize = 20
if (($traceBytes.Length % $RecordSize) -ne 0) {
    throw "Compact trace size $($traceBytes.Length) is not divisible by record size $RecordSize."
}
$recordCount = [int]($traceBytes.Length / $RecordSize)
$wrongThis = 0
$firstPreA = $null
$lastPreA = $null
$firstTag = $null
$lastTag = $null
for ($i=0; $i -lt $recordCount; $i++) {
    $o = $i * $RecordSize
    $idx = [BitConverter]::ToUInt32($traceBytes,$o)
    $thisPtr = [BitConverter]::ToUInt32($traceBytes,$o+4)
    $tag = [BitConverter]::ToUInt32($traceBytes,$o+8)
    $len = [BitConverter]::ToUInt32($traceBytes,$o+12)
    $preA = [BitConverter]::ToUInt32($traceBytes,$o+16)
    if ($thisPtr -ne $root) { $wrongThis++ }
    if ($i -eq 0) { $firstPreA=$preA; $firstTag=$tag }
    $lastPreA=$preA; $lastTag=$tag
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$safeLabel = ($Label -replace '[^A-Za-z0-9_.-]','_')
$bin = Join-Path $OutputDir ("AOTR_WOTR_LOCALROOT_COMPACT_V3_{0}_{1}.bin" -f $safeLabel,$stamp)
$gzPath = $bin + '.gz'
[System.IO.File]::WriteAllBytes($bin,$traceBytes)
$fs = [System.IO.File]::Create($gzPath)
try {
    $gz = [System.IO.Compression.GZipStream]::new($fs,[System.IO.Compression.CompressionLevel]::Optimal,$false)
    try { $gz.Write($traceBytes,0,$traceBytes.Length) } finally { $gz.Dispose() }
} finally { $fs.Dispose() }

Write-Host ''
Write-Host '================ COMPACT TRACE SUMMARY ================'
Write-Host ("localRoot            : 0x{0:X8}" -f $root)
Write-Host ("localRoot vtable     : 0x{0:X8}" -f $rootVT)
Write-Host ("records              : {0}" -f $recordCount)
Write-Host ("record bytes         : {0}" -f $traceBytes.Length)
Write-Host ("wrong-this records   : {0}" -f $wrongThis)
Write-Host ("overflow             : {0}" -f $overflow)
if ($recordCount -gt 0) {
    Write-Host ("first preA/tag      : 0x{0:X8} / 0x{1:X8}" -f $firstPreA,$firstTag)
    Write-Host ("last preA/tag       : 0x{0:X8} / 0x{1:X8}" -f $lastPreA,$lastTag)
}
if ($null -ne $globalDerivedA) {
    Write-Host ("B04 live             : 0x{0:X8}" -f $b04)
    Write-Host ("Component B          : 0x{0:X8}" -f $componentB)
    Write-Host ("derived Component A  : 0x{0:X8}" -f $globalDerivedA)
}
Write-Host ("Trace BIN             : {0}" -f $bin)
Write-Host ("Trace GZIP            : {0}" -f $gzPath)
Write-Host ("COMPACT_TRACE_KEY     : LABEL={0};ROOTVT={1:X8};RECORDS={2};BYTES={3};WRONGTHIS={4};OVERFLOW={5};DERIVED_A={6}" -f $Label,$rootVT,$recordCount,$traceBytes.Length,$wrongThis,$overflow,$(if ($null -ne $globalDerivedA) {('{0:X8}' -f $globalDerivedA)} else {'NA'}))
Write-Host ''
Write-Host 'CONTROLLED V3 CAPTURE COMPLETE. game.dat on disk was never modified.'
Write-Host 'The process hook was restored to the exact original 7 bytes.'
'@
    $tailRx = [regex]::new($tailPattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $tailRx.IsMatch($text)) { throw 'Payload parser/output tail anchor not found.' }
    $text = $tailRx.Replace($text,$newTail.TrimEnd("`r","`n"),1)

    Set-Content -LiteralPath $temp -Value $text -Encoding utf8NoBOM
    Write-Host ("V3 source transform  : PID tokens={0}; unique native type=ON; localRoot filter=ON; fixed record=20 B; buffer=64 MiB" -f $pidCount)
    & $temp -Label $Label -OutputDir $OutputDir
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
