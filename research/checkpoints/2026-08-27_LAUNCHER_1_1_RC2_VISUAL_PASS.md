# Launcher 1.1 RC2 Visual Pass — 2026-08-27

## STATUS
PASS — user confirmed RC2 topbar and window controls work and look acceptable.

## WHAT WE KNOW
- Launcher version target: 1.1
- RC2 EXE SHA256: `A3A20BD540E429330F6A97FD30DE6B416EB70426AEF8FD9223C03856B4EBBBF8`
- RC2 GUI SHA256: `23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C`
- RC2 skin SHA256: `BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6`
- Original robust-autodetect builder remains pinned at `D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0`.
- Engine remains protected from the topbar polish change.
- Fake maximize graphic removed.
- Minimize visual and MinHit moved from x=726..773 / Canvas.Left=726 to x=777..824 / Canvas.Left=777.
- Close visual and CloseHit remain unchanged at x=825..899 / Canvas.Left=825.

## EVIDENCE
RC2 build report:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE8_1_1_RC2_20260827_033129\V18_STAGE8_1_1_RC2_TOPBAR_POLISH_REPORT.txt`

RC2 build output:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE8_1_1_RC2_20260827_033129\PACKAGE\_GITHUB_UPDATE\AotR 8P WotR Mod.exe`

User visual confirmation after isolated RC2 smoke: `a geht` — interpreted as confirmation that the polished topbar/control test works.

## WHAT FAILED
- Earlier RC1 topbar looked visually unnatural because removing the fake maximize art left a large empty gap.
- RC2 fixed this by moving Minimize directly adjacent to Close while preserving Close position.

## CURRENT HYPOTHESIS
RC2 is the final Launcher 1.1 UI candidate and should be promoted without further UI changes unless a concrete regression is found.

## FILES / HASHES / OFFSETS
- EXE: `A3A20BD540E429330F6A97FD30DE6B416EB70426AEF8FD9223C03856B4EBBBF8`
- GUI: `23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C`
- Skin: `BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6`
- Minimize visual/hit: `x=777..824`, `Canvas.Left=777`
- Close visual/hit: `x=825..899`, `Canvas.Left=825`

## SAFE TESTS COMPLETED
- Robust autodetect Stage 1–7: PASS
- Physical USB/FAT32/USB-bus proof: PASS
- RC2 build: PASS
- RC2 visual topbar polish: PASS
- Minimize works: user confirmed
- Close works / launcher closes normally: accepted as part of the successful smoke confirmation
- No release promotion performed by this checkpoint

## NEXT PRACTICAL ACTION
Promote the exact RC2 bundle as Launcher 1.1 after a fail-closed verification of all five release files and manifest / repair-manifest relationships.

## DO NOT REPEAT
- Do not change resolver logic.
- Do not reintroduce fake maximize artwork or hit area.
- Do not move CloseHit.
- Do not rebuild from an unpinned builder.
- Do not publish a different EXE hash than the RC2 candidate without rerunning the visual gate.
