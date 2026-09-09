$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

if (-not ("AotR8PAppIdentity" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class AotR8PAppIdentity {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string AppID);
}
"@
}
[void][AotR8PAppIdentity]::SetCurrentProcessExplicitAppUserModelID("eliaauditore.AotR8P.WotRMod")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Net.Http

$script:HttpClient = New-Object System.Net.Http.HttpClient
$script:HttpClient.Timeout = [TimeSpan]::FromSeconds(30)
$script:HttpClient.DefaultRequestHeaders.UserAgent.ParseAdd(
    "AotR-8P-WotR-Launcher/$([string]$global:AOTR8P_LAUNCHER_VERSION)"
)
$script:HttpClient.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json")

function Get-HttpText([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) { throw "HTTP URL is empty." }
    $response = $script:HttpClient.GetAsync($Url).GetAwaiter().GetResult()
    try {
        [void]$response.EnsureSuccessStatusCode()
        return $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    }
    finally { $response.Dispose() }
}

function Save-HttpFile([string]$Url,[string]$Destination) {
    if ([string]::IsNullOrWhiteSpace($Url)) { throw "HTTP URL is empty." }
    $response = $script:HttpClient.GetAsync($Url).GetAwaiter().GetResult()
    try {
        [void]$response.EnsureSuccessStatusCode()
        $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        [IO.File]::WriteAllBytes($Destination,$bytes)
    }
    finally { $response.Dispose() }
}

$packageRoot = [string]$global:AOTR8P_PACKAGE_ROOT
if ([string]::IsNullOrWhiteSpace($packageRoot)) { throw "Embedded launcher package root is missing." }
$stateRoot = Join-Path $env:LOCALAPPDATA "AotR 8P WotR Mod"
New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
$ConfigPath = Join-Path $stateRoot "launcher_config.json"
$Icon = Join-Path $packageRoot "assets\launcher.ico"
$EmbeddedEngine = [string]$global:AOTR8P_ENGINE_SCRIPT
$UiSource = Join-Path $packageRoot "payload\!!!WOTR_8P_UI_TEST.big"
$PaperSource = Join-Path $packageRoot "payload\data\ini\campaigns\scenarios\PaperScenario001.inc"
$CompatCachePath = Join-Path $stateRoot "compatibility_cache.json"

# 9.3.1 remains a known reference build, but newer AotR builds are no longer blocked by whole-file SHA.
$Known931GameSize = 11347456
$Known931GameSha256 = "66AB714EA565CC490F9C41E1350F9A30708AEF6FBC2942325F50470BCB980202"
$ExpectedUiSize = 366667
$ExpectedUiSha256 = "827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376"
$ExpectedPaperSha256 = "3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43"

$LogDir = Join-Path $env:LOCALAPPDATA "AotR 8P WotR Mod"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir "launcher_current.log"

$RepairLogFile = Join-Path $LogDir "repair.log"
$RepairManifestUrl = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/repair-manifest.json"
$ModManifestUrl = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/manifest.json"
$GitHubApiRoot = "https://api.github.com/repos/eliaauditore/AotR-8P-WotR"
$GitHubIssueUrl = "https://github.com/eliaauditore/AotR-8P-WotR/issues/new"
$GitHubRepoUrl = "https://github.com/eliaauditore/AotR-8P-WotR"
$SupportStatePath = Join-Path $stateRoot "support_state.json"
$SupportBundlePath = Join-Path $stateRoot "support_bundle_latest.json"

$script:RepairMode = $false
$script:RepairStage = "NONE"
$script:LastErrorCode = ""
$script:LastErrorTitle = ""
$script:LastErrorDetail = ""
$script:LastDiagnosticReport = ""
$script:LastFingerprint = ""
$script:LastRepairPlan = @()
$script:RepairAttempts = @()
$script:LastRetryAt = $null
$script:AutoRepairRetryInProgress = $false
$script:ReportReady = $false
$script:SupportState = $null

function Write-RepairLog([string]$Text) {
    try {
        ("{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Text) |
            Add-Content -LiteralPath $RepairLogFile -Encoding UTF8
    } catch {}
}

# Stop only legacy background runtime components installed by older 8P builds.
# These can otherwise attach to the same AotR process and race the new launcher.
function Stop-Legacy8PRuntime {
    try {
        $legacyRoot = (Join-Path $env:LOCALAPPDATA "AotR 8P WotR Runtime").ToLowerInvariant()
        $legacy = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $cmd = [string]$_.CommandLine
            $cmd -and $cmd.ToLowerInvariant().Contains($legacyRoot) -and (
                $cmd -match '(?i)runtime_supervisor\.ps1' -or
                $cmd -match '(?i)AOTR_8P_WOTR_RUNTIME_WATCHER.*\.ps1'
            )
        })
        foreach ($p in $legacy) {
            Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

Stop-Legacy8PRuntime

function Get-CanonicalAotRPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
        return [IO.Path]::GetFullPath($expanded).TrimEnd('\')
    } catch {
        return $null
    }
}

function Get-AotRPathClassification([string]$Root) {
    $text = [string]$Root
    $penalty = 0
    $hardReject = $false
    $autoEligible = $true
    $reasons = New-Object System.Collections.Generic.List[string]

    if ($text -match '(?i)(^|[\\/])_?(?:AotR8P|AOTR[_ -]*\d+P).*WotR.*Runtime[^\\/]*([\\/]|$)') {
        $penalty -= 1000
        $hardReject = $true
        $autoEligible = $false
        [void]$reasons.Add('8P runtime copy')
    }
    if ($text -match '(?i)(all[ _-]*in[ _-]*one|allinone)') {
        $penalty -= 1000
        $hardReject = $true
        $autoEligible = $false
        [void]$reasons.Add('All-in-One path')
    }
    if ($text -match '(?i)(^|[\\/])BFME_RESEARCH([\\/]|$)') {
        $penalty -= 80
        $autoEligible = $false
        [void]$reasons.Add('BFME_RESEARCH')
    }
    if ($text -match '(?i)(^|[\\/])[^\\/]*backup[^\\/]*([\\/]|$)') {
        $penalty -= 60
        $autoEligible = $false
        [void]$reasons.Add('backup')
    }
    if ($text -match '(?i)(^|[\\/])[^\\/]*checkpoint[^\\/]*([\\/]|$)') {
        $penalty -= 50
        $autoEligible = $false
        [void]$reasons.Add('checkpoint')
    }
    if ($text -match '(?i)(^|[\\/])(temp|tmp)([\\/]|$)') {
        $penalty -= 40
        $autoEligible = $false
        [void]$reasons.Add('temp/tmp')
    }

    return [PSCustomObject]@{
        Penalty = $penalty
        HardReject = $hardReject
        AutoEligible = $autoEligible
        Reasons = @($reasons)
    }
}

function Test-AotRStandaloneRoot([string]$Root) {
    $rootPath = Get-CanonicalAotRPath $Root
    if (-not $rootPath) { return $null }
    if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { return $null }

    $runtime = Join-Path $rootPath 'rotwk'
    $sourceMod = Join-Path $rootPath 'aotr'
    $exe = Join-Path $runtime 'lotrbfme2ep1.exe'

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

    $hasExe = Test-Path -LiteralPath $exe -PathType Leaf
    $hasGameDat = -not [string]::IsNullOrWhiteSpace([string]$gameDat)
    $hasAotr = Test-Path -LiteralPath $sourceMod -PathType Container
    $hardValid = $hasExe -and $hasGameDat -and $hasAotr

    $score = 0
    if ($hasExe) { $score += 40 }
    if ($hasGameDat) { $score += 30 }
    if ($hasAotr) { $score += 25 }
    if (Test-Path -LiteralPath (Join-Path $rootPath 'AotR_Launcher.exe') -PathType Leaf) { $score += 10 }
    if (Test-Path -LiteralPath (Join-Path $sourceMod 'data\ini') -PathType Container) { $score += 10 }
    if (Test-Path -LiteralPath (Join-Path $sourceMod 'Changelist.txt') -PathType Leaf) { $score += 5 }

    $class = Get-AotRPathClassification $rootPath
    $score += [int]$class.Penalty

    $missing = New-Object System.Collections.Generic.List[string]
    if (-not $hasExe) { [void]$missing.Add('rotwk\lotrbfme2ep1.exe') }
    if (-not $hasGameDat) { [void]$missing.Add('rotwk\game.dat or rotwk\zGameDats\game.dat') }
    if (-not $hasAotr) { [void]$missing.Add('aotr\') }

    $gameDatCanonical = $null
    if ($gameDat) { $gameDatCanonical = Get-CanonicalAotRPath $gameDat }

    return [PSCustomObject]@{
        Root = $rootPath
        Runtime = Get-CanonicalAotRPath $runtime
        SourceMod = Get-CanonicalAotRPath $sourceMod
        GameDat = $gameDatCanonical
        Exe = Get-CanonicalAotRPath $exe
        HardValid = [bool]$hardValid
        AutoEligible = [bool]($hardValid -and -not $class.HardReject -and $class.AutoEligible)
        HardReject = [bool]$class.HardReject
        Score = [int]$score
        Missing = @($missing)
        Classification = @($class.Reasons)
        Origins = @()
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

            foreach ($p in $possible) {
                if ([string]::IsNullOrWhiteSpace($p)) { continue }
                $canon = Get-CanonicalAotRPath $p
                if (-not $canon) { continue }
                $key = $canon.ToLowerInvariant()
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    [void]$roots.Add($canon)
                }
            }

            $parent = Split-Path $walk -Parent
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ieq $walk) { break }
            $walk = $parent
        }

        foreach ($root in $roots) {
            $result = Test-AotRStandaloneRoot $root
            if ($result -and $result.HardValid) { return $result }
        }
    } catch {}

    return $null
}

function Add-AotRCandidate {
    param(
        [hashtable]$Map,
        [string]$Path,
        [string]$Origin
    )

    $found = Get-AotRInstallFromPath $Path
    if (-not $found -or -not $found.HardValid) { return }

    $key = $found.Root.ToLowerInvariant()
    if ($Map.ContainsKey($key)) {
        $existing = $Map[$key]
        if (@($existing.Origins) -notcontains $Origin) {
            $existing.Origins = @($existing.Origins) + @($Origin)
        }
        return
    }

    $found.Origins = @($Origin)
    $Map[$key] = $found
}

