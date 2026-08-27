# AotR 8P WotR — Launcher Source / Builder Audit V1

Date: 2026-08-26
Branch: `feature/robust-aotr-autodetect`
Purpose: establish exactly what launcher source/build material is and is not present in GitHub before robust AotR auto-detection is integrated.

## RESULT

**No authoritative launcher builder or editable embedded GUI/engine source has been found in this GitHub repository or its current development branches.**

The repository is currently a release/support repository, not yet the canonical Windows launcher-source repository.

Therefore:

- do not patch `AotR 8P WotR Mod.exe` blindly;
- do not invent GUI/engine resolver function names;
- do not invent repair-dispatcher action support;
- do not claim the robust resolver is production-integrated yet;
- integration must continue on the canonical Windows research/build machine.

## MAIN AUDITED

`main` at the start of this research branch:

```text
8b83f907d5d29b720ce2317e1a7150e51cac90b2
```

Observed repository classes:

```text
.github/...
AotR 8P WotR Mod.exe
README.md
docs/...
manifest.json
payload_paper.inc
payload_ui.big
repair-manifest.json
```

No builder/source tree is present.

## CURRENT BRANCHES AUDITED

Branches enumerated during the audit:

```text
feature/github-ticket-system
feature/launcher-error-reporting
feature/master-ticket-clustering
feature/robust-aotr-autodetect
fix/burst-safe-clustering
fix/issue-processing-race
fix/oos-triage-regex
fix/unify-issue-processing
main
```

The historical feature branches inspected are variations of the same release/support tree plus GitHub workflows/docs. They do not expose a canonical launcher builder.

In particular:

### `feature/github-ticket-system`

Contains ticketing forms/workflows/docs plus the same release artifacts. No Windows launcher builder/source tree was found.

### `feature/launcher-error-reporting`

Contains launcher-reporting docs/workflows plus the same release artifacts. No Windows launcher builder/source tree was found.

### Current robust-autodetect branch

Contains only the deliberately added research preparation under:

```text
research/installer/
```

It does not pretend to be the production launcher source.

## COMMIT-HISTORY SEARCH

Commit-message searches performed in the repository:

```text
V17
builder
launcher
```

Results:

- `V17`: no matching commits
- `builder`: no matching commits
- `launcher`: only the recent GitHub-side launcher error-reporting/ticketing work

No evidence was found that the canonical V17 builder was previously committed and later deleted under an obvious builder/V17 commit message.

This is not a mathematical proof that no unreachable Git object ever existed, but it is sufficient to establish that no usable builder is available through the current repository refs/history exposed by normal project workflow.

## KNOWN CANONICAL-BUILDER CANDIDATES FROM THE RESEARCH WORKSPACE

The project research checkpoint already identified these V17 builder files on the Windows research machine:

```text
BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_START_SIGNAL_MVP.ps1
BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_GLOBAL_LOBBY_MVP.ps1
BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_MULTIPLAYER_EXACT.ps1
```

Known checkpoint metadata from the research workspace:

```text
BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_START_SIGNAL_MVP.ps1
Length: 258905
LastWriteTime: 2026-08-23 15:12:04
SHA256: 79D31C3DCE6833781BFECF5B87230B1C463483EA4F31A89D2431238D42A17C6F

BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_GLOBAL_LOBBY_MVP.ps1
Length: 257283
LastWriteTime: 2026-08-23 14:59:13
SHA256: BAC0A4E8381919DA80B6FB98CEB258343DD481BE4F940EBDB401579ACDE99473

BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_MULTIPLAYER_EXACT.ps1
Length: 253487
LastWriteTime: 2026-08-23 14:16:45
SHA256 begins with: 082967B350022B...
```

The full hash of `MULTIPLAYER_EXACT` must be re-read from the local research checkpoint rather than guessed.

## LOCAL SOURCE-RECOVERY PROCEDURE

Run this from PowerShell 7 on the canonical Windows development machine.

### 1. Search the known research roots first

```powershell
$roots = @(
    'D:\BFME_RESEARCH',
    'D:\Games\AotR'
) | Where-Object { Test-Path -LiteralPath $_ }

$names = @(
    'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_START_SIGNAL_MVP.ps1',
    'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_GLOBAL_LOBBY_MVP.ps1',
    'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_MULTIPLAYER_EXACT.ps1'
)

foreach ($root in $roots) {
    Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in $names } |
        Select-Object FullName, Length, LastWriteTime
}
```

