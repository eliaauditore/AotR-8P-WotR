# AotR 8P WotR — Stage 3 V3 Visual PASS checkpoint

## STATUS
PASS — Robust Autodetect V2 + Get-FileHash host fix produces a clean launcher GUI on fresh isolated state.

## WHAT WE KNOW
- Stage 3 V3 parser validation: PASS.
- Hash-fixed non-release EXE built successfully.
- Built EXE SHA256: `A91EA762439DC855DDD38D68BAC81B59031B2063CBCDB6E52D3B50A9D7926F48`.
- Built EXE size: `685568` bytes.
- Fresh isolated config resolved canonical standalone AotR root: `D:\Games\AotR\AgeoftheRing`.
- Config schema: 2.
- Validation marker: `aotr-standalone-v2`.
- Score: 120.
- `game_dat`: `D:\Games\AotR\AgeoftheRing\rotwk\game.dat`.
- `Get-FileHash` host failure in isolated launcher log: NO.
- Real launcher config modified: NO.
- Public/release EXE modified: NO.
- AOTR_HOME used: NO.
- Test auto-update target remained intentionally invalid/safe.

## VISUAL EVIDENCE / REVIEW
User supplied screenshot of the running Stage 3 V3 launcher. Visual inspection shows:
- Main Age of the Ring / 8 Player War of the Ring skin renders normally.
- No red preflight failure row is visible.
- No `game.dat not found` message is visible.
- No `A8P-INSTALL-001` diagnostic panel is visible.
- No Auto Repair / repair-mode failure state is visible.
- No PowerShell/Get-FileHash command-not-found overlay is visible.
- Main action shows `LAUNCH + COMPAT CHECK`.
- Mode selector shows `MULTIPLAYER`.
- Informational footer shows `Original game.dat remains unchanged on disk`.
- Test version footer shows `V1.0.10-autodetect-v2-hashfix-test`.

`LAUNCH + COMPAT CHECK` is expected on the fresh isolated state because no compatibility cache has yet been created for the detected game.dat; it is not an installation-detection failure.

## EVIDENCE
Stage 3 V3 output:
- Work root: `D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE3_V3_20260827_013117`
- Built EXE: `...\BUILD\_GITHUB_UPDATE\AotR 8P WotR Mod.exe`
- Launcher log: `...\LOCALAPPDATA\AotR 8P WotR Mod\launcher_current.log`
- Report: `...\STAGE3_V3_REPORT.txt`

## WHAT FAILED BEFORE
- Original Stage 3 V1 launched directly from `_GITHUB_UPDATE` without required package assets.
- Stage 3 V2 proved fresh discovery, but GUI preflight falsely reported `game.dat not found` because embedded runspace could not resolve `Get-FileHash`.
- Root cause was removed by replacing embedded hashing with .NET SHA256 and routing engine direct hashes through the internal hash helper.

## CURRENT HYPOTHESIS
Fresh install detection and preflight hashing are now working. The next meaningful proof is the first real launch/compatibility-check path, followed by cached second launch and the required autodetection matrix.

## SAFE TESTS COMPLETED
- Fresh isolated LOCALAPPDATA.
- AOTR_HOME removed.
- Real standalone installation auto-detected.
- Config V2 write/read validation.
- Get-FileHash host failure absence checked.
- Visual clean-GUI review.
- No public/release replacement.

## NEXT PRACTICAL ACTION
Run a controlled isolated first launch with `LAUNCH + COMPAT CHECK` and verify engine consumes the same Config V2 root, compatibility check succeeds, game launch reaches the expected start signal/runtime state, then verify a second launch uses compatibility cache correctly.

## DO NOT REPEAT
- Do not alter the proven Robust Autodetect V2 resolver for the old game.dat false-negative.
- Do not reintroduce `Get-FileHash` into embedded GUI/engine payloads.
- Do not launch a bundle EXE without its required package asset structure.
- Do not touch public release artifacts during matrix/runtime testing.