function Get-AotRLocalDrives {
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($drive in @([IO.DriveInfo]::GetDrives())) {
        try {
            if (-not $drive.IsReady) { continue }
            if ($drive.DriveType -ne [IO.DriveType]::Fixed -and
                $drive.DriveType -ne [IO.DriveType]::Removable) { continue }

            $isUsb = $false
            $busType = ''
            $letter = $drive.Name.TrimEnd('\').TrimEnd(':')

            if ($letter -match '^[A-Za-z]$' -and
                (Get-Command Get-Partition -ErrorAction SilentlyContinue) -and
                (Get-Command Get-Disk -ErrorAction SilentlyContinue)) {
                try {
                    $partition = Get-Partition -DriveLetter $letter -ErrorAction Stop | Select-Object -First 1
                    if ($partition) {
                        $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
                        $busType = [string]$disk.BusType
                        if ($busType -match '(?i)USB|SD|MMC') { $isUsb = $true }
                    }
                } catch {}
            }

            $isExFat = ([string]$drive.DriveFormat -ieq 'exFAT')
            $isSecondary = ($drive.DriveType -eq [IO.DriveType]::Removable) -or $isUsb -or $isExFat

            $type = 'Fixed'
            $rank = 0
            if ($isSecondary) {
                $type = 'RemovableUsbOrExFat'
                $rank = 1
            }

            [void]$rows.Add([PSCustomObject]@{
                Root = $drive.RootDirectory.FullName
                Type = $type
                Rank = $rank
                DriveType = [string]$drive.DriveType
                FileSystem = [string]$drive.DriveFormat
                BusType = $busType
            })
        } catch {}
    }

    return @($rows | Sort-Object Rank,Root)
}

function Get-AotRKnownPaths([string]$DriveRoot) {
    return @(
        (Join-Path $DriveRoot 'AgeoftheRing'),
        (Join-Path $DriveRoot 'Age of the Ring'),
        (Join-Path $DriveRoot 'AotR\AgeoftheRing'),
        (Join-Path $DriveRoot 'AotR'),
        (Join-Path $DriveRoot 'Games\AotR\AgeoftheRing'),
        (Join-Path $DriveRoot 'Games\AotR'),
        (Join-Path $DriveRoot 'Games\AgeoftheRing'),
        (Join-Path $DriveRoot 'Games\Age of the Ring'),
        (Join-Path $DriveRoot 'Spiele\AotR\AgeoftheRing'),
        (Join-Path $DriveRoot 'Spiele\AotR'),
        (Join-Path $DriveRoot 'Program Files\AgeoftheRing'),
        (Join-Path $DriveRoot 'Program Files\Age of the Ring'),
        (Join-Path $DriveRoot 'Program Files\AotR\AgeoftheRing'),
        (Join-Path $DriveRoot 'Program Files (x86)\AgeoftheRing'),
        (Join-Path $DriveRoot 'Program Files (x86)\Age of the Ring'),
        (Join-Path $DriveRoot 'Program Files (x86)\AotR\AgeoftheRing')
    )
}

function Find-AotRRootsBounded {
    param(
        [string]$DriveRoot,
        [int]$MaxDepth = 4,
        [int]$MaxDirectories = 5000
    )

    $results = New-Object System.Collections.Generic.List[string]
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue([PSCustomObject]@{ Path=$DriveRoot; Depth=0 })
    $visited = 0

    while ($queue.Count -gt 0 -and $visited -lt $MaxDirectories) {
        $node = $queue.Dequeue()
        if ([int]$node.Depth -ge $MaxDepth) { continue }

        $dirs = @()
        try {
            $dirs = @(Get-ChildItem -LiteralPath $node.Path -Directory -Force -ErrorAction SilentlyContinue)
        } catch {}

        foreach ($dir in $dirs) {
            $visited++
            if ($visited -ge $MaxDirectories) { break }

            $name = [string]$dir.Name
            $full = [string]$dir.FullName

            if ($name -in @('$Recycle.Bin','System Volume Information','Windows','Recovery','WinSxS','node_modules','.git')) { continue }
            if ($full -match '(?i)(^|[\\/])BFME_RESEARCH([\\/]|$)') { continue }
            if ($full -match '(?i)(^|[\\/])_?(?:AotR8P|AOTR[_ -]*\d+P).*WotR.*Runtime[^\\/]*([\\/]|$)') { continue }
            if ($full -match '(?i)(all[ _-]*in[ _-]*one|allinone)') { continue }
            if ($full -match '(?i)(^|[\\/])[^\\/]*(backup|checkpoint)[^\\/]*([\\/]|$)') { continue }

            if ($name -ieq 'AgeoftheRing' -or $name -ieq 'Age of the Ring') {
                [void]$results.Add($full)
                continue
            }

            $queue.Enqueue([PSCustomObject]@{
                Path = $full
                Depth = ([int]$node.Depth + 1)
            })
        }
    }

    return @($results)
}

function Get-AotRConfigValue($Config,[string]$Name) {
    try {
        $prop = $Config.PSObject.Properties[$Name]
        if ($prop) { return [string]$prop.Value }
    } catch {}
    return ''
}

function Save-AotRInstall($Install) {
    if (-not $Install -or -not $Install.HardValid -or $Install.HardReject) { return $false }

    try {
        New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
        $config = [ordered]@{
            schema = 2
            aotr_root = $Install.Root
            runtime = $Install.Runtime
            source_mod = $Install.SourceMod
            game_dat = $Install.GameDat
            validation = 'aotr-standalone-v2'
            score = [int]$Install.Score
            last_verified_utc = [DateTime]::UtcNow.ToString('o')
        }
        ($config | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $ConfigPath -Encoding UTF8

        $verify = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        if ([int]$verify.schema -ne 2) { return $false }
        if ([string]$verify.validation -ne 'aotr-standalone-v2') { return $false }
        if ([string]$verify.aotr_root -ne [string]$Install.Root) { return $false }
        return $true
    } catch {
        return $false
    }
}

function Use-AotRInstall($Install) {
    if (-not $Install -or -not $Install.HardValid -or $Install.HardReject) { return $null }
    if (Save-AotRInstall $Install) { return $Install }

    $script:LastErrorCode = 'A8P-INSTALL-004'
    $script:LastErrorDetail = 'AotR was found but launcher_config.json could not be written and verified.'
    return $null
}

function Select-AotRInstallCandidate([object[]]$Candidates) {
    if (-not $Candidates -or $Candidates.Count -eq 0) { return $null }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Multiple Age of the Ring installations found'
    $form.Width = 760
    $form.Height = 360
    $form.StartPosition = 'CenterScreen'

    $label = New-Object System.Windows.Forms.Label
    $label.Left = 12
    $label.Top = 12
    $label.Width = 720
    $label.Height = 36
    $label.Text = 'Choose the standalone AotR installation to use. The choice will be validated and saved.'
    $form.Controls.Add($label)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Left = 12
    $list.Top = 52
    $list.Width = 720
    $list.Height = 220
    $form.Controls.Add($list)

    foreach ($candidate in $Candidates) {
        $origins = (@($candidate.Origins) -join ', ')
        [void]$list.Items.Add(('[{0}] {1}    ({2})' -f $candidate.Score,$candidate.Root,$origins))
    }
    $list.SelectedIndex = 0

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Use selected installation'
    $ok.Left = 520
    $ok.Top = 285
    $ok.Width = 210
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $ok
    $form.Controls.Add($ok)

    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $list.SelectedIndex -ge 0) {
        return $Candidates[$list.SelectedIndex]
    }
    return $null
}

function Resolve-AotRInstall([switch]$PromptIfMissing) {
    # 1) Config V2 is a cache, never a blind trust anchor.
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        try {
            $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
            $schemaText = Get-AotRConfigValue $cfg 'schema'
            $cachedRoot = Get-AotRConfigValue $cfg 'aotr_root'
            $validation = Get-AotRConfigValue $cfg 'validation'
            $schema = 0
            [void][int]::TryParse($schemaText,[ref]$schema)

            if ($schema -ge 2 -and $validation -eq 'aotr-standalone-v2' -and -not [string]::IsNullOrWhiteSpace($cachedRoot)) {
                $cached = Get-AotRInstallFromPath $cachedRoot
                if ($cached -and $cached.HardValid -and -not $cached.HardReject) {
                    return (Use-AotRInstall $cached)
                }
                $script:LastErrorCode = 'A8P-INSTALL-007'
                $script:LastErrorDetail = 'Cached AotR installation moved, disappeared, or no longer validates.'
            }
        } catch {}
    }

    # 2) Explicit environment override is a validated priority path.
    if ($env:AOTR_HOME) {
        $explicit = Get-AotRInstallFromPath $env:AOTR_HOME
        if ($explicit -and $explicit.HardValid -and -not $explicit.HardReject) {
            return (Use-AotRInstall $explicit)
        }
    }

    $candidateMap = @{}

    # Legacy config is migration input only and never bypasses ranking.
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        try {
            $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
            foreach ($name in @('install_root','aotr_root','runtime')) {
                $value = Get-AotRConfigValue $cfg $name
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    Add-AotRCandidate -Map $candidateMap -Path $value -Origin 'legacy config'
                }
            }
        } catch {}
    }

    # Launcher/package vicinity is a bounded hint only.
    $vicinity = New-Object System.Collections.Generic.List[string]
    if ($packageRoot) {
        [void]$vicinity.Add($packageRoot)
        $parent1 = Split-Path $packageRoot -Parent
        if ($parent1) {
            [void]$vicinity.Add($parent1)
            $parent2 = Split-Path $parent1 -Parent
            if ($parent2) { [void]$vicinity.Add($parent2) }
        }
    }
    foreach ($p in $vicinity) {
        Add-AotRCandidate -Map $candidateMap -Path $p -Origin 'launcher vicinity'
    }

    # Fixed/local drives are searched before Removable/USB/exFAT. Network drives are excluded.
    $drives = @(Get-AotRLocalDrives)
    foreach ($drive in $drives) {
        foreach ($candidate in @(Get-AotRKnownPaths $drive.Root)) {
            Add-AotRCandidate -Map $candidateMap -Path $candidate -Origin ('known path / ' + $drive.Type)
        }
        foreach ($candidate in @(Find-AotRRootsBounded -DriveRoot $drive.Root)) {
            Add-AotRCandidate -Map $candidateMap -Path $candidate -Origin ('bounded search / ' + $drive.Type)
        }
    }

    $eligible = @(
        $candidateMap.Values |
            Where-Object { $_.HardValid -and $_.AutoEligible } |
            Sort-Object @{Expression='Score';Descending=$true},Root
    )

    if ($eligible.Count -gt 0) {
        $topScore = [int]$eligible[0].Score
        $top = @($eligible | Where-Object { [int]$_.Score -eq $topScore })

        if ($top.Count -eq 1) {
            return (Use-AotRInstall $top[0])
        }

        $script:LastErrorCode = 'A8P-INSTALL-002'
        $script:LastErrorDetail = 'Multiple equally ranked standalone AotR installations were found.'

        if ($PromptIfMissing) {
            $selected = Select-AotRInstallCandidate $top
            if ($selected) {
                $revalidated = Get-AotRInstallFromPath $selected.Root
                if ($revalidated -and $revalidated.HardValid -and -not $revalidated.HardReject) {
                    return (Use-AotRInstall $revalidated)
                }
            }
        }
        return $null
    }

    $script:LastErrorCode = 'A8P-INSTALL-001'
    $script:LastErrorDetail = 'No automatically eligible standalone AotR installation was found.'

    if ($PromptIfMissing) {
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Select the standalone AgeoftheRing folder (or its rotwk/aotr child or direct parent).'
        $dialog.ShowNewFolderButton = $false

        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $found = Get-AotRInstallFromPath $dialog.SelectedPath
            if ($found -and $found.HardValid -and -not $found.HardReject) {
                return (Use-AotRInstall $found)
            }

            $script:LastErrorCode = 'A8P-INSTALL-003'
            $missing = 'standalone AotR structure'
            if ($found) { $missing = (@($found.Missing) -join ', ') }
            $script:LastErrorDetail = 'Selected directory is not a valid standalone AotR installation. Missing/invalid: ' + $missing

            [System.Windows.Forms.MessageBox]::Show(
                $script:LastErrorDetail,
                'AotR 8P War of the Ring',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    }

    return $null
}

$Install = Resolve-AotRInstall -PromptIfMissing
if ($Install) { $GameDat = $Install.GameDat }
else { $GameDat = Join-Path $packageRoot "__AOTR_NOT_FOUND__\game.dat" }

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

function Get-WindowsVersionSafe {
    $key = $null
    try {
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\Windows NT\CurrentVersion")
        if ($key) {
            $product = [string]$key.GetValue("ProductName","Windows")
            $display = [string]$key.GetValue("DisplayVersion","")
            if ([string]::IsNullOrWhiteSpace($display)) { $display = [string]$key.GetValue("ReleaseId","") }
            $buildText = [string]$key.GetValue("CurrentBuildNumber","")
            $ubr = $key.GetValue("UBR",$null)
            $buildNumber = 0
            [void][int]::TryParse($buildText,[ref]$buildNumber)
            if ($buildNumber -ge 22000 -and $product -match "Windows 10") {
                $product = $product -replace "Windows 10","Windows 11"
            }
            $build = $buildText
            if ($null -ne $ubr -and -not [string]::IsNullOrWhiteSpace($buildText)) {
                $build = $buildText + "." + [string]$ubr
            }
            $parts = New-Object System.Collections.Generic.List[string]
            if (-not [string]::IsNullOrWhiteSpace($product)) { [void]$parts.Add($product) }
            if (-not [string]::IsNullOrWhiteSpace($display)) { [void]$parts.Add($display) }
            if (-not [string]::IsNullOrWhiteSpace($build)) { [void]$parts.Add("build " + $build) }
            if ($parts.Count -gt 0) { return ($parts -join " | ") }
        }
    }
    catch {}
    finally {
        if ($key) { $key.Dispose() }
    }
    return [Environment]::OSVersion.VersionString
}

