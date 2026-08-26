# AotR 8P WotR — Robust Standalone AotR Auto-Detection Checkpoint V1

Date: 2026-08-26
Branch: `feature/robust-aotr-autodetect`
Scope: research, read-only prototype preparation, integration contract. No release EXE changes.

> Note on provenance: the previously prepared File Library artifacts could not be retrieved in this chat because no File Library source is exposed to the current session. This checkpoint therefore preserves the confirmed project findings supplied in the project context and re-verifies the GitHub-side repository state. It does not invent missing binary offsets or source function names.

## STATUS

**Research/preparation ready for review. Production launcher integration is not yet safe to build from GitHub alone.**

Confirmed repository state at the start of this work:

- `main` head: `8b83f907d5d29b720ce2317e1a7150e51cac90b2`
- public launcher manifest version: `1.0.9`
- public launcher is a single EXE containing embedded GUI + engine logic
- canonical Windows builder/source is not present in this repository
- existing GitHub ticket system, launcher-reporting contract, support fingerprinting, master-ticket clustering, and repair-manifest are present
- no release EXE, payload, `manifest.json`, or `repair-manifest.json` is changed by this branch

## WHAT WE KNOW

### Existing launcher detection behavior

The prior reverse-engineering work established all of the following:

1. The launcher already has automatic AotR path detection.
2. GUI and engine have separate AotR resolver logic.
3. Changing only the GUI resolver is insufficient; the engine can still resolve independently.
4. The existing resolver behavior is substantially `first valid match wins`.
5. A plain RotWK copy, backup, or research copy can therefore become a false-positive candidate if validation is too weak or appears earlier.
6. AotR must be treated as a standalone installation for this project.
7. The All-in-One Launcher must not participate in AotR detection.
8. `_AotR8P_WotR_Runtime` is generated runtime state and must never be accepted as the canonical AotR installation.
9. `BFME_RESEARCH`, backup, checkpoint, temp, and tmp paths must not be silently preferred as production installs.
10. Candidate discovery must collect, normalize, deduplicate, validate, score, and rank **all** candidates before choosing.

### Hard standalone validation

A candidate `<AgeoftheRing>` root is valid only when all of the following are true:

```text
<AgeoftheRing>\
    rotwk\
        lotrbfme2ep1.exe
        game.dat
        OR zGameDats\game.dat

    aotr\
```

A plain RotWK installation is therefore **not** sufficient.

Strong optional AotR markers:

```text
AotR_Launcher.exe
aotr\data\ini\
aotr\Changelist.txt
```

### Desired detection order

```text
cached previously validated AotR root
↓
AOTR_HOME
↓
launcher / installation environment
↓
known AotR paths on local Fixed drives
↓
bounded search for directories named AgeoftheRing on local Fixed drives
↓
Removable / USB / exFAT candidates
↓
validate every candidate
↓
deduplicate canonical roots
↓
score / rank all valid candidates
↓
one unambiguous best candidate -> use automatically
multiple equally valid top candidates -> user choice
no valid candidate -> manual folder browser
```

No automatic recursive scanning of network drives.

### Scoring baseline

Positive markers:

