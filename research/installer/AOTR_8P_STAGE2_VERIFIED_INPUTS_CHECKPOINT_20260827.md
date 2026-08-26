# AOTR 8P Stage 2 — verified build inputs checkpoint

Date: 2026-08-27
Branch: `feature/robust-aotr-autodetect`

## STATUS
Stage 1 robust-autodetect source integration is complete. Stage 2 has not yet produced the final V4 non-release EXE. RC4 input discovery is now complete and all required build inputs are known.

## WHAT WE KNOW
The V17 builder requires five package-root inputs before compilation:

1. `AotR 8P WotR Mod.exe`
2. `assets\launcher.ico`
3. `internal\assets\launcher_skin.png`
4. `payload\!!!WOTR_8P_UI_TEST.big`
5. `payload\data\ini\campaigns\scenarios\PaperScenario001.inc`

The release seed EXE and support files do not coexist in one original package root. A safe hybrid isolated build root is therefore required.

## EVIDENCE
Verified seed:

`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\RELEASE_1_0_9_UI_POLISH_20260822_183040\github_repo\AotR 8P WotR Mod.exe`

SHA256:
`97A8163CA72BDFB5C6C24931E06B2BFCE1D0E33C382FEA2462F73BC80BD3EA9F`

Recommended verified support donor:

`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\V18_RC1_TEST_20260827_004234`

Support hashes:

- launcher.ico: `3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A`
- launcher_skin.png: `2158FD8BB4E9195E27667F517FF81C745983BEE200394FB64107FFF902666473`
- UI BIG: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- PaperScenario001.inc: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`

Multiple other donor roots contain byte-identical support files, confirming a stable support set.

Stage-1 patched builder:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE1_20260827_003823\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_NONRELEASE.ps1`

SHA256:
`6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386`

## WHAT FAILED
Earlier Stage 2 attempts exposed package prerequisites incrementally:

- V1: isolated package root had no RC4 seed EXE.
- V2: assumed seed at AOTR_8P_WOTR_MOD root; none existed.
- V3: seed discovery return stream was polluted by `Format-Table`; fixed by routing formatting to `Out-Host`.
- Next V3 run: seed was verified, but `assets\launcher.ico` was absent from isolated package root.
- RC4 support audit V2 initially had one PowerShell Sort-Object parser bug, then a Generic List conversion runtime bug; both were fixed.

None of these failures modified the public release.

## CURRENT HYPOTHESIS
A hash-pinned hybrid package root consisting of the exact 1.0.9 release EXE plus one coherent verified support donor is sufficient for the V17 builder.

## FILES / HASHES
- Stage-1 builder: `6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386`
- Release seed EXE: `97A8163CA72BDFB5C6C24931E06B2BFCE1D0E33C382FEA2462F73BC80BD3EA9F`
- launcher.ico: `3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A`
- launcher_skin.png: `2158FD8BB4E9195E27667F517FF81C745983BEE200394FB64107FFF902666473`
- UI BIG: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- PaperScenario001.inc: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`

## SAFE TESTS COMPLETED
- Stage 1 payload syntax and builder syntax PASS.
- Stage 1 roundtrip/re-embed PASS.
- Builder PackageRoot / BundleOnly / EmitGitHubBundle control flow audited.
- Verified release seed discovered by exact SHA256.
- RC4 support files inventoried and grouped by SHA256.
- Six complete verified support donor roots found.
- No build/release/public launcher modification during these audits.

## NEXT PRACTICAL ACTION
Run `research/installer/AOTR_8P_STAGE2_BUILD_NONRELEASE_V4.ps1` from commit `60ba4a5598d9d82ac8b1f0fb29f58dac023dd839` after local PowerShell parser validation. It must invoke Windows PowerShell 5.1, use a fresh isolated package root, build with `-BundleOnly -EmitGitHubBundle`, use intentionally invalid test update URLs, verify the resulting PE/manifest/hashes, and prove all source inputs are unchanged afterward.

## DO NOT REPEAT
- Do not search for another seed path unless the pinned release seed disappears or its hash changes.
- Do not discover RC4 files one at a time.
- Do not use the current AOTR_8P_WOTR_MOD payload root: its UI BIG hash is not the pinned release UI hash.
- Do not build without the icon and skin.
- Do not replace the real/public launcher.
- Do not emit a public release.
- Do not use unverified donor files.
- Do not bypass hash or parser guards.