function Test-CachedCompatibleBuild([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if (-not (Test-Path -LiteralPath $CompatCachePath -PathType Leaf)) { return $false }
    try {
        $info = Get-Item -LiteralPath $Path
        $hash = Get-Sha256 $Path
        $cache = Get-Content -LiteralPath $CompatCachePath -Raw | ConvertFrom-Json
        return (
            [string]$cache.sha256 -eq $hash -and
            [Int64]$cache.size -eq [Int64]$info.Length -and
            [string]$cache.validation -eq "runtime-signatures-v1"
        )
    } catch { return $false }
}

function Find-OfficialAotRLauncher {
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Install) {
        foreach ($base in @(
            $Install.Root,
            (Split-Path $Install.Root -Parent),
            $Install.Runtime,
            (Split-Path $Install.Runtime -Parent)
        )) {
            if ([string]::IsNullOrWhiteSpace($base)) { continue }
            [void]$candidates.Add((Join-Path $base "AotR_Launcher.exe"))
        }
    }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

# V12: clean row backgrounds are derived from the untouched ORIGINAL launcher skin.
# They are embedded in-memory only; no runtime image files are created.


[xml]$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AotR 8P WotR Mod"
        Width="900" Height="675"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        ResizeMode="NoResize"
        AllowsTransparency="True"
        Background="Transparent"
        ShowInTaskbar="True">
    <Canvas Width="900" Height="675" ClipToBounds="True">

        <Image x:Name="SkinImage"
               Canvas.Left="0" Canvas.Top="0"
               Width="900" Height="675"
               Stretch="None" SnapsToDevicePixels="True"
               IsHitTestVisible="False"/>

        <!-- Invisible hit areas only. Borders do not have any hover visuals. -->
        <Border x:Name="DragRegion"
                Canvas.Left="0" Canvas.Top="0"
                Width="720" Height="41"
                Background="Transparent"/>

        <Border x:Name="MinHit"
                Canvas.Left="777" Canvas.Top="0"
                Width="48" Height="41"
                Background="Transparent"
                Cursor="Hand"/>

        <Border x:Name="CloseHit"
                Canvas.Left="825" Canvas.Top="0"
                Width="75" Height="41"
                Background="Transparent"
                Cursor="Hand"/>

        <Border x:Name="UpdateTextHost"
                Canvas.Left="585" Canvas.Top="0"
                Width="135" Height="41"
                Background="Transparent"
                IsHitTestVisible="False">
            <TextBlock Text="AOTR UPDATER"
                       HorizontalAlignment="Center"
                       VerticalAlignment="Center"
                       Foreground="#9AA5AA"
                       FontFamily="Georgia"
                       FontSize="12.5"
                       FontWeight="Bold"/>
        </Border>
        <Border x:Name="UpdateHit"
                Canvas.Left="585" Canvas.Top="0"
                Width="135" Height="41"
                Background="Transparent"
                Cursor="Hand"/>

        <!-- Dynamic launch text centered in the ACTUAL visual button bounds: Y=503, H=80. -->
        <Border x:Name="LaunchTextHost"
                Canvas.Left="191" Canvas.Top="503"
                Width="498" Height="80"
                Background="Transparent"
                IsHitTestVisible="False">
            <TextBlock x:Name="LaunchText"
                       Text="LAUNCH AOTR 8P WOTR"
                       HorizontalAlignment="Center"
                       VerticalAlignment="Center"
                       TextAlignment="Center"
                       Foreground="#D5D6D7"
                       FontFamily="Georgia"
                       FontSize="22"
                       FontWeight="Bold"
                       IsHitTestVisible="False">
                <TextBlock.Effect>
                    <DropShadowEffect Color="#000000" BlurRadius="2" ShadowDepth="1" Opacity="0.65"/>
                </TextBlock.Effect>
            </TextBlock>
        </Border>

        <Border x:Name="LaunchHit"
                Canvas.Left="191" Canvas.Top="488"
                Width="498" Height="80"
                Background="Transparent"
                Cursor="Hand"/>

        <!-- Dynamic health/status panel. Do not depend on text baked into the skin. -->
        <Border x:Name="StatusRowsHost"
                Canvas.Left="286" Canvas.Top="260"
                Width="360" Height="166"
                Background="Transparent"
                IsHitTestVisible="False">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="44"/>
                    <RowDefinition Height="44"/>
                    <RowDefinition Height="44"/>
                    <RowDefinition Height="34"/>
                </Grid.RowDefinitions>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="230"/>
                    <ColumnDefinition Width="130"/>
                </Grid.ColumnDefinitions>

                <TextBlock Grid.Row="0" Grid.Column="0"
                           Text="AOTR INSTALLATION"
                           VerticalAlignment="Center"
                           Foreground="#A8A092"
                           FontFamily="Georgia" FontSize="12.5" FontWeight="Bold"/>
                <TextBlock x:Name="StatusGameText" Grid.Row="0" Grid.Column="1"
                           Text="CHECKING..."
                           HorizontalAlignment="Right" VerticalAlignment="Center"
                           Foreground="#D7A45F"
                           FontFamily="Georgia" FontSize="12.5" FontWeight="Bold"/>

                <Border Grid.Row="0" Grid.ColumnSpan="2"
                        BorderBrush="#2B756B58" BorderThickness="0,0,0,1"/>

                <TextBlock Grid.Row="1" Grid.Column="0"
                           Text="8P WOTR CAMPAIGN"
                           VerticalAlignment="Center"
                           Foreground="#A8A092"
                           FontFamily="Georgia" FontSize="12.5" FontWeight="Bold"/>
                <TextBlock x:Name="StatusCampaignText" Grid.Row="1" Grid.Column="1"
                           Text="CHECKING..."
                           HorizontalAlignment="Right" VerticalAlignment="Center"
                           Foreground="#D7A45F"
                           FontFamily="Georgia" FontSize="12.5" FontWeight="Bold"/>

                <Border Grid.Row="1" Grid.ColumnSpan="2"
                        BorderBrush="#2B756B58" BorderThickness="0,0,0,1"/>

                <TextBlock Grid.Row="2" Grid.Column="0"
                           Text="8-PLAYER WOTR UI"
                           VerticalAlignment="Center"
                           Foreground="#A8A092"
                           FontFamily="Georgia" FontSize="12.5" FontWeight="Bold"/>
                <TextBlock x:Name="StatusUiText" Grid.Row="2" Grid.Column="1"
                           Text="CHECKING..."
                           HorizontalAlignment="Right" VerticalAlignment="Center"
                           Foreground="#D7A45F"
                           FontFamily="Georgia" FontSize="12.5" FontWeight="Bold"/>

                <Border Grid.Row="2" Grid.ColumnSpan="2"
                        BorderBrush="#3A756B58" BorderThickness="0,0,0,1"/>

                <TextBlock x:Name="OverallStatusText"
                           Grid.Row="3" Grid.ColumnSpan="2"
                           Text="CHECKING SYSTEM..."
                           HorizontalAlignment="Center" VerticalAlignment="Center"
                           TextAlignment="Center"
                           Foreground="#D7A45F"
                           FontFamily="Georgia" FontSize="12.5" FontWeight="Bold"/>
            </Grid>
        </Border>

        <!-- Failure overlays are ICON-ONLY. The original baked row text is never redrawn. -->
        <Border x:Name="Row1Fail"
                Canvas.Left="233" Canvas.Top="264"
                Width="55" Height="44"
                Background="Transparent" BorderThickness="0"
                ClipToBounds="True" Visibility="Collapsed">
            <Grid>
                <Image x:Name="Row1CleanPatch" Width="405" Height="44"
                       HorizontalAlignment="Left" Stretch="Fill"/>
                <Canvas Width="55" Height="44">
                    <Line X1="16" Y1="13" X2="34" Y2="31" Stroke="#D96358" StrokeThickness="2.6"/>
                    <Line X1="34" Y1="13" X2="16" Y2="31" Stroke="#D96358" StrokeThickness="2.6"/>
                </Canvas>
                <TextBlock x:Name="Row1FailText" Visibility="Collapsed"/>
            </Grid>
        </Border>

        <Border x:Name="Row2Fail"
                Canvas.Left="233" Canvas.Top="314"
                Width="55" Height="44"
                Background="Transparent" BorderThickness="0"
                ClipToBounds="True" Visibility="Collapsed">
            <Grid>
                <Image x:Name="Row2CleanPatch" Width="405" Height="44"
                       HorizontalAlignment="Left" Stretch="Fill"/>
                <Canvas Width="55" Height="44">
                    <Line X1="16" Y1="13" X2="34" Y2="31" Stroke="#D96358" StrokeThickness="2.6"/>
                    <Line X1="34" Y1="13" X2="16" Y2="31" Stroke="#D96358" StrokeThickness="2.6"/>
                </Canvas>
                <TextBlock x:Name="Row2FailText" Visibility="Collapsed"/>
            </Grid>
        </Border>

        <Border x:Name="Row3Fail"
                Canvas.Left="233" Canvas.Top="361"
                Width="55" Height="47"
                Background="Transparent" BorderThickness="0"
                ClipToBounds="True" Visibility="Collapsed">
            <Grid>
                <Image x:Name="Row3CleanPatch" Width="405" Height="47"
                       HorizontalAlignment="Left" Stretch="Fill"/>
                <Canvas Width="55" Height="47">
                    <Line X1="16" Y1="14" X2="34" Y2="32" Stroke="#D96358" StrokeThickness="2.6"/>
                    <Line X1="34" Y1="14" X2="16" Y2="32" Stroke="#D96358" StrokeThickness="2.6"/>
                </Canvas>
                <TextBlock x:Name="Row3FailText" Visibility="Collapsed"/>
            </Grid>
        </Border>

        <!-- Covers ONLY the baked green Ready to launch text while repair mode is active. -->
        <Image x:Name="ReadyCleanPatch"
               Canvas.Left="330" Canvas.Top="450"
               Width="260" Height="45"
               Stretch="Fill" IsHitTestVisible="False"
               Visibility="Collapsed"/>

        <!-- Manual mod/update-channel check. GitHub is the source; this is the user-triggered control. -->
        <Border x:Name="ModUpdateTextHost"
                Canvas.Left="20" Canvas.Top="637"
                Width="185" Height="24"
                Background="Transparent"
                IsHitTestVisible="False">
            <TextBlock x:Name="ModUpdateText"
                       Text="CHECK MOD UPDATE"
                       HorizontalAlignment="Left"
                       VerticalAlignment="Center"
                       Foreground="#8E999E"
                       FontFamily="Georgia"
                       FontSize="11.5"
                       FontWeight="Bold"/>
        </Border>
        <Border x:Name="ModUpdateHit"
                Canvas.Left="16" Canvas.Top="633"
                Width="195" Height="32"
                Background="Transparent"
                Cursor="Hand"/>

        <!-- Public GitHub support inbox. The red dot is local-only unread state. -->
        <Border x:Name="MessagesTextHost"
                Canvas.Left="338" Canvas.Top="637"
                Width="224" Height="24"
                Background="Transparent"
                IsHitTestVisible="False">
            <Grid>
                <TextBlock x:Name="MessagesText"
                           Text="MESSAGES"
                           HorizontalAlignment="Center"
                           VerticalAlignment="Center"
                           Foreground="#8E999E"
                           FontFamily="Georgia"
                           FontSize="11.5"
                           FontWeight="Bold"/>
                <Ellipse x:Name="MessagesDot"
                         Width="7" Height="7"
                         Fill="#D96358"
                         HorizontalAlignment="Right"
                         VerticalAlignment="Center"
                         Margin="0,0,54,0"
                         Visibility="Collapsed"/>
            </Grid>
        </Border>
        <Border x:Name="MessagesHit"
                Canvas.Left="338" Canvas.Top="633"
                Width="224" Height="32"
                Background="Transparent"
                Cursor="Hand"/>

        <!-- Always read from the running EXE; never hard-code the displayed version. -->
        <Border Canvas.Left="710" Canvas.Top="637"
                Width="170" Height="24"
                Background="Transparent"
                IsHitTestVisible="False">
            <TextBlock x:Name="VersionText"
                       Text="Launcher v0.0.0"
                       HorizontalAlignment="Right"
                       VerticalAlignment="Center"
                       TextAlignment="Right"
                       Foreground="#78858B"
                       FontFamily="Georgia"
                       FontSize="11"/>
        </Border>

        <!-- Error-only message. Normal startup never uses this. -->
        <Border x:Name="ErrorStatus"
                Canvas.Left="300" Canvas.Top="445"
                Width="300" Height="35"
                Background="#F5121A21"
                Visibility="Collapsed">
            <TextBlock x:Name="ErrorStatusText"
                       HorizontalAlignment="Center"
                       VerticalAlignment="Center"
                       Foreground="#D96358"
                       FontFamily="Georgia"
                       FontSize="15"/>
        </Border>
    </Canvas>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $Xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)

if (Test-Path -LiteralPath $Icon -PathType Leaf) {
    try { $Window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri($Icon, [UriKind]::Absolute))) } catch {}
}

$SkinImage = $Window.FindName("SkinImage")
$DragRegion = $Window.FindName("DragRegion")
$MinHit = $Window.FindName("MinHit")
$CloseHit = $Window.FindName("CloseHit")
$UpdateHit = $Window.FindName("UpdateHit")
$ModUpdateHit = $Window.FindName("ModUpdateHit")
$ModUpdateText = $Window.FindName("ModUpdateText")
$MessagesHit = $Window.FindName("MessagesHit")
$MessagesText = $Window.FindName("MessagesText")
$MessagesDot = $Window.FindName("MessagesDot")
$VersionText = $Window.FindName("VersionText")
$LaunchHit = $Window.FindName("LaunchHit")
$LaunchText = $Window.FindName("LaunchText")
$StatusGameText = $Window.FindName("StatusGameText")
$StatusCampaignText = $Window.FindName("StatusCampaignText")
$StatusUiText = $Window.FindName("StatusUiText")
$OverallStatusText = $Window.FindName("OverallStatusText")

$displayLauncherVersion = [string]$global:AOTR8P_LAUNCHER_VERSION
if ([string]::IsNullOrWhiteSpace($displayLauncherVersion)) { $displayLauncherVersion = "unknown" }
$VersionText.Text = "Launcher v$displayLauncherVersion"

$Row1Fail = $Window.FindName("Row1Fail")
$Row2Fail = $Window.FindName("Row2Fail")
$Row3Fail = $Window.FindName("Row3Fail")
$Row1FailText = $Window.FindName("Row1FailText")
$Row2FailText = $Window.FindName("Row2FailText")
$Row3FailText = $Window.FindName("Row3FailText")
$Row1CleanPatch = $Window.FindName("Row1CleanPatch")
$Row2CleanPatch = $Window.FindName("Row2CleanPatch")
$Row3CleanPatch = $Window.FindName("Row3CleanPatch")
$ReadyCleanPatch = $Window.FindName("ReadyCleanPatch")
$ErrorStatus = $Window.FindName("ErrorStatus")
$ErrorStatusText = $Window.FindName("ErrorStatusText")
# V14: original baked row text is never redrawn. Failure changes only the status icon; Ready text is cleanly masked during repair.
$ErrorStatus.Visibility = [Windows.Visibility]::Collapsed
$script:ErrorPanelWanted = $false

