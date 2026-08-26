# Launcher source baseline

This directory is reserved for the authoritative source/build material for the public AotR 8P WotR launcher.

## 1.0.9 authoritative baseline

Local source path used for launcher 1.0.9:

`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_LAN_UI_POLISH.ps1`

Verified duplicate release snapshot:

`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\RELEASE_1_0_9_UI_POLISH_20260822_183040\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_LAN_UI_POLISH.ps1`

Verified source properties:

- Size: `249043` bytes
- SHA256: `5F806FB048BF7761252AC9D7B557B0177D71C3E9FFEA1E9003CD4DC300867E2C`
- LastWriteTime: `2026-08-22 18:30:40` local time

Both local copies were byte-identical.

## V18 / launcher 1.0.10 ticket integration

The production candidate adds:

- local `A8P-FP-*` fingerprint generation matching GitHub fallback semantics;
- privacy-safe support-bundle generation;
- one bounded Auto-Repair cycle followed by one automatic retry;
- `REPORT ERROR` only after Auto-Repair is exhausted and the retry still fails;
- prefilled GitHub issue reporting without a GitHub write token in the launcher;
- public master-ticket lookup and `MESSAGES` with local unread/read state;
- a dynamic launcher status panel showing installation, WotR campaign, UI, repair, launch and runtime state;
- PowerShell 7 build-host compatibility by explicitly compiling against the Windows PowerShell 5.1 automation assembly;
- pure .NET SHA256 in all embedded GUI, engine and FINAL_STABLE_V7 paths so the embedded runspace does not depend on `Get-FileHash`.

## Windows validation history

The RC sequence deliberately exposed and fixed several runtime/toolchain issues before release:

- RC1: built successfully under Windows PowerShell 5.1; exposed embedded-runspace hash dependency and stale OS version reporting.
- RC2: PowerShell 7 build-host fix and GUI/preflight .NET SHA256; exposed an engine-side `Get-FileHash` dependency.
- RC3: engine hash fix; normal launch reached `FINAL_STABLE_V7` and exposed one final nested V7 `Get-FileHash` dependency.
- RC4: added the dynamic middle status panel so launcher health is visible without relying on text baked into the skin.
- RC5: removed the final nested `Get-FileHash`; normal production path passed: compat check, 7/7 runtime signatures, 8-player slot patch, strategic-row patch, FINAL_STABLE_V7, successful game start, clean launcher exit.
- RC6 E2E: added an opt-in synthetic `A8P_TEST_FORCE_ERROR=1` hook with retry-only repair semantics solely to validate support plumbing without modifying game files.

## Ticket-system E2E proof

Synthetic GitHub issue `#22` / `A8P-TICKET-0022` used fingerprint `A8P-FP-0EFAAC6AF17B` and verified the complete path:

`Launcher failure -> bounded Auto-Repair -> REPORT ERROR -> prefilled GitHub issue -> ticket metadata -> fingerprint/master assignment -> maintainer reply -> Master Ticket Broadcast -> needs-retest -> launcher MESSAGES red unread dot -> message rendering -> local read state clears dot`.

The generated report also verified:

- Windows 11 25H2/build detection;
- real `game.dat`, UI payload and PaperScenario SHA256 values;
- support-bundle repair plan/history;
- no username, machine name, IP address, MAC address or account identity in the default bundle.

Issue #22 was closed after successful validation and marked `fixed`.

## Production rule

The synthetic RC6 test hook must not ship. The production 1.0.10 builder is based on the proven RC5 production logic, with no `A8P_TEST_FORCE_ERROR`, no `A8P-TEST-001`, and no synthetic failure strings.

Do not update the public launcher EXE, `manifest.json`, `repair-manifest.json`, `payload_ui.big`, or `payload_paper.inc` until the final 1.0.10 build is produced and one final normal-launch regression passes.
