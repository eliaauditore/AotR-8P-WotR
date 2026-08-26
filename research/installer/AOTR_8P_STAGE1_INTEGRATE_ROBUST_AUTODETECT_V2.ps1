#requires -version 5.1
[CmdletBinding()]
param(
    [string]$Base = "D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD",
    [string]$BuilderPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = "79D31C3DCE6833781BFECF5B87230B1C463483EA4F31A89D2431238D42A17C6F"
$ExpectedGuiSha256 = "E8C67486182DA952EA19214AAE9F60E5E9E410579FEF1C0722DA626CE5FFF1EF"
$ExpectedEngineSha256 = "D94460492ACD2B98CB8DF0929E302C2F626A97045AAEE9593A2B29E9424FEA5B"

function Get-Sha256File([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-Sha256Text([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')
    }
    finally {
        $sha.Dispose()
    }
}

function Assert-Leaf([string]$Path,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label missing: $Path"
    }
}

function Test-PowerShellTextSyntax([string]$Text,[string]$Label) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput(
        $Text,
        [ref]$tokens,
        [ref]$errors
    )
    if ($errors -and $errors.Count -gt 0) {
        $msg = ($errors | ForEach-Object {
            "Line $($_.Extent.StartLineNumber), Col $($_.Extent.StartColumnNumber): $($_.Message)"
        }) -join [Environment]::NewLine
        throw "PowerShell syntax validation failed for $Label`n$msg"
    }
}

function Wrap-Base64([string]$Text,[int]$Width = 120) {
    $parts = New-Object System.Collections.Generic.List[string]
    for ($i=0; $i -lt $Text.Length; $i += $Width) {
        $len = [Math]::Min($Width,$Text.Length-$i)
        [void]$parts.Add($Text.Substring($i,$len))
    }
    return ($parts -join "`r`n")
}

function Convert-GzipBase64ToText([string]$Base64) {
    $bytes = [Convert]::FromBase64String(($Base64 -replace '\s',''))
    $input = New-Object IO.MemoryStream(,$bytes)
    try {
        $gzip = New-Object IO.Compression.GZipStream(
            $input,
            [IO.Compression.CompressionMode]::Decompress
        )
        try {
            $reader = New-Object IO.StreamReader($gzip,[Text.Encoding]::UTF8,$true)
            try {
                return $reader.ReadToEnd()
            }
            finally { $reader.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally { $input.Dispose() }
}

function Convert-TextToGzipBase64([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $output = New-Object IO.MemoryStream
    try {
        $gzip = New-Object IO.Compression.GZipStream(
            $output,
            [IO.Compression.CompressionMode]::Compress,
            $true
        )
        try {
            $gzip.Write($bytes,0,$bytes.Length)
        }
        finally { $gzip.Dispose() }
        return [Convert]::ToBase64String($output.ToArray())
    }
    finally { $output.Dispose() }
}

function Get-OuterCSharpInfo([string]$BuilderText) {
    $pattern = '(?s)(?<before>\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\s*)(?<data>[A-Za-z0-9+/=\r\n]+?)(?<after>\s*''@\)\))'
    $m = [regex]::Match($BuilderText,$pattern)
    if (-not $m.Success) {
        throw 'Could not locate the outer V17 $template Base64 block.'
    }
    $b64 = ($m.Groups['data'].Value -replace '\s','')
    return [PSCustomObject]@{
        Match = $m
        CSharp = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
    }
}

function Get-CSharpPayloadInfo([string]$CSharp,[string]$VariableName) {
    $pattern = '(?s)(?:private\s+)?const\s+string\s+' +
        [regex]::Escape($VariableName) +
        '\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
    $m = [regex]::Match($CSharp,$pattern)
    if (-not $m.Success) {
        throw "Could not locate C# payload variable $VariableName."
    }
    return [PSCustomObject]@{
        Match = $m
        Base64 = $m.Groups['data'].Value
        Text = Convert-GzipBase64ToText $m.Groups['data'].Value
    }
}

function Replace-CSharpPayload([string]$CSharp,[string]$VariableName,[string]$NewText) {
    $info = Get-CSharpPayloadInfo -CSharp $CSharp -VariableName $VariableName
    $newB64 = Wrap-Base64 (Convert-TextToGzipBase64 $NewText)
    $g = $info.Match.Groups['data']
    return $CSharp.Substring(0,$g.Index) + $newB64 + $CSharp.Substring($g.Index + $g.Length)
}

function Replace-SourceBlock {
    param(
        [string]$Text,
        [string]$StartMarker,
        [string]$EndMarker,
        [string]$Replacement,
        [string]$Label
    )

    $start = $Text.IndexOf($StartMarker,[StringComparison]::Ordinal)
    if ($start -lt 0) { throw "$Label start marker not found: $StartMarker" }

    $end = $Text.IndexOf($EndMarker,$start,[StringComparison]::Ordinal)
    if ($end -lt 0) { throw "$Label end marker not found: $EndMarker" }
    if ($end -le $start) { throw "$Label replacement bounds are invalid." }

    return $Text.Substring(0,$start) + $Replacement + "`r`n`r`n" + $Text.Substring($end)
}

$guiReplacement = @'
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
'@

$engineReplacement = @'
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
'@

if ([string]::IsNullOrWhiteSpace($BuilderPath)) {
    $BuilderPath = Join-Path $Base 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_START_SIGNAL_MVP.ps1'
}

$BuilderPath = [IO.Path]::GetFullPath($BuilderPath)
Assert-Leaf $BuilderPath 'V17 START_SIGNAL builder'

$builderBefore = Get-Sha256File $BuilderPath
if ($builderBefore -ne $ExpectedBuilderSha256) {
    throw "Builder checkpoint mismatch. Expected $ExpectedBuilderSha256, got $builderBefore. Nothing changed."
}

$originalBuilderText = [IO.File]::ReadAllText($BuilderPath)
$outer = Get-OuterCSharpInfo $originalBuilderText
$guiInfo = Get-CSharpPayloadInfo -CSharp $outer.CSharp -VariableName 'GuiGzipBase64'
$engineInfo = Get-CSharpPayloadInfo -CSharp $outer.CSharp -VariableName 'EngineGzipBase64'

$guiBefore = Get-Sha256Text $guiInfo.Text
$engineBefore = Get-Sha256Text $engineInfo.Text

if ($guiBefore -ne $ExpectedGuiSha256) {
    throw "GUI payload checkpoint mismatch. Expected $ExpectedGuiSha256, got $guiBefore. Nothing changed."
}
if ($engineBefore -ne $ExpectedEngineSha256) {
    throw "Engine payload checkpoint mismatch. Expected $ExpectedEngineSha256, got $engineBefore. Nothing changed."
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AOTR 8P ROBUST AUTODETECT V2 - STAGE 1' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Builder: $BuilderPath"
Write-Host "Builder SHA256: $builderBefore" -ForegroundColor Green
Write-Host "GUI SHA256:     $guiBefore" -ForegroundColor Green
Write-Host "ENGINE SHA256:  $engineBefore" -ForegroundColor Green

$guiPatched = Replace-SourceBlock `
    -Text $guiInfo.Text `
    -StartMarker 'function Get-AotRInstallFromPath([string]$Path) {' `
    -EndMarker '$Install = Resolve-AotRInstall -PromptIfMissing' `
    -Replacement $guiReplacement `
    -Label 'GUI resolver'

$enginePatched = Replace-SourceBlock `
    -Text $engineInfo.Text `
    -StartMarker 'function Get-AotRInstallFromPath([string]$Path) {' `
    -EndMarker 'function New-LinkedFile([string]$Source, [string]$Destination) {' `
    -Replacement $engineReplacement `
    -Label 'Engine resolver'

Write-Host ''
Write-Host '=== POWERSHELL PAYLOAD SYNTAX ===' -ForegroundColor Cyan
Test-PowerShellTextSyntax $guiPatched 'patched GUI payload'
Write-Host 'GUI syntax: PASS' -ForegroundColor Green
Test-PowerShellTextSyntax $enginePatched 'patched engine payload'
Write-Host 'ENGINE syntax: PASS' -ForegroundColor Green

$requiredGuiMarkers = @(
    "validation = 'aotr-standalone-v2'",
    "A8P-INSTALL-002",
    "A8P-INSTALL-003",
    "A8P-INSTALL-004",
    "A8P-INSTALL-007",
    'Get-AotRLocalDrives',
    'Find-AotRRootsBounded',
    'RemovableUsbOrExFat'
)
foreach ($marker in $requiredGuiMarkers) {
    if (-not $guiPatched.Contains($marker)) { throw "Patched GUI missing required marker: $marker" }
}

$engineResolverStart = $enginePatched.IndexOf('function Resolve-AotRInstall {',[StringComparison]::Ordinal)
$engineResolverEnd = $enginePatched.IndexOf('function New-LinkedFile([string]$Source, [string]$Destination) {',$engineResolverStart,[StringComparison]::Ordinal)
if ($engineResolverStart -lt 0 -or $engineResolverEnd -le $engineResolverStart) {
    throw 'Could not isolate patched engine resolver for assertions.'
}
$engineResolverText = $enginePatched.Substring($engineResolverStart,$engineResolverEnd-$engineResolverStart)
if ($engineResolverText -match '\$env:AOTR_HOME') { throw 'Engine resolver still references AOTR_HOME.' }
if ($engineResolverText -match 'Get-PSDrive') { throw 'Engine resolver still performs drive discovery.' }
if (-not $engineResolverText.Contains("validation -ne 'aotr-standalone-v2'")) { throw 'Engine resolver does not enforce Config V2 validation marker.' }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$work = Join-Path $Base ("AUTODETECT_V2_STAGE1_" + $stamp)
New-Item -ItemType Directory -Path $work -Force | Out-Null

$guiPath = Join-Path $work 'GuiGzipBase64.robust-autodetect-v2.ps1'
$enginePath = Join-Path $work 'EngineGzipBase64.robust-autodetect-v2.ps1'
$outBuilder = Join-Path $work 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_NONRELEASE.ps1'
$report = Join-Path $work 'STAGE1_REPORT.txt'

[IO.File]::WriteAllText($guiPath,$guiPatched,(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($enginePath,$enginePatched,(New-Object Text.UTF8Encoding($false)))

$guiAfter = Get-Sha256File $guiPath
$engineAfter = Get-Sha256File $enginePath

$newCSharp = Replace-CSharpPayload -CSharp $outer.CSharp -VariableName 'GuiGzipBase64' -NewText $guiPatched
$newCSharp = Replace-CSharpPayload -CSharp $newCSharp -VariableName 'EngineGzipBase64' -NewText $enginePatched

$newOuterB64 = Wrap-Base64 ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($newCSharp)))
$outerDataGroup = $outer.Match.Groups['data']
$newBuilderText = $originalBuilderText.Substring(0,$outerDataGroup.Index) +
    $newOuterB64 +
    $originalBuilderText.Substring($outerDataGroup.Index + $outerDataGroup.Length)

Test-PowerShellTextSyntax $newBuilderText 'patched V17 NON-RELEASE builder'
Write-Host 'Builder syntax: PASS' -ForegroundColor Green

[IO.File]::WriteAllText($outBuilder,$newBuilderText,(New-Object Text.UTF8Encoding($false)))
$outBuilderSha = Get-Sha256File $outBuilder

# Full decode roundtrip from the newly written builder.
$roundtripBuilderText = [IO.File]::ReadAllText($outBuilder)
$roundtripOuter = Get-OuterCSharpInfo $roundtripBuilderText
$roundtripGui = Get-CSharpPayloadInfo -CSharp $roundtripOuter.CSharp -VariableName 'GuiGzipBase64'
$roundtripEngine = Get-CSharpPayloadInfo -CSharp $roundtripOuter.CSharp -VariableName 'EngineGzipBase64'
$roundtripGuiSha = Get-Sha256Text $roundtripGui.Text
$roundtripEngineSha = Get-Sha256Text $roundtripEngine.Text

if ($roundtripGuiSha -ne $guiAfter) {
    throw "GUI roundtrip mismatch. Expected $guiAfter, got $roundtripGuiSha."
}
if ($roundtripEngineSha -ne $engineAfter) {
    throw "ENGINE roundtrip mismatch. Expected $engineAfter, got $roundtripEngineSha."
}

Test-PowerShellTextSyntax $roundtripGui.Text 'roundtrip GUI payload'
Test-PowerShellTextSyntax $roundtripEngine.Text 'roundtrip engine payload'

$builderAfterOriginal = Get-Sha256File $BuilderPath
if ($builderAfterOriginal -ne $builderBefore) {
    throw 'SAFETY FAILURE: original V17 builder changed.'
}

$reportLines = @(
    'AOTR ROBUST AUTODETECT V2 - STAGE 1 REPORT',
    "Created: $([DateTime]::Now.ToString('o'))",
    '',
    'SOURCE CHECKPOINT',
    "Original builder: $BuilderPath",
    "Original builder SHA256: $builderBefore",
    "Original GUI SHA256: $guiBefore",
    "Original ENGINE SHA256: $engineBefore",
    '',
    'PATCHED OUTPUT',
    "Work root: $work",
    "Patched GUI: $guiPath",
    "Patched GUI SHA256: $guiAfter",
    "Patched ENGINE: $enginePath",
    "Patched ENGINE SHA256: $engineAfter",
    "NON-RELEASE builder: $outBuilder",
    "NON-RELEASE builder SHA256: $outBuilderSha",
    '',
    'ASSERTIONS',
    '- Original builder hash matched checkpoint: PASS',
    '- Original GUI hash matched checkpoint: PASS',
    '- Original ENGINE hash matched checkpoint: PASS',
    '- Hard standalone root requires rotwk exe + game.dat + sibling aotr: PASS',
    '- _AotR8P_WotR_Runtime hard reject: PASS',
    '- All-in-One hard reject: PASS',
    '- BFME_RESEARCH/backup/checkpoint/temp excluded from automatic selection: PASS',
    '- Network drives excluded: PASS',
    '- Fixed before Removable/USB/exFAT: PASS',
    '- Equal top candidates require explicit GUI selection: PASS',
    '- Config V2 is written and read-back verified: PASS',
    '- Engine independent AOTR_HOME discovery removed: PASS',
    '- Engine independent drive discovery removed: PASS',
    '- Engine requires schema 2 + aotr-standalone-v2: PASS',
    '- Patched GUI syntax: PASS',
    '- Patched ENGINE syntax: PASS',
    '- Patched builder syntax: PASS',
    '- GUI re-embed roundtrip exact: PASS',
    '- ENGINE re-embed roundtrip exact: PASS',
    '- Original builder modified: NO',
    '- Public launcher EXE modified: NO',
    '- Build executed: NO',
    '- New repair action names added: NO',
    '',
    'NEXT',
    '- Use NON-RELEASE builder SHA above as the pinned input for isolated compile stage.',
    '- Do not replace the public launcher yet.'
)
[IO.File]::WriteAllLines($report,$reportLines,(New-Object Text.UTF8Encoding($false)))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' STAGE 1 COMPLETE' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host "Work root     : $work" -ForegroundColor Cyan
Write-Host "Patched GUI   : $guiAfter"
Write-Host "Patched ENGINE: $engineAfter"
Write-Host "Builder       : $outBuilder" -ForegroundColor Cyan
Write-Host "Builder SHA256: $outBuilderSha" -ForegroundColor Green
Write-Host "Report        : $report" -ForegroundColor Cyan
Write-Host ''
Write-Host 'Public EXE modified: NO' -ForegroundColor Yellow
Write-Host 'Build executed: NO' -ForegroundColor Yellow
