# Robust Standalone AotR Auto-Detection — Integration Plan V1

This document is a production integration plan for the canonical Windows launcher builder. It does not modify the current v1.0.9 release.

## Goal

Replace duplicated GUI/engine AotR path resolution with one shared standalone-AotR resolver whose output is a validated canonical Config V2.

The resolver must never rely on first-valid-candidate-wins.

## Source prerequisite

The current GitHub repository does not contain the authoritative launcher builder or editable embedded GUI/engine source. Production integration must therefore wait until the canonical Windows builder is available on the main development PC or versioned into the repository.

Do not patch the release EXE blindly.

## Required source audit on the canonical build machine

Before changing behavior, identify and checkpoint:

1. current authoritative launcher builder entry point;
2. embedded GUI source;
3. embedded engine source;
4. GUI AotR resolver function and every caller;
5. engine AotR resolver function and every caller;
6. current config load/save implementation;
7. runtime-root construction;
8. source-mod-root construction;
9. game.dat selection logic;
10. Auto-Repair dispatcher and internal action allowlist;
11. failure/error-code mapping;
12. launch retry path after Auto-Repair.

Record hashes before edits. If exact functions cannot be identified, do not release a resolver change.

## Shared resolver contract

Conceptual interface:

```text
ResolveAotrInstallation(
    cachedConfig,
    environment,
    launcherLocation,
    localDrives,
    optionalUserSelection
)
    -> ResolutionResult
```

Conceptual result:

```text
ResolutionResult
  status
  error_code
  selected_installation
  candidates[]
  ambiguity_candidates[]
  cached_path_state
  diagnostics
```

A selected installation must contain at least:

```text
aotr_root
runtime
source_mod
game_dat
validation = aotr-standalone-v2
score
last_verified_utc
```

## Discovery pipeline

Use this order for candidate discovery, but do not select during discovery:

```text
1. cached previously validated root
2. AOTR_HOME
3. launcher/install environment
4. known paths on local Fixed drives
5. bounded AgeoftheRing search on local Fixed drives
6. known paths on Removable drives
7. bounded AgeoftheRing search on Removable drives
```

Network drives are not recursively searched automatically.

The All-in-One Launcher is not a discovery source.

Every discovered path is canonicalized and normalized to an `AgeoftheRing` root before deduplication.

## Validation

Hard standalone validation:

```text
Exists: <root>\rotwk\lotrbfme2ep1.exe
AND
Exists: <root>\rotwk\game.dat
  OR:  <root>\rotwk\zGameDats\game.dat
AND
Exists directory: <root>\aotr\
```

A candidate missing `aotr\` is a RotWK-style installation, not a standalone AotR installation.

Optional scoring markers:

```text
AotR_Launcher.exe
aotr\data\ini\
aotr\Changelist.txt
```

## Scoring

Baseline:

```text
rotwk\lotrbfme2ep1.exe       +40
rotwk\game.dat or zGameDats  +30
aotr\                        +25
AotR_Launcher.exe             +10
aotr\data\ini\               +10
aotr\Changelist.txt            +5
```

Unsafe/deprioritized path classes:

```text
_AotR8P_WotR_Runtime -> hard reject
All-in-One            -> hard reject from automatic detection
BFME_RESEARCH         -> strong penalty + not auto-selectable
backup                -> strong penalty + not auto-selectable
checkpoint            -> strong penalty + not auto-selectable
temp/tmp              -> strong penalty + not auto-selectable
```

Production code may tune penalty values after testing, but must preserve the policy distinction between structural validity and automatic eligibility.

## Selection rules

After all candidates are validated and scored:

```text
0 eligible valid candidates
  -> A8P-INSTALL-001
  -> show folder browser / manual selection path

1 unique top eligible candidate
  -> select
  -> write Config V2
  -> continue

2+ equally ranked top eligible candidates
  -> A8P-INSTALL-002
  -> present user choice
  -> validate selection again
  -> write Config V2
  -> continue
```

Never resolve ambiguity by filesystem enumeration order.

## Cached path behavior

At every launch:

```text
load Config V2
-> quickly hard-validate aotr_root + resolved game_dat
-> if valid: continue without broad rediscovery
-> if invalid/missing: classify cached path as stale (`A8P-INSTALL-007`)
-> rediscover all approved candidate sources
-> if one result: update Config V2 and continue
-> if ambiguous: user choice
-> if none: installation-not-found flow
```

`A8P-INSTALL-007` should be recoverable without becoming a final visible failure when rediscovery immediately finds the moved installation.

## GUI / engine unification

Target architecture:

```text
GUI ----\
         -> one shared resolver -> Config V2 -> launch context
