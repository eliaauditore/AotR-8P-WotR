# Launcher source baseline

This directory contains the authoritative source/build material for the public AotR 8P WotR launcher.

## Current production baseline

The current GitHub production baseline is launcher **1.1.1**.

Public release identity:

- Main release commit: `303c202ffd809dbe70fb6e2611d98ce4f9773128`
- Accepted staging commit: `19b1c5cf70c277d5892638649697c9d41d0a68ef`
- Release tag: `v1.1.1`
- GitHub Release: `Launcher 1.1.1`
- Launcher EXE SHA256: `2141EA9690708EA7A61B7298AD90E0C76CC417FED996AC0CF3685276BA2A4024`
- Manifest SHA256: `B5B499DCC5ADA8A5ED5FADE3E60248F0685CD48D61042F7487D34660F83B6830`
- Repair-manifest SHA256: `DE45A92444E5943D9908267C5B80D1263F957E58EBC0840A6EDD00318A7741A8`
- UI SHA256: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- Paper SHA256: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`
- Embedded/materialized skin SHA256: `BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6`

Authoritative repository builder:

`launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_1.ps1`

Canonical FINAL_1_1_1 builder SHA256:

`32BCAC9D82F2A8FC9651C9F6B4E655D8B161F788174854F7118D30F37EB2516F`

The repository Release Consistency, Ticket System and Guardian Tools workflows all passed on the exact final PR head before promotion.

## Exact-final runtime acceptance

Launcher 1.1.1 closes the standalone-bootstrap defect tracked in Issue #33. The exact frozen EXE `2141EA...` was tested from a fresh package containing only the five intended public release artifacts.

Recorded acceptance:

- no pre-existing `internal/` directory;
- launcher opened successfully;
- bootstrap self-materialized `internal\assets\launcher_skin.png` with the exact frozen skin SHA;
- Auto-Repair provisioning completed, including the intended `retry_launch` behavior;
- the provisioning-launched game was explicitly separated from manual START evidence;
- a fresh launcher instance then reached all required `OK` rows;
- explicit manual START created a new `D:\Games\AotR\AgeoftheRing\rotwk\lotrbfme2ep1.exe` process;
- exact-final game PID: `12428`;
- game survived the configured `15 s` stability window;
- launcher handed off and exited as expected;
- all five public release files remained byte-identical through provisioning and START.

The earlier exact-final runtime-evidence gap recorded for launcher 1.1 is therefore closed by launcher 1.1.1.

Versioned checkpoint:

`docs/release/LAUNCHER_1_1_1_RELEASE_CHECKPOINT.md`

## Standalone skin fix

Launcher 1.1 failed before START because the embedded GUI still expected the build-tree path:

`internal\assets\launcher_skin.png`

while the public release contract contained only five flat root artifacts.

Launcher 1.1.1 keeps the skin as a build-time input but gzip+Base64 embeds its exact bytes into the outer C# bootstrapper. An explicit static `Program` constructor SHA-verifies and materializes the skin before the embedded GUI executes.

The embedded GUI and ENGINE payload bytes from the accepted V18 baseline remain unchanged.

## Build reproducibility boundary

The legacy V18 .NET Framework `csc.exe` path is **byte-nondeterministic** across repeated compiles.

Two identical-input 1.1.1 default-version builds produced different EXE hashes:

- `F71902996345E12E37800424C60D3D4F058CFA2909E19720FF03803AFD052B68`
- `E3CA46A516F0DCF7E231E905B0C7AFE064089E3D947848B916A14AAEDB6FA040`

and different PE timestamps while preserving the same launcher/product version, manifest semantics, repair behavior and approved payload hashes.

Therefore the project records two separate identities:

1. **Frozen release artifact:** exact runtime-tested EXE SHA `2141EA...`.
2. **Canonical source identity:** FINAL_1_1_1 builder SHA `32BCAC...`.

A later compile from the same source is not expected to reproduce `2141EA...` byte-for-byte unless the compiler pipeline is deliberately made deterministic. Never silently substitute a later recompile into the release solely because the source is the same.

## Historical launcher 1.1 failure provenance

Launcher 1.1 is **not** the current production baseline and is **not** a known-good rollback reference.

Preserve it as reproduced-failure evidence for Issue #33:

- release commit: `bbd7eff483d2cdbf3e799f764433b49195dc55b6`
- tag: `v1.1`
- GitHub Release: `Launcher 1.1`
- failed standalone EXE SHA256: `9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4`
- historical builder: `launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1.ps1`

Do not rewrite the historical tag/release or delete its source/evidence merely because 1.1.1 supersedes it.

## Historical 1.0.10 / V18 rollback reference

Launcher 1.0.10 remains the historical known-good rollback reference older than 1.1.1.

- release commit: `1303e0a6b268b082e9352ded1461fa8d794f16d3`
- builder: `launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10.ps1`
- EXE SHA256: `6A80E0F7B862ABE3E0F19C3DF5ED9EE9EE730F246CF603ED00A39D1EE7DFF2F8`

The exact 1.0.10 EXE was previously regression-tested from a fresh isolated package: compatibility checks passed, the existing 8-player runtime path activated, AotR started successfully, and the launcher exited cleanly after game start. Its ticket-system E2E path was also validated through the RC5/RC6 checkpoint sequence.

## Historical 1.0.9 / V17 reference

The validated 1.0.9/V17 material remains older research/rollback evidence and is not current production.

Local source reference:

`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_LAN_UI_POLISH.ps1`

Verified historical source properties:

- size: `249043` bytes
- SHA256: `5F806FB048BF7761252AC9D7B557B0177D71C3E9FFEA1E9003CD4DC300867E2C`

## Stable launcher behavior carried forward

The current production line preserves the validated launcher behavior required by future regressions:

- existing 8-player runtime path and FINAL_STABLE_V7;
- robust AotR Config V2 discovery/validation;
- local `A8P-FP-*` fingerprint generation;
- privacy-safe support-bundle generation;
- bounded Auto-Repair and retry behavior;
- `REPORT ERROR` after repair exhaustion;
- prefilled GitHub issue reporting without an embedded write token;
- `MESSAGES` with local unread state and master-ticket updates;
- dynamic launcher status rows;
- custom topbar behavior;
- PowerShell 7 build-host compatibility via the Windows PowerShell automation assembly;
- .NET SHA256 implementations in embedded runspaces rather than relying on `Get-FileHash`.

Their presence in prior versions is not automatic proof for a future EXE. Test the exact final release artifact and record its identity.

## Robust auto-detection research

The completed robustness research and its reproducible audit/test history are preserved under:

`research/installer/**`

Historical files in that directory intentionally retain the assumptions and intermediate failures that were true at the time of each experiment. They are research evidence, not current release metadata.

## Safety rule

The current 1.1.1 production working set is:

- `AotR 8P WotR Mod.exe`
- `manifest.json`
- `repair-manifest.json`
- `payload_ui.big`
- `payload_paper.inc`
- `launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1_1.ps1`

Do not overwrite these files as part of unrelated research or cleanup.

Future release work must:

- start from or explicitly reconcile against the current production baseline;
- pass `release-consistency`, `ticket-system` and `guardian-tools`;
- test and freeze the exact final EXE hash;
- document the exact final runtime result;
- preserve the canonical builder/source identity separately;
- preserve historical failure and rollback references.
