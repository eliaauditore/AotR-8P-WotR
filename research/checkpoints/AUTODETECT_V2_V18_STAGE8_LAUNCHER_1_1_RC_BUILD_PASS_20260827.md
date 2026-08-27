# AUTODETECT V2 / V18 / LAUNCHER 1.1 RC BUILD PASS — 2026-08-27

## STATUS
PASS — Launcher 1.1 RC built successfully from the fully tested V18 robust-autodetect builder. Public release not modified yet.

## WHAT WE KNOW
- Launcher version built: `1.1`
- Robust autodetect / Config V2 logic remains based on the fully tested Stage1 builder.
- The fake maximize symbol is not a functional control. The main launcher is WPF with `WindowStyle="None"` and `ResizeMode="NoResize"`.
- Real hit areas exist only for Minimize (`x=726..773`) and Close (`x=825..899`).
- The visual fake maximize area between them was baked into the launcher skin.
- The 1.1 RC changes only the copied skin region `x=774..824, y=0..40`.
- No public release files or game files were modified by the RC build.

## EVIDENCE
User-run Stage8 RC V1.1 result:
- Wrapper parser validation: PASS
- Runtime parser validation: PASS
- RC build: PASS
- Built EXE SHA256: `08C9298600B59FD4EA629F88014AD152880858998E0C522BF8DAA9DEDAEEAC77`
- Built bytes: `691200`
- Patched skin SHA256: `C359C28BA2DFBE481E529E87F3F90DF71AE3348FC660006B46A956457C1AF72D`
- Report: `D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE8_1_1_RC_20260827_032114\V18_STAGE8_1_1_RC_NO_FAKE_MAXIMIZE_REPORT.txt`
- Built EXE: `D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE8_1_1_RC_20260827_032114\PACKAGE\_GITHUB_UPDATE\AotR 8P WotR Mod.exe`
- Before crop: `...\TOPRIGHT_BEFORE.png`
- After crop: `...\TOPRIGHT_AFTER.png`

## FILES / HASHES
- Fully tested autodetect builder SHA256: `D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0`
- GUI SHA256: `CFAF397833536769D726B0DD0960D940AAA6896ED62BFEFA0764185C2CEA90DC`
- ENGINE SHA256: `94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA`
- Released 1.0.10 seed EXE SHA256: `6A80E0F7B862ABE3E0F19C3DF5ED9EE9EE730F246CF603ED00A39D1EE7DFF2F8`
- UI payload SHA256: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- Paper payload SHA256: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`
- Icon SHA256: `3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A`
- Original skin SHA256: `2158FD8BB4E9195E27667F517FF81C745983BEE200394FB64107FFF902666473`
- Patched 1.1 skin SHA256: `C359C28BA2DFBE481E529E87F3F90DF71AE3348FC660006B46A956457C1AF72D`
- Launcher 1.1 RC EXE SHA256: `08C9298600B59FD4EA629F88014AD152880858998E0C522BF8DAA9DEDAEEAC77`

## SAFE TESTS COMPLETED
- Robust autodetect full matrix already PASS through Stage 7.
- Stage8 window-chrome diagnostic proved the fake maximize symbol is skin-only.
- Stage8 RC build changed only the intended top-right skin region.
- Bundle UI and Paper hashes remained pinned.
- Build used non-release workflow and did not replace public release files.

## NEXT PRACTICAL ACTION
Run exactly the 1.1 RC EXE with isolated LOCALAPPDATA and visually confirm:
1. fake maximize symbol is gone,
2. Minimize still works,
3. after restoring from taskbar, Close still works,
4. status panel / MESSAGES / launcher v1.1 remain visually correct,
5. do not launch the game during this smoke.

After user-confirmed visual PASS, promote exactly this 1.1 state to the final five-file release bundle and verify manifest / repair-manifest / payload hashes before publishing.

## DO NOT REPEAT
- Do not patch `MaximizeBox`; the main launcher is WPF skin chrome, not the WinForms picker.
- Do not touch robust autodetect / Config V2 resolver without a new concrete failure.
- Do not alter ticket system, REPORT ERROR, MESSAGES, dynamic status panel, Auto-Repair, .NET SHA256, or FINAL_STABLE_V7.
- Do not publish before visual RC confirmation and final five-file release verification.
