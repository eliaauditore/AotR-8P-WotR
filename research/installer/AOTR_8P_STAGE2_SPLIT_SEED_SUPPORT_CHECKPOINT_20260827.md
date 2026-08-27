# AOTR 8P STAGE 2 — SPLIT SEED / SUPPORT CHECKPOINT — 2026-08-27

## STATUS
Stage 1 robust autodetect integration remains successful. Stage 2 has not compiled a new EXE yet. Real/public launcher and release artifacts remain unchanged.

## WHAT WE KNOW
- Stage-1 non-release builder SHA256: `6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386`.
- V17 builder requires an RC4 seed package containing more than the seed EXE.
- Verified public 1.0.9 seed EXE exists at:
  `D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\RELEASE_1_0_9_UI_POLISH_20260822_183040\github_repo\AotR 8P WotR Mod.exe`
- Verified seed EXE SHA256:
  `97A8163CA72BDFB5C6C24931E06B2BFCE1D0E33C382FEA2462F73BC80BD3EA9F`
- The isolated build then failed because `assets\launcher.ico` was absent.
- A read-only RC4 package audit found no single package root that simultaneously satisfied the complete verified package criteria.
- Support files do exist in several later working/test roots, including icon, skin, UI BIG and PaperScenario copies.

## EVIDENCE
Latest failed isolated build root:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_BUILD_20260827_004948`

Failure:
`Required RC4 file missing: ...\assets\launcher.ico`

Read-only package audit listed candidate roots including:
- `AUTODETECT_V2_NONRELEASE_BUILD_20260827_002926`
- `AUTODETECT_V21_NONRELEASE_BUILD_20260827_003850`
- `V18_RC1_TEST_20260827_004234`
- `V18_RC1_TEST_20260827_004405`
- release `github_repo`

## CURRENT HYPOTHESIS
The correct isolated build seed should be assembled from two proven sources:
1. the verified public 1.0.9 EXE, and
2. a coherent support donor root containing launcher.ico, launcher_skin.png, expected UI BIG and expected PaperScenario.

Do not choose support files by path/name alone. Hash and group all support copies first, pin UI/Paper to their known release hashes, and identify a coherent donor root.

## KNOWN PAYLOAD HASHES
- UI expected SHA256: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- Paper expected SHA256: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`

Icon and skin hashes are not yet pinned. Do not invent them.

## SAFE TESTS COMPLETED
- Builder hash guard passed.
- Verified seed discovery passed.
- BundleOnly control flow proven to skip local launcher replacement.
- Isolated PackageRoot used.
- Missing-support failure occurred before compile.
- No release/public launcher modification occurred.

## NEXT PRACTICAL ACTION
Run `AOTR_8P_STAGE2_RC4_SUPPORT_HASH_AUDIT_V2.ps1` read-only. It must:
- group seed/icon/skin/UI/Paper copies by SHA256,
- mark expected seed/UI/Paper hashes,
- identify support donor roots containing icon + skin + expected UI + expected Paper,
- recommend one verified seed and one verified support donor.

## DO NOT REPEAT
- Do not assume the release github_repo is a complete RC4 package root.
- Do not copy support files one-at-a-time based only on missing-file errors.
- Do not use an unverified launcher EXE as RC4 seed.
- Do not replace or modify the real/public launcher during Stage 2.
- Do not build until a coherent support donor root is proven.
