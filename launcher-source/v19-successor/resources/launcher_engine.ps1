# =================================================================================================
# AOTR 8P WOTR LAUNCHER - FINAL STABLE FIXED V2
#
# Based on CURRENT_WORKING_LAUNCHER:
#   - deploys final native 8-row UI BIG BEFORE game start
#   - applies the same two proven 8P runtime patches
#   - installs byte-identical FINAL_STABLE_V7 from a verified launcher resource
#
# One file for normal use.
# =================================================================================================

[CmdletBinding()]
param(
    [string]$LogFile = ""
)

# -------------------------------------------------
# Adminrechte nur für diesen Start anfordern.
# IMPORTANT: the elevated instance receives the SAME log path, so the GUI
# can follow the real engine instead of losing output at the UAC boundary.
# -------------------------------------------------

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)

$isAdmin = $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    $self = $MyInvocation.MyCommand.Path
    $argList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ('"{0}"' -f $self)
    )
    if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
        $argList += @("-LogFile", ('"{0}"' -f $LogFile))
    }

    try {
        Start-Process `
            -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -Verb RunAs `
            -ArgumentList $argList | Out-Null
        exit 0
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $LogFile -Parent) -ErrorAction SilentlyContinue | Out-Null
            "AOTR8P_ENGINE_EXIT=1`r`nUAC/elevation failed: $($_.Exception.Message)" | Set-Content -LiteralPath $LogFile -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        exit 1
    }
}

$script:TranscriptStarted = $false
if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path $LogFile -Parent) | Out-Null
        Start-Transcript -LiteralPath $LogFile -Force | Out-Null
        $script:TranscriptStarted = $true
    } catch {}
}

Write-Host "Administratorrechte aktiv." -ForegroundColor Green
Write-Host ""
try {
    $ErrorActionPreference = "Stop"

if (-not ("AotR8PChildPatch" -as [type])) {
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class AotR8PChildPatch {

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(
        uint access, bool inherit, int pid);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool ReadProcessMemory(
        IntPtr h, IntPtr address,
        byte[] buffer, int size,
        out IntPtr read);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool WriteProcessMemory(
        IntPtr h, IntPtr address,
        byte[] buffer, int size,
        out IntPtr written);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool VirtualProtectEx(
        IntPtr h, IntPtr address,
        UIntPtr size, uint newProtect,
        out uint oldProtect);

    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr h);
}
"@
}

$packageRoot = [string]$global:AOTR8P_PACKAGE_ROOT
if ([string]::IsNullOrWhiteSpace($packageRoot)) { throw "Embedded launcher package root is missing." }
$stateRoot = Join-Path $env:LOCALAPPDATA "AotR 8P WotR Mod"
New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
$configPath  = Join-Path $stateRoot "launcher_config.json"
$payloadBig  = Join-Path $packageRoot "payload\!!!WOTR_8P_UI_TEST.big"
$payloadPaper = Join-Path $packageRoot "payload\data\ini\campaigns\scenarios\PaperScenario001.inc"

$Known931GameSize = 11347456
$Known931GameSha256 = "66AB714EA565CC490F9C41E1350F9A30708AEF6FBC2942325F50470BCB980202"
$CompatCachePath = Join-Path $stateRoot "compatibility_cache.json"
$ExpectedUiHash = "827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376"
$ExpectedPaperHash = "3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43"

