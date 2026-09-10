param(
    [string]$AotrResearch = 'C:\AOTR_RESEARCH',
    [string]$BfmeResearch = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-BfmeResearchRoot {
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Container)) {
            throw "Explicit BFME_RESEARCH path does not exist: $ExplicitPath"
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add('C:\BFME_RESEARCH')
    $candidates.Add('D:\BFME_RESEARCH')
    $candidates.Add('E:\BFME_RESEARCH')
    $candidates.Add((Join-Path $env:USERPROFILE 'BFME_RESEARCH'))
    $candidates.Add((Join-Path $env:USERPROFILE 'Desktop\BFME_RESEARCH'))
    $candidates.Add((Join-Path $env:USERPROFILE 'Documents\BFME_RESEARCH'))
    $candidates.Add((Join-Path $env:USERPROFILE 'Downloads\BFME_RESEARCH'))

    foreach ($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($drive.Root)) { continue }
        $candidates.Add((Join-Path $drive.Root 'BFME_RESEARCH'))
    }

    $hits = @($candidates | Select-Object -Unique | Where-Object {
        Test-Path -LiteralPath $_ -PathType Container
    } | ForEach-Object {
        (Resolve-Path -LiteralPath $_).Path
    } | Select-Object -Unique)

    if ($hits.Count -eq 1) { return $hits[0] }
    if ($hits.Count -gt 1) {
        Write-Host 'BFME_RESEARCH_AUTOSELECT=AMBIGUOUS' -ForegroundColor Yellow
        $hits | ForEach-Object { Write-Host ("  CANDIDATE={0}" -f $_) }
        throw 'Multiple BFME_RESEARCH roots found. Re-run with -BfmeResearch <exact path>.'
    }

    return $null
}

function Is-ProbablyTextFile {
    param([System.IO.FileInfo]$File)

    $allowed = @(
        '.md','.txt','.ps1','.psm1','.psd1','.py','.cs','.c','.cpp','.h','.hpp',
        '.json','.yml','.yaml','.ini','.cfg','.xml','.csv','.log','.asm','.inc',
        '.lst','.map','.sym','.disasm','.ghidra','.bat','.cmd','.toml','.properties'
    )

    if ($allowed -contains $File.Extension.ToLowerInvariant()) { return $true }
    if ($File.Length -gt 2MB) { return $false }

    try {
        $stream = [IO.File]::Open($File.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        try {
            $count = [Math]::Min(4096,[int]$stream.Length)
            if ($count -eq 0) { return $true }
            $buf = New-Object byte[] $count
            [void]$stream.Read($buf,0,$count)
            $nul = 0
            $ctrl = 0
            foreach ($b in $buf) {
                if ($b -eq 0) { $nul++; continue }
                if (($b -lt 9) -or (($b -gt 13) -and ($b -lt 32))) { $ctrl++ }
            }
            if ($nul -gt 0) { return $false }
            return (($ctrl / [double]$count) -lt 0.02)
        }
        finally { $stream.Dispose() }
    }
    catch { return $false }
}

$Out = Join-Path $AotrResearch 'ASTRA_CONTEXT'
$Zip = Join-Path $AotrResearch 'ASTRA_CONTEXT.zip'
$Docs = Join-Path $AotrResearch 'DOCS_FROM_GITHUB'
$Tools = Join-Path $AotrResearch 'TOOLS_FROM_GITHUB'
$Pr70 = Join-Path $AotrResearch '_RECOVERY\PR70'
$Manifest = Join-Path $AotrResearch '_RECOVERY\RECOVERY_MANIFEST.json'

if (-not (Test-Path -LiteralPath $AotrResearch -PathType Container)) { throw "AOTR_RESEARCH missing: $AotrResearch" }
if (-not (Test-Path -LiteralPath $Docs -PathType Container)) { throw "Recovered AotR docs missing: $Docs" }
if (-not (Test-Path -LiteralPath $Tools -PathType Container)) { throw "Recovered AotR tools missing: $Tools" }
if (-not (Test-Path -LiteralPath $Pr70 -PathType Container)) { throw "Recovered PR70 export missing: $Pr70" }

$ResolvedBfme = Resolve-BfmeResearchRoot -ExplicitPath $BfmeResearch

if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse -Force }
if (Test-Path -LiteralPath $Zip -PathType Leaf) { Remove-Item -LiteralPath $Zip -Force }
New-Item -ItemType Directory -Path $Out -Force | Out-Null

