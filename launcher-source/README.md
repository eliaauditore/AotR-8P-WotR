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

## V18 ticket-system release candidate

A V18 source candidate has now been generated from the verified V17 baseline. It is **not released yet** and must pass a Windows build/runtime test before any public release artifact is changed.

Candidate builder:

`BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_TICKET_SYSTEM.ps1`

Verified candidate properties:

- Size: `258302` bytes
- SHA256: `3119B095F1D603D3E31BC26073967F51EF737245ED2B353BD1E3DD622ACF6250`
- Embedded GUI SHA256: `B8380F4D03DE10BE78452536CF87B1101D3F246D49D5A40FA3A70DAF35917D84`
- Embedded engine SHA256: `D94460492ACD2B98CB8DF0929E302C2F626A97045AAEE9593A2B29E9424FEA5B`
- Embedded engine is byte-identical to V17.
- C# wrapper outside the embedded GUI blob is byte-identical to V17.
- Main, diagnostics, and Messages XAML all parse as well-formed XML.
- Static PowerShell token/bracket balance check passes.
- No obvious GitHub token/API secret/email/personal `C:\Users\...` path was found in the candidate source.

### V18 behavior

- Computes a stable local `A8P-FP-*` fingerprint using the same normalized error signature as GitHub triage.
- Records Auto-Repair actions/results and writes `support_bundle_latest.json` locally.
- Sanitizes default report text for user/profile/package/AotR paths, computer/user names, IPv4, IPv6, and MAC addresses.
- Fixes the V17 repair loop: one Auto-Repair cycle -> one automatic retry -> `REPORT ERROR` if the retry still fails.
- Adds `RETRY` and `REPORT ERROR` to the final diagnostics state.
- Opens a user-reviewed prefilled GitHub issue; no repository write credential is embedded in the launcher.
- Uses a compact prefill fallback if the GitHub issue URL would exceed a conservative safe length, while preserving the full support bundle locally and on the clipboard.
- Adds `MESSAGES` plus a local unread indicator and public master-ticket maintainer-message lookup.
- Read/unread state remains local; no read receipt or player/device identity is sent to GitHub.

## Safety rule

Do not change the current public launcher EXE, `manifest.json`, `repair-manifest.json`, `payload_ui.big`, or `payload_paper.inc` merely by adding source material here.

The 1.0.9 baseline must remain reproducible. Functional launcher changes are promoted only after source verification and a Windows build/runtime regression test.

## Remaining gate

1. Build V18 on Windows with `-BundleOnly -EmitGitHubBundle` so the installed 1.0.9 launcher is not replaced.
2. Launch the generated candidate from `_GITHUB_UPDATE` and smoke-test normal launch, Auto-Repair failure -> Report Error, fingerprint/support bundle, and Messages UI.
3. Only after the smoke test passes, commit the exact source artifacts, open the integration PR, run repository checks, and promote a new public launcher version.