function Get-Sha256([string]$Path) {
    $stream = $null
    $sha = $null
    try {
        $stream = [System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hash = $sha.ComputeHash($stream)
        return ([System.BitConverter]::ToString($hash)).Replace("-","").ToUpperInvariant()
    }
    finally {
        if ($stream) { $stream.Dispose() }
        if ($sha) { $sha.Dispose() }
    }
}

function Save-CompatibleBuildCache([string]$Path) {
    try {
        $info = Get-Item -LiteralPath $Path
        $entry = [PSCustomObject]@{
            schema = 1
            sha256 = (Get-Sha256 $Path)
            size = [Int64]$info.Length
            validation = "runtime-signatures-v1"
            verified_at_utc = [DateTime]::UtcNow.ToString("o")
        }
        $entry | ConvertTo-Json | Set-Content -LiteralPath $CompatCachePath -Encoding UTF8
    } catch {
        Write-Host "[WARN] Compatibility cache could not be written: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

function Get-CanonicalAotRPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
        return [IO.Path]::GetFullPath($expanded).TrimEnd('\')
    } catch {
        return $null
    }
}

function Get-AotRInstallFromPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    try {
        $candidate = Get-CanonicalAotRPath $Path
        if (-not $candidate) { return $null }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $candidate = Split-Path $candidate -Parent
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { return $null }

        $roots = New-Object System.Collections.Generic.List[string]
        $seen = @{}
        $walk = $candidate

        for ($up=0; $up -lt 5 -and -not [string]::IsNullOrWhiteSpace($walk); $up++) {
            $possible = New-Object System.Collections.Generic.List[string]
            [void]$possible.Add($walk)

            $leaf = Split-Path $walk -Leaf
            if ($leaf -ieq 'rotwk' -or $leaf -ieq 'aotr') {
                $parentOfChild = Split-Path $walk -Parent
                if ($parentOfChild) { [void]$possible.Add($parentOfChild) }
            }

            [void]$possible.Add((Join-Path $walk 'AgeoftheRing'))
            [void]$possible.Add((Join-Path $walk 'Age of the Ring'))

            foreach ($rootCandidate in $possible) {
                if ([string]::IsNullOrWhiteSpace($rootCandidate)) { continue }
                $root = Get-CanonicalAotRPath $rootCandidate
                if (-not $root) { continue }
                $key = $root.ToLowerInvariant()
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true
                [void]$roots.Add($root)
            }

            $parent = Split-Path $walk -Parent
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ieq $walk) { break }
            $walk = $parent
        }

        foreach ($root in $roots) {
            if ($root -match '(?i)(^|[\\/])_?(?:AotR8P|AOTR[_ -]*\d+P).*WotR.*Runtime[^\\/]*([\\/]|$)') { continue }
            if ($root -match '(?i)(all[ _-]*in[ _-]*one|allinone)') { continue }

            $runtime = Join-Path $root 'rotwk'
            $sourceMod = Join-Path $root 'aotr'
            $exe = Join-Path $runtime 'lotrbfme2ep1.exe'
            if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { continue }
            if (-not (Test-Path -LiteralPath $sourceMod -PathType Container)) { continue }

            $gameDat = $null
            foreach ($g in @(
                (Join-Path $runtime 'game.dat'),
                (Join-Path $runtime 'zGameDats\game.dat')
            )) {
                if (Test-Path -LiteralPath $g -PathType Leaf) {
                    $gameDat = $g
                    break
                }
            }
            if (-not $gameDat) { continue }

            return [PSCustomObject]@{
                Root = Get-CanonicalAotRPath $root
                Runtime = Get-CanonicalAotRPath $runtime
                SourceMod = Get-CanonicalAotRPath $sourceMod
                GameDat = Get-CanonicalAotRPath $gameDat
            }
        }
    } catch {}

    return $null
}

function Get-AotRConfigValue($Config,[string]$Name) {
    try {
        $prop = $Config.PSObject.Properties[$Name]
        if ($prop) { return [string]$prop.Value }
    } catch {}
    return ''
}

function Resolve-AotRInstall {
    # Engine is deliberately NOT a second discovery authority anymore.
    # GUI selects/validates AotR and writes schema-2 canonical config;
    # engine only consumes and hard-revalidates that exact root.
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Write-Host '[ERROR] Canonical launcher_config.json is missing. GUI resolver must select AotR first.' -ForegroundColor Red
        return $null
    }

    try {
        $cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $schemaText = Get-AotRConfigValue $cfg 'schema'
        $validation = Get-AotRConfigValue $cfg 'validation'
        $aotrRoot = Get-AotRConfigValue $cfg 'aotr_root'
        $schema = 0
        [void][int]::TryParse($schemaText,[ref]$schema)

        if ($schema -lt 2 -or $validation -ne 'aotr-standalone-v2' -or [string]::IsNullOrWhiteSpace($aotrRoot)) {
            Write-Host '[ERROR] launcher_config.json is not canonical schema 2. Open the GUI launcher and select AotR again.' -ForegroundColor Red
            return $null
        }

        $found = Get-AotRInstallFromPath $aotrRoot
        if ($found) { return $found }

        Write-Host '[ERROR] Canonical AotR root from launcher_config.json no longer validates.' -ForegroundColor Red
    } catch {
        Write-Host ("[ERROR] Canonical AotR config could not be parsed/revalidated: " + $_.Exception.Message) -ForegroundColor Red
    }

    return $null
}

