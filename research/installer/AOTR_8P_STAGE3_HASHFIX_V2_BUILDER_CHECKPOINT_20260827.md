# AotR 8P WotR — Stage 3 hash-host-fixed builder checkpoint

## STATUS

Hash-host source fix V2 completed successfully. Next action is one combined non-release build + fresh discovery smoke test.

## WHAT WE KNOW

The robust standalone AotR resolver already passed a fresh-state test and correctly wrote canonical Config V2 for `D:\Games\AotR\AgeoftheRing`.

The prior GUI preflight falsely reported `game.dat not found` because the embedded PowerShell host could not resolve the `Get-FileHash` cmdlet. The exception was swallowed by an empty catch in `Invoke-Preflight`.

The embedded engine had three `Get-FileHash` dependencies: one inside `Get-Sha256` and two direct UI deployment hash calls. These were audited before modification.

Hash-host fix V2 replaced only the proven hash dependencies and did not modify the autodetect resolver.

## EVIDENCE

Input non-release autodetect builder SHA256:
`6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386`

Input GUI SHA256:
`D8C3E27E35F3EDA101EE74362C9E744BB942D6F06928B61D22036640C22E5F47`

Input engine SHA256:
`3A03D47B6A094A4892A146866DFEAD53858C500F812615672D66690D7812A873`

Hash-host-fix V2 work root:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE3_HASHFIX_V2_20260827_012753`

Patched non-release builder:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE3_HASHFIX_V2_20260827_012753\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_HASHFIX_V2_NONRELEASE.ps1`

Patched builder SHA256:
`B244D987A99533DD3A79978032F64C261FF7EBBDDA1AAFA6BB0142FFA9BC2572`

Patched GUI SHA256:
`AA8893A160CF790644FF794F4E8E47B3D1E05E1022AD22FB784A071B91920D8E`

Patched engine SHA256:
`D045567058775DE4EBB56266DC5751D5A57BA7C236B8056DC41EC2CD7C5931E6`

Post-fix proof:
- GUI `Get-FileHash`: 1 -> 0
- ENGINE `Get-FileHash`: 3 -> 0
- ENGINE direct hash reroutes: 2
- Autodetect resolver changed: NO
- Original builder modified: NO
- Public/release EXE modified: NO
- Game files modified: NO

## WHAT FAILED

Hash-host fix V1 correctly refused to patch the engine because its first implementation only recognized a single `Get-Sha256` wrapper while the engine also had two direct `Get-FileHash` calls.

This refusal prevented an unproven broad patch.

## CURRENT HYPOTHESIS

A new EXE built from builder SHA256 `B244D987...` should preserve the already proven fresh standalone discovery and eliminate the false GUI `game.dat not found` condition caused by missing `Get-FileHash` in the embedded host.

## FILES / HASHES / OFFSETS

Known build support hashes remain:
- 1.0.9 seed: `97A8163CA72BDFB5C6C24931E06B2BFCE1D0E33C382FEA2462F73BC80BD3EA9F`
- launcher.ico: `3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A`
- launcher_skin.png: `2158FD8BB4E9195E27667F517FF81C745983BEE200394FB64107FFF902666473`
- UI: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- Paper: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`

## SAFE TESTS COMPLETED

- Fresh standalone discovery: PASS
- Config V2 write/readback: PASS
- Correct root/runtime/source_mod/game_dat: PASS
- Hash-host fix parser validation: PASS
- GUI/engine re-embed roundtrip: PASS
- Zero embedded `Get-FileHash` after patch: PASS

## NEXT PRACTICAL ACTION

Run `research/installer/AOTR_8P_STAGE3_BUILD_AND_FRESH_SMOKE_V3.ps1` from commit `75b6d9874dad5125ac5b84f5154b4126ecd21147`.

It will build a new isolated non-release EXE from the hash-fixed builder, verify the output, construct a complete temporary runtime package, run with isolated `LOCALAPPDATA` and no `AOTR_HOME`, and revalidate Config V2 plus absence of the `Get-FileHash` host failure in the isolated log.

## DO NOT REPEAT

- Do not change the proven autodetect resolver for this preflight bug.
- Do not reintroduce `Get-FileHash` into embedded GUI or engine PowerShell.
- Do not replace the public launcher during this test.
- Do not use a partial `_GITHUB_UPDATE` directory as the GUI runtime package.
- Do not use the real launcher config for fresh discovery proof.
- Do not invent new repair actions or version thresholds.
