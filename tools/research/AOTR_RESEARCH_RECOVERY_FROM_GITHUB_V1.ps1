param(
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH',
    [string]$BfmeResearchRoot = 'C:\BFME_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoOwner = 'eliaauditore'
$RepoName  = 'AotR-8P-WotR'
$ResearchRef = 'f704fae949ccea70e2f80f87b8b9fe146b52404d'
$PrNumber = 70

$ExpectedGameDatSha256 = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ExpectedPlayerTemplateSha256 = '2D162EE705DE9D96A7B65140C22EBA6EBD0B8F155AE062C97F9884E37DC59F4D'

$RecoveryRoot = Join-Path $ResearchRoot '_RECOVERY'
$SnapshotRoot = Join-Path $RecoveryRoot '_GITHUB_SNAPSHOT'
$SnapshotDir  = Join-Path $SnapshotRoot $ResearchRef
$PrRoot       = Join-Path $RecoveryRoot 'PR70'
$ToolsMirror  = Join-Path $ResearchRoot 'TOOLS_FROM_GITHUB'
$DocsMirror   = Join-Path $ResearchRoot 'DOCS_FROM_GITHUB'
$ConflictDir  = Join-Path $RecoveryRoot 'RECOVERY_CONFLICTS'
$ZipPath      = Join-Path $RecoveryRoot ("AotR-8P-WotR_{0}.zip" -f $ResearchRef)
$ManifestPath = Join-Path $RecoveryRoot 'RECOVERY_MANIFEST.json'

$Headers = @{ 'User-Agent' = 'AOTR-Research-Recovery-V1' }

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-GitHubPaged([string]$BaseUrl) {
    $all = @()
    for ($page = 1; $page -le 50; $page++) {
        $sep = if ($BaseUrl.Contains('?')) { '&' } else { '?' }
        $url = "{0}{1}per_page=100&page={2}" -f $BaseUrl,$sep,$page
        $batch = @(Invoke-RestMethod -UseBasicParsing -Headers $Headers -Uri $url -Method Get)
        if ($batch.Count -eq 0) { break }
        $all += $batch
        if ($batch.Count -lt 100) { break }
    }
    return @($all)
}

function Copy-WorkingToolSafely([System.IO.FileInfo]$Source) {
    $dest = Join-Path $ResearchRoot $Source.Name
    if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) {
        Copy-Item -LiteralPath $Source.FullName -Destination $dest
        return 'COPIED_MISSING'
    }

    $srcHash = (Get-FileHash -LiteralPath $Source.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
    $dstHash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($srcHash -eq $dstHash) {
        return 'ALREADY_IDENTICAL'
    }

    Ensure-Directory $ConflictDir
    $conflictName = '{0}.github_{1}' -f $Source.Name,$ResearchRef.Substring(0,12)
    Copy-Item -LiteralPath $Source.FullName -Destination (Join-Path $ConflictDir $conflictName) -Force
    return 'LOCAL_DIFF_PRESERVED'
}

Write-Host '============================================================'
Write-Host ' AOTR RESEARCH RECOVERY FROM GITHUB V1'
Write-Host '============================================================'
Write-Host ("Research root : {0}" -f $ResearchRoot)
Write-Host ("Pinned ref    : {0}" -f $ResearchRef)
Write-Host ("PR            : #{0}" -f $PrNumber)
Write-Host 'POLICY        : BFME_RESEARCH IS NEVER MODIFIED'
Write-Host ''

if (Test-Path -LiteralPath $BfmeResearchRoot -PathType Container) {
    Write-Host ("BFME_RESEARCH_STATUS=PRESENT path={0}" -f $BfmeResearchRoot) -ForegroundColor Green
} else {
    Write-Host ("BFME_RESEARCH_STATUS=NOT_FOUND path={0}" -f $BfmeResearchRoot) -ForegroundColor Yellow
}

Ensure-Directory $ResearchRoot
Ensure-Directory $RecoveryRoot
Ensure-Directory $SnapshotRoot
Ensure-Directory $PrRoot
Ensure-Directory $ToolsMirror
Ensure-Directory $DocsMirror
Ensure-Directory $ConflictDir
Ensure-Directory (Join-Path $ResearchRoot 'RUNS')
Ensure-Directory (Join-Path $ResearchRoot 'LOCALDUMPS')
Ensure-Directory (Join-Path $ResearchRoot 'WER_SALVAGED_DUMPS')

# Pin TLS 1.2 for older Windows PowerShell 5.1 environments.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$archiveUrl = "https://github.com/$RepoOwner/$RepoName/archive/$ResearchRef.zip"
$zipHash = $null

if (-not (Test-Path -LiteralPath (Join-Path $SnapshotDir 'tools\research') -PathType Container) -or
    -not (Test-Path -LiteralPath (Join-Path $SnapshotDir 'docs\reverse-engineering') -PathType Container)) {

    Write-Host 'SNAPSHOT_PRESENT=NO - downloading exact pinned repository archive...'
    if (Test-Path -LiteralPath $ZipPath -PathType Leaf) { Remove-Item -LiteralPath $ZipPath -Force }
    Invoke-WebRequest -UseBasicParsing -Headers $Headers -Uri $archiveUrl -OutFile $ZipPath

    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf) -or (Get-Item -LiteralPath $ZipPath).Length -lt 10000) {
        throw 'Repository archive download failed or is implausibly small.'
    }

    $zipHash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToUpperInvariant()
    $extractTemp = Join-Path $RecoveryRoot ('_extract_' + [guid]::NewGuid().ToString('N'))
    Ensure-Directory $extractTemp
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractTemp -Force

    $top = @(Get-ChildItem -LiteralPath $extractTemp -Directory)
    if ($top.Count -ne 1) {
        throw "Expected exactly one top-level repository directory in archive, found $($top.Count)."
    }

    if (Test-Path -LiteralPath $SnapshotDir) { Remove-Item -LiteralPath $SnapshotDir -Recurse -Force }
    Move-Item -LiteralPath $top[0].FullName -Destination $SnapshotDir
    Remove-Item -LiteralPath $extractTemp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'SNAPSHOT_RECOVERY_PASS' -ForegroundColor Green
} else {
    Write-Host 'SNAPSHOT_PRESENT=YES - reusing exact pinned snapshot.' -ForegroundColor Green
    if (Test-Path -LiteralPath $ZipPath -PathType Leaf) {
        $zipHash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToUpperInvariant()
    }
}

