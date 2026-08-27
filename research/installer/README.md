# Installer / AotR Auto-Detection Research

This directory is the canonical GitHub handoff for the robust standalone Age of the Ring path-resolution work.

## STATUS

**Preparation / research only.**

The current public launcher release is not modified by this directory.

Production integration is blocked only on identifying the authoritative Windows launcher builder and its embedded GUI/engine resolver code on the canonical development machine.

## FILE INDEX

### `AOTR_8P_ROBUST_AUTODETECT_CHECKPOINT_V1.md`

**Canonical knowledge checkpoint.**

Read this first when resuming the work.

Contains:

- STATUS
- WHAT WE KNOW
- EVIDENCE
- WHAT FAILED
- CURRENT HYPOTHESIS
- FILES / HASHES / OFFSETS
- SAFE TESTS COMPLETED
- NEXT PRACTICAL ACTION
- DO NOT REPEAT
- open risks

Do not redo reverse engineering already recorded there unless new evidence contradicts it.

### `AOTR_8P_ROBUST_AUTODETECT_INTEGRATION_PLAN_V1.md`

**Production architecture contract.**

Defines how the eventual launcher implementation should work:

```text
validated Config V2 cache
-> AOTR_HOME
-> launcher/install environment
-> normal local Fixed drives
-> bounded AgeoftheRing search
-> removable / USB / exFAT local drives
-> validate / deduplicate / score
-> unique result, user choice, or folder browser
```

Also defines GUI/engine unification, error classes, repair-manifest safety and the production test matrix.

### `AOTR_8P_ROBUST_AUTODETECT_PROTOTYPE_V1.ps1`

**READ-ONLY detection prototype.**

It does not write files, registry, config, game state or launcher state.

Current behavior includes:

- cached valid installation fast path;
- validated `AOTR_HOME` priority;
- full candidate collection when discovery is required;
- canonicalization and deduplication;
- hard standalone AotR validation;
- scoring/ranking;
- `_AotR8P_WotR_Runtime` and All-in-One rejection;
- research/backup/checkpoint/temp deprioritization;
- normal Fixed drives before Removable/USB/exFAT;
- no automatic recursive network scan;
- ambiguity result `A8P-INSTALL-002` rather than first-match selection;
- optional `-AuditAllCandidates` research mode.

This is not production launcher source.

### `AOTR_8P_LAUNCHER_SOURCE_AUDIT_V1.md`

**GitHub/source-availability audit.**

Records that the authoritative V17 Windows builder is not present in `main` or the currently exposed feature/fix branches and was not found through the relevant commit-history searches.

Also records the known V17 builder candidate filenames and known checkpoint hashes from the Windows research workspace.

### `AOTR_8P_MAIN_PC_SOURCE_AUDIT_V1.ps1`

**READ-ONLY main-PC source audit helper.**

Run this when back on the canonical Windows research/build machine.

First pass:

```powershell
pwsh -File .\research\installer\AOTR_8P_MAIN_PC_SOURCE_AUDIT_V1.ps1
```

This searches the known research roots for V17 builder candidates and prints:

- full path;
- size;
- timestamp;
- SHA256;
- whether known checkpoint metadata matches.

Do **not** select the newest timestamp automatically.

After one builder is proven to be the correct integration base:

```powershell
pwsh -File .\research\installer\AOTR_8P_MAIN_PC_SOURCE_AUDIT_V1.ps1 `
    -InspectPath 'D:\FULL\PATH\TO\CONFIRMED_BUILDER.ps1'
```

This prints relevant source hits and approximate enclosing functions for:

- AotR path detection;
- `AOTR_HOME`;
- `AgeoftheRing`;
- `lotrbfme2ep1.exe`;
- runtime path logic;
- `game.dat` / `zGameDats`;
- config logic;
- repair-manifest action names;
- REPORT ERROR / launcher GUI markers.

It performs no edits.

### `aotr-config-v2.example.json`

**Target persisted config shape.**

Example only; the research prototype does not write it.

## MAIN-PC RESUME ORDER

Use this order when development resumes on the Windows machine:

```text
1. Pull/inspect feature/robust-aotr-autodetect.
2. Read AOTR_8P_ROBUST_AUTODETECT_CHECKPOINT_V1.md.
3. Run AOTR_8P_MAIN_PC_SOURCE_AUDIT_V1.ps1 without -InspectPath.
4. Compare V17 candidate hashes and feature lineage.
5. Prove the authoritative builder.
6. Re-run the source audit with -InspectPath.
7. Record exact GUI resolver.
8. Record exact engine resolver.
9. Record Config V1 read/write logic.
10. Record repair dispatcher / allowlist.
11. Update the checkpoint with exact functions/lines/hashes.
12. Only then integrate the shared resolver.
13. Build a NON-RELEASE test EXE.
14. Run the documented test matrix.
15. Verify Auto-Repair + REPORT ERROR regressions.
16. Only after successful validation prepare a release update.
```

## NAMING RULES

Research files in this directory use:

```text
AOTR_8P_<SUBJECT>_<TYPE>_V<number>.<ext>
```

Examples:

```text
AOTR_8P_ROBUST_AUTODETECT_CHECKPOINT_V1.md
AOTR_8P_ROBUST_AUTODETECT_PROTOTYPE_V1.ps1
AOTR_8P_MAIN_PC_SOURCE_AUDIT_V1.ps1
```

Keep major checkpoints immutable where practical. If assumptions materially change, create or explicitly promote a new version rather than silently erasing historical evidence.

## RELEASE-SAFETY BOUNDARY

Files in this directory must not be treated as a release by themselves.

In particular, research work must not silently modify:

```text
AotR 8P WotR Mod.exe
manifest.json
repair-manifest.json
payload_ui.big
payload_paper.inc
```

Any future change to those files must belong to a separately validated launcher/release step.

## DO NOT REPEAT

- Do not involve All-in-One Launcher in AotR detection.
- Do not search only for `lotrbfme2ep1.exe`.
- Do not modify only the GUI resolver.
- Do not use first-valid-candidate-wins.
- Do not treat `_AotR8P_WotR_Runtime` as a real AotR installation.
- Do not automatically prefer `BFME_RESEARCH`, backup, checkpoint or temp copies.
- Do not recursively scan network drives automatically.
- Do not blindly patch the public release EXE.
- Do not invent new repair actions before proving the internal dispatcher/allowlist.
- Do not choose the authoritative V17 builder solely by timestamp.
- Do not edit a builder before recording its exact hash/checkpoint.
