# Launcher source baseline

This directory contains the authoritative source/build material for the public AotR 8P WotR launcher.

## Current production baseline

The current GitHub production baseline is launcher **1.1**.

Release commit:

`bbd7eff483d2cdbf3e799f764433b49195dc55b6`

Canonical 1.1 builder commit:

`7072e19bd43a350da0344b1b5e32ab9d052b3404`

Authoritative repository builder:

`launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1.ps1`

Approved production launcher EXE SHA256:

`9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4`

The repository Release Consistency workflow passed for the canonical 1.1 builder commit and verified the versioned EXE hash, payload hashes, repair-manifest version/action set, and presence of the FINAL 1.1 builder.

### Runtime-evidence boundary

The repository integrity gate proves file/metadata consistency. It does **not** by itself prove launcher/game runtime behavior. At the current Guardian checkpoint, no versioned document was found that explicitly ties the complete final runtime regression matrix to the exact final 1.1 EXE hash above. That evidence remains `REVIEW_REQUIRED` until recorded or located.

### Source-comment note

The canonical `FINAL_1_1` builder inherits an introductory source comment that says `V18 FINAL 1.0.10`, while its actual default `LauncherVersion` parameter is `1.1` and the release consistency gate identifies it as the current 1.1 FINAL builder. This is non-functional historical comment metadata.

Do **not** modify the already released canonical builder solely to cosmetically change that comment. Correct it in the next deliberate builder revision while preserving this exact 1.1 source as a working reference.

## Historical 1.0.10 / V18 reference

Launcher 1.0.10 remains a historical working/rollback reference. It is **not** the current production baseline.

Release commit:

`1303e0a6b268b082e9352ded1461fa8d794f16d3`

Authoritative repository builder:

`launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10.ps1`

Validated local Windows builder SHA256 before Git line-ending normalization:

`7D847B66CAF060F3E1C5FD539DA3DF6E97865421651608CDD98898342C1BB2E0`

Approved 1.0.10 launcher EXE SHA256:

`6A80E0F7B862ABE3E0F19C3DF5ED9EE9EE730F246CF603ED00A39D1EE7DFF2F8`

The exact 1.0.10 EXE hash above was previously regression-tested from a fresh isolated package: compatibility checks passed, the existing 8-player runtime path activated, AotR started successfully, and the launcher exited cleanly after game start. Its ticket-system E2E path was also validated through the RC5/RC6 checkpoint sequence.

Git may normalize PowerShell source from CRLF to LF when committing text. Therefore a raw repository-byte SHA256 of a builder source file is not automatically expected to equal a separately recorded local Windows source hash unless the byte representation is explicitly preserved.

## Historical 1.0.9 / V17 reference

The following information is retained as an older working research/rollback checkpoint. It is **not** the current production baseline.

Local source path used for launcher 1.0.9:

`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_LAN_UI_POLISH.ps1`

Verified duplicate release snapshot:

`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\RELEASE_1_0_9_UI_POLISH_20260822_183040\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_LAN_UI_POLISH.ps1`

Expected source properties:

- Size: `249043` bytes
- SHA256: `5F806FB048BF7761252AC9D7B557B0177D71C3E9FFEA1E9003CD4DC300867E2C`
- LastWriteTime: `2026-08-22 18:30:40` local time

Both local copies were verified byte-identical before the original launcher-source branch was created.

## Stable launcher behavior carried forward from the validated V18 line

The validated launcher line includes:

- the existing 8-player runtime path and FINAL_STABLE_V7;
- local `A8P-FP-*` fingerprint generation;
- privacy-safe support-bundle generation;
- bounded Auto-Repair and retry behavior;
- `REPORT ERROR` after repair exhaustion;
- prefilled GitHub issue reporting without an embedded write token;
- `MESSAGES` with local unread state and master-ticket updates;
- dynamic launcher status rows;
- PowerShell 7 build-host compatibility via the Windows PowerShell automation assembly;
- .NET SHA256 implementations in embedded runspaces rather than relying on `Get-FileHash`.

These carried-forward behaviors are regression requirements for future launcher builds. Their presence in prior validated versions must not be treated as automatic proof that an untested later EXE behaves identically; test the exact final release hash and record the result.

## Robust auto-detection research

The completed robustness research and its reproducible audit/test history are preserved under:

`research/installer/**`

Historical files in that directory intentionally retain the assumptions and intermediate failures that were true at the time of each experiment. They are research evidence, not current release metadata.

## Safety rule

The current 1.1 working reference consists of:

- `AotR 8P WotR Mod.exe`
- `manifest.json`
- `repair-manifest.json`
- `payload_ui.big`
- `payload_paper.inc`
- `launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1.ps1`

Do not overwrite these files as part of unrelated research or cleanup. Future release work must start from or explicitly reconcile against the current production baseline, pass the Release Consistency gate, document the exact final EXE hash, and preserve a rollback path.

The 1.0.10 and 1.0.9/V17 materials remain historical working/research references and must not be deleted merely because 1.1 is newer.