function New-LinkedFile([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue }
    try {
        New-Item -ItemType HardLink -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
    }
    catch {
        try {
            New-Item -ItemType SymbolicLink -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
        }
        catch {
            Copy-Item -LiteralPath $Source -Destination $Destination -Force
        }
    }
}

function New-LinkedDirectory([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force -Recurse -ErrorAction SilentlyContinue }
    try {
        New-Item -ItemType Junction -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
    }
    catch {
        # Fallback is deliberately a normal directory copy only if junction creation is unavailable.
        Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
    }
}

$script:OverlayDirs = @("data","ini","campaigns","scenarios")
$script:OverlayFile = "PaperScenario001.inc"

function Build-OverlayBranch([string]$Source, [string]$Destination, [int]$Depth) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "AotR source folder missing while building runtime: $Source"
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    foreach ($file in @(Get-ChildItem -LiteralPath $Source -File -Force -ErrorAction SilentlyContinue)) {
        if ($Depth -ge $script:OverlayDirs.Count -and $file.Name -ieq $script:OverlayFile) { continue }
        New-LinkedFile $file.FullName (Join-Path $Destination $file.Name)
    }

    foreach ($dir in @(Get-ChildItem -LiteralPath $Source -Directory -Force -ErrorAction SilentlyContinue)) {
        $destDir = Join-Path $Destination $dir.Name
        if ($Depth -lt $script:OverlayDirs.Count -and $dir.Name -ieq $script:OverlayDirs[$Depth]) {
            Build-OverlayBranch $dir.FullName $destDir ($Depth + 1)
        } else {
            New-LinkedDirectory $dir.FullName $destDir
        }
    }
}

function Prepare-PortableModLayer {
    if (-not (Test-Path -LiteralPath $payloadBig -PathType Leaf)) { throw "8P UI payload missing: $payloadBig" }
    if (-not (Test-Path -LiteralPath $payloadPaper -PathType Leaf)) { throw "8P campaign payload missing: $payloadPaper" }

    $bigInfo = Get-Item -LiteralPath $payloadBig
    if ($bigInfo.Length -ne 366667 -or (Get-Sha256 $payloadBig) -ne $ExpectedUiHash) {
        throw "8P UI payload failed size/SHA256 verification."
    }
    $paperInfo = Get-Item -LiteralPath $payloadPaper
    if ($paperInfo.Length -ne 1648 -or (Get-Sha256 $payloadPaper) -ne $ExpectedPaperHash) {
        throw "PaperScenario001.inc failed size/SHA256 verification."
    }

    $gameInfo = Get-Item -LiteralPath $gameDat
    if ($gameInfo.Length -le 1048576) {
        throw "game.dat is unexpectedly small and cannot be a supported AotR runtime."
    }
    $gameHash = Get-Sha256 $gameDat
    if ($gameInfo.Length -eq $Known931GameSize -and $gameHash -eq $Known931GameSha256) {
        Write-Host "[OK] Known AotR 9.3.1 reference build detected." -ForegroundColor Green
    }
    else {
        Write-Host "[INFO] New/other AotR game.dat detected: $gameHash" -ForegroundColor Yellow
        Write-Host "[INFO] Runtime compatibility signatures will be checked before any patch write." -ForegroundColor Yellow
    }

    $already = @(Get-Process -Name "game","lotrbfme2ep1" -ErrorAction SilentlyContinue)
    if ($already.Count -gt 0) {
        throw "AotR is already running. Close game.dat / lotrbfme2ep1.exe and try again."
    }

    $marker = Join-Path $test "AOTR8P_V4_SOURCE.txt"
    $needBuild = $true
    if ((Test-Path -LiteralPath $test -PathType Container) -and (Test-Path -LiteralPath $marker -PathType Leaf)) {
        try {
            $markedSource = ([IO.File]::ReadAllText($marker)).Trim()
            if ($markedSource -ieq $sourceMod) { $needBuild = $false }
        } catch {}
    }

    if ($needBuild -and (Test-Path -LiteralPath $test)) {
        # Never recurse-delete a folder that may contain junctions to the user's AotR.
        # Use a fresh sibling runtime instead.
        $script:test = Join-Path $install.Root ("_AOTR_8P_WOTR_RUNTIME_V4_" + $PID)
        $test = $script:test
        $script:uiActive = Join-Path $test "!!!WOTR_8P_UI_TEST.big"
        $uiActive = $script:uiActive
        $marker = Join-Path $test "AOTR8P_V4_SOURCE.txt"
    }

    if ($needBuild) {
        New-Item -ItemType Directory -Force -Path $test | Out-Null
        Write-Host "Baue saubere AotR-8P-Laufzeitschicht..." -ForegroundColor Cyan
        Write-Host ("  AotR source : " + $sourceMod) -ForegroundColor DarkGray
        Write-Host ("  Runtime mod : " + $test) -ForegroundColor DarkGray
        Build-OverlayBranch $sourceMod $test 0
        [IO.File]::WriteAllText($marker,$sourceMod,[Text.Encoding]::UTF8)
    } else {
        Write-Host "Verwende bereits gebaute saubere V4-Laufzeitschicht." -ForegroundColor DarkGray
    }

    Copy-Item -LiteralPath $payloadBig -Destination (Join-Path $test "!!!WOTR_8P_UI_TEST.big") -Force
    $paperDest = Join-Path $test "data\ini\campaigns\scenarios\PaperScenario001.inc"
    New-Item -ItemType Directory -Force -Path (Split-Path $paperDest -Parent) | Out-Null
    if (Test-Path -LiteralPath $paperDest) { Remove-Item -LiteralPath $paperDest -Force }
    Copy-Item -LiteralPath $payloadPaper -Destination $paperDest -Force

    if ((Get-Sha256 (Join-Path $test "!!!WOTR_8P_UI_TEST.big")) -ne $ExpectedUiHash) { throw "Runtime BIG verification failed." }
    if ((Get-Sha256 $paperDest) -ne $ExpectedPaperHash) { throw "Runtime PaperScenario verification failed." }

    Write-Host "PORTABLE RUNTIME READY" -ForegroundColor Green
    Write-Host ""
}

