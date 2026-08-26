# AOTR 8P Stage 2 Seed Discovery Checkpoint — 2026-08-27

## STATUS
Stage 1 remains complete and valid. Stage 2 has not yet compiled the non-release EXE because the V17 builder requires an existing `AotR 8P WotR Mod.exe` in `PackageRoot` as its RC4 seed input.

## WHAT WE KNOW
- Stage-1 non-release builder SHA256: `6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386`.
- Public 1.0.9 launcher SHA256: `97A8163CA72BDFB5C6C24931E06B2BFCE1D0E33C382FEA2462F73BC80BD3EA9F`.
- `-BundleOnly` still compiles the EXE but skips local backup/replacement.
- `-EmitGitHubBundle` persists the built EXE under isolated `_GITHUB_UPDATE` before temp cleanup.
- Builder performs a required-file check for `$PackageRoot\AotR 8P WotR Mod.exe` before compile.

## EVIDENCE
Stage-2 V1 failed in the isolated build root with:
`Required RC4 file missing: ...\AUTODETECT_V2_BUILD_...\AotR 8P WotR Mod.exe`

Stage-2 V2 then checked the assumed seed path:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AotR 8P WotR Mod.exe`
and failed because that file does not exist.

No compile occurred in either failed Stage-2 attempt.

## WHAT FAILED
The assumption that the public 1.0.9 seed launcher is stored directly in the live `AOTR_8P_WOTR_MOD` working directory was wrong.

## CURRENT HYPOTHESIS
A byte-identical 1.0.9 launcher copy likely exists elsewhere in the bounded reverse-engineering/release tree. Its location must not be guessed.

## SAFE NEXT ACTION
Use `AOTR_8P_STAGE2_BUILD_NONRELEASE_V3.ps1` to search only `D:\BFME_RESEARCH\05_REVERSE_ENGINEERING` for files named exactly `AotR 8P WotR Mod.exe`, hash every hit, and accept only SHA256 `97A8163CA72BDFB5C6C24931E06B2BFCE1D0E33C382FEA2462F73BC80BD3EA9F` as the seed.

If no exact hash match exists, abort and print all candidate paths/hashes. Do not substitute another launcher automatically.

## SAFETY
- No public/release launcher modified.
- No game files modified.
- No release manifest modified.
- No EXE compiled in the two failed Stage-2 attempts.
- All partial build roots remain isolated under `AUTODETECT_V2_BUILD_*`.

## DO NOT REPEAT
- Do not assume the seed lives directly in `AOTR_8P_WOTR_MOD`.
- Do not accept a seed based on filename alone.
- Do not use an unverified launcher hash.
- Do not build against the real/public launcher path.
- Continue using `-BundleOnly -EmitGitHubBundle` in an isolated PackageRoot.
