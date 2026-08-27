# AOTR 8P Robust Autodetect V2 — Stage 2 Build Success Checkpoint

## STATUS
PASS — first executable Robust Autodetect V2 non-release test launcher built successfully.

## WHAT WE KNOW
- Stage-1 patched builder was used.
- Build completed in an isolated PackageRoot.
- `-BundleOnly` and `-EmitGitHubBundle` were used.
- Test update URLs were intentionally invalid/safe.
- Isolated seed was not modified/replaced.
- Real/public launcher was not modified.
- Support donor was not modified.
- Public release was not modified.

## EVIDENCE
Build root:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE2_V4_BUILD_20260827_010245`

Built EXE:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE2_V4_BUILD_20260827_010245\_GITHUB_UPDATE\AotR 8P WotR Mod.exe`

Built EXE SHA256:
`0EE6D45F01270F6C81DF2D5A828FE373C66202806EC742FDF7B9C64F6FBA7F0B`

Built EXE size:
`684032` bytes

Builder log:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE2_V4_BUILD_20260827_010245\STAGE2_V4_BUILDER_OUTPUT.log`

Build report:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE2_V4_BUILD_20260827_010245\STAGE2_V4_BUILD_REPORT.txt`

## PINNED INPUT HASHES
- Stage-1 builder: `6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386`
- Public 1.0.9 seed: `97A8163CA72BDFB5C6C24931E06B2BFCE1D0E33C382FEA2462F73BC80BD3EA9F`
- launcher.ico: `3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A`
- launcher_skin.png: `2158FD8BB4E9195E27667F517FF81C745983BEE200394FB64107FFF902666473`
- UI BIG: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- PaperScenario001.inc: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`

## WHAT FAILED EARLIER
- Stage2 V1: isolated root lacked required RC4 seed EXE.
- Stage2 V2: fixed seed path assumed an EXE under AOTR_8P_WOTR_MOD that did not exist.
- Stage2 V3: Format-Table polluted the function success stream; hotfixed with Out-Host.
- First support audit: invalid Sort-Object syntax; corrected and commit-pinned.
- Corrected support audit then proved a coherent support donor set.

## CURRENT HYPOTHESIS
Packaging is no longer the blocker. The next risk is runtime behavior of the new resolver/config migration logic.

## SAFE TESTS COMPLETED
- Exact builder hash guard.
- Exact seed/support hashes.
- Isolated PackageRoot.
- BundleOnly/no local replacement.
- PE validation.
- Manifest/hash validation.
- Before/after integrity checks on builder, release seed and support donor.

## NEXT PRACTICAL ACTION
Run the built EXE against the normal standalone installation `D:\Games\AotR\AgeoftheRing` and verify:
1. no stale cache masks discovery,
2. standalone root is selected,
3. Config V2 is written and revalidated,
4. runtime/source_mod/game_dat are canonical and correct,
5. launcher proceeds without treating `_AotR8P_WotR_Runtime`, BFME_RESEARCH or plain RotWK as the real install.

## DO NOT REPEAT
- no All-in-One
- no exe-only detection
- no first-valid selection
- runtime directory is not a real install
- no research/backup auto-preference
- no blind EXE patching
- no unproven repair actions
- no network recursive scan
- no unvalidated config save
- no public release replacement before test matrix passes
