param(
    [string]$AotrRoot = '',
    [string]$ModExe = '',
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedGameDatHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'
$ExpectedGameDatLength = 11347456
$ExpectedPlayerTemplateHash = '2D162EE705DE9D96A7B65140C22EBA6EBD0B8F155AE062C97F9884E37DC59F4D'
$ExpectedPlayerTemplateLength = 33211
$PinnedResearchRef = 'f704fae949ccea70e2f80f87b8b9fe146b52404d'

function Hash-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Report-File([string]$Label,[string]$Path,[string]$ExpectedHash,[Nullable[long]]$ExpectedLength) {
    Write-Host ("[{0}]" -f $Label)
    Write-Host ("PATH   = {0}" -f $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Host 'EXISTS = NO' -ForegroundColor Red
        Write-Host ''
        return [pscustomobject]@{ Exists=$false; HashOk=$false; LengthOk=$false; Hash=$null; Length=$null }
    }

    $f = Get-Item -LiteralPath $Path
    $h = Hash-File $Path
    $hashOk = if ([string]::IsNullOrWhiteSpace($ExpectedHash)) { $true } else { $h -eq $ExpectedHash }
    $lengthOk = if ($null -eq $ExpectedLength) { $true } else { [long]$f.Length -eq [long]$ExpectedLength }

    Write-Host 'EXISTS = YES'
    Write-Host ("LENGTH = {0}" -f $f.Length)
    Write-Host ("SHA256 = {0}" -f $h)
    if (-not [string]::IsNullOrWhiteSpace($ExpectedHash)) {
        Write-Host ("HASH_OK = {0}" -f ($(if($hashOk){'YES'}else{'NO'}))) $(if($hashOk){'-ForegroundColor Green'}else{'-ForegroundColor Red'})
    }
    if ($null -ne $ExpectedLength) {
        Write-Host ("LENGTH_OK = {0}" -f ($(if($lengthOk){'YES'}else{'NO'})))
    }
    Write-Host ''
    return [pscustomobject]@{ Exists=$true; HashOk=$hashOk; LengthOk=$lengthOk; Hash=$h; Length=[long]$f.Length }
}

Write-Host '============================================================'
Write-Host ' AOTR REINSTALL HOST HEALTHCHECK V1'
Write-Host '============================================================'
Write-Host 'MODE = READ ONLY'
Write-Host 'GAME_START = NO'
Write-Host 'GAME_MEMORY_WRITE = NO'
Write-Host 'FILE_WRITE = NO'
Write-Host ''

if ([string]::IsNullOrWhiteSpace($AotrRoot)) {
    $candidates = @(
        'D:\Games\AotR\AgeoftheRing',
        'C:\AgeoftheRing',
        'C:\Games\AotR\AgeoftheRing',
        (Join-Path $env:USERPROFILE 'Games\AotR\AgeoftheRing')
    ) | Select-Object -Unique

    $hits = @($candidates | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'rotwk\game.dat') -PathType Leaf })
    if ($hits.Count -eq 1) {
        $AotrRoot = $hits[0]
    }
    elseif ($hits.Count -gt 1) {
        Write-Host 'AOTR_ROOT_AUTOSELECT=AMBIGUOUS' -ForegroundColor Yellow
        $hits | ForEach-Object { Write-Host ("  CANDIDATE={0}" -f $_) }
        Write-Host 'RESULT=NEED_EXPLICIT_AOTR_ROOT' -ForegroundColor Yellow
        exit 2
    }
    else {
        Write-Host 'AOTR_ROOT_AUTOSELECT=NOT_FOUND' -ForegroundColor Red
        $candidates | ForEach-Object { Write-Host ("  CHECKED={0}" -f $_) }
        Write-Host 'RESULT=NEED_EXPLICIT_AOTR_ROOT' -ForegroundColor Yellow
        exit 2
    }
}

$AotrRoot = (Resolve-Path -LiteralPath $AotrRoot).Path
Write-Host ("AOTR_ROOT={0}" -f $AotrRoot)
Write-Host ''

$gameDat = Join-Path $AotrRoot 'rotwk\game.dat'
$playerTemplate = Join-Path $AotrRoot 'aotr\data\ini\playertemplate.ini'
$runtimePlayerTemplate = Join-Path $AotrRoot '_AOTR_8P_WOTR_RUNTIME\data\ini\playertemplate.ini'
$officialLauncher = Join-Path $AotrRoot 'AotR_Launcher.exe'

$g = Report-File 'GAME.DAT' $gameDat $ExpectedGameDatHash $ExpectedGameDatLength
$p = Report-File 'PLAYER TEMPLATE CANONICAL' $playerTemplate $ExpectedPlayerTemplateHash $ExpectedPlayerTemplateLength
$r = Report-File 'PLAYER TEMPLATE RUNTIME MIRROR' $runtimePlayerTemplate $ExpectedPlayerTemplateHash $ExpectedPlayerTemplateLength

Write-Host '[AOTR OFFICIAL LAUNCHER]'
Write-Host ("PATH   = {0}" -f $officialLauncher)
Write-Host ("EXISTS = {0}" -f ($(if(Test-Path -LiteralPath $officialLauncher -PathType Leaf){'YES'}else{'NO'})))
Write-Host ''