$install = Resolve-AotRInstall
if (-not $install) {
    throw "Age of the Ring installation not found. Open the launcher once and select your AgeoftheRing/rotwk/aotr folder."
}

$runtime   = $install.Runtime
$gameDat   = $install.GameDat
$sourceMod = $install.SourceMod
$test      = Join-Path $install.Root "_AOTR_8P_WOTR_RUNTIME"

# -------------------------------------------------
# FINAL STABLE assets (portable package paths)
# -------------------------------------------------
$uiBuildRoot = Split-Path $payloadBig -Parent
$uiPreferred = $payloadBig
$uiActive    = Join-Path $test "!!!WOTR_8P_UI_TEST.big"
$uiExpectedSize = 366667

# FINAL_STABLE_V7 is embedded byte-for-byte and executed as a real temporary .ps1.
$FinalStableV7Sha256 = "72D00490538BE2222F5BAAF3D8A1648A86071D3A098946A7B8751E7D337300E2"

function Install-Final8PUI {
    Write-Host "Pruefe finale 8-Row-WotR-UI..." -ForegroundColor Cyan

    $source = $null

    if (Test-Path -LiteralPath $uiPreferred -PathType Leaf) {
        $source = Get-Item -LiteralPath $uiPreferred
    }
    elseif (Test-Path -LiteralPath $uiBuildRoot -PathType Container) {
        $source = Get-ChildItem `
            -LiteralPath $uiBuildRoot `
            -Directory `
            -Filter "WOTR_8P_NATIVE_FRAME_AND_FILL_*" `
            -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object {
                $candidate = Join-Path $_.FullName "WOTR_8P_NATIVE_ORIGINAL_8ROW_FRAME_AND_FILL.big"
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    Get-Item -LiteralPath $candidate
                }
            } |
            Where-Object { $_.Length -eq $uiExpectedSize } |
            Select-Object -First 1
    }

    if (-not $source) {
        throw @"
Finale 8-Row-UI-BIG wurde nicht gefunden.

Gesucht:
  $uiPreferred

oder unter:
  $uiBuildRoot\WOTR_8P_NATIVE_FRAME_AND_FILL_*\WOTR_8P_NATIVE_ORIGINAL_8ROW_FRAME_AND_FILL.big

Erwartete Dateigroesse: $uiExpectedSize Bytes
"@
    }

    if ($source.Length -ne $uiExpectedSize) {
        throw "8-Row-UI-BIG hat unerwartete Groesse: $($source.Length), erwartet $uiExpectedSize."
    }

    if (-not (Test-Path -LiteralPath $test -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $test | Out-Null
    }

    Copy-Item -LiteralPath $source.FullName -Destination $uiActive -Force

    $deployed = Get-Item -LiteralPath $uiActive
    if ($deployed.Length -ne $source.Length) {
        throw "8-Row-UI-Deployment fehlgeschlagen: Dateigroesse stimmt danach nicht."
    }

    $sourceHash = Get-Sha256 $source.FullName
    $activeHash = Get-Sha256 $uiActive
    if ($sourceHash -ne $activeHash) {
        throw "8-Row-UI-Deployment fehlgeschlagen: SHA256 stimmt danach nicht."
    }

    Write-Host ("  Quelle : " + $source.FullName) -ForegroundColor DarkGray
    Write-Host ("  Aktiv  : " + $uiActive) -ForegroundColor DarkGray
    Write-Host ("  SHA256 : " + $activeHash) -ForegroundColor DarkGray
    Write-Host "  [OK] Finale 8-Row-UI ist aktiv." -ForegroundColor Green
    Write-Host ""
}