$SnapshotTools = Join-Path $SnapshotDir 'tools\research'
$SnapshotDocs  = Join-Path $SnapshotDir 'docs\reverse-engineering'
if (-not (Test-Path -LiteralPath $SnapshotTools -PathType Container)) { throw 'Recovered snapshot is missing tools/research.' }
if (-not (Test-Path -LiteralPath $SnapshotDocs -PathType Container))  { throw 'Recovered snapshot is missing docs/reverse-engineering.' }

# Dedicated immutable-ish mirrors for browsing / Astra context.
Get-ChildItem -LiteralPath $SnapshotTools -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $ToolsMirror $_.Name) -Force
}
Get-ChildItem -LiteralPath $SnapshotDocs -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $DocsMirror $_.Name) -Force
}

# Restore the old working-root convention without overwriting local differences.
$workingCandidates = @(Get-ChildItem -LiteralPath $SnapshotTools -File | Where-Object {
    $_.Name -like 'AOTR*.ps1' -or $_.Name -like 'PATCH_AOTR*.ps1' -or $_.Name -like 'README_AOTR*'
})

$copyStats = [ordered]@{
    COPIED_MISSING = 0
    ALREADY_IDENTICAL = 0
    LOCAL_DIFF_PRESERVED = 0
}
foreach ($f in $workingCandidates) {
    $r = Copy-WorkingToolSafely $f
    $copyStats[$r]++
}

