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

## Safety rule

Do not change the current public launcher EXE, `manifest.json`, `repair-manifest.json`, `payload_ui.big`, or `payload_paper.inc` merely by adding source material here.

The first source commit should preserve the exact 1.0.9 builder byte-for-byte. Functional launcher changes belong in later commits after the baseline source hash is verified.

## Planned ticket-system integration

After the exact baseline builder is committed:

1. Extract/version the embedded GUI and engine payloads reproducibly.
2. Add local support-fingerprint generation matching GitHub fallback semantics.
3. Add support-bundle generation with privacy-safe fields only.
4. Show `REPORT ERROR` only after Auto-Repair is exhausted and retry still fails.
5. Open a prefilled GitHub issue; do not embed a GitHub write token in the public launcher.
6. Add `MESSAGES` with local unread state and public master-ticket comment polling.
7. Rebuild as a new launcher version and regression-test before touching release artifacts.