function Install-FinalStableV7 {
    param(
        [int]$GamePid
    )

    Write-Host "Aktiviere FINAL_STABLE_V7 Kamera / Zoom / Drag..." -ForegroundColor Cyan
    Write-Host ""

    $bytes = [byte[]]$global:AOTR8P_FINAL_STABLE_V7_BYTES
    if ($null -eq $bytes -or $bytes.Length -eq 0) {
        throw "FINAL_STABLE_V7 resource is missing."
    }
    $embeddedHash = [BitConverter]::ToString(
        [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    ).Replace("-","")
    if ($embeddedHash -ne $FinalStableV7Sha256) {
        throw "FINAL_STABLE_V7 resource hash mismatch."
    }

    $v7Text = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
    $v7 = [powershell]::Create()

    try {
        [void]$v7.AddScript($v7Text)
        [void]$v7.AddParameter("GameDat", $gameDat)
        [void]$v7.AddParameter("AnchorGain", [single]2.0)
        [void]$v7.AddParameter("DragSpeed", [single]-16.0)
        [void]$v7.AddParameter("V7Shellcode", [byte[]]$global:AOTR8P_V7_SHELLCODE_BYTES)

        $null = $v7.Invoke()

        if ($v7.HadErrors) {
            $detail = ($v7.Streams.Error | ForEach-Object { $_.ToString() }) -join " | "
            throw "FINAL_STABLE_V7 In-Memory PowerShell failed: $detail"
        }
    }
    finally {
        $v7.Dispose()
    }

    Write-Host ""
    Write-Host "[OK] FINAL_STABLE_V7 automatisch aktiviert." -ForegroundColor Green
    Write-Host ""
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "          AotR 8P WotR Mod" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Prepare-PortableModLayer
Install-Final8PUI

Write-Host "Starte Age of the Ring..." -ForegroundColor Yellow

# WICHTIG:
# Wir merken uns exakt DIESE gestartete lotrbfme2ep1.exe.
$launcher = Start-Process `
    -FilePath "$runtime\lotrbfme2ep1.exe" `
    -WorkingDirectory $runtime `
    -ArgumentList "-mod `"$test`"" `
    -PassThru

$launcherPid = $launcher.Id

Write-Host "lotrbfme2ep1.exe PID: $launcherPid" -ForegroundColor Green
Write-Host "Suche deren Child-Prozess game.dat..." -ForegroundColor Yellow

$gameInfo = $null
$deadline = (Get-Date).AddSeconds(60)

while (-not $gameInfo -and (Get-Date) -lt $deadline) {

    $gameInfo = Get-CimInstance Win32_Process `
        -Filter "ParentProcessId=$launcherPid" `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -ieq "game.dat"
        } |
        Select-Object -First 1

    if (-not $gameInfo) {
        Start-Sleep -Milliseconds 100
    }
}

if (-not $gameInfo) {
    throw "Child game.dat von PID $launcherPid wurde nicht gefunden."
}

$gamePid = [int]$gameInfo.ProcessId

Write-Host ""
Write-Host "game.dat GEFUNDEN!" -ForegroundColor Green
Write-Host "game.dat PID: $gamePid" -ForegroundColor Green
Write-Host ""
Write-Host "AotR wird jetzt 25 Sekunden komplett in Ruhe gelassen." -ForegroundColor Yellow
Write-Host "Noch NICHT War of the Ring öffnen." -ForegroundColor Yellow
Write-Host ""

for ($i = 25; $i -gt 0; $i--) {

    if (-not (Get-Process -Id $gamePid -ErrorAction SilentlyContinue)) {
        throw "game.dat wurde während der Initialisierung beendet."
    }

    Write-Host -NoNewline "`r8P-Patch in $i Sekunden...     "
    Start-Sleep -Seconds 1
}

Write-Host ""
Write-Host ""

$game = Get-Process -Id $gamePid -ErrorAction Stop
$game.Refresh()
$base = [Int64]$game.MainModule.BaseAddress.ToInt64()
if ($base -ne [Int64]0x00400000) {
    throw ("Unexpected game.dat ImageBase 0x{0:X8}; expected 0x00400000. Nothing patched." -f $base)
}

Write-Host ("game.dat Base: 0x{0:X8}" -f $base)
Write-Host ""

$access = 0x0008 -bor 0x0010 -bor 0x0020 -bor 0x0400

$h = [AotR8PChildPatch]::OpenProcess(
    $access,
    $false,
    $gamePid
)

if ($h -eq [IntPtr]::Zero) {
    throw "OpenProcess fehlgeschlagen."
}

function Assert-CompatBytes {
    param(
        [Int64]$Address,
        [byte[]]$Expected,
        [string]$Name
    )

    $actual = New-Object byte[] $Expected.Length
    $read = [IntPtr]::Zero
    if (-not [AotR8PChildPatch]::ReadProcessMemory(
        $h,
        [IntPtr]$Address,
        $actual,
        $Expected.Length,
        [ref]$read
    )) {
        throw "$Name : compatibility read failed. Nothing patched."
    }
    if ($read.ToInt64() -ne $Expected.Length) {
        throw "$Name : compatibility read was incomplete. Nothing patched."
    }
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($actual[$i] -ne $Expected[$i]) {
            $actualText = ($actual | ForEach-Object { "{0:X2}" -f $_ }) -join " "
            $expectedText = ($Expected | ForEach-Object { "{0:X2}" -f $_ }) -join " "
            throw "$Name changed in this AotR build. Expected [$expectedText], got [$actualText]. Nothing patched."
        }
    }
}