Write-Host ("WORKING_ROOT_COPIED_MISSING={0}" -f $copyStats.COPIED_MISSING)
Write-Host ("WORKING_ROOT_ALREADY_IDENTICAL={0}" -f $copyStats.ALREADY_IDENTICAL)
Write-Host ("WORKING_ROOT_LOCAL_DIFF_PRESERVED={0}" -f $copyStats.LOCAL_DIFF_PRESERVED)

# Export PR #70 metadata and discussion because many runtime proofs were documented in comments.
$prExportStatus = 'PASS'
$issueComments = @()
$reviewComments = @()
$reviews = @()
try {
    $apiBase = "https://api.github.com/repos/$RepoOwner/$RepoName"
    $pr = Invoke-RestMethod -UseBasicParsing -Headers $Headers -Uri "$apiBase/pulls/$PrNumber" -Method Get
    $issueComments  = @(Get-GitHubPaged "$apiBase/issues/$PrNumber/comments")
    $reviewComments = @(Get-GitHubPaged "$apiBase/pulls/$PrNumber/comments")
    $reviews        = @(Get-GitHubPaged "$apiBase/pulls/$PrNumber/reviews")

    $pr | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $PrRoot 'PR70_METADATA.json') -Encoding UTF8
    $issueComments | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $PrRoot 'PR70_ISSUE_COMMENTS.json') -Encoding UTF8
    $reviewComments | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $PrRoot 'PR70_REVIEW_COMMENTS.json') -Encoding UTF8
    $reviews | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $PrRoot 'PR70_REVIEWS.json') -Encoding UTF8

    $timeline = New-Object System.Collections.Generic.List[string]
    $timeline.Add('# PR #70 local recovery timeline')
    $timeline.Add('')
    $timeline.Add(('Pinned research baseline: `{0}`' -f $ResearchRef))
    $timeline.Add('')
    foreach ($c in ($issueComments | Sort-Object created_at)) {
        $timeline.Add(('## Comment {0} - {1} - @{2}' -f $c.id,$c.created_at,$c.user.login))
        $timeline.Add('')
        $timeline.Add([string]$c.body)
        $timeline.Add('')
    }
    $timeline | Set-Content -LiteralPath (Join-Path $PrRoot 'PR70_TIMELINE.md') -Encoding UTF8
}
catch {
    $prExportStatus = 'WARNING_FAILED'
    Set-Content -LiteralPath (Join-Path $PrRoot 'PR70_EXPORT_ERROR.txt') -Value $_.Exception.ToString() -Encoding UTF8
    Write-Warning ("PR #70 export failed, but repository recovery continues: {0}" -f $_.Exception.Message)
}

$keyTools = @(
    'AOTR_OWN_MP_START_ACK_POC.ps1',
    'AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1',
    'AOTR_WOTR_NORMAL_CLIENT_FRONTEND_TIMELINE_OBSERVER.ps1',
    'AOTR_WOTR_FRONTEND_OWNER_GLOBAL_RUNTIME_VALIDATE.ps1',
    'AOTR_WOTR_STATE8_JOIN_POSTJOIN_8472BF_V1.ps1',
    'AOTR_WOTR_STATE8_JOIN_POSTJOIN_8472BF_PS51_BOOTSTRAP_V1.ps1',
    'AOTR_WOTR_POSTJOIN_HELPERS_846C6D_846CDE_PURE_PS.ps1',
    'AOTR_WOTR_POSTJOIN_EVENT_CORE_62279C_AND_C545XX_PURE_PS.ps1',
    'AOTR_WOTR_POSTJOIN_8472BF_TERRITORY_CRASH_FORENSICS_V1.ps1',
    'AOTR_WOTR_TERRITORY_CRASH_NATIVE_VS_POC_EVENT_COMPARE_V2.ps1',
    'AOTR_WOTR_WER_TEMP_DUMP_SALVAGE_V1.ps1',
    'AOTR_WOTR_WER_TEMP_LIVE_DUMP_CAPTURE_V1.ps1',
    'AOTR_WOTR_LOCALROOT_COMPACT_FINAL_DIRECT.ps1'
)

