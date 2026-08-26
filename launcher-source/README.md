# Launcher source baseline

This directory is reserved for the authoritative source/build material for the public AotR 8P WotR launcher.

## Current authoritative launcher builder

Local source path used for launcher 1.0.9:

`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_LAN_UI_POLISH.ps1`

Verified duplicate release snapshot:

`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\RELEASE_1_0_9_UI_POLISH_20260822_183040\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_LAN_UI_POLISH.ps1`

Expected source properties:

- Size: `249043` bytes
- SHA256: `5F806FB048BF7761252AC9D7B557B0177D71C3E9FFEA1E9003CD4DC300867E2C`
- LastWriteTime: `2026-08-22 18:30:40` local time

Both local copies were verified byte-identical before this branch was created.

## V18 / launcher 1.0.10 validation

The V18 launcher adds:

- local `A8P-FP-*` fingerprint generation;
- privacy-safe support-bundle generation;
- one bounded Auto-Repair cycle followed by one automatic retry;
- `REPORT ERROR` only after Auto-Repair is exhausted and retry still fails;
- prefilled GitHub issue reporting without embedding a GitHub write token;
- `MESSAGES` with local unread state, red unread indicator, refresh, and master-ticket updates;
- dynamic launcher status rows for AotR installation, 8P campaign payload, 8-player WotR UI, and overall readiness;
- PowerShell 7 build-host compatibility by explicitly compiling against the Windows PowerShell automation assembly;
- .NET SHA256 implementations in GUI, engine, and nested FINAL_STABLE_V7 code so embedded runspaces do not depend on `Get-FileHash`.

### Runtime validation completed

The production logic was validated through multiple isolated RC builds on Windows:

- RC5 normal path: compatibility check passed, all seven runtime signatures matched, 8-player slot patch `06 -> 08` succeeded, strategic player rows `06 -> 08` succeeded, FINAL_STABLE_V7 activated, AotR launched, and the launcher exited cleanly after game start.
- RC6 synthetic E2E path: controlled `A8P-TEST-001` failure -> bounded Auto-Repair -> automatic retry -> `REPORT ERROR` -> GitHub issue #22 / `A8P-TICKET-0022` -> fingerprint/master processing -> maintainer reply -> launcher `MESSAGES` red unread dot -> message rendering -> local read-state clearing. No game files were modified by the synthetic test.
- Synthetic issue #22 was closed after successful validation and marked fixed.

RC6 is test-only and must not ship because it contains the synthetic `A8P_TEST_FORCE_ERROR` hook.

### Final production build checkpoint

A final production builder derived from the proven RC5 logic contains no synthetic test hook.

Final builder checks:

- `A8P_TEST_FORCE_ERROR`: 0 occurrences
- `A8P-TEST-001`: 0 occurrences
- synthetic validation error string: 0 occurrences
- `Get-FileHash`: 0 occurrences
- Builder SHA256: `7D847B66CAF060F3E1C5FD539DA3DF6E97865421651608CDD98898342C1BB2E0`

Successful `-EmitGitHubBundle -BundleOnly` production build:

- Launcher version: `1.0.10`
- Launcher EXE SHA256: `6A80E0F7B862ABE3E0F19C3DF5ED9EE9EE730F246CF603ED00A39D1EE7DFF2F8`
- Build completed without replacing the local installed launcher.

### Final regression passed

The exact final EXE hash above was copied into a fresh isolated test package and launched normally on Windows. The final `1.0.10` build completed compatibility checks, activated the existing 8P runtime path, started AotR successfully, produced no Auto-Repair/error state, and the launcher exited cleanly after game start.

This exact EXE hash is the approved production release candidate.

## Safety rule

The current public `1.0.9` launcher EXE, `manifest.json`, `repair-manifest.json`, `payload_ui.big`, and `payload_paper.inc` remain unchanged on `main` until the separately generated five-file `1.0.10` update bundle is deliberately promoted.
