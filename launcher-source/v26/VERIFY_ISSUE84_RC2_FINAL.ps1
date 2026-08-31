#requires -version 5.1
[CmdletBinding()]
param(
    [string]$BuildRoot = ".\_V26_1_1_8_RC2_FINAL_BUILD"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
$Engine = Join-Path $BuildRoot "work\resources\launcher_engine.ps1"
$Gui = Join-Path $BuildRoot "work\resources\launcher_gui.ps1"
$CSharp = Join-Path $BuildRoot "work\launcher_v26.cs"
$Exe = Join-Path $BuildRoot "package\AotR 8P WotR Mod.exe"

foreach ($path in @($Engine,$Gui,$CSharp,$Exe)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Issue84 RC2 verifier input missing: $path"
    }
}

foreach ($path in @($Engine,$Gui)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "PS5.1 generated parse failure: $path :: $($errors[0].Message)"
    }
}

$engineText = [IO.File]::ReadAllText($Engine)
$guiText = [IO.File]::ReadAllText($Gui)
$csText = [IO.File]::ReadAllText($CSharp)

foreach ($needle in @(
    '$runtimeRoot = Join-Path $stateRootFull "runtime"',
    '$sessionRoot = Join-Path $runtimeRoot "sessions"',
    'launcher_start_utc_ticks',
    'game_launcher_start_utc_ticks',
    'game_start_utc_ticks',
    '--cleanup-runtime-watch',
    'ReparsePoint'
)) {
    if (-not $engineText.Contains($needle)) {
        throw "RC2 engine contract missing: $needle"
    }
}

$markerMatches = [regex]::Matches(
    $engineText,
    '(?ms)^function\s+Write-AotR8PSessionMarker\b.*?^}\s*(?=\r?\n)'
)
if ($markerMatches.Count -ne 1) {
    throw "Expected exactly one Write-AotR8PSessionMarker definition, found $($markerMatches.Count)."
}
$markerText = $markerMatches[0].Value
if (-not $markerText.Contains('schema = 2')) {
    throw "Session marker writer is not schema 2."
}
if ($markerText.Contains('schema = 1')) {
    throw "RC1 schema remains inside the session marker writer."
}
foreach ($needle in @(
    'session_id',
    'launcher_start_utc_ticks',
    'game_launcher_start_utc_ticks',
    'game_start_utc_ticks',
    'updated_utc'
)) {
    if (-not $markerText.Contains($needle)) {
        throw "Session marker writer missing: $needle"
    }
}

if ($engineText.Contains('Join-Path $runtimeStageRoot ("_AOTR_8P_WOTR_RUNTIME_V4_" + $PID)')) {
    throw "Legacy V4 runtime creation remains."
}
if ($engineText.Contains('__A8P_RC2_RUNTIME_SESSIONS_SENTINEL__')) {
    throw "Source-only RC2 sentinel leaked into generated engine."
}

foreach ($needle in @('--cleanup-runtime-stale','Remove-AotR8PLegacyRuntimeFolders')) {
    if (-not $guiText.Contains($needle)) {
        throw "RC2 GUI contract missing: $needle"
    }
}
foreach ($forbidden in @(
    '"--cleanup-runtime",',
    'Move-Item -LiteralPath $runtimePath -Destination $quarantine',
    '$leaf + "_REPAIR_"'
)) {
    if ($guiText.Contains($forbidden)) {
        throw "Unsafe/persistent RC1 primitive remains: $forbidden"
    }
}

foreach ($needle in @(
    'RunRuntimeCleanupWatch',
    'RunRuntimeCleanupStale',
    'TryReadRuntimeSessionMarker',
    'IsRecordedProcessAlive',
    'RuntimeSessionRootComponentsSafe',
    'CanDeleteRuntimeSessionNow',
    'RuntimeLifecycleSelfTest',
    'Path.GetDirectoryName(full)',
    'HasRuntimeSessionForUpdateDeferral',
    'Update deferred while a transient runtime session or cleanup watcher is active.'
)) {
    if (-not $csText.Contains($needle)) {
        throw "RC2 C# contract missing: $needle"
    }
}
foreach ($forbidden in @(
    'RunRuntimeCleanupHelper',
    'WaitForPidExit',
    'String.Equals(args[0], "--cleanup-runtime",'
)) {
    if ($csText.Contains($forbidden)) {
        throw "RC1 weak lifecycle primitive remains: $forbidden"
    }
}
Write-Host "ISSUE84_RC2_GENERATED_CONTRACT=PASS" -ForegroundColor Green

$fvi = [Diagnostics.FileVersionInfo]::GetVersionInfo($Exe)
if ($fvi.ProductVersion -ne '1.1.8') {
    throw "Unexpected ProductVersion: $($fvi.ProductVersion)"
}