$missingKeyTools = @()
foreach ($name in $keyTools) {
    if (-not (Test-Path -LiteralPath (Join-Path $SnapshotTools $name) -PathType Leaf)) {
        $missingKeyTools += $name
    }
}

$keyDocs = @(
    '2026-08-27_P3_NATIVE_NETWORK_TO_LIVINGWORLD_PATH.md',
    '2026-08-28_PLAYERTEMPLATE_MANIFEST_DIVERGENCE.md',
    '2026-08-28_LOCALROOT_FIRST_HOST_VM_DIVERGENCE.md',
    '2026-08-28_NORMAL_CLIENT_JOIN_FRONTEND_TIMELINE.md',
    '2026-08-30_STATE8_PREJOIN_CAUSAL_PUBLICATION_PROOF.md'
)
$missingKeyDocs = @()
foreach ($name in $keyDocs) {
    if (-not (Test-Path -LiteralPath (Join-Path $SnapshotDocs $name) -PathType Leaf)) {
        $missingKeyDocs += $name
    }
}

$toolCount = @(Get-ChildItem -LiteralPath $SnapshotTools -File).Count
$docCount = @(Get-ChildItem -LiteralPath $SnapshotDocs -File).Count

$manifest = [ordered]@{
    recovered_at = (Get-Date).ToString('o')
    repository = "$RepoOwner/$RepoName"
    research_ref = $ResearchRef
    pull_request = $PrNumber
    research_root = $ResearchRoot
    bfme_research_root = $BfmeResearchRoot
    bfme_research_modified = $false
    snapshot_dir = $SnapshotDir
    tools_mirror = $ToolsMirror
    docs_mirror = $DocsMirror
    pr_export_dir = $PrRoot
    archive_sha256 = $zipHash
    snapshot_tool_count = $toolCount
    snapshot_doc_count = $docCount
    working_root_copy_stats = $copyStats
    pr_export_status = $prExportStatus
    pr_issue_comment_count = $issueComments.Count
    pr_review_comment_count = $reviewComments.Count
    pr_review_count = $reviews.Count
    expected_game_dat_sha256 = $ExpectedGameDatSha256
    expected_playertemplate_sha256 = $ExpectedPlayerTemplateSha256
    missing_key_tools = $missingKeyTools
    missing_key_docs = $missingKeyDocs
}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

Write-Host ''
Write-Host '================ RECOVERY RESULT ================'
Write-Host ("SNAPSHOT_TOOL_COUNT={0}" -f $toolCount)
Write-Host ("SNAPSHOT_DOC_COUNT={0}" -f $docCount)
Write-Host ("PR70_EXPORT_STATUS={0}" -f $prExportStatus)
Write-Host ("PR70_ISSUE_COMMENT_COUNT={0}" -f $issueComments.Count)
Write-Host ("PR70_REVIEW_COMMENT_COUNT={0}" -f $reviewComments.Count)
Write-Host ("MISSING_KEY_TOOL_COUNT={0}" -f $missingKeyTools.Count)
Write-Host ("MISSING_KEY_DOC_COUNT={0}" -f $missingKeyDocs.Count)
Write-Host ("MANIFEST={0}" -f $ManifestPath)
Write-Host ("CANONICAL_GAME_DAT_SHA256={0}" -f $ExpectedGameDatSha256)
Write-Host ("CANONICAL_PLAYERTEMPLATE_SHA256={0}" -f $ExpectedPlayerTemplateSha256)

if ($missingKeyTools.Count -eq 0 -and $missingKeyDocs.Count -eq 0) {
    Write-Host 'RECOVERY_RESULT=PASS' -ForegroundColor Green
} else {
    Write-Host 'RECOVERY_RESULT=PARTIAL - inspect missing key files before runtime research.' -ForegroundColor Yellow
    if ($missingKeyTools.Count -gt 0) { Write-Host ('MISSING_KEY_TOOLS=' + ($missingKeyTools -join ';')) }
    if ($missingKeyDocs.Count -gt 0)  { Write-Host ('MISSING_KEY_DOCS=' + ($missingKeyDocs -join ';')) }
}