### 2. Hash every exact candidate before opening/editing it

```powershell
Get-ChildItem -LiteralPath 'D:\BFME_RESEARCH' -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17*.ps1' } |
    ForEach-Object {
        $h = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
        [pscustomobject]@{
            FullName      = $_.FullName
            Length        = $_.Length
            LastWriteTime = $_.LastWriteTime
            SHA256        = $h.Hash
        }
    } |
    Sort-Object LastWriteTime -Descending |
    Format-Table -AutoSize
```

### 3. Search for embedded resolver/config/repair logic without modifying files

Once the authoritative builder candidate is identified:

```powershell
$builder = 'FULL_PATH_TO_CONFIRMED_V17_BUILDER.ps1'

$patterns = @(
    'AOTR_HOME',
    'AgeoftheRing',
    'lotrbfme2ep1.exe',
    '_AotR8P_WotR_Runtime',
    'repair-manifest',
    'reset_install',
    'retry_launch',
    'game.dat',
    'zGameDats',
    'config',
    'launcher_gui'
)

Select-String -LiteralPath $builder -Pattern $patterns -SimpleMatch -Context 5,12
```

Do not edit the builder at this stage.

### 4. Extract exact resolver boundaries

For every matching block, record:

```text
function name
line range
guarded/fallback callers
input variables
returned path variables
config reads
config writes
runtime construction
game.dat construction
error code emitted
```

The important proof is not merely finding the string `AgeoftheRing`; it is proving where GUI and engine independently resolve/canonicalize the install root.

### 5. Find internal Repair dispatcher / allowlist

Search for every action currently present in `repair-manifest.json`, including:

```text
reset_install
retry_launch
repair_payloads
reset_runtime
stop_old_dev_launchers
stop_legacy_runtime
stop_failed_game
check_launcher_update
clear_compat_cache
```

Then identify the actual dispatcher construct, for example a `switch`, action map, or explicit allowlist.

Only actions proven there may be referenced by future remote repair plans.

## BUILDER SELECTION RULE

Do not automatically assume the newest timestamp is authoritative.

A builder is accepted as the production integration base only after comparing:

1. SHA256 and known checkpoint metadata;
2. embedded launcher version;
3. feature set expected in the current public v1.0.9 line;
4. ticket/reporting integration state where applicable;
5. current multiplayer/start-signal/global-lobby changes;
6. generated EXE behavior or known release ancestry.

If multiple V17 builders are descendants/variants, establish their lineage before choosing a base.

## REQUIRED OUTPUT OF THE MAIN-PC AUDIT

Before robust auto-detection code is integrated, create a new checkpoint containing at least:

```text
AUTHORITATIVE_BUILDER
BUILDER_SHA256
BUILDER_SIZE
BUILDER_LASTWRITE
CURRENT_LAUNCHER_VERSION
GUI_RESOLVER_FUNCTION
GUI_RESOLVER_LINE_RANGE
ENGINE_RESOLVER_FUNCTION
ENGINE_RESOLVER_LINE_RANGE
CONFIG_READ_FUNCTION
CONFIG_WRITE_FUNCTION
REPAIR_DISPATCHER_FUNCTION
SUPPORTED_REPAIR_ACTIONS
CURRENT_RUNTIME_ROOT_LOGIC
CURRENT_SOURCE_MOD_LOGIC
CURRENT_GAME_DAT_LOGIC
```

If any of these cannot be proven, mark it `UNKNOWN` rather than guessing.

## DO NOT REPEAT

- Do not search only `main` and assume another current branch contains the builder; current branches have now been audited for this purpose.
- Do not infer that the release EXE is editable source.
- Do not use an old external `launcher_gui.ps1` as proof that the current Single-EXE uses that file at runtime.
- Do not choose a V17 builder only because its timestamp is newest.
- Do not modify any builder before its SHA256/checkpoint has been recorded.
- Do not add new repair-manifest actions before locating the internal dispatcher/allowlist.
- Do not replace only one of the GUI/engine resolver paths.