$p = Start-Process -FilePath $Exe -ArgumentList '--runtime-lifecycle-selftest' -WindowStyle Hidden -PassThru -Wait
if ($p.ExitCode -ne 0) {
    throw "Runtime lifecycle self-test failed with exit code $($p.ExitCode)"
}
Write-Host "ISSUE84_RC2_BUILTIN_SELFTEST=PASS" -ForegroundColor Green

$Sessions = Join-Path $env:LOCALAPPDATA 'AotR 8P WotR Mod\runtime\sessions'
New-Item -ItemType Directory -Force -Path $Sessions | Out-Null

$cleanupPaths = New-Object System.Collections.Generic.List[string]
$dummy = $null
$watcher = $null
$junction = $null
$junctionTarget = $null

function Add-CleanupPath([string]$Path) {
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        [void]$script:cleanupPaths.Add($Path)
    }
}

function Write-Marker(
    [string]$Path,
    [string]$SessionId,
    [int]$LauncherPid,
    [long]$LauncherTicks,
    [int]$GameLauncherPid = 0,
    [long]$GameLauncherTicks = 0,
    [int]$GamePid = 0,
    [long]$GameTicks = 0
) {
    $obj = [ordered]@{
        schema = 2
        session_id = $SessionId
        launcher_pid = $LauncherPid
        launcher_start_utc_ticks = $LauncherTicks
        game_launcher_pid = $GameLauncherPid
        game_launcher_start_utc_ticks = $GameLauncherTicks
        game_pid = $GamePid
        game_start_utc_ticks = $GameTicks
        updated_utc = [DateTime]::UtcNow.ToString('o')
    }
    $json = $obj | ConvertTo-Json -Depth 3
    [IO.File]::WriteAllText(
        (Join-Path $Path 'AOTR8P_SESSION.json'),
        $json,
        (New-Object Text.UTF8Encoding($false))
    )
}

function Invoke-Stale([string]$Path) {
    $proc = Start-Process -FilePath $Exe `
        -ArgumentList ('--cleanup-runtime-stale "' + $Path + '"') `
        -WindowStyle Hidden -PassThru -Wait
    return [int]$proc.ExitCode
}