[xml]$ErrorPanelXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AotR 8P WotR Diagnostics"
        Width="460" Height="458"
        WindowStyle="None"
        ResizeMode="NoResize"
        AllowsTransparency="True"
        Background="Transparent"
        ShowInTaskbar="False"
        ShowActivated="False">
    <Border CornerRadius="3"
            BorderThickness="1"
            BorderBrush="#756B58"
            Background="#F512181D">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="44"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="68"/>
            </Grid.RowDefinitions>

            <Border Grid.Row="0" Background="#F3171E24" BorderBrush="#4E4940" BorderThickness="0,0,0,1">
                <Grid Margin="16,0,12,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="38"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text="◆" Foreground="#B8945D" FontSize="10" Margin="0,0,9,0"/>
                        <TextBlock Text="AOTR 8P — LAUNCH DIAGNOSTICS"
                                   Foreground="#AEB5B8"
                                   FontFamily="Georgia"
                                   FontSize="12"
                                   FontWeight="Bold"/>
                    </StackPanel>
                    <Border x:Name="DiagCloseHit" Grid.Column="1" Background="Transparent" Cursor="Hand">
                        <TextBlock Text="×" HorizontalAlignment="Center" VerticalAlignment="Center"
                                   Foreground="#899297" FontFamily="Segoe UI" FontSize="21"/>
                    </Border>
                </Grid>
            </Border>

            <Grid Grid.Row="1" Margin="22,19,22,14">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="1"/>
                    <RowDefinition Height="14"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="16"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <Border Grid.Row="0" HorizontalAlignment="Left" Padding="8,4"
                        Background="#332B1C1C" BorderBrush="#74423D" BorderThickness="1" CornerRadius="2">
                    <TextBlock x:Name="DiagCodeText" Text="A8P-ENGINE-001"
                               Foreground="#DF7468" FontFamily="Consolas" FontSize="12" FontWeight="Bold"/>
                </Border>

                <TextBlock x:Name="DiagTitleText" Grid.Row="1" Margin="0,10,0,0"
                           Text="Launcher runtime failed"
                           Foreground="#D6D3CC" FontFamily="Georgia" FontSize="19" FontWeight="Bold"
                           TextWrapping="Wrap"/>

                <TextBlock x:Name="DiagFingerprintText" Grid.Row="2" Margin="0,7,0,7"
                           Text="A8P-FP-PENDING"
                           Foreground="#7E898E" FontFamily="Consolas" FontSize="10.5"
                           TextWrapping="Wrap"/>

                <Border Grid.Row="3" Background="#514B40"/>

                <TextBlock Grid.Row="5" Text="DETAILS"
                           Foreground="#887F70" FontFamily="Georgia" FontSize="10.5" FontWeight="Bold"/>

                <ScrollViewer Grid.Row="6" Margin="0,7,0,0" VerticalScrollBarVisibility="Auto"
                              HorizontalScrollBarVisibility="Disabled">
                    <TextBlock x:Name="DiagDetailText"
                               Text="Full diagnostic detail appears here."
                               Foreground="#AAB1B4" FontFamily="Segoe UI" FontSize="12.5"
                               TextWrapping="Wrap" LineHeight="19"/>
                </ScrollViewer>

                <TextBlock Grid.Row="8" Text="REPAIR STATUS"
                           Foreground="#887F70" FontFamily="Georgia" FontSize="10.5" FontWeight="Bold"/>
                <TextBlock x:Name="DiagRepairText" Grid.Row="9" Margin="0,5,0,0"
                           Text="AUTO REPAIR READY"
                           Foreground="#D3A55F" FontFamily="Georgia" FontSize="13.5" FontWeight="Bold"
                           TextWrapping="Wrap"/>
            </Grid>

            <Border Grid.Row="2" Background="#E9141A1F" BorderBrush="#3E3A33" BorderThickness="0,1,0,0">
                <Grid Margin="16,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="8"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock x:Name="DiagFooterText" Text="Use AUTO REPAIR in the main launcher"
                                   Foreground="#7E898E" FontFamily="Georgia" FontSize="10.5"/>
                        <TextBlock x:Name="DiagVersionText" Text="Launcher v0.0.0" Margin="0,3,0,0"
                                   Foreground="#69767C" FontFamily="Georgia" FontSize="9.5"/>
                    </StackPanel>
                    <Border x:Name="DiagRetryHit" Grid.Column="1" Padding="11,7"
                            VerticalAlignment="Center" Background="#221E1B18"
                            BorderBrush="#756B58" BorderThickness="1" CornerRadius="2"
                            Cursor="Hand" Visibility="Collapsed">
                        <TextBlock Text="RETRY" Foreground="#B5B9B8" FontFamily="Georgia" FontSize="10.5" FontWeight="Bold"/>
                    </Border>
                    <Border x:Name="DiagReportHit" Grid.Column="3" Padding="11,7"
                            VerticalAlignment="Center" Background="#332B1C1C"
                            BorderBrush="#8B4D45" BorderThickness="1" CornerRadius="2"
                            Cursor="Hand" Visibility="Collapsed">
                        <TextBlock Text="REPORT ERROR" Foreground="#DF7468" FontFamily="Georgia" FontSize="10.5" FontWeight="Bold"/>
                    </Border>
                </Grid>
            </Border>
        </Grid>
    </Border>
</Window>
'@

$diagReader = New-Object System.Xml.XmlNodeReader $ErrorPanelXaml
$ErrorWindow = [Windows.Markup.XamlReader]::Load($diagReader)
$DiagCloseHit = $ErrorWindow.FindName("DiagCloseHit")
$DiagCodeText = $ErrorWindow.FindName("DiagCodeText")
$DiagTitleText = $ErrorWindow.FindName("DiagTitleText")
$DiagFingerprintText = $ErrorWindow.FindName("DiagFingerprintText")
$DiagDetailText = $ErrorWindow.FindName("DiagDetailText")
$DiagRepairText = $ErrorWindow.FindName("DiagRepairText")
$DiagFooterText = $ErrorWindow.FindName("DiagFooterText")
$DiagRetryHit = $ErrorWindow.FindName("DiagRetryHit")
$DiagReportHit = $ErrorWindow.FindName("DiagReportHit")
$DiagVersionText = $ErrorWindow.FindName("DiagVersionText")
$DiagVersionText.Text = "Launcher v$displayLauncherVersion"

if (Test-Path -LiteralPath $Icon -PathType Leaf) {
    try { $ErrorWindow.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri($Icon, [UriKind]::Absolute))) } catch {}
}

[xml]$MessagesPanelXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AotR 8P WotR Messages"
        Width="520" Height="430"
        WindowStyle="None"
        ResizeMode="NoResize"
        AllowsTransparency="True"
        Background="Transparent"
        ShowInTaskbar="False">
    <Border CornerRadius="3" BorderThickness="1" BorderBrush="#756B58" Background="#F512181D">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="44"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="60"/>
            </Grid.RowDefinitions>
            <Border Grid.Row="0" Background="#F3171E24" BorderBrush="#4E4940" BorderThickness="0,0,0,1">
                <Grid Margin="16,0,12,0">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="38"/></Grid.ColumnDefinitions>
                    <TextBlock Text="AOTR 8P — MESSAGES" VerticalAlignment="Center"
                               Foreground="#AEB5B8" FontFamily="Georgia" FontSize="12" FontWeight="Bold"/>
                    <Border x:Name="MsgCloseHit" Grid.Column="1" Background="Transparent" Cursor="Hand">
                        <TextBlock Text="×" HorizontalAlignment="Center" VerticalAlignment="Center"
                                   Foreground="#899297" FontFamily="Segoe UI" FontSize="21"/>
                    </Border>
                </Grid>
            </Border>
            <Grid Grid.Row="1" Margin="20,18,20,14">
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="10"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                <TextBlock x:Name="MsgHeaderText" Text="No tracked support report yet."
                           Foreground="#D6D3CC" FontFamily="Georgia" FontSize="14" FontWeight="Bold" TextWrapping="Wrap"/>
                <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <TextBlock x:Name="MsgBodyText" Text="After a reportable launcher failure, maintainer updates for its master ticket will appear here."
                               Foreground="#AAB1B4" FontFamily="Segoe UI" FontSize="12.5" TextWrapping="Wrap" LineHeight="19"/>
                </ScrollViewer>
            </Grid>
            <Border Grid.Row="2" Background="#E9141A1F" BorderBrush="#3E3A33" BorderThickness="0,1,0,0">
                <Grid Margin="16,0">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="8"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                    <TextBlock x:Name="MsgStatusText" Text="Public GitHub updates — no read receipt is sent"
                               VerticalAlignment="Center" Foreground="#69767C" FontFamily="Georgia" FontSize="9.5"/>
                    <Border x:Name="MsgRefreshHit" Grid.Column="1" Padding="11,7" VerticalAlignment="Center"
                            Background="#221E1B18" BorderBrush="#756B58" BorderThickness="1" CornerRadius="2" Cursor="Hand">
                        <TextBlock Text="REFRESH" Foreground="#B5B9B8" FontFamily="Georgia" FontSize="10.5" FontWeight="Bold"/>
                    </Border>
                    <Border x:Name="MsgOpenMasterHit" Grid.Column="3" Padding="11,7" VerticalAlignment="Center"
                            Background="#221E1B18" BorderBrush="#756B58" BorderThickness="1" CornerRadius="2" Cursor="Hand" Visibility="Collapsed">
                        <TextBlock Text="OPEN MASTER" Foreground="#B5B9B8" FontFamily="Georgia" FontSize="10.5" FontWeight="Bold"/>
                    </Border>
                </Grid>
            </Border>
        </Grid>
    </Border>
</Window>
'@
$msgReader = New-Object System.Xml.XmlNodeReader $MessagesPanelXaml
$MessagesWindow = [Windows.Markup.XamlReader]::Load($msgReader)
$MsgCloseHit = $MessagesWindow.FindName("MsgCloseHit")
$MsgHeaderText = $MessagesWindow.FindName("MsgHeaderText")
$MsgBodyText = $MessagesWindow.FindName("MsgBodyText")
$MsgStatusText = $MessagesWindow.FindName("MsgStatusText")
$MsgRefreshHit = $MessagesWindow.FindName("MsgRefreshHit")
$MsgOpenMasterHit = $MessagesWindow.FindName("MsgOpenMasterHit")
if (Test-Path -LiteralPath $Icon -PathType Leaf) {
    try { $MessagesWindow.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri($Icon, [UriKind]::Absolute))) } catch {}
}

$DiagCloseHit.Add_MouseLeftButtonUp({
    $script:ErrorPanelWanted = $false
    $ErrorWindow.Hide()
})

function Position-ErrorWindow {
    try {
        $gap = 12.0
        $work = [Windows.SystemParameters]::WorkArea
        $rightCandidate = $Window.Left + $Window.ActualWidth + $gap
        $leftCandidate = $Window.Left - $ErrorWindow.Width - $gap

        if (($rightCandidate + $ErrorWindow.Width) -le $work.Right) {
            $ErrorWindow.Left = $rightCandidate
        }
        elseif ($leftCandidate -ge $work.Left) {
            $ErrorWindow.Left = $leftCandidate
        }
        else {
            $ErrorWindow.Left = [Math]::Max($work.Left + 8, $work.Right - $ErrorWindow.Width - 8)
        }

        $preferredTop = $Window.Top + 118
        $ErrorWindow.Top = [Math]::Min(
            [Math]::Max($work.Top + 8, $preferredTop),
            $work.Bottom - $ErrorWindow.Height - 8
        )
    } catch {}
}

$Window.Add_LocationChanged({ if ($script:ErrorPanelWanted -and $ErrorWindow.IsVisible) { Position-ErrorWindow } })
$Window.Add_StateChanged({
    if ($Window.WindowState -eq [Windows.WindowState]::Minimized) {
        if ($ErrorWindow.IsVisible) { $ErrorWindow.Hide() }
    }
    elseif ($script:ErrorPanelWanted) {
        Position-ErrorWindow
        if (-not $ErrorWindow.IsVisible) { $ErrorWindow.Show() }
    }
})

function Set-EmbeddedPngSource($ImageControl, [byte[]]$Bytes) {
    if ($null -eq $ImageControl -or $null -eq $Bytes -or $Bytes.Length -eq 0) { return }
    $ms = New-Object IO.MemoryStream(,$Bytes)
    try {
        $bi = New-Object Windows.Media.Imaging.BitmapImage
        $bi.BeginInit()
        $bi.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bi.StreamSource = $ms
        $bi.EndInit()
        $bi.Freeze()
        $ImageControl.Source = $bi
    }
    finally { $ms.Dispose() }
}

Set-EmbeddedPngSource $SkinImage ([byte[]]$global:AOTR8P_SKIN_BYTES)
Set-EmbeddedPngSource $Row1CleanPatch ([byte[]]$global:AOTR8P_ROW1_PATCH)
Set-EmbeddedPngSource $Row2CleanPatch ([byte[]]$global:AOTR8P_ROW2_PATCH)
Set-EmbeddedPngSource $Row3CleanPatch ([byte[]]$global:AOTR8P_ROW3_PATCH)
Set-EmbeddedPngSource $ReadyCleanPatch ([byte[]]$global:AOTR8P_READY_PATCH)

$NormalText = (New-Object Windows.Media.BrushConverter).ConvertFromString("#D5D6D7")
$RunningText = (New-Object Windows.Media.BrushConverter).ConvertFromString("#86B866")

$RepairText = (New-Object Windows.Media.BrushConverter).ConvertFromString("#D7A45F")
$DangerText = (New-Object Windows.Media.BrushConverter).ConvertFromString("#D96358")

$StatusMutedText = (New-Object Windows.Media.BrushConverter).ConvertFromString("#A8A092")

function Set-StatusCheck($Control, [bool]$Ok, [string]$OkText = "OK", [string]$FailText = "CHECK FAILED") {
    if ($null -eq $Control) { return }
    if ($Ok) {
        $Control.Text = $OkText
        $Control.Foreground = $RunningText
    } else {
        $Control.Text = $FailText
        $Control.Foreground = $DangerText
    }
}

function Set-StatusChecking {
    foreach ($control in @($StatusGameText,$StatusCampaignText,$StatusUiText)) {
        if ($null -ne $control) {
            $control.Text = "CHECKING..."
            $control.Foreground = $RepairText
        }
    }
    if ($null -ne $OverallStatusText) {
        $OverallStatusText.Text = "CHECKING SYSTEM..."
        $OverallStatusText.Foreground = $RepairText
    }
}

function Set-OverallStatus([string]$Text, $Brush = $NormalText) {
    if ($null -eq $OverallStatusText) { return }
    $OverallStatusText.Text = $Text
    $OverallStatusText.Foreground = $Brush
}


function Set-LaunchState([string]$Text, $Brush = $NormalText) {
    $LaunchText.Text = $Text
    $LaunchText.Foreground = $Brush
}

