# AotR 8P WotR Launcher 1.1 — Stage 11 Final Promotion Gate PASS

STATUS: PASS / READY TO PROMOTE

## Production candidate
- Launcher version: `1.1`
- Production EXE SHA256: `9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4`
- Production GUI SHA256: `23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C`
- Production skin SHA256: `BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6`
- Manifest SHA256: `61B559D2AEAB72DE2ECB9BF0F2F1E437D2742C34947CA9B414CD7390AAEAA38A`
- Repair manifest SHA256: `684B8B4F39EE7ADB97D4C0837036F742D67C28B0EFC86A2006043BB2B3C36685`
- UI SHA256: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- Paper SHA256: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`

## Stage 11 evidence
- Bundle contains exactly the five release-root files: PASS
- Production manifest cross-links all five files correctly: PASS
- Repair manifest plan set/actions exactly match proven production dispatcher: PASS
- Current live 1.0.10 baseline verified before promotion: PASS
- Live 1.0.10 EXE SHA256: `6A80E0F7B862ABE3E0F19C3DF5ED9EE9EE730F246CF603ED00A39D1EE7DFF2F8`
- Live UI and Paper hashes match expected baseline: PASS
- Local rollback snapshot saved: PASS
- Exact production EXE `9F2D...` launched from a complete isolated runtime package: PASS
- Production launcher exit code: `0`
- Exact production EXE unchanged after smoke: PASS
- Exact production manifest unchanged after smoke: PASS
- Exact production repair manifest unchanged after smoke: PASS
- Exact production UI/Paper unchanged after smoke: PASS
- Isolated Config V2 smoke: PASS
- Real launcher config unchanged: PASS
- User visually confirmed polished topbar earlier: Minimize directly beside Close, fake Maximize removed, controls functional.

## Rollback snapshot
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE11_PROMOTION_GATE_20260827_034038\ROLLBACK_1_0_10`

## Production bundle
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE8_1_1_RC2_20260827_033705\PACKAGE\_GITHUB_UPDATE`

## Promotion policy
Promotion must remain atomic. Do not update `manifest.json` separately before the new EXE exists at the same root state. The five-file root surface is:
1. `AotR 8P WotR Mod.exe`
2. `manifest.json`
3. `repair-manifest.json`
4. `payload_ui.big`
5. `payload_paper.inc`

`payload_ui.big` and `payload_paper.inc` are byte-identical to 1.0.10 and therefore may retain their existing Git blobs in the final Git tree; they must still be reverified as part of the five-file release set.

NEXT PRACTICAL ACTION: stage the exact verified local production bundle on `release/launcher-1.1-promotion`, verify the staged commit, then fast-forward `main` atomically.