try {
    # 1. Exact live PID+StartTime identity must be protected from stale cleanup.
    $self = Get-Process -Id $PID
    $selfTicks = [long]$self.StartTime.ToUniversalTime().Ticks
    $activeId = 'AOTR8P_SESSION_' + $PID + '_' + [Guid]::NewGuid().ToString('N')
    $activePath = Join-Path $Sessions $activeId
    New-Item -ItemType Directory -Path $activePath | Out-Null
    Add-CleanupPath $activePath
    Write-Marker $activePath $activeId $PID $selfTicks
    $exit = Invoke-Stale $activePath
    if ($exit -ne 5 -or -not (Test-Path -LiteralPath $activePath -PathType Container)) {
        throw "Active session protection failed. exit=$exit"
    }
    Remove-Item -LiteralPath $activePath -Recurse -Force
    Write-Host "ISSUE84_RC2_ACTIVE_SESSION_PROTECTION=PASS" -ForegroundColor Green

    # 2. PID reuse protection: same PID but wrong creation time is stale.
    $reuseId = 'AOTR8P_SESSION_' + $PID + '_' + [Guid]::NewGuid().ToString('N')
    $reusePath = Join-Path $Sessions $reuseId
    New-Item -ItemType Directory -Path $reusePath | Out-Null
    Add-CleanupPath $reusePath
    Write-Marker $reusePath $reuseId $PID ($selfTicks + ([TimeSpan]::TicksPerSecond * 30L))
    $exit = Invoke-Stale $reusePath
    if ($exit -ne 0 -or (Test-Path -LiteralPath $reusePath)) {
        throw "PID reuse resistance failed. exit=$exit"
    }
    Write-Host "ISSUE84_RC2_PID_REUSE_RESISTANCE=PASS" -ForegroundColor Green

    # 3. Invalid/malformed markers get a conservative 30-minute grace period.
    $deadPid = 2147483000
    $badId = 'AOTR8P_SESSION_' + $deadPid + '_' + [Guid]::NewGuid().ToString('N')
    $badPath = Join-Path $Sessions $badId
    New-Item -ItemType Directory -Path $badPath | Out-Null
    Add-CleanupPath $badPath
    [IO.File]::WriteAllText(
        (Join-Path $badPath 'AOTR8P_SESSION.json'),
        '{broken-json',
        (New-Object Text.UTF8Encoding($false))
    )
    $exit = Invoke-Stale $badPath
    if ($exit -ne 5 -or -not (Test-Path -LiteralPath $badPath -PathType Container)) {
        throw "Fresh malformed marker was not retained. exit=$exit"
    }
    [IO.Directory]::SetLastWriteTimeUtc($badPath,[DateTime]::UtcNow.AddMinutes(-31))
    $exit = Invoke-Stale $badPath
    if ($exit -ne 0 -or (Test-Path -LiteralPath $badPath)) {
        throw "Aged malformed stale session was not removed. exit=$exit"
    }
    Write-Host "ISSUE84_RC2_INVALID_MARKER_GRACE=PASS" -ForegroundColor Green

    # 4. Only direct child session paths are accepted.
    $outer = Join-Path $Sessions ('nested-' + [Guid]::NewGuid().ToString('N'))
    $nestedId = 'AOTR8P_SESSION_' + $deadPid + '_' + [Guid]::NewGuid().ToString('N')
    $nested = Join-Path $outer $nestedId
    New-Item -ItemType Directory -Force -Path $nested | Out-Null
    Add-CleanupPath $outer
    $exit = Invoke-Stale $nested
    if ($exit -ne 3 -or -not (Test-Path -LiteralPath $nested -PathType Container)) {
        throw "Direct-child path boundary failed. exit=$exit"
    }
    Remove-Item -LiteralPath $outer -Recurse -Force
    Write-Host "ISSUE84_RC2_DIRECT_CHILD_BOUNDARY=PASS" -ForegroundColor Green

    # 5. Watch mode must retain while the recorded process lives, then delete.
    $dummy = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList '-NoProfile -WindowStyle Hidden -Command "Start-Sleep -Seconds 4"' `
        -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 300
    $dummy.Refresh()
    $dummyTicks = [long]$dummy.StartTime.ToUniversalTime().Ticks
    $watchId = 'AOTR8P_SESSION_' + $dummy.Id + '_' + [Guid]::NewGuid().ToString('N')
    $watchPath = Join-Path $Sessions $watchId
    New-Item -ItemType Directory -Path $watchPath | Out-Null
    Add-CleanupPath $watchPath
    Write-Marker $watchPath $watchId $dummy.Id $dummyTicks
    $watcher = Start-Process -FilePath $Exe `
        -ArgumentList ('--cleanup-runtime-watch "' + $watchPath + '"') `
        -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 1
    $watcher.Refresh()
    if ($watcher.HasExited -or -not (Test-Path -LiteralPath $watchPath -PathType Container)) {
        throw "Cleanup watcher failed to retain an active session."
    }
    $dummy.WaitForExit()
    if (-not $watcher.WaitForExit(20000)) {
        try { $watcher.Kill() } catch {}
        throw "Cleanup watcher did not finish after recorded process exit."
    }
    if ($watcher.ExitCode -ne 0 -or (Test-Path -LiteralPath $watchPath)) {
        throw "Cleanup watcher did not delete ended session. exit=$($watcher.ExitCode)"
    }
    Write-Host "ISSUE84_RC2_WATCHER_LIFECYCLE=PASS" -ForegroundColor Green

    # 6. Session directory junctions/reparse points must not be followed.
    $junctionTarget = Join-Path $env:TEMP ('issue84-junction-target-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $junctionTarget | Out-Null
    $junctionId = 'AOTR8P_SESSION_' + $deadPid + '_' + [Guid]::NewGuid().ToString('N')
    Write-Marker $junctionTarget $junctionId $deadPid 1
    $junction = Join-Path $Sessions $junctionId
    New-Item -ItemType Junction -Path $junction -Target $junctionTarget | Out-Null
    $exit = Invoke-Stale $junction
    if ($exit -ne 4 -or -not (Test-Path -LiteralPath $junction) -or -not (Test-Path -LiteralPath $junctionTarget -PathType Container)) {
        throw "Reparse no-follow protection failed. exit=$exit"
    }
    [IO.Directory]::Delete($junction,$false)
    $junction = $null
    Remove-Item -LiteralPath $junctionTarget -Recurse -Force
    $junctionTarget = $null
    Write-Host "ISSUE84_RC2_REPARSE_NO_FOLLOW=PASS" -ForegroundColor Green
}
finally {
    if ($watcher -ne $null) {
        try { if (-not $watcher.HasExited) { $watcher.Kill() } } catch {}
        try { $watcher.Dispose() } catch {}
    }
    if ($dummy -ne $null) {
        try { if (-not $dummy.HasExited) { $dummy.Kill() } } catch {}
        try { $dummy.Dispose() } catch {}
    }
    if ($junction -ne $null) {
        try { if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction,$false) } } catch {}
    }
    if ($junctionTarget -ne $null) {
        try { if (Test-Path -LiteralPath $junctionTarget) { Remove-Item -LiteralPath $junctionTarget -Recurse -Force } } catch {}
    }
    foreach ($path in @($cleanupPaths)) {
        try {
            if (Test-Path -LiteralPath $path) {
                $item = Get-Item -LiteralPath $path -Force
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    [IO.Directory]::Delete($path,$false)
                }
                else {
                    Remove-Item -LiteralPath $path -Recurse -Force
                }
            }
        }
        catch {}
    }
}

Write-Host "ISSUE84_RC2_EXECUTABLE_LIFECYCLE_GATE=PASS" -ForegroundColor Green
