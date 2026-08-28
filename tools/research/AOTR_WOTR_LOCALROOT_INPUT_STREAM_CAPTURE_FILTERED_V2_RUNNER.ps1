param(
    [string]$Label = 'NODE',
    [string]$OutputDir = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Compatibility/filter runner for the pinned first-generation capture.
# It fixes the PowerShell $PID collision and changes the injected hook so it
# records ONLY calls whose ECX matches the currently published localRoot at
# [DE3380] -> +0x24. This avoids filling the trace with unrelated A211DF calls.
# It also gives V2 its own Add-Type class name because PowerShell cannot replace
# an already-loaded C# type from V1 in the same PowerShell process.
# game.dat on disk is never modified.

$SourceCommit = 'd9c786a74a305f15dac2c6ebb2d9785196c55f0c'
$SourceUri = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/$SourceCommit/tools/research/AOTR_WOTR_LOCALROOT_INPUT_STREAM_CAPTURE.ps1"
$temp = Join-Path $env:TEMP ('AOTR_WOTR_LOCALROOT_INPUT_STREAM_CAPTURE_FILTERED_V2_' + [guid]::NewGuid().ToString('N') + '.ps1')

try {
    $text = (Invoke-WebRequest -UseBasicParsing -Uri $SourceUri).Content
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'Pinned capture source download returned empty content.' }

    # 1) PowerShell automatic-variable compatibility.
    $pidCount = ([regex]::Matches($text, '\$pid\b')).Count
    if ($pidCount -lt 1) { throw 'Expected at least one lowercase $pid token in pinned source.' }
    $text = $text.Replace('$pid','$gamePid')
    if ([regex]::IsMatch($text, '\$pid\b')) { throw 'PID token replacement incomplete.' }

    # 2) Give V2 a unique C# helper type. Add-Type types persist for the entire
    #    PowerShell process, so reusing A8PInputTraceNative would retain V1's
    #    old three-argument BuildStub overload.
    $nativeTypeCount = ([regex]::Matches($text, 'A8PInputTraceNative')).Count
    if ($nativeTypeCount -lt 2) { throw 'Expected A8PInputTraceNative source references not found.' }
    $text = $text.Replace('A8PInputTraceNative','A8PInputTraceNativeFilteredV2')
    if ($text.Contains('A8PInputTraceNative]')) { throw 'Native type replacement incomplete.' }

    # 3) Give the filtered trace extra headroom.
    $oldAlloc = '$AllocSize = 0x01000000                  # 16 MiB'
    $newAlloc = '$AllocSize = 0x02000000                  # 32 MiB (V2 filtered trace)'
    if (-not $text.Contains($oldAlloc)) { throw 'AllocSize source anchor not found.' }
    $text = $text.Replace($oldAlloc,$newAlloc)

    # 4) Extend BuildStub contract with the absolute manager-global VA.
    $oldSig = 'public static byte[] BuildStub(UInt32 remoteBase, UInt32 continueVa, UInt32 capacity) {'
    $newSig = 'public static byte[] BuildStub(UInt32 remoteBase, UInt32 continueVa, UInt32 capacity, UInt32 rootMgrGlobalVa) {'
    if (-not $text.Contains($oldSig)) { throw 'BuildStub signature anchor not found.' }
    $text = $text.Replace($oldSig,$newSig)

    # 5) Filter in the injected x86 stub before any record is written:
    #    manager=[rootMgrGlobalVa], currentRoot=[manager+0x24], require currentRoot==saved original ECX.
    $pushadAnchor = '        b.Add(0x60);                    // pushad'
    $filterBlock = @'
        b.Add(0x60);                    // pushad
        b.Add(0xA1); U32(b,rootMgrGlobalVa);                       // eax=[DE3380]
        b.AddRange(new byte[]{0x85,0xC0});                          // test eax,eax
        int jSkipNoMgr=Jcc(b,0x84);                                // je skip/log-disabled
        b.AddRange(new byte[]{0x8B,0x40,0x24});                    // eax=[manager+0x24] current localRoot
        b.AddRange(new byte[]{0x85,0xC0});                          // test eax,eax
        int jSkipNoRoot=Jcc(b,0x84);                               // je skip
        b.AddRange(new byte[]{0x3B,0x44,0x24,0x18});               // cmp eax,saved original ECX(this)
        int jSkipOtherThis=Jcc(b,0x85);                            // jne skip
'@
    if (-not $text.Contains($pushadAnchor)) { throw 'pushad anchor not found.' }
    $text = $text.Replace($pushadAnchor,$filterBlock.TrimEnd("`r","`n"))

    # 6) Resolve the new skip branches to the existing common epilogue immediately before popad.
    $doneAnchor = '        int done=b.Count; Patch(b,jDone,done);'
    $doneReplacement = @'
        int done=b.Count; Patch(b,jDone,done);
        Patch(b,jSkipNoMgr,done); Patch(b,jSkipNoRoot,done); Patch(b,jSkipOtherThis,done);
'@
    if (-not $text.Contains($doneAnchor)) { throw 'done-label anchor not found.' }
    $text = $text.Replace($doneAnchor,$doneReplacement.TrimEnd("`r","`n"))

    # 7) Pass the runtime manager-global VA into the stub builder.
    $oldCall = '$stub = [A8PInputTraceNativeFilteredV2]::BuildStub($remoteBase,[uint32]$continue,[uint32]$DataCapacity)'
    $newCall = '$stub = [A8PInputTraceNativeFilteredV2]::BuildStub($remoteBase,[uint32]$continue,[uint32]$DataCapacity,[uint32]($base + $MgrGlobalRva))'
    if (-not $text.Contains($oldCall)) { throw 'BuildStub invocation anchor not found.' }
    $text = $text.Replace($oldCall,$newCall)

    # 8) Make V2 identity explicit in the console so stale output is obvious.
    $banner = "Write-Host ' AOTR WOTR LOCALROOT INPUT-STREAM CAPTURE'"
    $bannerV2 = "Write-Host ' AOTR WOTR LOCALROOT INPUT-STREAM CAPTURE - FILTERED V2'"
    if (-not $text.Contains($banner)) { throw 'Banner anchor not found.' }
    $text = $text.Replace($banner,$bannerV2)
    $mode = "Write-Host 'Mode                 : controlled process-only instrumentation'"
    $modeV2 = "Write-Host 'Mode                 : controlled process-only instrumentation; in-stub localRoot filter'"
    $text = $text.Replace($mode,$modeV2)

    Set-Content -LiteralPath $temp -Value $text -Encoding utf8NoBOM
    Write-Host ("V2 source transform  : PID tokens={0}; native type refs={1}; localRoot in-stub filter=ON; buffer=32 MiB" -f $pidCount,$nativeTypeCount)
    & $temp -Label $Label -OutputDir $OutputDir
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
