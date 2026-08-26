# AotR 8P WotR — Stage 2 RC4 Seed Checkpoint

Date: 2026-08-27 (Europe/Berlin)
Branch: `feature/robust-aotr-autodetect`

## STATUS

Stage 2 V1 reached the V17 builder but intentionally isolated `PackageRoot` did not contain the existing launcher seed required by the builder's RC4 input validation. Build stopped before compilation.

## EVIDENCE

Stage-1 builder SHA256:
`6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386`

Failed isolated root:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_BUILD_20260827_004325`

Observed error:
`Required RC4 file missing: ...\AotR 8P WotR Mod.exe`

The previously inspected builder control flow proves `-BundleOnly` still performs compilation but skips the backup/replace block guarded by `if (-not $BundleOnly)`.

Public 1.0.9 launcher SHA256 already established:
`97A8163CA72BDFB5C6C24931E06B2BFCE1D0E33C382FEA2462F73BC80BD3EA9F`

## CURRENT HYPOTHESIS / FIX

The existing launcher is a required build seed/input even for `-BundleOnly`. The safe isolated build therefore must contain a COPY of the known launcher seed.

Stage 2 V2 now:
- requires a seed launcher with the exact public 1.0.9 SHA256;
- copies it into the new isolated PackageRoot;
- records its hash before build;
- builds with `-BundleOnly -EmitGitHubBundle`;
- records the seed hash after build and refuses success if it changed;
- validates the built bundle EXE separately;
- keeps dead `invalid.invalid` updater URLs in the test build.

## WHAT FAILED

The V1 runner incorrectly treated absence of a root launcher as an isolation requirement. In reality the builder itself validates that file as a required RC4 input.

No public launcher, release artifact, game file, or original builder was modified by the failed attempt.

## NEXT PRACTICAL ACTION

Run `AOTR_8P_STAGE2_BUILD_NONRELEASE_V2.ps1`.

If the default seed path under the research base does not match the pinned public 1.0.9 hash, do not loosen the hash. Locate/provide the exact verified 1.0.9 launcher copy instead.

## DO NOT REPEAT

- Do not remove the seed requirement from the V17 builder blindly.
- Do not use an unverified executable as the RC4 seed.
- Do not run the builder against the real launcher directory.
- Do not omit `-BundleOnly`.
- Do not point the non-release test build at the live update URLs.