| Marker | Score |
| --- | ---: |
| `rotwk\lotrbfme2ep1.exe` | +40 |
| `rotwk\game.dat` or `rotwk\zGameDats\game.dat` | +30 |
| `aotr\` | +25 |
| `AotR_Launcher.exe` | +10 |
| `aotr\data\ini\` | +10 |
| `aotr\Changelist.txt` | +5 |

A complete install with every optional marker scores 120 before penalties.

Negative/deprioritized path classes:

| Path class | V1 research penalty / policy |
| --- | --- |
| `_AotR8P_WotR_Runtime` | hard reject; never canonical |
| All-in-One / All In One | hard reject from automatic detection |
| `BFME_RESEARCH` | strong negative; not auto-selectable |
| `backup` | strong negative; not auto-selectable |
| `checkpoint` | strong negative; not auto-selectable |
| `temp` / `tmp` | strong negative; not auto-selectable |

The read-only prototype records these classifications explicitly so production code can distinguish “valid structure” from “safe automatic production choice”.

## EVIDENCE

### Repository evidence

At `main` head `8b83f907d5d29b720ce2317e1a7150e51cac90b2`, the repository contains:

```text
.github/ISSUE_TEMPLATE/*
.github/workflows/issue-cluster.yml
.github/workflows/issue-triage.yml
.github/workflows/validate-ticket-system.yml
AotR 8P WotR Mod.exe
README.md
docs/LAUNCHER_REPORTING.md
docs/MASTER_TICKETS.md
docs/TICKETING.md
docs/support-bundle.example.json
docs/support-bundle.schema.json
manifest.json
payload_paper.inc
payload_ui.big
repair-manifest.json
```

There is no launcher source tree, no canonical Windows builder, and no editable GUI/engine resolver implementation in `main`.

`docs/LAUNCHER_REPORTING.md` explicitly records that the current public launcher is a Single-EXE with embedded GUI and engine logic, that editing old external `internal/launcher_gui.ps1` files does not update the running launcher, and that the authoritative builder must be versioned before remote-only launcher releases can be produced reliably.

### Existing release manifest

`manifest.json` currently declares:

```text
schema: 1
launcher_version: 1.0.9
launcher SHA256: 97A8163CA72BDFB5C6C24931E06B2BFCE1D0E33C382FEA2462F73BC80BD3EA9F
UI SHA256:       827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376
Paper SHA256:    3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43
```

This branch intentionally does not update these release values.

### Existing repair contract

`repair-manifest.json` is schema 1 / generated for launcher 1.0.9. Existing `A8P-INSTALL-001` maps to:

```text
reset_install
retry_launch
```

The repository does **not** contain the internal repair-action dispatcher/allowlist implementation. Therefore adding arbitrary new remote action names would be unsafe and misleading. New install error codes are documented here as future detection classes only; they must not gain remote repair actions until the canonical launcher source proves the dispatcher supports them.

### Ticket system

The repository already defines:

```text
Player Report -> GitHub Issue -> Triage -> Fingerprint / error class
-> Master Ticket -> Diagnosis -> Fix or repair-manifest extension -> Retest -> Closed
```

Stable project ticket IDs are derived from GitHub issue numbers as `A8P-TICKET-000X`. Support fingerprints use `A8P-FP-XXXXXXXXXXXX` and are deliberately separate from individual ticket IDs.

## WHAT FAILED

1. The previous File Library copies of `AOTR_8P_ROBUST_AUTODETECT_PROTOTYPE_V1.ps1` and `AOTR_8P_ROBUST_AUTODETECT_CHECKPOINT_V1.md` were not exposed to this chat session, so their byte-for-byte original content could not be imported.
2. The canonical launcher builder/source is not present in GitHub. Exact resolver function names therefore cannot be safely named from repository source.
3. A source-level repair-action dispatcher/allowlist is not present in GitHub, so new remote repair actions cannot be validated or added safely.
4. No attempt was made to patch/decompile and modify the release EXE. That is intentionally out of scope for this branch.

## CURRENT HYPOTHESIS

The production fix should replace both independent resolver paths with one shared standalone-AotR resolver contract.

Preferred architecture:

```text
GUI ----\
         -> Shared Resolve-AotrInstallation() -> canonical Config V2
Engine -/
```

The shared resolver should:

1. fast-validate cached config;
2. rediscover only when cache is invalid/missing;
3. collect every candidate from approved discovery sources;
4. canonicalize paths;
5. deduplicate roots;
6. hard-validate standalone AotR structure;
7. classify unsafe/deprioritized locations;
8. score all valid candidates;
9. return either one canonical root, an ambiguity set, or no result;
10. let UI handle user choice/folder browser while engine consumes only the resulting validated canonical config.

The engine must not independently fall back to a weaker search after the GUI has already produced a canonical result.

## CONFIG V2

Target schema:

```json
{
  "schema": 2,
  "aotr_root": "D:\\Games\\AotR\\AgeoftheRing",
  "runtime": "D:\\Games\\AotR\\AgeoftheRing\\rotwk",
  "source_mod": "D:\\Games\\AotR\\AgeoftheRing\\aotr",
  "game_dat": "D:\\Games\\AotR\\AgeoftheRing\\rotwk\\game.dat",
  "validation": "aotr-standalone-v2",
  "score": 120,
  "last_verified_utc": ""
}
```

`game_dat` may canonicalize to `rotwk\zGameDats\game.dat` when that is the valid layout.

Startup behavior:

```text
load cached Config V2
-> validate cached canonical root quickly
-> valid: refresh verification state and continue
-> invalid/moved: classify A8P-INSTALL-007
-> rediscover
-> validate all candidates
-> select / ask user
-> persist new canonical Config V2
-> continue
```

The read-only research prototype does not persist this config; it only emits a suggested object.

## INSTALL ERROR CLASSES TO PREPARE

| Code | Meaning | Production expectation |
| --- | --- | --- |
| `A8P-INSTALL-001` | AotR installation not found | discovery/folder-browser path |
| `A8P-INSTALL-002` | Multiple valid AotR installations found | require explicit user choice |
| `A8P-INSTALL-003` | Selected directory is not a valid standalone AotR installation | reject selection and show required structure |
| `A8P-INSTALL-004` | Installation/runtime path not usable or writable | permission/path handling; production write test only |
| `A8P-INSTALL-005` | Unsupported/incompatible AotR version | version compatibility gate |
| `A8P-INSTALL-006` | Required AotR files missing | marker/file diagnostics |
| `A8P-INSTALL-007` | Cached AotR installation moved or disappeared | invalidate cache, rediscover, then continue if recovered |

Important: these codes do not imply that new `repair-manifest.json` actions already exist.

## FILES / HASHES / OFFSETS

Repository/release evidence:

```text
main commit:
8b83f907d5d29b720ce2317e1a7150e51cac90b2

AotR 8P WotR Mod.exe
Git blob SHA: 6634848cd25181d0d789e16e585a2572667d5f38
manifest expected SHA256:
97A8163CA72BDFB5C6C24931E06B2BFCE1D0E33C382FEA2462F73BC80BD3EA9F

manifest.json
Git blob SHA: 773b03d465a254efa0f5958a7b64982e14cf504c

repair-manifest.json
Git blob SHA: 87d9cd941bf650a00a4d1350fde41435ffb0b4a2

payload_ui.big
Git blob SHA: 79d709ca256294f0425e986e8e330cfd5b573357
manifest expected SHA256:
827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376

payload_paper.inc
Git blob SHA: 0afbaaf27d0321fbc55dde6b0cf88e9c79e302c9
manifest expected SHA256:
3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43
```

**Resolver offsets:** not available from repository source and not reconstructed in this checkpoint. Do not invent or reuse unknown offsets.

## SAFE TESTS COMPLETED

GitHub/repository-side checks completed safely:

- branch created from `main`
- repository tree enumerated
- release manifest inspected
- repair manifest inspected
- ticket-system documentation inspected
- current branches enumerated
- current/recent PRs enumerated
- open issue backlog checked
- repository searched for launcher source/resolver symbols; no source implementation found
- no release binary changed
- no payload changed
- no release manifest changed
- no repair manifest changed

The PowerShell prototype on this branch is intentionally read-only and contains no file, registry, launcher, or game mutation operations.

## TEST MATRIX FOR THE FUTURE PRODUCTION BUILD

| Scenario | Expected result |
| --- | --- |
| `C:\AgeoftheRing` valid standalone install | auto-detect |
| `D:\Games\AotR\AgeoftheRing` valid standalone install | auto-detect |
| launcher EXE stored in Downloads | detection independent of launcher location |
| launcher directly inside AotR root | local-environment candidate validated |
| AotR moved to another drive after Config V2 was saved | cached path invalid -> `A8P-INSTALL-007` -> rediscover -> save new root -> continue |
| two genuine equally valid AotR installs | `A8P-INSTALL-002`; user choice, no first-match selection |
| `BFME_RESEARCH` contains structurally valid AotR copies | not automatically selected |
| `_AotR8P_WotR_Runtime` exists | hard reject as canonical AotR |
| plain RotWK copy exists | reject: missing `aotr\` |
| AotR candidate missing `aotr\` | invalid / `A8P-INSTALL-003` or `006` depending context |
| AotR candidate missing `lotrbfme2ep1.exe` | invalid / required file diagnostic |
| AotR candidate missing both game.dat layouts | invalid / required file diagnostic |
| valid AotR on USB / exFAT | considered after local Fixed-drive discovery; can be selected if valid |
| network share contains AotR | no automatic recursive network scan |
| target path lacks required write access | `A8P-INSTALL-004` in production write-capability test |
| unsupported AotR version | `A8P-INSTALL-005` |
| German Windows/environment | same canonical result and path semantics |
| English Windows/environment | same canonical result and path semantics |
| strong-marker optional files absent but hard structure valid | still valid, lower score |
| All-in-One path contains an AotR-looking tree | excluded from automatic detection |

## NEXT PRACTICAL ACTION

On the canonical Windows build/research machine:

1. locate the authoritative V17/current launcher builder and all non-secret source inputs;
2. hash and checkpoint them before edits;
3. identify the exact GUI AotR resolver function;
4. identify the exact engine AotR resolver function;
5. identify Config V1 read/write code and the repair dispatcher/allowlist;
6. port the shared resolver design from the read-only prototype into the authoritative builder;
7. make GUI and engine consume one validated Config V2 result;
8. implement user-choice UI for `A8P-INSTALL-002` and folder browser for `001/003` paths;
9. implement production-only safe writeability/version checks for `004/005`;
10. run the full test matrix on clean and intentionally broken layouts;
11. build a new non-release test EXE first;
12. verify existing Auto-Repair and REPORT ERROR sequencing still works;
13. only then prepare a versioned launcher release and update manifest hashes.

## DO NOT REPEAT

- Do not involve All-in-One Launcher in AotR detection.
- Do not search only for `lotrbfme2ep1.exe`.
- Do not modify only the GUI resolver.
- Do not use first-valid-candidate-wins.
- Do not treat `_AotR8P_WotR_Runtime` as a real AotR installation.
- Do not automatically prefer `BFME_RESEARCH`/backup copies.
- Do not blindly patch the public release EXE when canonical builder source is unavailable.
- Do not add remote repair actions that the internal launcher dispatcher/allowlist has not been proven to support.
- Do not recursively scan network drives.
- Do not persist an unvalidated candidate into Config V2.
- Do not invent resolver function names, hashes, or binary offsets that have not been evidenced.

## OPEN RISKS

1. Exact GUI and engine resolver function names remain unknown until the authoritative builder is available.
2. The existing internal action allowlist/dispatcher must be inspected before any new repair-manifest behavior is introduced.
3. AotR version compatibility rules for `A8P-INSTALL-005` still need an authoritative version source/range.
4. Production writeability checks must be designed so they do not damage game files and do not confuse source install permissions with generated runtime permissions.
5. Bounded filesystem discovery needs performance testing on large Fixed drives and removable/exFAT media.
6. Ambiguity handling must remain deterministic and must never silently fall back to first match.
7. Config V1 -> Config V2 migration must preserve existing working installs and recover cleanly from stale paths.
8. The previously prepared File Library artifacts were not byte-for-byte recoverable in this session; this GitHub checkpoint is the new versioned canonical research baseline unless the originals are later supplied for comparison.