Engine -/
```

Rules:

- GUI may own interaction (candidate chooser, folder browser, error panel).
- Engine must consume the already validated canonical result.
- Engine must not run an independent weaker fallback search afterward.
- Both layers must use the same canonical `aotr_root`, `runtime`, `source_mod`, and `game_dat` values.
- Config write should occur only after validation and user choice when required.

## Folder browser contract

When manual selection is required:

1. user selects a directory;
2. normalize selection to a candidate root;
3. hard-validate the standalone structure;
4. if invalid, emit `A8P-INSTALL-003` with missing marker diagnostics;
5. do not save the invalid path;
6. keep browser/retry available.

## Install error mapping

```text
A8P-INSTALL-001  AotR installation not found
A8P-INSTALL-002  Multiple valid AotR installations found
A8P-INSTALL-003  Selected directory is not a valid standalone AotR installation
A8P-INSTALL-004  Installation/runtime path not usable or writable
A8P-INSTALL-005  Unsupported/incompatible AotR version
A8P-INSTALL-006  Required AotR files missing
A8P-INSTALL-007  Cached AotR installation moved or disappeared
```

`003` is primarily a user-selection validation error. `006` is suitable when an otherwise recognized install has known required files missing. Exact production mapping should remain deterministic.

## Writeability policy

The research prototype does not test writeability because it is strictly read-only.

Production code must decide what actually needs to be writable. Do not assume the source AotR installation itself must always be writable if the launcher only needs to write its generated runtime/config elsewhere.

Any capability test must be minimal, bounded, cleaned up, and performed only in the location that genuinely requires writes.

## Version compatibility

`A8P-INSTALL-005` requires an authoritative version source and compatibility rule before implementation.

Potential evidence sources can be evaluated in the canonical builder research, but no version threshold should be invented in remote preparation.

## Repair-manifest safety

Current `repair-manifest.json` already knows `A8P-INSTALL-001` and uses existing action names such as `reset_install` and `retry_launch`.

Do not add new remote action names for `002`–`007` merely because these error classes are documented.

Before any repair-manifest extension:

1. inspect the internal dispatcher/allowlist;
2. prove every action name is implemented;
3. prove the action is safe and bounded;
4. prove post-action success can be verified;
5. add regression evidence;
6. only then publish the remote rule.

## Ticket/reporting integration

Keep the existing launcher reporting sequence:

```text
Launch
-> failure
-> classify error
-> Auto-Repair
-> retry where allowed
-> if recovered: continue, no report
-> if exhausted: final error panel
-> REPORT ERROR becomes available
```

Detection failures should feed the same stable `A8P-*` + fingerprint + support-bundle pipeline once implemented in the launcher.

## Full test matrix

Mandatory cases:

1. valid `C:\AgeoftheRing`;
2. valid `D:\Games\AotR\AgeoftheRing`;
3. launcher in Downloads;
4. launcher inside AotR root;
5. cached install moved to another drive;
6. two genuine AotR installations;
7. `BFME_RESEARCH` containing valid-looking copies;
8. `_AotR8P_WotR_Runtime` present;
9. plain RotWK copy present;
10. `aotr\` missing;
11. `lotrbfme2ep1.exe` missing;
12. both game.dat layouts missing;
13. only `rotwk\zGameDats\game.dat` present;
14. valid AotR on USB/exFAT;
15. network share containing AotR;
16. missing required write permission in the actual write target;
17. supported AotR version;
18. unsupported AotR version;
19. German Windows/environment;
20. English Windows/environment;
21. optional strong markers absent but hard structure valid;
22. valid-looking AotR under backup/checkpoint/temp;
23. All-in-One path containing a valid-looking AotR tree;
24. stale Config V1 / Config V2 migration;
25. malformed cached config;
26. duplicate discovery paths resolving to the same canonical root.

## Acceptance criteria

Production integration is ready for release only when:

- GUI and engine both use the same resolver result;
- no first-match path remains active;
- plain RotWK cannot be accepted as AotR;
- runtime/research copies cannot silently win;
- ambiguity produces user choice;
- stale cache self-recovers after a move;
- network recursive scanning is absent;
- USB/exFAT works after Fixed-drive discovery;
- Config V2 is persisted only after validation;
- current Auto-Repair behavior still works;
- final REPORT ERROR behavior still follows repair exhaustion;
- clean-install and broken-state regression tests pass;
- a non-release test build is validated before manifest/release updates.
