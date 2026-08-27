# Launcher 1.1.1 Release Checkpoint

Date: 2026-08-27

Status: `STABLE / RELEASED`

This checkpoint freezes the production identity and acceptance evidence for launcher 1.1.1, the guarded replacement for the standalone-bootstrap failure tracked in Issues #25 and #33.

## Frozen release identity

- Version: `1.1.1`
- Main release commit: `303c202ffd809dbe70fb6e2611d98ce4f9773128`
- Accepted staging commit: `19b1c5cf70c277d5892638649697c9d41d0a68ef`
- Release PR: `#34`
- Tag: `v1.1.1`
- GitHub Release: `Launcher 1.1.1`
- Launcher EXE SHA256: `2141EA9690708EA7A61B7298AD90E0C76CC417FED996AC0CF3685276BA2A4024`
- Manifest SHA256: `B5B499DCC5ADA8A5ED5FADE3E60248F0685CD48D61042F7487D34660F83B6830`
- Repair-manifest SHA256: `DE45A92444E5943D9908267C5B80D1263F957E58EBC0840A6EDD00318A7741A8`
- UI SHA256: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- Paper SHA256: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`
- Embedded/materialized skin SHA256: `BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6`
- Embedded GUI SHA256: `23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C`
- Embedded ENGINE SHA256: `94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA`
- Canonical builder: `launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_1.ps1`
- Canonical builder SHA256: `32BCAC9D82F2A8FC9651C9F6B4E655D8B161F788174854F7118D30F37EB2516F`

## Issue #33 root cause and fix

Launcher 1.1 failed before the user could reach START because its embedded GUI still loaded:

`internal\assets\launcher_skin.png`

from the runtime filesystem. The public release root intentionally contained only five flat artifacts and therefore did not ship that build-tree-only path.

Launcher 1.1.1 embeds the exact frozen skin into the outer C# bootstrapper as gzip+Base64. An explicit static `Program` constructor verifies and materializes the skin before the embedded GUI can execute.

The embedded GUI and ENGINE payload bytes remain unchanged from the accepted V18 source baseline.

## Exact-final acceptance

The exact final EXE SHA `2141EA...` was tested from a fresh isolated copy of the five intended public release files.

### Phase A — standalone boot / provisioning

- five-file root: PASS
- no pre-existing `internal/`: PASS
- exact EXE hash: PASS
- skin self-materialization: PASS
- materialized skin SHA `BA044C...`: PASS
- launcher GUI rendered and remained alive: PASS
- Auto-Repair provisioning: PASS
- intended `retry_launch` behavior observed: YES
- any game created by provisioning was closed and excluded from manual START evidence
- all five public artifacts remained byte-identical after provisioning: PASS

### Phase B — manual START

- clean process baseline before manual START: PASS
- installation row: OK
- BP WotR campaign row: OK
- 8-player WotR UI row: OK
- manual START created fresh `lotrbfme2ep1.exe`: PASS
- recorded game PID: `12428`
- game path: `D:\Games\AotR\AgeoftheRing\rotwk\lotrbfme2ep1.exe`
- stability window: `15 s` PASS
- launcher handoff/exit: PASS
- all five public artifacts remained byte-identical after START: PASS

Exact-final local acceptance report:

`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_054456\PACKAGE\_ISSUE33_EXACT_FINAL_1_1_1_ACCEPTANCE_20260827_135305\ISSUE33_EXACT_FINAL_1_1_1_ACCEPTANCE_REPORT.txt`

## Guardian CI

Required workflows passed on exact final release head `19b1c5cf70c277d5892638649697c9d41d0a68ef` before guarded merge:

- `release-consistency`: PASS
- `ticket-system`: PASS
- `guardian-tools`: PASS

The release-publisher PR and publisher-cleanup PR also passed all three required checks before merge.

## Promotion / GitHub Release

PR #34 was merged with expected-head protection.

- guarded main merge: `303c202ffd809dbe70fb6e2611d98ce4f9773128`

A one-time idempotent publisher reused the same release-hygiene mechanism previously used for v1.1:

- publisher PR: `#35`
- publisher branch commit: `3d9b4162896c39bf8f0dcda0dc67b483ad3a5d4d`
- publisher merge commit: `a755fc3894ad0ef17524d528ece8aa805b3164cc`
- publisher workflow run: `33073543355` PASS

Independent verification after publishing confirmed:

- `refs/tags/v1.1.1` points exactly to `303c202ffd809dbe70fb6e2611d98ce4f9773128`;
- GitHub Release `Launcher 1.1.1` exists and is not a prerelease;
- release notes record the accepted hashes and runtime evidence.

The temporary publisher workflow was then removed:

- cleanup PR: `#36`
- cleanup branch commit: `75277f91ac659c79723e82d574b6d9b82bccc5a4`
- cleanup merge commit: `05b9e690580a8c3aa08d8cbf5f2d5f6dc31ad326`

No temporary release publisher remains in current `main`.

## V18 compiler nondeterminism

The legacy .NET Framework `csc.exe` compilation path is byte-nondeterministic.

Two identical-input builds from the canonical 1.1.1 builder, using the same default version and release inputs, produced:

- run 1 EXE SHA256: `F71902996345E12E37800424C60D3D4F058CFA2909E19720FF03803AFD052B68`
- run 2 EXE SHA256: `E3CA46A516F0DCF7E231E905B0C7AFE064089E3D947848B916A14AAEDB6FA040`

Their PE timestamps differed, while launcher/product version, manifest semantics, repair manifest and approved payload hashes remained equivalent.

Guardian release rule:

- freeze and ship the exact runtime-tested EXE (`2141EA...`);
- freeze the canonical source builder separately (`32BCAC...`);
- do not require later recompiles to reproduce the release EXE SHA until the compiler path is deliberately made deterministic;
- never silently replace the frozen release artifact with a later recompile.

## Repository protection

Ruleset `Protect Main` (ID `21617326`) is active and protects the default/main branch with:

- PR-only updates;
- review-thread resolution;
- deletion protection;
- non-fast-forward / force-push protection;
- strict required-status policy;
- no bypass actors;
- required checks `release-consistency`, `ticket-system`, `guardian-tools`.

## Historical provenance and rollback

### Launcher 1.1 — preserved failure provenance

- release commit: `bbd7eff483d2cdbf3e799f764433b49195dc55b6`
- tag: `v1.1`
- EXE SHA256: `9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4`
- classification: `HISTORICAL_FAILURE_PROVENANCE`

Do not rewrite or delete the v1.1 tag/release/source evidence.

### Launcher 1.0.10 — historical known-good rollback

- release commit: `1303e0a6b268b082e9352ded1461fa8d794f16d3`
- EXE SHA256: `6A80E0F7B862ABE3E0F19C3DF5ED9EE9EE730F246CF603ED00A39D1EE7DFF2F8`
- classification: `HISTORICAL_ROLLBACK`

## Guardian closure

- Issue #33: `COMPLETED`
- Guardian Issue #25: `COMPLETED / RESOLVED`
- launcher 1.1.1: `STABLE / RELEASED`
- standalone skin release blocker: `CLOSED`

Future launcher work must start from or explicitly reconcile against this 1.1.1 baseline and must preserve the exact release identity, source identity and historical provenance recorded here.
