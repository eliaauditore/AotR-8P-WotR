#requires -version 7.0
[CmdletBinding()]
param(
    [string]$Base = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD',
    [string]$BuilderPath = 'D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE1_20260827_022948\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10_ROBUST_AUTODETECT_V2_NONRELEASE.ps1',
    [string]$ExpectedAotRRoot = 'D:\Games\AotR\AgeoftheRing'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBuilderSha256 = 'D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0'
$ExpectedGuiSha256 = 'CFAF397833536769D726B0DD0960D940AAA6896ED62BFEFA0764185C2CEA90DC'
$ExpectedEngineSha256 = '94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA'
$ExpectedValidation = 'aotr-standalone-v2'

function Get-Sha256File([string]$Path) {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Get-Sha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Get-Utf8Text([byte[]]$Bytes) {
    $offset = 0
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { $offset = 3 }
    return [Text.UTF8Encoding]::new($false,$true).GetString($Bytes,$offset,$Bytes.Length-$offset)
}

function Expand-GzipBase64Bytes([string]$Base64) {
    $compressed = [Convert]::FromBase64String(($Base64 -replace '\s',''))
    $input = [IO.MemoryStream]::new($compressed)
    try {
        $gzip = [IO.Compression.GZipStream]::new($input,[IO.Compression.CompressionMode]::Decompress)
        try {
            $output = [IO.MemoryStream]::new()
            try { $gzip.CopyTo($output); return $output.ToArray() }
            finally { $output.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally { $input.Dispose() }
}

function Get-OuterCSharp([string]$BuilderText) {
    $pattern = '(?s)\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\s*(?<data>[A-Za-z0-9+/=\r\n]+?)\s*''@\)\)'
    $m = [regex]::Match($BuilderText,$pattern)
    if (-not $m.Success) { throw 'Could not locate outer C# template.' }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($m.Groups['data'].Value -replace '\s','')))
}

function Get-Payload([string]$CSharp,[string]$Name) {
    $pattern = '(?s)(?:private\s+)?const\s+string\s+' + [regex]::Escape($Name) + '\s*=\s*@"(?<data>[A-Za-z0-9+/=\r\n]+)"\s*;'
    $m = [regex]::Match($CSharp,$pattern)
    if (-not $m.Success) { throw "Could not locate payload $Name." }
    $bytes = Expand-GzipBase64Bytes $m.Groups['data'].Value
    return [PSCustomObject]@{ Bytes=$bytes; Text=(Get-Utf8Text $bytes); Sha256=(Get-Sha256Bytes $bytes) }
}

function Test-PowerShellText([string]$Text,[string]$Label) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) {
        $msg = ($errors | ForEach-Object { "Line $($_.Extent.StartLineNumber), Col $($_.Extent.StartColumnNumber): $($_.Message)" }) -join [Environment]::NewLine
        throw "Parser failure for $Label`n$msg"
    }
}

function Canon([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function New-EmptyFile([string]$Path) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($Path,[byte[]](0x00))
}

function New-SyntheticAotR {
    param(
        [string]$Root,
        [switch]$MissingAotr,
        [switch]$MissingExe,
        [switch]$MissingGameDat,
        [switch]$UseZGameDat,
        [switch]$FullMarkers
    )

    if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $runtime = Join-Path $Root 'rotwk'
    New-Item -ItemType Directory -Force -Path $runtime | Out-Null

    if (-not $MissingExe) { New-EmptyFile (Join-Path $runtime 'lotrbfme2ep1.exe') }
    if (-not $MissingGameDat) {
        if ($UseZGameDat) { New-EmptyFile (Join-Path $runtime 'zGameDats\game.dat') }
        else { New-EmptyFile (Join-Path $runtime 'game.dat') }
    }

    if (-not $MissingAotr) {
        $aotr = Join-Path $Root 'aotr'
        New-Item -ItemType Directory -Force -Path $aotr | Out-Null
        if ($FullMarkers) {
            New-EmptyFile (Join-Path $Root 'AotR_Launcher.exe')
            New-Item -ItemType Directory -Force -Path (Join-Path $aotr 'data\ini') | Out-Null
            New-EmptyFile (Join-Path $aotr 'Changelist.txt')
        }
    }

    return (Canon $Root)
}

$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Case,[bool]$Pass,[string]$Detail) {
    [void]$results.Add([PSCustomObject]@{ Case=$Case; Pass=$Pass; Detail=$Detail })
    $color = if ($Pass) { 'Green' } else { 'Red' }
    Write-Host ('[{0}] {1} -- {2}' -f ($(if ($Pass) {'PASS'} else {'FAIL'})),$Case,$Detail) -ForegroundColor $color
}

function Expect-True([string]$Case,[bool]$Condition,[string]$Detail) {
    Add-Result $Case $Condition $Detail
}

if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw "Base missing: $Base" }
if (-not (Test-Path -LiteralPath $BuilderPath -PathType Leaf)) { throw "Builder missing: $BuilderPath" }
$builderSha = Get-Sha256File $BuilderPath
if ($builderSha -ne $ExpectedBuilderSha256) { throw "Builder hash mismatch. Expected $ExpectedBuilderSha256, got $builderSha" }

