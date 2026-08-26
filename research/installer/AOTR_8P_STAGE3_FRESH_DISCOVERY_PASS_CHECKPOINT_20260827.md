# AOTR 8P ROBUST AUTODETECT V2 — STAGE 3 FRESH DISCOVERY PASS

Date: 2026-08-27 (Europe/Berlin)
Branch: `feature/robust-aotr-autodetect`
Status: **PASS — fresh standalone discovery proven**

## STATUS

Robust Autodetect V2 successfully discovered the real standalone Age of the Ring installation from a fresh isolated launcher state with no cached config, no `AOTR_HOME`, and no manual folder selection.

## WHAT WE KNOW

Test EXE:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE2_V4_BUILD_20260827_010245\_GITHUB_UPDATE\AotR 8P WotR Mod.exe`

EXE SHA256:
`0EE6D45F01270F6C81DF2D5A828FE373C66202806EC742FDF7B9C64F6FBA7F0B`

Stage-3 disposable package:
`C:\Users\eliab\AppData\Local\Temp\AOTR8P_STAGE3_FRESH_DISCOVERY_V2_20260827_011140\PACKAGE`

Isolated LOCALAPPDATA:
`C:\Users\eliab\AppData\Local\Temp\AOTR8P_STAGE3_FRESH_DISCOVERY_V2_20260827_011140\LOCALAPPDATA`

## EVIDENCE

Generated canonical Config V2:

```json
{
  "schema": 2,
  "aotr_root": "D:\\Games\\AotR\\AgeoftheRing",
  "runtime": "D:\\Games\\AotR\\AgeoftheRing\\rotwk",
  "source_mod": "D:\\Games\\AotR\\AgeoftheRing\\aotr",
  "game_dat": "D:\\Games\\AotR\\AgeoftheRing\\rotwk\\game.dat",
  "validation": "aotr-standalone-v2",
  "score": 120,
  "last_verified_utc": "2026-08-26T23:12:26.5758652Z"
}
```

Harness result:
- launcher exit code: 0
- schema 2: PASS
- canonical root: PASS
- runtime: PASS
- source_mod: PASS
- game_dat: PASS
- validation marker: PASS
- last_verified_utc: populated
- fresh standalone discovery: PASS
- AOTR_HOME used: NO
- manual folder selection used: NO
- real launcher config modified: NO
- Stage-2 build modified: NO

## WHAT FAILED

The GUI still displayed an `A8P-INSTALL-001` panel with detail `game.dat not found` even though the resolver had already written a valid Config V2 containing the real existing game.dat path.

This is therefore **not a resolver failure**. It is a downstream/legacy GUI or startup validation/diagnostic path that runs after successful `Resolve-AotRInstall` and disagrees with the canonical resolver result.

## CURRENT HYPOTHESIS

An older GUI/startup check remains after the replaced resolver block and still derives or validates `game.dat` independently instead of consuming `$Install.GameDat` / canonical Config V2. Patch only that downstream path after exact source proof.

## FILES / HASHES / PATHS

- Stage-2 V4 EXE SHA256: `0EE6D45F01270F6C81DF2D5A828FE373C66202806EC742FDF7B9C64F6FBA7F0B`
- Stage-1 patched builder SHA256: `6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386`
- Canonical AotR root: `D:\Games\AotR\AgeoftheRing`
- Canonical runtime: `D:\Games\AotR\AgeoftheRing\rotwk`
- Canonical source_mod: `D:\Games\AotR\AgeoftheRing\aotr`
- Canonical game_dat: `D:\Games\AotR\AgeoftheRing\rotwk\game.dat`
- Score: `120`

## SAFE TESTS COMPLETED

- fresh isolated LOCALAPPDATA
- no cached config
- AOTR_HOME removed for test process
- no manual folder selection
- disposable complete runtime package
- real launcher/config untouched
- public release untouched

## NEXT PRACTICAL ACTION

Decode the embedded patched GUI source from the hash-pinned Stage-1 builder and locate the exact downstream code that emits `game.dat not found` / `A8P-INSTALL-001`. Patch only that proven legacy block, rebuild a new non-release EXE, then repeat the same Stage-3 fresh-state test.

## DO NOT REPEAT

- Do not debug Robust Autodetect V2 discovery itself for this symptom; discovery is proven PASS.
- Do not add AOTR_HOME to make the test pass.
- Do not use a real launcher cache for the smoke test.
- Do not manually select the AotR folder.
- Do not patch the public release.
- Do not guess which downstream block is wrong; locate it from decoded embedded source first.
