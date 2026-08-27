# Project Guardian State

Snapshot: 2026-08-27

This document records the current cross-component integration baseline. It is not a feature roadmap and does not replace detailed reverse-engineering checkpoints.

## STABLE

### Production launcher

- Version: `1.1.1`
- Main release commit: `303c202ffd809dbe70fb6e2611d98ce4f9773128`
- Accepted staging commit: `19b1c5cf70c277d5892638649697c9d41d0a68ef`
- Release tag: `v1.1.1`
- GitHub Release: `Launcher 1.1.1`
- Launcher EXE SHA256: `2141EA9690708EA7A61B7298AD90E0C76CC417FED996AC0CF3685276BA2A4024`
- Manifest SHA256: `B5B499DCC5ADA8A5ED5FADE3E60248F0685CD48D61042F7487D34660F83B6830`
- Repair-manifest SHA256: `DE45A92444E5943D9908267C5B80D1263F957E58EBC0840A6EDD00318A7741A8`
- Authoritative repository builder: `launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_1.ps1`
- Canonical builder SHA256: `32BCAC9D82F2A8FC9651C9F6B4E655D8B161F788174854F7118D30F37EB2516F`
- Embedded/materialized skin SHA256: `BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6`
- Versioned release/promotion evidence: `docs/release/LAUNCHER_1_1_1_RELEASE_CHECKPOINT.md`

Launcher 1.1.1 is the current stable production reference. It replaces the failed launcher 1.1 standalone release without rewriting the historical `v1.1` tag/release.

### Exact-final runtime acceptance

The exact final EXE hash `2141EA...` passed the Issue #33 acceptance sequence from a fresh five-file public package:

- no pre-existing `internal/` directory;
- launcher opened successfully and self-materialized the exact frozen skin;
- Auto-Repair provisioning completed; `retry_launch` behavior was observed and isolated from manual START evidence;
- explicit manual START created a fresh `D:\Games\AotR\AgeoftheRing\rotwk\lotrbfme2ep1.exe` process;
- exact-final game PID recorded: `12428`;
- game survived the configured `15 s` stability window;
- launcher handed off and exited as expected;
- all five public release artifacts remained byte-identical through provisioning and START.

The former exact-final runtime evidence gap for launcher 1.1 is therefore closed by the guarded 1.1.1 replacement release.

### Build reproducibility boundary

The V18 .NET Framework `csc.exe` build path is byte-nondeterministic. Two identical-input default-version 1.1.1 builds produced different EXE SHA256 values and different PE timestamps:

- run 1: `F71902996345E12E37800424C60D3D4F058CFA2909E19720FF03803AFD052B68`
- run 2: `E3CA46A516F0DCF7E231E905B0C7AFE064089E3D947848B916A14AAEDB6FA040`

Both builds preserved the same release semantics, version identity, repair-manifest behavior and approved payload hashes. Therefore:

- the exact runtime-tested `2141EA...` EXE is the frozen release artifact;
- the `32BCAC...` FINAL_1_1_1 builder is the canonical source identity;
- later recompiles are not required to reproduce the frozen EXE SHA256 byte-for-byte unless the compiler pipeline is deliberately made deterministic.

### Approved payload hashes

- `payload_ui.big`: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- `payload_paper.inc`: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`

## COMPLETED / INTEGRATED

### Issue #33 — standalone skin bootstrap

- Owner issue: `#33`
- Guarded release PR: `#34`
- Status: `RESOLVED / RELEASED`
- Root cause: the embedded GUI still expected `internal\assets\launcher_skin.png` on disk although the public release contract contained only five root artifacts.
- Fix: the exact skin is gzip+Base64 embedded into the outer bootstrapper and SHA-verified/materialized before the embedded GUI starts.

The historical launcher 1.1 release remains preserved as reproduced-failure provenance:

- release commit: `bbd7eff483d2cdbf3e799f764433b49195dc55b6`
- tag: `v1.1`
- failed EXE SHA256: `9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4`

Do not rewrite or delete that historical evidence.

### Robust AotR auto-detection

- Pull request: `#21`
- Former branch: `feature/robust-aotr-autodetect`
- Status: `COMPLETED / INTEGRATED`
- Ownership: Launcher / Robustness
- Research location: `research/installer/**`

Historical robustness checkpoints intentionally retain the assumptions and intermediate failures that were true when each experiment was performed. Do not silently rewrite them as if they described the current release.

## CROSS-COMPONENT OWNERSHIP

