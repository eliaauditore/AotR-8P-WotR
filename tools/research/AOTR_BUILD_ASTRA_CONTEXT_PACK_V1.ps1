param(
    [string]$AotrResearch = 'C:\AOTR_RESEARCH',
    [string]$BfmeResearch = 'C:\BFME_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse -Force }
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

$bfmeCopied = 0
$bfmeBytes = [int64]0
$allowed = @('.md','.txt','.ps1','.psm1','.psd1','.py','.cs','.c','.cpp','.h','.hpp','.json','.yml','.yaml','.ini','.cfg','.xml','.csv','.log','.asm','.inc')
$index = New-Object System.Collections.Generic.List[object]

if (Test-Path -LiteralPath $BfmeResearch -PathType Container) {
    $rootFull = (Resolve-Path -LiteralPath $BfmeResearch).Path.TrimEnd('\\')
    Get-ChildItem -LiteralPath $BfmeResearch -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        if ($allowed -notcontains $_.Extension.ToLowerInvariant()) { return }
        if ($_.Length -gt 20MB) { return }
        $rel = $_.FullName.Substring($rootFull.Length).TrimStart('\\')
        $dest = Join-Path $BfmeOut $rel
        $parent = Split-Path -Parent $dest
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
        $index.Add([pscustomobject]@{ RelativePath=$rel; Length=[int64]$_.Length; SHA256=$hash })
        $script:bfmeCopied++
        $script:bfmeBytes += [int64]$_.Length
    }
}

$index | Export-Csv -LiteralPath (Join-Path $Out 'BFME_TEXT_INDEX.csv') -NoTypeInformation -Encoding UTF8

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
    bfme_research = $BfmeResearch
    bfme_text_files_copied = $bfmeCopied
    bfme_text_bytes_copied = $bfmeBytes
    canonical_game_dat_sha256 = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
    canonical_playertemplate_sha256 = '2D162EE705DE9D96A7B65140C22EBA6EBD0B8F155AE062C97F9884E37DC59F4D'
    research_baseline = 'f704fae949ccea70e2f80f87b8b9fe146b52404d'
    pr = 70
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Out 'CONTEXT_MANIFEST.json') -Encoding UTF8

if (Test-Path -LiteralPath $Zip -PathType Leaf) { Remove-Item -LiteralPath $Zip -Force }
Compress-Archive -LiteralPath (Join-Path $Out '*') -DestinationPath $Zip -CompressionLevel Optimal

Write-Host '============================================================'
Write-Host ' ASTRA CONTEXT PACK V1'
Write-Host '============================================================'
Write-Host ("AOTR_CONTEXT_DIR={0}" -f $Out)
Write-Host ("BFME_TEXT_FILES={0}" -f $bfmeCopied)
Write-Host ("BFME_TEXT_BYTES={0}" -f $bfmeBytes)
Write-Host ("ZIP={0}" -f $Zip)
Write-Host ("ZIP_SIZE={0}" -f (Get-Item -LiteralPath $Zip).Length)
Write-Host ("ZIP_SHA256={0}" -f (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash.ToUpperInvariant())
Write-Host 'BFME_RESEARCH_MODIFIED=NO'
Write-Host 'RESULT=PASS_ASTRA_CONTEXT_READY' -ForegroundColor Green