if ([string]::IsNullOrWhiteSpace($ModExe)) {
    $downloadRoot = Join-Path $env:USERPROFILE 'Downloads'
    if (Test-Path -LiteralPath $downloadRoot -PathType Container) {
        $modHits = @(Get-ChildItem -LiteralPath $downloadRoot -Filter 'AotR 8P WotR Mod.exe' -File -Recurse -ErrorAction SilentlyContinue)
        if ($modHits.Count -eq 1) {
            $ModExe = $modHits[0].FullName
        }
        elseif ($modHits.Count -gt 1) {
            Write-Host 'MOD_EXE_AUTOSELECT=AMBIGUOUS' -ForegroundColor Yellow
            $modHits | ForEach-Object { Write-Host ("  MOD_CANDIDATE={0}" -f $_.FullName) }
        }
    }
}

Write-Host '[8P MOD EXECUTABLE]'
if ([string]::IsNullOrWhiteSpace($ModExe)) {
    Write-Host 'PATH   = NOT RESOLVED'
    Write-Host 'EXISTS = NO' -ForegroundColor Yellow
    $modPresent = $false
} else {
    Write-Host ("PATH   = {0}" -f $ModExe)
    $modPresent = Test-Path -LiteralPath $ModExe -PathType Leaf
    Write-Host ("EXISTS = {0}" -f ($(if($modPresent){'YES'}else{'NO'})))
}
Write-Host ''

Write-Host '[AOTR RESEARCH RECOVERY]'
$manifest = Join-Path $ResearchRoot '_RECOVERY\RECOVERY_MANIFEST.json'
$keyTool = Join-Path $ResearchRoot 'AOTR_WOTR_WER_TEMP_LIVE_DUMP_CAPTURE_V1.ps1'
$docsMirror = Join-Path $ResearchRoot 'DOCS_FROM_GITHUB'
Write-Host ("ROOT              = {0}" -f $ResearchRoot)
Write-Host ("MANIFEST_EXISTS   = {0}" -f ($(if(Test-Path -LiteralPath $manifest -PathType Leaf){'YES'}else{'NO'})))
Write-Host ("KEY_TOOL_EXISTS   = {0}" -f ($(if(Test-Path -LiteralPath $keyTool -PathType Leaf){'YES'}else{'NO'})))
Write-Host ("DOCS_MIRROR       = {0}" -f ($(if(Test-Path -LiteralPath $docsMirror -PathType Container){'YES'}else{'NO'})))

$researchOk = (Test-Path -LiteralPath $manifest -PathType Leaf) -and (Test-Path -LiteralPath $keyTool -PathType Leaf) -and (Test-Path -LiteralPath $docsMirror -PathType Container)
if (Test-Path -LiteralPath $manifest -PathType Leaf) {
    try {
        $m = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
        Write-Host ("RECOVERY_REF      = {0}" -f $m.research_ref)
        Write-Host ("RECOVERY_REF_OK   = {0}" -f ($(if([string]$m.research_ref -eq $PinnedResearchRef){'YES'}else{'NO'})))
        if ([string]$m.research_ref -ne $PinnedResearchRef) { $researchOk = $false }
    } catch {
        Write-Host 'RECOVERY_MANIFEST_PARSE=FAIL' -ForegroundColor Red
        $researchOk = $false
    }
}
Write-Host ''

$coreOk = $g.Exists -and $g.HashOk -and $g.LengthOk -and $p.Exists -and $p.HashOk -and $p.LengthOk -and $researchOk
$runtimeOk = $r.Exists -and $r.HashOk -and $r.LengthOk

Write-Host '================ HEALTH SUMMARY ================'
Write-Host ("CORE_GAME_OK={0}" -f ($(if($g.Exists -and $g.HashOk -and $g.LengthOk){'YES'}else{'NO'})))
Write-Host ("CANONICAL_PLAYERTEMPLATE_OK={0}" -f ($(if($p.Exists -and $p.HashOk -and $p.LengthOk){'YES'}else{'NO'})))
Write-Host ("RUNTIME_MIRROR_OK={0}" -f ($(if($runtimeOk){'YES'}else{'NO'})))
Write-Host ("MOD_EXE_PRESENT={0}" -f ($(if($modPresent){'YES'}else{'NO'})))
Write-Host ("AOTR_RESEARCH_OK={0}" -f ($(if($researchOk){'YES'}else{'NO'})))
Write-Host ''

if (-not $coreOk) {
    Write-Host 'RESULT=FAIL_CORE_RECOVERY' -ForegroundColor Red
    Write-Host 'ACTION=Do not start reverse-engineering runtime tests yet.' -ForegroundColor Yellow
    exit 1
}

if (-not $runtimeOk -or -not $modPresent) {
    Write-Host 'RESULT=CORE_PASS_MOD_NOT_FULLY_READY' -ForegroundColor Yellow
    Write-Host 'ACTION=Do not patch anything. Send this full output so the missing mod/runtime layer can be classified.' -ForegroundColor Yellow
    exit 0
}

Write-Host 'RESULT=PASS_RESEARCH_ENVIRONMENT_RESTORED' -ForegroundColor Green
Write-Host 'NEXT_GATE=Fresh native UI territory-crash baseline, then live WER temp dump capture.' -ForegroundColor Green