| Component | Primary owner | Guardian rule |
| --- | --- | --- |
| Launcher path/install detection | Launcher / Robustness | Integrated in the 1.1.1 production line; future changes start from current production baseline |
| Auto-Repair / launcher process handling | Launcher / Robustness | Cross-component because ticket reporting consumes repair results |
| GitHub ticket creation/triage/clustering | Ticket System | Do not change launcher runtime unless coordinated |
| `REPORT ERROR` / support bundle / Messages | Ticket System + Launcher integration | Regression gate for future launcher builds |
| `game.dat`, WotR network/player logic, RAM patches | Reverse Engineering | Experimental results must remain isolated from release baseline until integration review |
| APT/UI/BIG research | Reverse Engineering | Preserve hashes and working references |
| Research checkpoints | Documentation / owning research task | Never delete based on filename/age alone |
| Cross-component release integration | Project Guardian | No direct promotion before consistency/regression review |

## CRITICAL SHARED FILES

Changes to any of the following require cross-task review before release integration:

- `AotR 8P WotR Mod.exe`
- `launcher-source/**`
- `manifest.json`
- `repair-manifest.json`
- `payload_ui.big`
- `payload_paper.inc`
- `.github/workflows/**`
- `.github/ISSUE_TEMPLATE/**`
- `.github/labels.yml`

Local equivalents of the launcher builder, runtime patch inputs, `game.dat`, BIG/APT payload sources and packaging scripts are also shared integration surfaces even when they are newer than GitHub.

## SOURCES OF TRUTH

1. `main` is the source of truth for currently versioned project/release files.
2. Tag `v1.1.1`, release commit `303c202f...`, and EXE SHA256 `2141EA...` identify the current launcher production release independently of later documentation/cleanup merges to `main`.
3. `docs/release/LAUNCHER_1_1_1_RELEASE_CHECKPOINT.md` is the compact versioned launcher 1.1.1 promotion/evidence checkpoint.
4. Tag `v1.1` and EXE SHA `9F2D79...` are historical reproduced-failure provenance, not a current working baseline.
5. Launcher 1.0.10 EXE SHA `6A80E0F7B862ABE3E0F19C3DF5ED9EE9EE730F246CF603ED00A39D1EE7DFF2F8` remains the historical known-good rollback reference.
6. Reproducible runtime tests override older assumptions when the test conditions and tested hash are documented.
7. Historical working builds and failed experiments remain references unless explicitly classified otherwise.

## CURRENT INTEGRATION GATES

A future launcher build must demonstrate at minimum:

- clean normal launch from a fresh isolated public package;
- no unintended runtime dependency on research/build-tree-only assets;
- existing compatibility checks still pass;
- existing 8-player runtime patches and FINAL_STABLE_V7 still activate correctly;
- robust install detection does not select runtime/research/backup copies as production installs;
- ambiguous top candidates fail safely instead of choosing arbitrarily;
- Auto-Repair remains bounded and preserves its intended retry behavior;
- `REPORT ERROR`, support fingerprint/bundle and `MESSAGES` behavior remain intact;
- release EXE and payload hashes match the manifests;
- the exact final EXE hash used for release is tied to recorded runtime acceptance;
- the canonical builder source identity is recorded separately from the frozen EXE hash while the legacy compiler remains byte-nondeterministic;
- rollback references remain preserved.

## CI / PROTECTION

Repository ruleset `Protect Main` is active for `main` and the default branch. It enforces:

- pull-request-only updates;
- review-thread resolution;
- deletion protection;
- non-fast-forward / force-push protection;
- strict required-status policy;
- no bypass actors;
- required checks:
  - `release-consistency`
  - `ticket-system`
  - `guardian-tools`

The Issue #33 exact-final release head, the v1.1.1 publisher PR and the publisher-cleanup PR all passed all three required checks before merge.

## CLEANUP CLASSIFICATION

Current policy:

- launcher 1.1.1 EXE/manifests/payloads: `KEEP / CURRENT_PRODUCTION`
- `BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_1.ps1`: `KEEP / CURRENT_CANONICAL_SOURCE`
- launcher 1.1 release/tag/builder/evidence: `KEEP / HISTORICAL_FAILURE_PROVENANCE`
- launcher 1.0.10 final builder/release evidence: `KEEP / HISTORICAL_ROLLBACK`
- V17 / 1.0.9 validated material: `RESEARCH_REFERENCE / ARCHIVE`, not delete-on-sight
- `research/installer/**`: `RESEARCH_REFERENCE / KEEP`
- merged feature/fix branches: `REVIEW_REQUIRED` before any branch deletion
- unknown local or GitHub artifacts: `REVIEW_REQUIRED`

## OPEN GUARDIAN RISKS

### CONTROLLED — legacy compiler byte nondeterminism

The current V18 builder line does not produce byte-identical EXEs across repeated compiles. This is documented and controlled by freezing the exact runtime-tested release EXE separately from the canonical source builder. Do not silently substitute a later recompile into a release solely because it came from the same source.

### HISTORICAL — launcher 1.1 standalone defect

Launcher 1.1 remains intentionally preserved as failure provenance for Issue #33. It must not be reclassified as a working rollback reference. Launcher 1.0.10 remains the historical known-good rollback if a rollback older than 1.1.1 is required.

There is no remaining open release blocker from Guardian issues #25/#33 for launcher 1.1.1.
