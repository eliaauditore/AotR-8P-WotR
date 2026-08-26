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

A V18 candidate has been derived from the verified V17 source with launcher-side support for:

- local `A8P-FP-*` fingerprint generation;
- privacy-safe support-bundle generation;
- a single Auto-Repair cycle followed by one automatic retry;
- `REPORT ERROR` only after Auto-Repair is exhausted and the retry still fails;
- prefilled GitHub issue reporting without embedding a GitHub write token;
- `MESSAGES` with local unread state and public master-ticket update checks.

Static verification performed before the first Windows build confirmed that the embedded engine payload remained byte-identical to V17 and that launcher changes were confined to the GUI/support payload.

### First successful Windows build

The first V18 RC build succeeded on 2026-08-27 using Windows PowerShell 5.1 as the build host:

- Launcher version: `1.0.10-rc1`
- RC EXE SHA256: `78BA3FA066ED53467ADC7E1356394456C2ABB21883DA4CA16880630D1CB176DB`
- Build mode: `-EmitGitHubBundle -BundleOnly`
- Result: update launcher built without replacing the installed/local launcher.

A PowerShell 7.6.5 build attempt failed because the legacy .NET Framework C# compiler was handed the .NET 10 `System.Management.Automation.dll`. This is a build-host/toolchain mismatch, not a launcher-runtime or ticket-system failure. Windows PowerShell 5.1 proved the existing V18 source builds successfully. A follow-up builder compatibility fix should explicitly select the Windows PowerShell 5.1 automation assembly when invoked from PowerShell 7.

## Safety rule

Do not change the current public launcher EXE, `manifest.json`, `repair-manifest.json`, `payload_ui.big`, or `payload_paper.inc` merely by adding source material here.

The first source commit should preserve the exact 1.0.9 builder byte-for-byte. Functional launcher changes belong in later commits after the baseline source hash is verified.

## Planned ticket-system integration

1. Version the exact V17 baseline source and reproducible embedded payload extraction.
2. Version the V18 ticket-system builder after runtime validation.
3. Validate the V18 RC GUI and normal launch path on Windows.
4. Validate `MESSAGES` and local unread state.
5. Validate an exhausted Auto-Repair path and `REPORT ERROR` end-to-end with a controlled synthetic failure.
6. Validate that the generated support bundle matches `docs/support-bundle.schema.json` and contains no personal absolute paths or identifiers.
7. Validate the PowerShell 7 build-host compatibility fix separately.
8. Only after regression tests pass, prepare the launcher update release and then update release artifacts deliberately.