# Read-only compatibility gate. ALL seven critical signatures are verified before the first RAM write.
Write-Host "Pruefe AotR Runtime-Kompatibilitaet (read-only)..." -ForegroundColor Cyan
Assert-CompatBytes -Address ($base + 0x00440A91) -Expected ([byte[]]@(0x06)) -Name "8 Player Slots"
Assert-CompatBytes -Address ($base + 0x0044692B) -Expected ([byte[]]@(0x06)) -Name "Strategic Player Rows"
Assert-CompatBytes -Address ($base + 0x0004128C) -Expected ([byte[]]@(0x8B,0x45,0xFC,0xC1,0xE8,0x10,0x0F,0xBF,0xC0,0x89,0x46,0x0C)) -Name "V7 Raw Wheel Hook"
Assert-CompatBytes -Address ($base + 0x00575507) -Expected ([byte[]]@(0x55,0x8B,0xEC,0x51,0x51,0x8B,0x45,0x08)) -Name "V7 Strategic Map Handler"
Assert-CompatBytes -Address ($base + 0x0009AB21) -Expected ([byte[]]@(0xF3,0x0F,0x58,0x86,0x34,0x01,0x00,0x00,0xF3,0x0F,0x11,0x86,0x34,0x01,0x00,0x00)) -Name "V7 Zoom Update"
Assert-CompatBytes -Address 0x0097548E -Expected ([byte[]]@(0x8B,0x0D,0x58,0x49,0xDE,0x00)) -Name "LivingWorld Camera Global Reference"
Assert-CompatBytes -Address 0x009D9167 -Expected ([byte[]]@(0x8B,0x41,0x1C,0x8B,0x54,0x24,0x04,0x3B,0xD0,0x74,0x12,0x50,0x51,0x89,0x51,0x1C)) -Name "Strategic Cancel/Release Callback"
Write-Host "[OK] Alle 7 kritischen Runtime-Signaturen passen. Erst jetzt sind RAM-Writes erlaubt." -ForegroundColor Green
Write-Host ""