function Show-Error([string]$Text, [string]$Detail = "", [bool]$Protected = $false) {
    $code = "A8P-ERROR"
    $title = [string]$Text
    if ($Text -match '^\s*([^—]+?)\s*—\s*(.+)$') {
        $code = $matches[1].Trim()
        $title = $matches[2].Trim()
    }
    elseif ($Text -match '^\s*(A8P-[A-Z0-9-]+)\b(.*)$') {
        $code = $matches[1].Trim()
        $tail = $matches[2].Trim(' ','-','—',':')
        if ($tail) { $title = $tail }
    }

    if ([string]::IsNullOrWhiteSpace($Detail)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$script:LastErrorDetail)) {
            $Detail = [string]$script:LastErrorDetail
        } else {
            $Detail = [string]$Text
        }
    }

    $DiagCodeText.Text = $code
    $DiagTitleText.Text = $title
    $DiagDetailText.Text = $Detail
    $DiagFingerprintText.Text = if ([string]::IsNullOrWhiteSpace([string]$script:LastFingerprint)) { "A8P-FP-PENDING" } else { [string]$script:LastFingerprint }

    if ($script:ReportReady) {
        $DiagRepairText.Text = if ($Protected) { "NO SAFE AUTO-REPAIR — REPORT READY" } else { "AUTO-REPAIR FAILED — REPORT READY" }
        $DiagRepairText.Foreground = $DangerText
        $DiagFooterText.Text = "Review the prefilled report before submitting to GitHub"
        $DiagRetryHit.Visibility = [Windows.Visibility]::Visible
        $DiagReportHit.Visibility = [Windows.Visibility]::Visible
    }
    elseif ($Protected) {
        $DiagRepairText.Text = "COMPATIBILITY UPDATE REQUIRED — NO UNSAFE PATCH WILL BE ATTEMPTED"
        $DiagRepairText.Foreground = $DangerText
        $DiagFooterText.Text = "Checking for a compatible launcher update first"
        $DiagRetryHit.Visibility = [Windows.Visibility]::Collapsed
        $DiagReportHit.Visibility = [Windows.Visibility]::Collapsed
    } else {
        $DiagRepairText.Text = "AUTO REPAIR READY"
        $DiagRepairText.Foreground = $RepairText
        $DiagFooterText.Text = "Use AUTO REPAIR in the main launcher"
        $DiagRetryHit.Visibility = [Windows.Visibility]::Collapsed
        $DiagReportHit.Visibility = [Windows.Visibility]::Collapsed
    }

    $script:ErrorPanelWanted = $true
    try {
        if (-not $ErrorWindow.Owner) { $ErrorWindow.Owner = $Window }
    } catch {}
    Position-ErrorWindow
    if (-not $ErrorWindow.IsVisible) { $ErrorWindow.Show() }
}

function Hide-Error {
    $script:ErrorPanelWanted = $false
    if ($ErrorWindow.IsVisible) { $ErrorWindow.Hide() }
    $ErrorStatus.Visibility = [Windows.Visibility]::Collapsed
}


function Get-LaunchFailureInfo([string]$Detail) {
    $d = [string]$Detail
    $code = "A8P-ENGINE-001"
    $title = "Launcher runtime failed"
    $protected = $false
    $actions = @("stop_legacy_runtime","stop_failed_game","reset_runtime","clear_compat_cache","retry_launch")

    if ($d -match '(?i)Age of the Ring installation not found|game\.dat not found|lotrbfme2ep1\.exe.*not found') {
        $code = "A8P-INSTALL-001"
        $title = "AotR installation could not be resolved"
        $actions = @("reset_install","retry_launch")
    }
    elseif ($d -match '(?i)8P UI payload|8-player roster UI|Runtime BIG verification|BIG verification failed') {
        $code = "A8P-PAYLOAD-UI-001"
        $title = "8-player UI payload is missing or damaged"
        $actions = @("repair_payloads","reset_runtime","retry_launch")
    }
    elseif ($d -match '(?i)PaperScenario|campaign payload') {
        $code = "A8P-PAYLOAD-PAPER-001"
        $title = "War of the Ring campaign payload is missing or damaged"
        $actions = @("repair_payloads","reset_runtime","retry_launch")
    }
    elseif ($d -match '(?i)OLD DEV LAUNCHER|BFME_RESEARCH.*launcher_11_portable') {
        $code = "A8P-LEGACY-001"
        $title = "An obsolete development launcher is still running"
        $actions = @("stop_old_dev_launchers","stop_legacy_runtime","retry_launch")
    }
    elseif ($d -match '(?i)AotR is already running|GAME ALREADY RUNNING') {
        $code = "A8P-PROCESS-001"
        $title = "A stale or running AotR process blocks launch"
        $actions = @("stop_legacy_runtime","stop_failed_game","retry_launch")
    }
    elseif ($d -match '(?i)PORTABLE RUNTIME|runtime.*verification|source folder missing while building runtime|Laufzeitschicht') {
        $code = "A8P-RUNTIME-001"
        $title = "Portable 8P runtime could not be prepared"
        $actions = @("stop_legacy_runtime","stop_failed_game","reset_runtime","repair_payloads","retry_launch")
    }
    elseif ($d -match '(?i)Child game\.dat|game\.dat.*nicht gefunden|game\.dat wurde.*beendet') {
        $code = "A8P-GAMEPROC-001"
        $title = "AotR game process did not initialize correctly"
        $actions = @("stop_legacy_runtime","stop_failed_game","reset_runtime","retry_launch")
    }
    elseif ($d -match '(?i)changed in this AotR build|Unexpected game\.dat ImageBase|Originalbytes stimmen nicht|compatibility read|signature|Nothing patched') {
        $code = "A8P-COMPAT-001"
        $title = "This AotR build changed a protected patch signature"
        $protected = $true
        $actions = @("check_launcher_update")
    }
    elseif ($d -match '(?i)OpenProcess|VirtualProtectEx|Schreiben fehlgeschlagen|Nicht alle Bytes geschrieben|Verifikation fehlgeschlagen|UAC/elevation') {
        $code = "A8P-PERMISSION-001"
        $title = "Windows blocked access to the AotR process"
        $actions = @("stop_failed_game","retry_launch")
    }

    [PSCustomObject]@{
        Code = $code
        Title = $title
        Protected = $protected
        Actions = @($actions)
    }
}

function Get-RemoteRepairPlan([string]$Code) {
    try {
        $json = Get-HttpText $RepairManifestUrl
        $db = $json | ConvertFrom-Json
        if ([int]$db.schema -ne 1 -or -not $db.plans) { return $null }
        $prop = $db.plans.PSObject.Properties[$Code]
        if (-not $prop) { return $null }
        return $prop.Value
    } catch {
        Write-RepairLog ("Remote repair database unavailable: " + $_.Exception.Message)
        return $null
    }
}

function Get-SanitizedDiagnosticReport([string]$Code,[string]$Detail) {
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("AotR 8P WotR diagnostic")
    [void]$lines.Add("Time: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
    [void]$lines.Add("ErrorCode: " + $Code)
    [void]$lines.Add("Launcher: " + [string]$global:AOTR8P_LAUNCHER_VERSION)

    try {
        if (Test-Path -LiteralPath $GameDat -PathType Leaf) {
            $g = Get-Item -LiteralPath $GameDat
            [void]$lines.Add("game.dat size: " + $g.Length)
            [void]$lines.Add("game.dat SHA256: " + (Get-Sha256 $GameDat))
        } else {
            [void]$lines.Add("game.dat: missing")
        }
    } catch {}

    foreach ($item in @(
        [PSCustomObject]@{ Name="UI"; Path=$UiSource },
        [PSCustomObject]@{ Name="PaperScenario"; Path=$PaperSource }
    )) {
        try {
            if (Test-Path -LiteralPath $item.Path -PathType Leaf) {
                [void]$lines.Add($item.Name + " SHA256: " + (Get-Sha256 $item.Path))
            } else {
                [void]$lines.Add($item.Name + ": missing")
            }
        } catch {}
    }

    [void]$lines.Add("Detail: " + $Detail)
    if (Test-Path -LiteralPath $LogFile -PathType Leaf) {
        try {
            [void]$lines.Add("--- launcher log tail ---")
            foreach ($line in @(Get-Content -LiteralPath $LogFile -Tail 35 -ErrorAction SilentlyContinue)) {
                [void]$lines.Add([string]$line)
            }
        } catch {}
    }

    $text = ($lines -join [Environment]::NewLine)
    $aotrRootForRedaction = ""
    $aotrRuntimeForRedaction = ""
    if ($Install) {
        try { $aotrRootForRedaction = [string]$Install.Root } catch {}
        try { $aotrRuntimeForRedaction = [string]$Install.Runtime } catch {}
    }
    if ($env:USERPROFILE) { $text = $text.Replace([string]$env:USERPROFILE,"%USERPROFILE%") }
    if ($packageRoot) { $text = $text.Replace([string]$packageRoot,"%MODROOT%") }
    if ($aotrRootForRedaction) { $text = $text.Replace($aotrRootForRedaction,"%AOTRROOT%") }
    if ($aotrRuntimeForRedaction) { $text = $text.Replace($aotrRuntimeForRedaction,"%AOTRRUNTIME%") }
    return (Get-SanitizedText $text)
}

function Get-SanitizedText([string]$Text) {
    $safe = [string]$Text

    $sensitive = @(
        [PSCustomObject]@{ Value = [string]$env:USERPROFILE; Replacement = "%USERPROFILE%" }
        [PSCustomObject]@{ Value = [string]$packageRoot; Replacement = "%MODROOT%" }
        [PSCustomObject]@{ Value = [string]$env:COMPUTERNAME; Replacement = "%COMPUTERNAME%" }
        [PSCustomObject]@{ Value = [string]$env:USERNAME; Replacement = "%USERNAME%" }
    )

    if ($Install) {
        try { $sensitive += [PSCustomObject]@{ Value = [string]$Install.Root; Replacement = "%AOTRROOT%" } } catch {}
        try { $sensitive += [PSCustomObject]@{ Value = [string]$Install.Runtime; Replacement = "%AOTRRUNTIME%" } } catch {}
    }

    foreach ($item in $sensitive) {
        if (-not [string]::IsNullOrWhiteSpace([string]$item.Value)) {
            try {
                $safe = [regex]::Replace(
                    $safe,
                    [regex]::Escape([string]$item.Value),
                    [string]$item.Replacement,
                    [Text.RegularExpressions.RegexOptions]::IgnoreCase
                )
            } catch {}
        }
    }

    # Default reports must not leak network identifiers.
    $safe = [regex]::Replace($safe,'(?<!\d)(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?!\d)','%IP%')
    $safe = [regex]::Replace($safe,'(?i)(?<![0-9A-F])(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}(?![0-9A-F])','%MAC%')
    $safe = [regex]::Replace($safe,'(?i)(?<![0-9A-F:])(?:[0-9A-F]{0,4}:){2,7}[0-9A-F]{0,4}(?![0-9A-F:])','%IPV6%')

    # Prevent an error message from breaking Markdown fences if a future template adds them.
    return $safe
}

function Limit-SupportText([string]$Text,[int]$MaxLength = 3000) {
    $value = [string]$Text
    if ($MaxLength -lt 64 -or $value.Length -le $MaxLength) { return $value }
    return $value.Substring(0,$MaxLength) + "`r`n...[truncated by launcher; full local logs remain on this PC]"
}

function Get-SupportFingerprint([string]$Code,[string]$ExactError) {
    $normalized = (Get-SanitizedText $ExactError).Trim().ToLowerInvariant()
    $normalized = [regex]::Replace($normalized,'\s+',' ')
    if ([string]::IsNullOrWhiteSpace($normalized)) { return "" }
    $signature = $Code.ToUpperInvariant() + "|" + $normalized
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($signature)
        $hash = $sha.ComputeHash($bytes)
        $hex = -join ($hash | ForEach-Object { $_.ToString("x2") })
        return "A8P-FP-" + $hex.Substring(0,12).ToUpperInvariant()
    }
    finally { $sha.Dispose() }
}

function Add-RepairAttempt([string]$Action,[string]$Result,[string]$Detail = "") {
    $safeDetail = $null
    if (-not [string]::IsNullOrWhiteSpace($Detail)) { $safeDetail = Get-SanitizedText $Detail }
    $entry = [PSCustomObject]@{
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        action = $Action
        result = $Result
        detail = $safeDetail
    }
    $script:RepairAttempts = @($script:RepairAttempts) + @($entry)
}

function Get-SupportFileEntry([string]$Role,[string]$DisplayPath,[string]$Path,[string]$ExpectedSha = "") {
    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    $size = $null
    $actual = $null
    if ($exists) {
        try {
            $item = Get-Item -LiteralPath $Path
            $size = [Int64]$item.Length
            $actual = Get-Sha256 $Path
        } catch {}
    }
    [PSCustomObject]@{
        path = $DisplayPath
        role = $Role
        exists = [bool]$exists
        size = $size
        expected_sha256 = $(if ([string]::IsNullOrWhiteSpace($ExpectedSha)) { $null } else { $ExpectedSha.ToUpperInvariant() })
        actual_sha256 = $actual
    }
}

function Get-AotRVersionSafe {
    try {
        if (Test-Path -LiteralPath $GameDat -PathType Leaf) {
            $g = Get-Item -LiteralPath $GameDat
            $hash = Get-Sha256 $GameDat
            if ($g.Length -eq $Known931GameSize -and $hash -eq $Known931GameSha256) { return "9.3.1" }
        }
    } catch {}
    return "unknown"
}

function New-SupportBundle {
    $code = [string]$script:LastErrorCode
    $errorText = Limit-SupportText (Get-SanitizedText ([string]$script:LastErrorDetail)) 3000
    $fingerprint = [string]$script:LastFingerprint
    if ([string]::IsNullOrWhiteSpace($fingerprint) -and -not [string]::IsNullOrWhiteSpace($code)) {
        $fingerprint = Get-SupportFingerprint $code $errorText
        $script:LastFingerprint = $fingerprint
    }

    $files = @(
        Get-SupportFileEntry "game" "game.dat" $GameDat ""
        Get-SupportFileEntry "ui" "payload_ui.big" $UiSource $ExpectedUiSha256
        Get-SupportFileEntry "paper" "payload_paper.inc" $PaperSource $ExpectedPaperSha256
    )

    $plan = [PSCustomObject]@{
        source_error_code = $(if ([string]::IsNullOrWhiteSpace($code)) { $null } else { $code })
        actions = @($script:LastRepairPlan)
    }

    [PSCustomObject]@{
        schema = 1
        launcher_version = [string]$global:AOTR8P_LAUNCHER_VERSION
        error_code = $(if ([string]::IsNullOrWhiteSpace($code)) { $null } else { $code })
        fingerprint = $(if ([string]::IsNullOrWhiteSpace($fingerprint)) { $null } else { $fingerprint })
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        windows = Get-WindowsVersionSafe
        aotr_version = Get-AotRVersionSafe
        language = [Globalization.CultureInfo]::CurrentUICulture.Name
        files = @($files)
        repair_plan = $plan
        repair_attempts = @($script:RepairAttempts)
        last_retry = $(if ($script:LastRetryAt) { ([DateTime]$script:LastRetryAt).ToUniversalTime().ToString("o") } else { $null })
        last_error = $errorText
        log_files = @("launcher_current.log","repair.log")
        notes = "Generated locally by the launcher after Auto-Repair was exhausted. No username, machine name, IP address, MAC address, or account identity is included."
    }
}