$builderText = Get-Utf8Text ([IO.File]::ReadAllBytes($BuilderPath))
$csharp = Get-OuterCSharp $builderText
$gui = Get-Payload $csharp 'GuiGzipBase64'
$engine = Get-Payload $csharp 'EngineGzipBase64'
if ($gui.Sha256 -ne $ExpectedGuiSha256) { throw "GUI hash mismatch. Expected $ExpectedGuiSha256, got $($gui.Sha256)" }
if ($engine.Sha256 -ne $ExpectedEngineSha256) { throw "ENGINE hash mismatch. Expected $ExpectedEngineSha256, got $($engine.Sha256)" }

$startMarker = 'function Get-CanonicalAotRPath([string]$Path) {'
$endMarker = '$Install = Resolve-AotRInstall -PromptIfMissing'
$start = $gui.Text.IndexOf($startMarker,[StringComparison]::Ordinal)
$end = $gui.Text.IndexOf($endMarker,$start,[StringComparison]::Ordinal)
if ($start -lt 0 -or $end -le $start) { throw 'Could not isolate current GUI resolver source.' }
$resolverText = $gui.Text.Substring($start,$end-$start)
Test-PowerShellText $resolverText 'current V18 GUI resolver'

if ($resolverText -notmatch "A8P-INSTALL-007") { throw 'Current resolver lacks A8P-INSTALL-007 marker.' }
if ($resolverText -notmatch "Sort-Object @{Expression='Score';Descending=\$true},Root") { throw 'Current resolver lacks expected score-first ranking.' }
if ($resolverText -notmatch '\$top\.Count -eq 1') { throw 'Current resolver lacks unique-top branch.' }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $Base ("AUTODETECT_V2_V18_STAGE4_MATRIX_" + $stamp)
$reportPath = Join-Path $workRoot 'V18_STAGE4_AUTODETECT_MATRIX_CORE_REPORT.txt'
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

$matrixRoot = Join-Path $env:LOCALAPPDATA ("A8P_AUTODETECT_MATRIX_" + [Guid]::NewGuid().ToString('N'))
$matrixState = Join-Path $matrixRoot 'STATE'
New-Item -ItemType Directory -Force -Path $matrixState | Out-Null

$realConfig = Join-Path $env:LOCALAPPDATA 'AotR 8P WotR Mod\launcher_config.json'
$realConfigExisted = Test-Path -LiteralPath $realConfig -PathType Leaf
$realConfigHashBefore = if ($realConfigExisted) { Get-Sha256File $realConfig } else { '' }
$oldAotrHomeExists = Test-Path Env:AOTR_HOME
$oldAotrHome = if ($oldAotrHomeExists) { $env:AOTR_HOME } else { $null }