function Set-8PPatch {

    param(
        [Int64]$Rva,
        [byte[]]$Expected,
        [byte[]]$Replacement,
        [string]$Name
    )

    $addr = [IntPtr]($base + $Rva)
    $len  = $Expected.Length
    $size = [UIntPtr]::new([UInt64]$len)

    $before = New-Object byte[] $len
    $read   = [IntPtr]::Zero

    if (-not [AotR8PChildPatch]::ReadProcessMemory(
        $h,
        $addr,
        $before,
        $len,
        [ref]$read
    )) {
        throw "$Name : Lesen fehlgeschlagen."
    }

    $beforeText = ($before | ForEach-Object {
        "{0:X2}" -f $_
    }) -join " "

    Write-Host "$Name"
    Write-Host "  BEFORE: $beforeText"

    for ($i = 0; $i -lt $len; $i++) {
        if ($before[$i] -ne $Expected[$i]) {
            throw "$Name : Originalbytes stimmen nicht."
        }
    }

    $oldProtect = 0

    if (-not [AotR8PChildPatch]::VirtualProtectEx(
        $h,
        $addr,
        $size,
        0x40,
        [ref]$oldProtect
    )) {
        throw "$Name : VirtualProtectEx fehlgeschlagen."
    }

    try {

        $written = [IntPtr]::Zero

        if (-not [AotR8PChildPatch]::WriteProcessMemory(
            $h,
            $addr,
            $Replacement,
            $len,
            [ref]$written
        )) {
            throw "$Name : Schreiben fehlgeschlagen."
        }

        if ($written.ToInt64() -ne $len) {
            throw "$Name : Nicht alle Bytes geschrieben."
        }
    }
    finally {

        $dummy = 0

        [void][AotR8PChildPatch]::VirtualProtectEx(
            $h,
            $addr,
            $size,
            $oldProtect,
            [ref]$dummy
        )
    }

    $after = New-Object byte[] $len
    $read2 = [IntPtr]::Zero

    [void][AotR8PChildPatch]::ReadProcessMemory(
        $h,
        $addr,
        $after,
        $len,
        [ref]$read2
    )

    $afterText = ($after | ForEach-Object {
        "{0:X2}" -f $_
    }) -join " "

    Write-Host "  AFTER:  $afterText"

    for ($i = 0; $i -lt $len; $i++) {
        if ($after[$i] -ne $Replacement[$i]) {
            throw "$Name : Verifikation fehlgeschlagen."
        }
    }

    Write-Host "  [OK]" -ForegroundColor Green
    Write-Host ""
}

try {

    Write-Host "Aktiviere 8 Player War of the Ring..." -ForegroundColor Cyan
    Write-Host ""

    Set-8PPatch `
        -Rva 0x00440A91 `
        -Expected ([byte[]]@(0x06)) `
        -Replacement ([byte[]]@(0x08)) `
        -Name "1) 8 Player Slots"

    Set-8PPatch `
        -Rva 0x0044692B `
        -Expected ([byte[]]@(0x06)) `
        -Replacement ([byte[]]@(0x08)) `
        -Name "2) Strategic Player Rows"

}
finally {
    [void][AotR8PChildPatch]::CloseHandle($h)
}

Install-FinalStableV7 -GamePid $gamePid

# We only cache this exact game.dat after BOTH 8P patch sites and ALL V7 runtime signatures succeeded.
Save-CompatibleBuildCache $gameDat
Write-Host "[OK] AotR build compatibility verified and cached." -ForegroundColor Green
Write-Host ""

Write-Host "========================================" -ForegroundColor Green
Write-Host "   AotR 8P WotR + FINAL_STABLE_V7 AKTIV" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "WotR-Lobby: 8 sichtbare Player-Rows erwartet." -ForegroundColor Yellow
Write-Host "Strategische WotR-Karte: V7 Zoom/Drag aktiv." -ForegroundColor Yellow
Write-Host "Hinweis: Die kleine Lobby-Map-Preview selbst ist NICHT der V7-Zoom-Bereich." -ForegroundColor DarkGray
Write-Host "AOTR8P_ENGINE_EXIT=0" -ForegroundColor Green

Start-Sleep -Seconds 2
if ($script:TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }

}
catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host " LAUNCHER-FEHLER" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "POSITION:" -ForegroundColor Yellow
    Write-Host $_.InvocationInfo.PositionMessage
    Write-Host ""
    Write-Host "STACK:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace
    Write-Host ""
    Write-Host "AOTR8P_ENGINE_EXIT=1" -ForegroundColor Red
    if ($script:TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
    return
}