function Save-LatestSupportBundle {
    try {
        $bundle = New-SupportBundle
        $prettyJson = $bundle | ConvertTo-Json -Depth 8
        $compactJson = $bundle | ConvertTo-Json -Depth 8 -Compress
        [IO.File]::WriteAllText($SupportBundlePath, $prettyJson + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        return $compactJson
    } catch {
        Write-RepairLog ("Support bundle generation failed: " + $_.Exception.Message)
        return ""
    }
}

function Load-SupportState {
    $state = [ordered]@{
        schema = 1
        fingerprint = ""
        master_issue = 0
        last_seen_message_id = 0
        latest_message_id = 0
        last_checked = ""
    }
    if (Test-Path -LiteralPath $SupportStatePath -PathType Leaf) {
        try {
            $old = Get-Content -LiteralPath $SupportStatePath -Raw | ConvertFrom-Json
            foreach ($name in @("fingerprint","master_issue","last_seen_message_id","latest_message_id","last_checked")) {
                $prop = $old.PSObject.Properties[$name]
                if ($prop) { $state[$name] = $prop.Value }
            }
        } catch {}
    }
    return $state
}

function Save-SupportState {
    if (-not $script:SupportState) { return }
    try {
        $json = $script:SupportState | ConvertTo-Json -Depth 4
        [IO.File]::WriteAllText($SupportStatePath, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    } catch {}
}

function Set-MessagesIndicator {
    if (-not $script:SupportState) { $script:SupportState = Load-SupportState }
    $latest = 0L
    $seen = 0L
    try { $latest = [Int64]$script:SupportState["latest_message_id"] } catch {}
    try { $seen = [Int64]$script:SupportState["last_seen_message_id"] } catch {}
    if ($latest -gt $seen) {
        $MessagesDot.Visibility = [Windows.Visibility]::Visible
        $MessagesText.Foreground = $DangerText
    } else {
        $MessagesDot.Visibility = [Windows.Visibility]::Collapsed
        $MessagesText.Foreground = (New-Object Windows.Media.BrushConverter).ConvertFromString("#8E999E")
    }
}

function Register-SupportFingerprint([string]$Fingerprint) {
    if ([string]::IsNullOrWhiteSpace($Fingerprint)) { return }
    if (-not $script:SupportState) { $script:SupportState = Load-SupportState }
    if ([string]$script:SupportState["fingerprint"] -ne $Fingerprint) {
        $script:SupportState["fingerprint"] = $Fingerprint
        $script:SupportState["master_issue"] = 0
        $script:SupportState["last_seen_message_id"] = 0
        $script:SupportState["latest_message_id"] = 0
    }
    Save-SupportState
    Set-MessagesIndicator
}

function Resolve-MasterIssue([string]$Fingerprint) {
    if ([string]::IsNullOrWhiteSpace($Fingerprint)) { return 0 }
    if (-not $script:SupportState) { $script:SupportState = Load-SupportState }
    try {
        $cached = [int]$script:SupportState["master_issue"]
        if ($cached -gt 0) { return $cached }
    } catch {}

    try {
        $query = [Uri]::EscapeDataString('repo:eliaauditore/AotR-8P-WotR label:master-ticket "' + $Fingerprint + '"')
        $result = Get-HttpText ("https://api.github.com/search/issues?q=$query&per_page=10") | ConvertFrom-Json
        $matches = @($result.items | Where-Object { ([string]$_.body) -match [regex]::Escape($Fingerprint) } | Sort-Object number)
        if ($matches.Count -gt 0) {
            $number = [int]$matches[0].number
            $script:SupportState["master_issue"] = $number
            Save-SupportState
            return $number
        }
    } catch {
        Write-RepairLog ("Master ticket lookup unavailable: " + $_.Exception.Message)
    }
    return 0
}

function Get-MaintainerMessages([int]$MasterIssue) {
    if ($MasterIssue -le 0) { return @() }
    try {
        $comments = @(Get-HttpText ("$GitHubApiRoot/issues/$MasterIssue/comments?per_page=100") | ConvertFrom-Json)
        $allowed = @("OWNER","MEMBER","COLLABORATOR")
        return @($comments | Where-Object {
            $body = [string]$_.body
            ($allowed -contains [string]$_.author_association) -and
            -not $body.Contains("<!-- no-broadcast -->") -and
            -not $body.TrimStart().StartsWith("[internal]",[StringComparison]::OrdinalIgnoreCase)
        } | Sort-Object id)
    } catch {
        Write-RepairLog ("Support messages unavailable: " + $_.Exception.Message)
        return @()
    }
}

function Refresh-SupportMessages([switch]$MarkRead) {
    if (-not $script:SupportState) { $script:SupportState = Load-SupportState }
    $fingerprint = [string]$script:SupportState["fingerprint"]
    if ([string]::IsNullOrWhiteSpace($fingerprint)) {
        Set-MessagesIndicator
        return @()
    }

    $master = Resolve-MasterIssue $fingerprint
    $script:SupportState["last_checked"] = (Get-Date).ToUniversalTime().ToString("o")
    if ($master -le 0) {
        Save-SupportState
        Set-MessagesIndicator
        return @()
    }

    $messages = @(Get-MaintainerMessages $master)
    if ($messages.Count -gt 0) {
        $latest = $messages[-1]
        $script:SupportState["latest_message_id"] = [Int64]$latest.id
        if ($MarkRead) { $script:SupportState["last_seen_message_id"] = [Int64]$latest.id }
    }
    Save-SupportState
    Set-MessagesIndicator
    return @($messages)
}

function Show-SupportMessages {
    if (-not $script:SupportState) { $script:SupportState = Load-SupportState }
    $fingerprint = [string]$script:SupportState["fingerprint"]
    if ([string]::IsNullOrWhiteSpace($fingerprint)) {
        $MsgHeaderText.Text = "NO TRACKED SUPPORT REPORT"
        $MsgBodyText.Text = "After REPORT ERROR creates a fingerprint, maintainer updates for its master ticket will appear here."
        $MsgOpenMasterHit.Visibility = [Windows.Visibility]::Collapsed
    }
    else {
        $messages = @(Refresh-SupportMessages -MarkRead)
        $master = 0
        try { $master = [int]$script:SupportState["master_issue"] } catch {}
        $MsgHeaderText.Text = $fingerprint + $(if ($master -gt 0) { "   •   A8P-TICKET-" + $master.ToString("0000") } else { "   •   master pending" })
        if ($messages.Count -eq 0) {
            $MsgBodyText.Text = if ($master -gt 0) {
                "The master ticket exists, but there is no maintainer update yet. Press REFRESH later to check again."
            } else {
                "No matching master ticket is visible yet. If you just submitted the GitHub report, press REFRESH after GitHub has processed it."
            }
        }
        else {
            $selected = @($messages | Select-Object -Last 8)
            $blocks = foreach ($msg in $selected) {
                $when = [string]$msg.created_at
                $author = if ($msg.user -and $msg.user.login) { [string]$msg.user.login } else { "maintainer" }
                $body = [string]$msg.body
                "[$when]  $author`r`n$body"
            }
            $MsgBodyText.Text = ($blocks -join "`r`n`r`n────────────────────────`r`n`r`n")
        }
        $MsgOpenMasterHit.Visibility = $(if ($master -gt 0) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed })
    }

    $MsgStatusText.Text = "Public GitHub updates — opening this window marks them read only on this PC"
    try { if (-not $MessagesWindow.Owner) { $MessagesWindow.Owner = $Window } } catch {}
    $MessagesWindow.WindowStartupLocation = [Windows.WindowStartupLocation]::CenterOwner
    if (-not $MessagesWindow.IsVisible) { $MessagesWindow.Show() }
    $MessagesWindow.Activate() | Out-Null
}

function Get-RepairAttemptsText {
    if (@($script:RepairAttempts).Count -eq 0) { return "none recorded" }
    return ((@($script:RepairAttempts) | ForEach-Object {
        $line = ([string]$_.action) + ": " + ([string]$_.result)
        if ($_.detail) { $line += " — " + [string]$_.detail }
        $line
    }) -join [Environment]::NewLine)
}

function Get-HashSummaryText {
    $bundle = New-SupportBundle
    return ((@($bundle.files) | ForEach-Object {
        $expected = if ($_.expected_sha256) { [string]$_.expected_sha256 } else { "n/a" }
        $actual = if ($_.actual_sha256) { [string]$_.actual_sha256 } elseif ($_.exists) { "hash-unavailable" } else { "missing" }
        ([string]$_.path) + ": expected=" + $expected + " actual=" + $actual
    }) -join [Environment]::NewLine)
}

function Get-LauncherReportBody([switch]$Compact) {
    $bundleJson = Save-LatestSupportBundle
    if ([string]::IsNullOrWhiteSpace($bundleJson)) { $bundleJson = '{"schema":1}' }

    $exactLimit = $(if ($Compact) { 1200 } else { 3000 })
    $exact = Limit-SupportText (Get-SanitizedText ([string]$script:LastErrorDetail)) $exactLimit
    $plan = if (@($script:LastRepairPlan).Count -gt 0) { @($script:LastRepairPlan) -join [Environment]::NewLine } else { "none" }
    $attempts = Limit-SupportText (Get-RepairAttemptsText) $(if ($Compact) { 1000 } else { 2400 })
    $hashes = Get-HashSummaryText
    $aotrVersion = Get-AotRVersionSafe
    $language = [Globalization.CultureInfo]::CurrentUICulture.Name
    $windows = Get-WindowsVersionSafe

    $lines = @(
        "### Launcher version","",[string]$global:AOTR8P_LAUNCHER_VERSION,"",
        "### AotR version","",$aotrVersion,"",
        "### Windows version","",$windows,"",
        "### Language","",$language,"",
        "### A8P Error Code","",[string]$script:LastErrorCode,"",
        "### Support Fingerprint","",[string]$script:LastFingerprint,"",
        "### Exact error","",$exact,"",
        "### Repair plan","",$plan,"",
        "### Repair attempts","",$attempts,"",
        "### Expected / actual hashes","",$hashes,"",
        "### Support bundle",""
    )

    if ($Compact) {
        $lines += "Full support bundle was too large for a safe GitHub prefill URL. The launcher saved support_bundle_latest.json locally and copied the full JSON to the clipboard."
    } else {
        $lines += $bundleJson
    }

    return ($lines -join [Environment]::NewLine)
}

function Open-LauncherReport {
    if (-not $script:ReportReady) { return }
    try {
        if ([string]::IsNullOrWhiteSpace([string]$script:LastFingerprint)) {
            $script:LastFingerprint = Get-SupportFingerprint ([string]$script:LastErrorCode) ([string]$script:LastErrorDetail)
        }
        Register-SupportFingerprint $script:LastFingerprint

        $titleText = [string]$script:LastErrorTitle
        if ([string]::IsNullOrWhiteSpace($titleText)) { $titleText = "Auto-Repair failed" }
        $title = "[Launcher Report] " + [string]$script:LastErrorCode + " - " + $titleText

        $body = Get-LauncherReportBody
        $url = $GitHubIssueUrl + "?template=launcher-auto-report.md&title=" + [Uri]::EscapeDataString($title) + "&body=" + [Uri]::EscapeDataString($body)
        $usedCompactFallback = $false

        # GitHub documents that oversized query URLs return HTTP 414. Keep a
        # safety margin and fall back to a concise report while preserving the
        # full bundle locally + on the clipboard.
        if ($url.Length -gt 7000) {
            $usedCompactFallback = $true
            $body = Get-LauncherReportBody -Compact
            $url = $GitHubIssueUrl + "?template=launcher-auto-report.md&title=" + [Uri]::EscapeDataString($title) + "&body=" + [Uri]::EscapeDataString($body)
            try {
                $fullBundle = Save-LatestSupportBundle
                if (-not [string]::IsNullOrWhiteSpace($fullBundle)) { [Windows.Clipboard]::SetText($fullBundle) }
            } catch {}
        } else {
            try { [Windows.Clipboard]::SetText($script:LastDiagnosticReport) } catch {}
        }

        Write-RepairLog ("Opening user-reviewed GitHub report for " + $script:LastFingerprint + $(if ($usedCompactFallback) { " using compact URL fallback" } else { "" }))
        Start-Process $url

        $DiagFooterText.Text = if ($usedCompactFallback) {
            "GitHub opened — full support bundle copied to clipboard"
        } else {
            "GitHub opened — review the prefilled report and press Submit"
        }
    }
    catch {
        Write-RepairLog ("Could not open GitHub report: " + $_.Exception.Message)
        try {
            $fullBundle = Save-LatestSupportBundle
            if (-not [string]::IsNullOrWhiteSpace($fullBundle)) { [Windows.Clipboard]::SetText($fullBundle) }
        } catch {}
        [System.Windows.Forms.MessageBox]::Show(
            "The report page could not be opened automatically. The support bundle was saved locally and copied to the clipboard when possible.`r`n`r`n" + $_.Exception.Message,
            "AotR 8P WotR - Report Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

function Set-ReportReady([string]$Detail,[bool]$Protected = $false) {
    if (-not [string]::IsNullOrWhiteSpace($Detail)) { $script:LastErrorDetail = [string]$Detail }
    $script:ReportReady = $true
    $script:RepairMode = $true
    $script:RepairStage = "REPORT"
    $script:AutoRepairRetryInProgress = $false
    $script:LastFingerprint = Get-SupportFingerprint ([string]$script:LastErrorCode) ([string]$script:LastErrorDetail)
    $script:LastDiagnosticReport = Get-SanitizedDiagnosticReport $script:LastErrorCode $script:LastErrorDetail
    Register-SupportFingerprint $script:LastFingerprint
    Save-LatestSupportBundle | Out-Null
    $ReadyCleanPatch.Visibility = [Windows.Visibility]::Visible
    Set-OverallStatus ("REPORT READY — " + $script:LastErrorCode) $DangerText
    Set-LaunchState "REPORT ERROR" $DangerText
    Show-Error ($script:LastErrorCode + " — " + $script:LastErrorTitle) $script:LastErrorDetail $Protected
    $LaunchHit.IsHitTestVisible = $true
}

function Enter-RepairMode([string]$Detail) {
    $wasRepairRetry = [bool]$script:AutoRepairRetryInProgress
    $script:AutoRepairRetryInProgress = $false

    $info = Get-LaunchFailureInfo $Detail
    $script:RepairMode = $true
    $script:RepairStage = "REPAIR"
    $script:ReportReady = $false
    $script:LastErrorCode = [string]$info.Code
    $script:LastErrorTitle = [string]$info.Title
    $script:LastErrorDetail = [string]$Detail
    $script:LastFingerprint = Get-SupportFingerprint $script:LastErrorCode $script:LastErrorDetail
    $script:LastDiagnosticReport = Get-SanitizedDiagnosticReport $script:LastErrorCode $script:LastErrorDetail
    Write-RepairLog ("Failure classified as " + $script:LastErrorCode + " " + $script:LastFingerprint + ": " + $script:LastErrorDetail)

    if ($wasRepairRetry) {
        Add-RepairAttempt "retry_launch" "failed" $script:LastErrorDetail
        Write-RepairLog "Automatic post-repair retry failed; repair cycle is exhausted and REPORT ERROR is now available."
        Set-ReportReady $script:LastErrorDetail ([bool]$info.Protected)
        return
    }

    $ReadyCleanPatch.Visibility = [Windows.Visibility]::Visible
    Set-OverallStatus ("REPAIR REQUIRED — " + $script:LastErrorCode) $RepairText
    Set-LaunchState "AUTO REPAIR"
    Show-Error ($script:LastErrorCode + " — " + $info.Title) $script:LastErrorDetail ([bool]$info.Protected)
    $LaunchHit.IsHitTestVisible = $true
}

function Stop-FailedAotRProcesses {
    foreach ($name in @("game","lotrbfme2ep1")) {
        foreach ($p in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            try {
                Write-RepairLog ("Stopping stale process " + $name + " PID " + $p.Id)
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
            } catch {
                Write-RepairLog ("Could not stop " + $name + ": " + $_.Exception.Message)
            }
        }
    }
}

function Stop-OldDevLaunchers {
    try {
        $old = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
            ([string]$_.CommandLine) -match '(?i)\\BFME_RESEARCH\\05_REVERSE_ENGINEERING\\AOTR_8P_WOTR_MOD\\internal\\launcher_11_portable\.ps1'
        })
        foreach ($p in $old) {
            Write-RepairLog ("Stopping old development launcher PID " + $p.ProcessId)
            Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Reset-PortableRuntime {
    if (-not $Install) { return }
    $runtimePath = Join-Path $Install.Root "_AOTR_8P_WOTR_RUNTIME"
    if (-not (Test-Path -LiteralPath $runtimePath -PathType Container)) { return }

    $quarantine = Join-Path $Install.Root ("_AOTR_8P_WOTR_RUNTIME_REPAIR_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
    try {
        Move-Item -LiteralPath $runtimePath -Destination $quarantine -Force -ErrorAction Stop
        Write-RepairLog ("Runtime quarantined without recursive deletion: " + $quarantine)
    } catch {
        Write-RepairLog ("Runtime quarantine failed: " + $_.Exception.Message)
        throw
    }
}

function Reset-InstallDetection {
    try { Remove-Item -LiteralPath $ConfigPath -Force -ErrorAction SilentlyContinue } catch {}
    $newInstall = Resolve-AotRInstall -PromptIfMissing
    if (-not $newInstall) { throw "Age of the Ring installation could not be resolved during repair." }
    $script:Install = $newInstall
    $script:GameDat = $newInstall.GameDat
    Write-RepairLog ("AotR installation re-detected: " + $newInstall.Runtime)
}

function Install-VerifiedDownload([string]$Url,[string]$ExpectedSha,[string]$Destination) {
    if ([string]::IsNullOrWhiteSpace($Url) -or [string]::IsNullOrWhiteSpace($ExpectedSha)) {
        throw "Remote payload metadata is incomplete."
    }
    $parent = Split-Path $Destination -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $temp = Join-Path $parent (".repair_" + [Guid]::NewGuid().ToString("N") + ".tmp")
    try {
        Save-HttpFile $Url $temp
        $actual = Get-Sha256 $temp
        if ($actual -ne $ExpectedSha.ToUpperInvariant()) {
            throw "Downloaded repair payload failed SHA256 verification."
        }
        Move-Item -LiteralPath $temp -Destination $Destination -Force
        Write-RepairLog ("Verified payload repaired: " + $Destination + " SHA256=" + $actual)
    } finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

function Repair-ModPayloads {
    $manifest = (Get-HttpText $ModManifestUrl | ConvertFrom-Json)

    if (-not $manifest.ui_url -or -not $manifest.ui_sha256 -or -not $manifest.paper_url -or -not $manifest.paper_sha256) {
        throw "GitHub manifest does not contain repair payload metadata yet."
    }

    $uiBad = $true
    if (Test-Path -LiteralPath $UiSource -PathType Leaf) {
        try { $uiBad = ((Get-Sha256 $UiSource) -ne [string]$manifest.ui_sha256) } catch {}
    }
    if ($uiBad) {
        Install-VerifiedDownload ([string]$manifest.ui_url) ([string]$manifest.ui_sha256) $UiSource
    }

    $paperBad = $true
    if (Test-Path -LiteralPath $PaperSource -PathType Leaf) {
        try { $paperBad = ((Get-Sha256 $PaperSource) -ne [string]$manifest.paper_sha256) } catch {}
    }
    if ($paperBad) {
        Install-VerifiedDownload ([string]$manifest.paper_url) ([string]$manifest.paper_sha256) $PaperSource
    }
}

function Copy-RepairDiagnostics {
    if ([string]::IsNullOrWhiteSpace($script:LastDiagnosticReport)) {
        $script:LastDiagnosticReport = Get-SanitizedDiagnosticReport $script:LastErrorCode $script:LastErrorDetail
    }
    [Windows.Clipboard]::SetText($script:LastDiagnosticReport)
    Write-RepairLog "Sanitized diagnostics copied to clipboard."
    Set-LaunchState "DIAGNOSTICS COPIED" $RunningText
    Show-Error ($script:LastErrorCode + " — Diagnostic report copied") "The sanitized diagnostic report was copied to the clipboard." $false
}

function Invoke-AutoRepair {
    $info = Get-LaunchFailureInfo $script:LastErrorDetail
    $script:LastErrorCode = [string]$info.Code
    $script:LastErrorTitle = [string]$info.Title
    $script:LastFingerprint = Get-SupportFingerprint $script:LastErrorCode $script:LastErrorDetail
    $script:RepairAttempts = @()
    $script:LastRepairPlan = @()
    $script:ReportReady = $false

    if ($info.Protected) {
        $script:LastRepairPlan = @("check_launcher_update")
        Write-RepairLog ("Protected compatibility failure; no unsafe memory repair attempted: " + $info.Code)
        try {
            $update = [AotR8PUpdateBridge]::CheckNow()
            if ($update -eq "UPDATE_STARTED") {
                Add-RepairAttempt "check_launcher_update" "success" "Compatible launcher update started."
                Set-LaunchState "UPDATING..." $RepairText
                $Window.Close()
                return
            }
            if ([string]$update -like "ERROR|*") {
                Add-RepairAttempt "check_launcher_update" "failed" ([string]$update).Substring(6)
            } else {
                Add-RepairAttempt "check_launcher_update" "success" ([string]$update)
            }
        } catch {
            Add-RepairAttempt "check_launcher_update" "failed" $_.Exception.Message
        }
        Set-ReportReady $script:LastErrorDetail $true
        return
    }

    $LaunchHit.IsHitTestVisible = $false
    Set-LaunchState "DIAGNOSING..."
    Set-OverallStatus "AUTO REPAIR — DIAGNOSING..." $RepairText
    Hide-Error
    Write-RepairLog ("AUTO REPAIR started for " + $info.Code)

    try {
        $actions = @($info.Actions)
        $remote = Get-RemoteRepairPlan $info.Code
        if ($remote -and $remote.actions) {
            $actions = @($remote.actions | ForEach-Object { [string]$_ })
            Write-RepairLog ("Using remote repair plan for " + $info.Code + ": " + ($actions -join ","))
        }
        $script:LastRepairPlan = @($actions)

        # Remote plans are data only. They may select from this fixed allow-list;
        # they can never inject or execute arbitrary commands.
        $allowed = @(
            "stop_legacy_runtime","stop_failed_game","stop_old_dev_launchers",
            "reset_runtime","clear_compat_cache","reset_install",
            "repair_payloads","check_launcher_update","retry_launch"
        )

        foreach ($action in $actions) {
            if ($allowed -notcontains $action) {
                Write-RepairLog ("Ignored unknown/unsafe remote repair action: " + $action)
                Add-RepairAttempt $action "skipped" "Not in the launcher's built-in repair allow-list."
                continue
            }
            if ($action -eq "retry_launch") { continue }

            Set-LaunchState ("REPAIR: " + $action.ToUpperInvariant().Replace("_"," "))
            Set-OverallStatus ("AUTO REPAIR — " + $action.ToUpperInvariant().Replace("_"," ")) $RepairText
            try {
                switch ($action) {
                    "stop_legacy_runtime"    { Stop-Legacy8PRuntime }
                    "stop_failed_game"       { Stop-FailedAotRProcesses }
                    "stop_old_dev_launchers" { Stop-OldDevLaunchers }
                    "reset_runtime"          { Reset-PortableRuntime }
                    "clear_compat_cache"     { Remove-Item -LiteralPath $CompatCachePath -Force -ErrorAction SilentlyContinue; Write-RepairLog "Compatibility cache cleared." }
                    "reset_install"          { Reset-InstallDetection }
                    "repair_payloads"        { Repair-ModPayloads }
                    "check_launcher_update" {
                        $u = [AotR8PUpdateBridge]::CheckNow()
                        if ($u -eq "UPDATE_STARTED") {
                            Add-RepairAttempt $action "success" "Compatible launcher update started."
                            $Window.Close()
                            return
                        }
                        if ([string]$u -like "ERROR|*") { throw ([string]$u).Substring(6) }
                    }
                }
                Add-RepairAttempt $action "success"
            }
            catch {
                Add-RepairAttempt $action "failed" $_.Exception.Message
                throw
            }
        }

        Write-RepairLog ("AUTO REPAIR actions completed for " + $info.Code)
        $script:RepairMode = $false
        $script:RepairStage = "NONE"
        Hide-Error

        # Issue #43: repair completion alone is never permission to launch.
        # First perform a full health re-check with normal repair semantics. If the
        # re-check discovers another repairable problem, remain in AUTO REPAIR instead
        # of escalating to REPORT ERROR. Only a clean re-check may auto-launch.
        $script:AutoRepairRetryInProgress = $false
        $script:LastRetryAt = Get-Date
        Set-OverallStatus "AUTO REPAIR COMPLETE — VERIFYING..." $RepairText
        Invoke-Preflight

        if ($script:ReportReady) { return }
        if ($script:RepairMode) {
            Write-RepairLog ("AUTO REPAIR health re-check found another issue: " + $script:LastErrorCode + "; staying in repair mode.")
            return
        }
        if ($LaunchHit.IsHitTestVisible -and $LaunchText.Text -match '^LAUNCH') {
            Write-RepairLog "AUTO REPAIR health re-check clean; launching automatically."
            $script:AutoRepairRetryInProgress = $true
            Start-AotR8PLaunch -FromRepair
            return
        }

        throw "Repair completed, but health re-check returned neither repair nor launchable state."
    }
    catch {
        $failedDuringRetry = [bool]$script:AutoRepairRetryInProgress
        $script:AutoRepairRetryInProgress = $false
        $script:LastErrorDetail = [string]$_.Exception.Message
        if ($failedDuringRetry) { Add-RepairAttempt "retry_launch" "failed" $script:LastErrorDetail }
        $script:LastFingerprint = Get-SupportFingerprint $script:LastErrorCode $script:LastErrorDetail
        $script:LastDiagnosticReport = Get-SanitizedDiagnosticReport $script:LastErrorCode $script:LastErrorDetail
        Write-RepairLog ("AUTO REPAIR failed: " + $_.Exception.Message)
        Set-ReportReady $script:LastErrorDetail $false
    }
}

$DiagRetryHit.Add_MouseLeftButtonUp({
    try {
        $script:ReportReady = $false
        $script:RepairMode = $false
        $script:RepairStage = "NONE"
        $script:AutoRepairRetryInProgress = $false
        Hide-Error
        Start-AotR8PLaunch
    } catch { Enter-RepairMode $_.Exception.Message }
})
$DiagReportHit.Add_MouseLeftButtonUp({ Open-LauncherReport })

$MsgCloseHit.Add_MouseLeftButtonUp({ $MessagesWindow.Hide() })
$MsgRefreshHit.Add_MouseLeftButtonUp({ Show-SupportMessages })
$MsgOpenMasterHit.Add_MouseLeftButtonUp({
    try {
        if (-not $script:SupportState) { $script:SupportState = Load-SupportState }
        $master = [int]$script:SupportState["master_issue"]
        if ($master -gt 0) { Start-Process ($GitHubRepoUrl + "/issues/" + $master) }
    } catch {}
})

$DragRegion.Add_MouseLeftButtonDown({
    try { $Window.DragMove() } catch {}
})
$MinHit.Add_MouseLeftButtonUp({
    $Window.WindowState = [Windows.WindowState]::Minimized
})
$CloseHit.Add_MouseLeftButtonUp({
    $Window.Close()
})
$UpdateHit.Add_MouseLeftButtonUp({
    try {
        $official = Find-OfficialAotRLauncher
        if (-not $official) {
            [System.Windows.Forms.MessageBox]::Show(
                "The official AotR_Launcher.exe could not be found. Re-select your Age of the Ring install folder and try again.",
                "AotR 8P War of the Ring",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }
        Start-Process -FilePath $official -WorkingDirectory (Split-Path $official -Parent) | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "AotR Updater",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})

$MessagesHit.Add_MouseLeftButtonUp({ Show-SupportMessages })

$ModUpdateHit.Add_MouseLeftButtonUp({
    $ModUpdateHit.IsHitTestVisible = $false
    $ModUpdateText.Text = "CHECKING..."
    try {
        $result = [AotR8PUpdateBridge]::CheckNow()
        if ($result -eq "UPDATE_STARTED") {
            $ModUpdateText.Text = "UPDATING..."
            # The verified new EXE is already running as the update helper. Closing this
            # window lets the old process exit so the helper can atomically replace it.
            $Window.Close()
            return
        }

        if ($result -like "UP_TO_DATE|*") {
            $current = $result.Substring("UP_TO_DATE|".Length)
            $ModUpdateText.Text = "UP TO DATE"
            [System.Windows.Forms.MessageBox]::Show(
                "AotR 8P WotR Mod is up to date.`r`n`r`nLauncher v$current",
                "Mod Update",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }

        $message = if ($result -like "ERROR|*") { $result.Substring("ERROR|".Length) } else { [string]$result }
        $ModUpdateText.Text = "UPDATE CHECK FAILED"
        [System.Windows.Forms.MessageBox]::Show(
            $message,
            "Mod Update",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {
        $ModUpdateText.Text = "UPDATE CHECK FAILED"
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "Mod Update",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    finally {
        if ($ModUpdateText.Text -ne "UPDATING...") {
            $ModUpdateHit.IsHitTestVisible = $true
        }
    }
})

$script:EnginePS = $null
$script:EngineRunspace = $null
$script:EngineAsync = $null
$script:LastLog = ""
$script:RunningReached = $false
$script:LaunchStartedAt = $null

function Invoke-Preflight {
    Set-StatusChecking
    $allOk = $true

    $gameOk = $false
    $script:GameNeedsCompatCheck = $false
    if (Test-Path -LiteralPath $GameDat -PathType Leaf) {
        try {
            $g = Get-Item -LiteralPath $GameDat
            $gameHash = Get-Sha256 $GameDat
            $known931 = ($g.Length -eq $Known931GameSize -and $gameHash -eq $Known931GameSha256)
            $cachedCompatible = Test-CachedCompatibleBuild $GameDat
            $gameOk = ($g.Length -gt 1048576)
            $script:GameNeedsCompatCheck = ($gameOk -and -not $known931 -and -not $cachedCompatible)
        } catch {}
    }

    if ($gameOk) {
        $Row1Fail.Visibility = [Windows.Visibility]::Collapsed
        Set-StatusCheck $StatusGameText $true "OK" "NOT FOUND"
    } else {
        $Row1FailText.Text = "game.dat not found"
        $Row1Fail.Visibility = [Windows.Visibility]::Visible
        Set-StatusCheck $StatusGameText $false "OK" "NOT FOUND"
        $allOk = $false
    }

    $modOk = $false
    if (Test-Path -LiteralPath $PaperSource -PathType Leaf) {
        try {
            $p = Get-Item -LiteralPath $PaperSource
            $modOk = ($p.Length -eq 1648 -and (Get-Sha256 $PaperSource) -eq $ExpectedPaperSha256)
        } catch {}
    }
    if ($modOk) {
        $Row2Fail.Visibility = [Windows.Visibility]::Collapsed
        Set-StatusCheck $StatusCampaignText $true "OK" "MISSING / INVALID"
    } else {
        $Row2FailText.Text = "8 Player WotR campaign payload missing"
        $Row2Fail.Visibility = [Windows.Visibility]::Visible
        Set-StatusCheck $StatusCampaignText $false "OK" "MISSING / INVALID"
        $allOk = $false
    }

    $rowsOk = $false
    if (Test-Path -LiteralPath $UiSource -PathType Leaf) {
        try {
            $u = Get-Item -LiteralPath $UiSource
            $rowsOk = (
                $u.Length -eq $ExpectedUiSize -and
                (Get-Sha256 $UiSource) -eq $ExpectedUiSha256
            )
        } catch {}
    }

    if ($rowsOk) {
        $Row3Fail.Visibility = [Windows.Visibility]::Collapsed
        Set-StatusCheck $StatusUiText $true "OK" "MISSING / INVALID"
    } else {
        $Row3FailText.Text = "8-player roster UI missing"
        $Row3Fail.Visibility = [Windows.Visibility]::Visible
        Set-StatusCheck $StatusUiText $false "OK" "MISSING / INVALID"
        $allOk = $false
    }

    $engineOk = -not [string]::IsNullOrWhiteSpace($EmbeddedEngine)
    if (-not $engineOk) {
        $allOk = $false
        Show-Error "Launcher runtime is missing."
    }

    $running = @(
        Get-Process -Name "game","lotrbfme2ep1" -ErrorAction SilentlyContinue
    )

    $oldDevLaunchers = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
        ([string]$_.CommandLine) -match '(?i)\\BFME_RESEARCH\\05_REVERSE_ENGINEERING\\AOTR_8P_WOTR_MOD\\internal\\launcher_11_portable\.ps1'
    })
    if ($oldDevLaunchers.Count -gt 0) {
        Enter-RepairMode "OLD DEV LAUNCHER RUNNING: BFME_RESEARCH launcher_11_portable.ps1"
        return
    }

    if ($running.Count -gt 0) {
        Enter-RepairMode "AotR is already running / GAME ALREADY RUNNING"
        return
    }

    if ($allOk) {
        Hide-Error
        $ReadyCleanPatch.Visibility = [Windows.Visibility]::Collapsed
        if ($script:GameNeedsCompatCheck) {
            Set-LaunchState "LAUNCH + COMPAT CHECK"
            Set-OverallStatus "READY — COMPAT CHECK ON LAUNCH" $RepairText
        } else {
            Set-LaunchState "LAUNCH AOTR 8P WOTR"
            Set-OverallStatus "ALL CHECKS PASSED — READY" $RunningText
        }
        $LaunchHit.IsHitTestVisible = $true
    } else {
        Set-OverallStatus "REPAIR REQUIRED" $RepairText
        if (-not $gameOk) {
            Enter-RepairMode "game.dat not found"
        }
        elseif (-not $modOk) {
            Enter-RepairMode "8P campaign payload missing"
        }
        elseif (-not $rowsOk) {
            Enter-RepairMode "8-player roster UI missing"
        }
        elseif (-not $engineOk) {
            Show-Error "Launcher runtime is missing."
            Set-LaunchState "LAUNCH UNAVAILABLE" $DangerText
            $LaunchHit.IsHitTestVisible = $false
        }
        else {
            Enter-RepairMode "Launcher cannot start this configuration."
        }
    }
}

$Timer = New-Object Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromMilliseconds(250)

$CloseTimer = New-Object Windows.Threading.DispatcherTimer
$CloseTimer.Interval = [TimeSpan]::FromMilliseconds(700)
$CloseTimer.Add_Tick({
    $CloseTimer.Stop()
    $Window.Close()
})

$Timer.Add_Tick({
    if (Test-Path -LiteralPath $LogFile -PathType Leaf) {
        try {
            $current = [IO.File]::ReadAllText($LogFile)

            if ($current -ne $script:LastLog) {
                $script:LastLog = $current

                if ($current -match "PORTABLE RUNTIME READY") {
                    Set-LaunchState "RUNTIME READY"
                    Set-OverallStatus "RUNTIME READY" $NormalText
                }

                if ($current -match "game\.dat GEFUNDEN") {
                    Set-LaunchState "GAME.DAT FOUND"
                }

                if ($current -match "8P-Patch in") {
                    Set-LaunchState "INITIALIZING..."
                }

                if ($current -match "AOTR8P_ENGINE_EXIT=1") {
                    $Timer.Stop()
                    $lastMeaningful = ($current -split "`r?`n" | Where-Object { $_ -and $_ -notmatch '^\*' } | Select-Object -Last 8) -join " | "
                    Enter-RepairMode $lastMeaningful
                    return
                }

                if ($current -match "FINAL_STABLE_V7 automatisch aktiviert") {
                    Set-LaunchState "RUNNING" $RunningText
                    Set-OverallStatus "RUNNING — ALL CHECKS PASSED" $RunningText
                    $script:RunningReached = $true
                    $Timer.Stop()
                    $CloseTimer.Start()
                }
            }
        } catch {}
    }

    if ($script:LaunchStartedAt -and -not $script:RunningReached -and ((Get-Date) - $script:LaunchStartedAt).TotalSeconds -gt 120) {
        $Timer.Stop()
        $detail = if (Test-Path -LiteralPath $LogFile -PathType Leaf) {
            "Launch timeout. " + ((Get-Content -LiteralPath $LogFile -Tail 12 -ErrorAction SilentlyContinue) -join " | ")
        } else { "Launch timed out before logging initialized." }
        Enter-RepairMode $detail
        return
    }

    if (
        $script:EngineAsync -and
        $script:EngineAsync.IsCompleted -and
        -not $script:RunningReached
    ) {
        try {
            if ($script:EnginePS) { $null = $script:EnginePS.EndInvoke($script:EngineAsync) }
        } catch {}
        if ($script:EnginePS) { $script:EnginePS.Dispose(); $script:EnginePS = $null }
        if ($script:EngineRunspace) { $script:EngineRunspace.Close(); $script:EngineRunspace.Dispose(); $script:EngineRunspace = $null }
        $script:EngineAsync = $null

        if (-not (Test-Path -LiteralPath $LogFile -PathType Leaf) -or
            -not (([IO.File]::ReadAllText($LogFile)) -match "AOTR8P_ENGINE_EXIT=0")) {
            $Timer.Stop()
            $detail = if (Test-Path -LiteralPath $LogFile -PathType Leaf) {
                (Get-Content -LiteralPath $LogFile -Tail 18 -ErrorAction SilentlyContinue) -join " | "
            } else { "Embedded engine stopped before logging initialized." }
            Enter-RepairMode $detail
        }
    }
})

function Start-AotR8PLaunch([switch]$FromRepair) {
    try {
        $script:RepairMode = $false
        $script:RepairStage = "NONE"
        $script:ReportReady = $false
        $script:AutoRepairRetryInProgress = [bool]$FromRepair
        $LaunchHit.IsHitTestVisible = $false
        Hide-Error
        Set-LaunchState "STARTING..."
        Set-OverallStatus "LAUNCHING..." $NormalText

        $script:LastLog = ""
        $script:RunningReached = $false
        $script:LaunchStartedAt = Get-Date
        Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $LogDir -ErrorAction SilentlyContinue | Out-Null
        ("AotR 8P WotR launcher handoff started: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) | Set-Content -LiteralPath $LogFile -Encoding UTF8

        if ($script:EnginePS) {
            try { $script:EnginePS.Stop() } catch {}
            $script:EnginePS.Dispose()
        }

        $script:EngineRunspace = [runspacefactory]::CreateRunspace()
        $script:EngineRunspace.Open()
        $script:EngineRunspace.SessionStateProxy.SetVariable("AOTR8P_PACKAGE_ROOT", $packageRoot)
        $script:EngineRunspace.SessionStateProxy.SetVariable("AOTR8P_LAUNCHER_VERSION", [string]$global:AOTR8P_LAUNCHER_VERSION)
        $script:EngineRunspace.SessionStateProxy.SetVariable("AOTR8P_FINAL_STABLE_V7_BYTES", [byte[]]$global:AOTR8P_FINAL_STABLE_V7_BYTES)
        $script:EngineRunspace.SessionStateProxy.SetVariable("AOTR8P_V7_SHELLCODE_BYTES", [byte[]]$global:AOTR8P_V7_SHELLCODE_BYTES)

        $script:EnginePS = [powershell]::Create()
        $script:EnginePS.Runspace = $script:EngineRunspace
        [void]$script:EnginePS.AddScript($EmbeddedEngine)
        [void]$script:EnginePS.AddParameter("LogFile", $LogFile)
        $script:EngineAsync = $script:EnginePS.BeginInvoke()

        $Timer.Start()
    }
    catch {
        Enter-RepairMode $_.Exception.Message
    }
}

$LaunchHit.Add_MouseLeftButtonUp({
    if ($script:RepairMode) {
        if ($script:RepairStage -eq "REPORT") {
            Open-LauncherReport
        }
        elseif ($script:RepairStage -eq "DIAGNOSTICS") {
            Copy-RepairDiagnostics
        }
        else {
            Invoke-AutoRepair
        }
        return
    }
    Start-AotR8PLaunch
})

$Window.Add_ContentRendered({
    $script:SupportState = Load-SupportState
    Set-MessagesIndicator
    Invoke-Preflight
    try { $null = Refresh-SupportMessages } catch {}
})

$Window.Add_Closed({
    try { $script:ErrorPanelWanted = $false; if ($ErrorWindow) { $ErrorWindow.Close() } } catch {}
    try { if ($MessagesWindow) { $MessagesWindow.Close() } } catch {}
    if ($script:EnginePS) {
        try { $script:EnginePS.Stop() } catch {}
        try { $script:EnginePS.Dispose() } catch {}
    }
    if ($script:EngineRunspace) {
        try { $script:EngineRunspace.Close() } catch {}
        try { $script:EngineRunspace.Dispose() } catch {}
    }
})

[void]$Window.ShowDialog()