try {
    $stateRoot = $matrixState
    $ConfigPath = Join-Path $stateRoot 'launcher_config.json'
    $script:LastErrorCode = ''
    $script:LastErrorDetail = ''

    # Load EXACT resolver functions from the current hash-pinned V18 GUI.
    . ([ScriptBlock]::Create($resolverText))

    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' AOTR 8P V18 STAGE 4 - AUTODETECT CORE MATRIX' -ForegroundColor Cyan
    Write-Host ' EXACT CURRENT RESOLVER / SYNTHETIC + ISOLATED LIVE CACHE' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host "Builder SHA : $builderSha"
    Write-Host "GUI SHA     : $($gui.Sha256)"
    Write-Host "ENGINE SHA  : $($engine.Sha256)"
    Write-Host "Matrix root : $matrixRoot"
    Write-Host ''

    # 1. Full canonical root should score 120.
    $fullRoot = New-SyntheticAotR (Join-Path $matrixRoot 'Full\AgeoftheRing') -FullMarkers
    $full = Test-AotRStandaloneRoot $fullRoot
    Expect-True 'full canonical root hard-valid' ([bool]($full -and $full.HardValid)) ("score=" + [string]$full.Score)
    Expect-True 'full canonical root auto-eligible' ([bool]($full -and $full.AutoEligible)) ("root=" + [string]$full.Root)
    Expect-True 'full canonical root score 120' ([bool]($full -and [int]$full.Score -eq 120)) ("score=" + [string]$full.Score)

    # 2. Minimal valid root should score 95.
    $minimalRoot = New-SyntheticAotR (Join-Path $matrixRoot 'Minimal\AgeoftheRing')
    $minimal = Test-AotRStandaloneRoot $minimalRoot
    Expect-True 'minimal standalone valid' ([bool]($minimal -and $minimal.HardValid)) ("score=" + [string]$minimal.Score)
    Expect-True 'minimal standalone score 95' ([bool]($minimal -and [int]$minimal.Score -eq 95)) ("score=" + [string]$minimal.Score)

    # 3. zGameDats layout accepted.
    $zRoot = New-SyntheticAotR (Join-Path $matrixRoot 'ZGame\AgeoftheRing') -UseZGameDat
    $z = Test-AotRStandaloneRoot $zRoot
    Expect-True 'zGameDats game.dat accepted' ([bool]($z -and $z.HardValid -and ([string]$z.GameDat -match '(?i)zGameDats\\game\.dat$'))) ([string]$z.GameDat)

    # 4-6. Manual path normalization from runtime/aotr/parent.
    $fromRuntime = Get-AotRInstallFromPath (Join-Path $fullRoot 'rotwk')
    Expect-True 'runtime directory resolves canonical root' ([bool]($fromRuntime -and (Canon $fromRuntime.Root) -eq $fullRoot)) ([string]$fromRuntime.Root)
    $fromAotr = Get-AotRInstallFromPath (Join-Path $fullRoot 'aotr')
    Expect-True 'aotr directory resolves canonical root' ([bool]($fromAotr -and (Canon $fromAotr.Root) -eq $fullRoot)) ([string]$fromAotr.Root)
    $parentOfFull = Split-Path $fullRoot -Parent
    $fromParent = Get-AotRInstallFromPath $parentOfFull
    Expect-True 'parent folder resolves AgeoftheRing child' ([bool]($fromParent -and (Canon $fromParent.Root) -eq $fullRoot)) ([string]$fromParent.Root)

    # 7. German-style parent naming still resolves by structure.
    $germanRoot = New-SyntheticAotR (Join-Path $matrixRoot 'Spiele\AotR\AgeoftheRing') -FullMarkers
    $germanFromParent = Get-AotRInstallFromPath (Split-Path $germanRoot -Parent)
    Expect-True 'German-style Spiele/AotR parent resolves' ([bool]($germanFromParent -and (Canon $germanFromParent.Root) -eq $germanRoot)) ([string]$germanFromParent.Root)

    # 8. Plain RotWK without sibling aotr must never count.
    $plainRoot = New-SyntheticAotR (Join-Path $matrixRoot 'PlainRotWK\AgeoftheRing') -MissingAotr
    $plainFromRuntime = Get-AotRInstallFromPath (Join-Path $plainRoot 'rotwk')
    Expect-True 'plain RotWK without aotr rejected' ([bool]($null -eq $plainFromRuntime)) 'expected null'

    # 9-11. Missing hard requirements.
    $missingAotrRoot = New-SyntheticAotR (Join-Path $matrixRoot 'MissingAotr\AgeoftheRing') -MissingAotr
    $missingAotr = Test-AotRStandaloneRoot $missingAotrRoot
    Expect-True 'missing aotr hard-invalid' ([bool]($missingAotr -and -not $missingAotr.HardValid -and (@($missingAotr.Missing) -contains 'aotr\'))) ((@($missingAotr.Missing) -join ', '))

    $missingExeRoot = New-SyntheticAotR (Join-Path $matrixRoot 'MissingExe\AgeoftheRing') -MissingExe
    $missingExe = Test-AotRStandaloneRoot $missingExeRoot
    Expect-True 'missing exe hard-invalid' ([bool]($missingExe -and -not $missingExe.HardValid -and (@($missingExe.Missing) -contains 'rotwk\lotrbfme2ep1.exe'))) ((@($missingExe.Missing) -join ', '))

    $missingGameRoot = New-SyntheticAotR (Join-Path $matrixRoot 'MissingGame\AgeoftheRing') -MissingGameDat
    $missingGame = Test-AotRStandaloneRoot $missingGameRoot
    Expect-True 'missing game.dat hard-invalid' ([bool]($missingGame -and -not $missingGame.HardValid -and (@($missingGame.Missing) -contains 'rotwk\game.dat or rotwk\zGameDats\game.dat'))) ((@($missingGame.Missing) -join ', '))

    # 12. Runtime copy must be hard rejected even if structurally valid.
    $runtimeCopyRoot = New-SyntheticAotR (Join-Path $matrixRoot 'AotR8P_WotR_Runtime_MATRIX') -FullMarkers
    $runtimeCopy = Test-AotRStandaloneRoot $runtimeCopyRoot
    Expect-True '8P runtime copy hard-rejected' ([bool]($runtimeCopy -and $runtimeCopy.HardValid -and $runtimeCopy.HardReject -and -not $runtimeCopy.AutoEligible)) ((@($runtimeCopy.Classification) -join ', '))

    # 13. All-in-One path hard rejection is structural policy only; no All-in-One discovery is performed.
    $aioRoot = New-SyntheticAotR (Join-Path $matrixRoot 'All-in-One\AgeoftheRing') -FullMarkers
    $aio = Test-AotRStandaloneRoot $aioRoot
    Expect-True 'All-in-One path hard-rejected' ([bool]($aio -and $aio.HardValid -and $aio.HardReject -and -not $aio.AutoEligible)) ((@($aio.Classification) -join ', '))

    # 14-17. Research/backup/checkpoint/temp are never auto-preferred.
    $researchClass = Get-AotRPathClassification 'D:\BFME_RESEARCH\candidate\AgeoftheRing'
    Expect-True 'BFME_RESEARCH not auto-eligible' ([bool](-not $researchClass.AutoEligible -and [int]$researchClass.Penalty -le -80)) ((@($researchClass.Reasons) -join ', '))
    $backupClass = Get-AotRPathClassification 'D:\Games\backup_2026\AgeoftheRing'
    Expect-True 'backup path not auto-eligible' ([bool](-not $backupClass.AutoEligible)) ((@($backupClass.Reasons) -join ', '))
    $checkpointClass = Get-AotRPathClassification 'D:\Games\checkpoint_42\AgeoftheRing'
    Expect-True 'checkpoint path not auto-eligible' ([bool](-not $checkpointClass.AutoEligible)) ((@($checkpointClass.Reasons) -join ', '))
    $tempClass = Get-AotRPathClassification 'D:\temp\AgeoftheRing'
    Expect-True 'temp path not auto-eligible' ([bool](-not $tempClass.AutoEligible)) ((@($tempClass.Reasons) -join ', '))

    # 18. Canonical dedupe: same root discovered from root/runtime/aotr remains one candidate.
    $map = @{}
    Add-AotRCandidate -Map $map -Path $fullRoot -Origin 'root'
    Add-AotRCandidate -Map $map -Path (Join-Path $fullRoot 'rotwk') -Origin 'runtime'
    Add-AotRCandidate -Map $map -Path (Join-Path $fullRoot 'aotr') -Origin 'aotr'
    $dedupeEntry = @($map.Values | Select-Object -First 1)
    $originCount = if ($dedupeEntry.Count -eq 1) { @($dedupeEntry[0].Origins).Count } else { 0 }
    Expect-True 'candidate canonical dedupe' ([bool]($map.Count -eq 1 -and $originCount -eq 3)) ("map=" + $map.Count + ', origins=' + $originCount)

    # 19. Score/rank: full 120 beats minimal 95.
    $ranked = @($full,$minimal | Sort-Object @{Expression='Score';Descending=$true},Root)
    Expect-True 'higher score wins ranking' ([bool]($ranked.Count -eq 2 -and [int]$ranked[0].Score -eq 120 -and (Canon $ranked[0].Root) -eq $fullRoot)) ("top=" + [string]$ranked[0].Root + ', score=' + [string]$ranked[0].Score)

    # 20. Equal top scores remain a tie (resolver source has a distinct unique-top branch).
    $tieRoot = New-SyntheticAotR (Join-Path $matrixRoot 'Tie\AgeoftheRing') -FullMarkers
    $tie = Test-AotRStandaloneRoot $tieRoot
    $tieRanked = @($full,$tie | Sort-Object @{Expression='Score';Descending=$true},Root)
    $topScore = [int]$tieRanked[0].Score
    $tops = @($tieRanked | Where-Object { [int]$_.Score -eq $topScore })
    Expect-True 'equal top candidates remain explicit tie' ([bool]($tops.Count -eq 2 -and $topScore -eq 120)) ("topCount=" + $tops.Count + ', score=' + $topScore)

    # Remove synthetic candidates before the live stale-cache test so they cannot interfere with drive discovery.
    $keepState = $matrixState
    Get-ChildItem -LiteralPath $matrixRoot -Force | Where-Object { $_.FullName -ne $keepState } | Remove-Item -Recurse -Force

    # 21. Cached path moved/disappeared: stale Config V2 must be revalidated, rediscovered, and rewritten.
    Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue
    $staleRoot = 'Z:\THIS_INSTALL_MOVED_AND_DOES_NOT_EXIST\AgeoftheRing'
    $staleConfig = [PSCustomObject]@{
        schema = 2
        aotr_root = $staleRoot
        runtime = (Join-Path $staleRoot 'rotwk')
        source_mod = (Join-Path $staleRoot 'aotr')
        game_dat = (Join-Path $staleRoot 'rotwk\game.dat')
        validation = $ExpectedValidation
        score = 120
        last_verified_utc = [DateTime]::UtcNow.AddDays(-1).ToString('o')
    }
    $staleConfig | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
    $script:LastErrorCode = ''
    $script:LastErrorDetail = ''

    $resolvedAfterMove = Resolve-AotRInstall
    $rewritten = if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) { Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json } else { $null }
    $expectedReal = Canon $ExpectedAotRRoot
    $cacheRecovered = (
        $resolvedAfterMove -and
        (Canon ([string]$resolvedAfterMove.Root)) -eq $expectedReal -and
        $rewritten -and
        [int]$rewritten.schema -eq 2 -and
        [string]$rewritten.validation -eq $ExpectedValidation -and
        (Canon ([string]$rewritten.aotr_root)) -eq $expectedReal
    )
    Expect-True 'stale/moved Config V2 rediscovered and rewritten' ([bool]$cacheRecovered) ("resolved=" + [string]$resolvedAfterMove.Root + ', errorCode=' + [string]$script:LastErrorCode)
    Expect-True 'A8P-INSTALL-007 path exists in current resolver' ([bool]($resolverText -match 'A8P-INSTALL-007')) 'source marker present'

    # 22. Engine must remain config-consumer only.
    $engineResolverStart = $engine.Text.IndexOf('function Resolve-AotRInstall {',[StringComparison]::Ordinal)
    $engineResolverEnd = $engine.Text.IndexOf('function New-LinkedFile([string]$Source, [string]$Destination) {',$engineResolverStart,[StringComparison]::Ordinal)
    $engineResolver = if ($engineResolverStart -ge 0 -and $engineResolverEnd -gt $engineResolverStart) { $engine.Text.Substring($engineResolverStart,$engineResolverEnd-$engineResolverStart) } else { '' }
    Expect-True 'engine has no independent AOTR_HOME discovery' ([bool]($engineResolver -and $engineResolver -notmatch '\$env:AOTR_HOME')) 'engine resolver source checked'
    Expect-True 'engine has no independent drive discovery' ([bool]($engineResolver -and $engineResolver -notmatch 'Get-PSDrive|DriveInfo]::GetDrives')) 'engine resolver source checked'
    Expect-True 'engine enforces Config V2 marker' ([bool]($engineResolver -and $engineResolver -match "aotr-standalone-v2")) 'engine resolver source checked'
}
finally {
    if ($oldAotrHomeExists) { $env:AOTR_HOME = $oldAotrHome }
    else { Remove-Item Env:AOTR_HOME -ErrorAction SilentlyContinue }

    # Verify real user config was never touched by this matrix runner.
    $realConfigHashAfter = if ($realConfigExisted -and (Test-Path -LiteralPath $realConfig -PathType Leaf)) { Get-Sha256File $realConfig } else { '' }
    $realConfigUnchanged = if ($realConfigExisted) { $realConfigHashBefore -eq $realConfigHashAfter } else { -not (Test-Path -LiteralPath $realConfig -PathType Leaf) }
    Add-Result 'real launcher config unchanged' ([bool]$realConfigUnchanged) (if ($realConfigExisted) { 'hash before/after compared' } else { 'remained absent' })

    if (Test-Path -LiteralPath $matrixRoot) { Remove-Item -LiteralPath $matrixRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

$failures = @($results | Where-Object { -not $_.Pass })
$reportLines = New-Object System.Collections.Generic.List[string]
[void]$reportLines.Add('AOTR 8P V18 STAGE4 AUTODETECT CORE MATRIX')
[void]$reportLines.Add('Generated UTC: ' + [DateTime]::UtcNow.ToString('o'))
[void]$reportLines.Add('Builder SHA256: ' + $builderSha)
[void]$reportLines.Add('GUI SHA256: ' + $gui.Sha256)
[void]$reportLines.Add('ENGINE SHA256: ' + $engine.Sha256)
[void]$reportLines.Add('Expected real AotR root: ' + (Canon $ExpectedAotRRoot))
[void]$reportLines.Add('Total cases: ' + $results.Count)
[void]$reportLines.Add('Failures: ' + $failures.Count)
[void]$reportLines.Add('')
foreach ($r in $results) {
    [void]$reportLines.Add(('[{0}] {1} -- {2}' -f ($(if ($r.Pass) {'PASS'} else {'FAIL'})),$r.Case,$r.Detail))
}
[void]$reportLines.Add('')
[void]$reportLines.Add('PENDING OUTSIDE CORE MATRIX')
[void]$reportLines.Add('- Actual removable/USB/exFAT drive ordering on physical media')
[void]$reportLines.Add('- Explicit no-write-rights filesystem test')
[void]$reportLines.Add('- Full launcher UI tie-picker interaction with two physical/real installs')
[void]$reportLines.Add('- Full launcher test from Downloads and from inside AotR path')
[void]$reportLines.Add('- Unsupported-version A8P-INSTALL-005 remains intentionally unimplemented without source proof')
[IO.File]::WriteAllLines($reportPath,$reportLines,[Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' V18 STAGE 4 CORE MATRIX RESULT' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Cases   : $($results.Count)"
Write-Host "Failures: $($failures.Count)"
Write-Host "Report  : $reportPath"
Write-Host ''

if ($failures.Count -gt 0) {
    Write-Host 'CORE MATRIX: FAIL' -ForegroundColor Red
    foreach ($f in $failures) { Write-Host ('  - ' + $f.Case + ': ' + $f.Detail) -ForegroundColor Red }
    exit 4
}

Write-Host 'CORE MATRIX: PASS' -ForegroundColor Green
Write-Host 'No release, game, or real launcher-config file was modified.' -ForegroundColor Green