$AotrOut = Join-Path $Out 'AOTR'
$BfmeOut = Join-Path $Out 'BFME_RESEARCH_TEXT'
New-Item -ItemType Directory -Path $AotrOut,$BfmeOut -Force | Out-Null

Copy-Item -LiteralPath $Docs -Destination (Join-Path $AotrOut 'DOCS_FROM_GITHUB') -Recurse -Force
Copy-Item -LiteralPath $Tools -Destination (Join-Path $AotrOut 'TOOLS_FROM_GITHUB') -Recurse -Force
Copy-Item -LiteralPath $Pr70 -Destination (Join-Path $AotrOut 'PR70') -Recurse -Force
if (Test-Path -LiteralPath $Manifest -PathType Leaf) {
    Copy-Item -LiteralPath $Manifest -Destination (Join-Path $AotrOut 'RECOVERY_MANIFEST.json') -Force
}

$bfmeTotal = 0
$bfmeTotalBytes = [int64]0
$bfmeCopied = 0
$bfmeBytes = [int64]0
$fileIndex = New-Object System.Collections.Generic.List[object]
$textIndex = New-Object System.Collections.Generic.List[object]

if ($null -ne $ResolvedBfme) {
    $rootFull = $ResolvedBfme.TrimEnd('\')
    $allFiles = @(Get-ChildItem -LiteralPath $ResolvedBfme -File -Recurse -Force -ErrorAction SilentlyContinue)
    foreach ($f in $allFiles) {
        $bfmeTotal++
        $bfmeTotalBytes += [int64]$f.Length
        $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\')
        $hash = $null
        try { $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToUpperInvariant() } catch {}
        $isText = Is-ProbablyTextFile -File $f
        $fileIndex.Add([pscustomobject]@{
            RelativePath = $rel
            Length = [int64]$f.Length
            Extension = $f.Extension
            ProbablyText = $isText
            SHA256 = $hash
        })

        if (-not $isText) { continue }
        if ($f.Length -gt 20MB) { continue }
        $dest = Join-Path $BfmeOut $rel
        $parent = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        $textIndex.Add([pscustomobject]@{ RelativePath=$rel; Length=[int64]$f.Length; SHA256=$hash })
        $bfmeCopied++
        $bfmeBytes += [int64]$f.Length
    }
}

$fileIndex | Export-Csv -LiteralPath (Join-Path $Out 'BFME_FILE_INDEX.csv') -NoTypeInformation -Encoding UTF8
$textIndex | Export-Csv -LiteralPath (Join-Path $Out 'BFME_TEXT_INDEX.csv') -NoTypeInformation -Encoding UTF8

$handoff = @'
# Astra handoff — AotR 8P War of the Ring / OWN_MP

## Goal
Build the minimal robust architecture for 8-player LAN strategic War of the Ring using our own network/session logic while retaining the original AotR game engine, UI, LivingWorld and tactical battle systems wherever possible.

## Evidence policy
Treat labels conservatively:
- BEWIESEN = direct runtime/static/hash/packet proof.
- STARKER HINWEIS = multiple consistent indicators.
- HYPOTHESE = pending.
Do not replace runtime proof with inference. Do not direct-write unrelated globals. Prefer native engine lifecycle/functions and one-variable experiments.

## Proven core findings
- Engine/game structures process eight PlayerInfo/GameInfo rows.
- Network-human Type6 + endpoint can map through GameInfo local-slot resolution into LivingWorld creation logic for slots beyond P2.
- PlayerTemplate mismatch was the root cause of Component-A/B04 join rejection; canonical PlayerTemplate SHA256 is 2D162EE705DE9D96A7B65140C22EBA6EBD0B8F155AE062C97F9884E37DC59F4D.
- Canonical game.dat SHA256 for all current VAs/proofs is CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC.
- Native session join +0x40 path, C54 current GameInfo creation, frontend State8->State9 publication, DE892C=current, and postjoin 0x8472BF cleanup were reproduced.
- Normal native UI join and our controlled join path both reach the same territory-selection crash family: 0xC000001D / StackHash_19d4 / identical WER bucket. Therefore that crash is not evidence of a missing PoC join lifecycle.
- Current unresolved runtime gate is territory selection / crash capture, not basic native join publication.
- OWN_MP external network PoC already passed 3 endpoints with deterministic slot requests and JOIN -> ACCEPT -> START -> START_ACK -> START_COMMIT.

## Current architecture question
Find the smallest stable seam between OWN_MP and the game. Prefer an architecture where OWN_MP owns discovery, lobby, 8-slot identity, ready/start, host authority, command sequencing/ACK and OOS detection, while AotR owns GameInfo representation, local-slot/LivingWorld binding, strategic simulation/UI and tactical battles.

## What to analyze
1. Read PR70_TIMELINE.md first, then the reverse-engineering docs, then key tools only where needed.
2. Reconstruct the proven dependency graph from external OWN_MP slot map -> native GameInfo/PlayerInfo -> localSlot -> LivingWorld -> strategic command path.
3. Identify which native lobby/network pieces can be bypassed entirely after we materialize a canonical 8-slot game state.
4. Identify the minimal native function/object boundary needed to create/bind each client to its correct local strategic player without unstable raw pointer patching.
5. Propose the strategic command bridge: capture semantic commands, assign host sequence IDs, distribute/ACK, execute through the same native command path on every client, and add deterministic state/OOS hashes.
6. Separate territory-selection baseline bug from the network architecture. Do not let it force unrelated lifecycle changes.
7. Use BFME_RESEARCH_TEXT only as supporting engine-family evidence; distinguish BFME-derived inference from AotR-specific proof.

## Required output
Return:
- a layered target architecture;
- a table of proven seams vs unknowns;
- the 3 highest-value next probes, ranked by information gain/risk;
- exact hypothesis -> probe -> expected split for the single best next probe;
- what we can stop reverse-engineering because existing proof is already sufficient;
- risks that could still make 8P strategic sync impossible or expensive.

Do not propose broad reinstalls/syncs or speculative raw-memory patches. Preserve canonical hashes and the current proof chain.
'@
$handoff | Set-Content -LiteralPath (Join-Path $Out '00_ASTRA_HANDOFF.md') -Encoding UTF8

$summary = [ordered]@{
    created_at = (Get-Date).ToString('o')
    aotr_research = $AotrResearch
    bfme_research_resolved = $ResolvedBfme
    bfme_total_files = $bfmeTotal
    bfme_total_bytes = $bfmeTotalBytes
    bfme_text_files_copied = $bfmeCopied
    bfme_text_bytes_copied = $bfmeBytes
    canonical_game_dat_sha256 = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
    canonical_playertemplate_sha256 = '2D162EE705DE9D96A7B65140C22EBA6EBD0B8F155AE062C97F9884E37DC59F4D'
    research_baseline = 'f704fae949ccea70e2f80f87b8b9fe146b52404d'
    pr = 70
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Out 'CONTEXT_MANIFEST.json') -Encoding UTF8

# IMPORTANT: -Path, not -LiteralPath, because the wildcard must expand.
Compress-Archive -Path (Join-Path $Out '*') -DestinationPath $Zip -CompressionLevel Optimal -Force

if (-not (Test-Path -LiteralPath $Zip -PathType Leaf)) {
    throw "ZIP_CREATION_FAILED: $Zip was not created."
}
$zipItem = Get-Item -LiteralPath $Zip
if ($zipItem.Length -le 0) { throw 'ZIP_CREATION_FAILED: resulting ZIP is empty.' }
$zipHash = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash.ToUpperInvariant()

Write-Host '============================================================'
Write-Host ' ASTRA CONTEXT PACK V2'
Write-Host '============================================================'
Write-Host ("AOTR_CONTEXT_DIR={0}" -f $Out)
Write-Host ("BFME_RESEARCH_RESOLVED={0}" -f ($(if($null -eq $ResolvedBfme){'NOT_FOUND'}else{$ResolvedBfme})))
Write-Host ("BFME_TOTAL_FILES={0}" -f $bfmeTotal)
Write-Host ("BFME_TOTAL_BYTES={0}" -f $bfmeTotalBytes)
Write-Host ("BFME_TEXT_FILES={0}" -f $bfmeCopied)
Write-Host ("BFME_TEXT_BYTES={0}" -f $bfmeBytes)
Write-Host ("ZIP={0}" -f $Zip)
Write-Host ("ZIP_SIZE={0}" -f $zipItem.Length)
Write-Host ("ZIP_SHA256={0}" -f $zipHash)
Write-Host 'BFME_RESEARCH_MODIFIED=NO'
if ($null -eq $ResolvedBfme) {
    Write-Host 'RESULT=PASS_ASTRA_CONTEXT_READY_WITHOUT_BFME' -ForegroundColor Yellow
    Write-Host 'ACTION=BFME_RESEARCH was not found at known locations. Re-run with -BfmeResearch <exact path> if it is stored elsewhere.' -ForegroundColor Yellow
} else {
    Write-Host 'RESULT=PASS_ASTRA_CONTEXT_READY' -ForegroundColor Green
}
