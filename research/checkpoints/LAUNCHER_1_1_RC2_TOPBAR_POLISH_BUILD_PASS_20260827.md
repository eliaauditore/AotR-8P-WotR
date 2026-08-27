# LAUNCHER 1.1 RC2 TOPBAR POLISH — BUILD PASS

## STATUS
PASS — Launcher 1.1 RC2 built successfully. Visual confirmation still pending.

## WHAT WE KNOW
- Robust Autodetect V2 remains the tested V18 base.
- RC1 proved the fake maximize glyph was baked into the skin, not a functional button.
- RC1 visual cleanup removed the glyph but left an unnatural gap between Minimize and Close.
- RC2 moves Minimize directly next to Close and moves the matching `MinHit` XAML hit area with it.
- Close remains at the far right and unchanged.

## EVIDENCE
User Stage 8 RC2 output on 2026-08-27:
- `V18 STAGE 8 - LAUNCHER 1.1 RC2 TOPBAR POLISH PASS`
- Built EXE SHA256: `A3A20BD540E429330F6A97FD30DE6B416EB70426AEF8FD9223C03856B4EBBBF8`
- Built bytes: `691200`
- Patched GUI SHA256: `23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C`
- Patched skin SHA256: `BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6`
- Report: `D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE8_1_1_RC2_20260827_033129\V18_STAGE8_1_1_RC2_TOPBAR_POLISH_REPORT.txt`

## WHAT FAILED
Nothing in the RC2 build. Visual smoke is not yet completed.

## CURRENT HYPOTHESIS
The RC2 topbar should look natural because the surviving Minimize control is positioned immediately adjacent to Close instead of leaving a dead 51-pixel gap.

## FILES / HASHES / OFFSETS
Pinned tested source builder:
- SHA256 `D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0`

RC2:
- EXE SHA256 `A3A20BD540E429330F6A97FD30DE6B416EB70426AEF8FD9223C03856B4EBBBF8`
- GUI SHA256 `23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C`
- Skin SHA256 `BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6`
- Minimize visual moved `x=726..773` -> `x=777..824`
- MinHit XAML moved `Canvas.Left=726` -> `777`
- Close visual/hit remains `x=825..899` / `Canvas.Left=825`

Preserved payload hashes:
- UI `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- Paper `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`

## SAFE TESTS COMPLETED
- RC2 builder parser validation: PASS
- Protected ticket/status/MESSAGES/Auto-Repair markers preserved by builder assertions
- ENGINE preserved by builder assertions
- Config V2 marker preserved
- Invalid test update URLs used
- No public release files modified
- No game files modified

## NEXT PRACTICAL ACTION
Run a full isolated runtime-package visual smoke using exactly the RC2 EXE and patched RC2 skin. Confirm:
1. topbar looks natural,
2. Minimize works at its new position,
3. Close still works,
4. Launcher v1.1 / status panel / MESSAGES remain clean.

## DO NOT REPEAT
- Do not use RC1 for release.
- Do not reintroduce a fake maximize glyph.
- Do not move or modify Close.
- Do not change Autodetect V2, ticketing, MESSAGES, status panel, Auto-Repair, or engine while polishing this topbar.
- Do not release before user visual confirmation of RC2.
