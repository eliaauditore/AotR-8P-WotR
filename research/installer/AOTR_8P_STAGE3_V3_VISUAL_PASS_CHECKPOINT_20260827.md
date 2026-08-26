# AotR 8P WotR — Stage 3 V3 visual review checkpoint

## STATUS
FUNCTIONAL PASS / VISUAL STATUS-PANEL FAIL.

Robust Autodetect V2 + Get-FileHash host fix work on fresh isolated state, but the large central preflight/status panel is visibly empty and therefore the launcher is not yet visually release-ready.

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

Working/visible:
- Main Age of the Ring / 8 Player War of the Ring skin renders normally.
- No `game.dat not found` message is visible.
- No `A8P-INSTALL-001` diagnostic panel is visible.
- No Auto Repair / repair-mode failure state is visible.
- No PowerShell/Get-FileHash command-not-found overlay is visible.
- Main action shows `LAUNCH + COMPAT CHECK`.
- Mode selector shows `MULTIPLAYER`.
- Informational footer shows `Original game.dat remains unchanged on disk`.
- Test version footer shows `V1.0.10-autodetect-v2-hashfix-test`.

Still wrong:
- The entire large bordered status/preflight panel in the center is blank.
- No positive preflight/status rows or icons are visible inside that panel.
- This is not merely low contrast: screenshot/crop inspection shows the panel contains no visible status content.

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
Fresh install detection and preflight hashing now work, but successful preflight paths likely collapse/hide only the fail-row controls without revealing a corresponding positive/status row, or the positive status controls are never populated/initialized. This must be source-audited before changing XAML or visibility logic.

## SAFE TESTS COMPLETED
- Fresh isolated LOCALAPPDATA.
- AOTR_HOME removed.
- Real standalone installation auto-detected.
- Config V2 write/read validation.
- Get-FileHash host failure absence checked.
- Visual screenshot review including central status panel.
- No public/release replacement.

## NEXT PRACTICAL ACTION
Decode the exact embedded GUI and audit the status/preflight XAML/control declarations plus `Invoke-Preflight` visibility/text assignments for all rows. Prove whether success controls exist and are hidden, or whether only failure controls were implemented. Fix the status panel before real launch/compatibility testing is considered visually complete.

## DO NOT REPEAT
- Do not alter the proven Robust Autodetect V2 resolver for the old game.dat false-negative.
- Do not reintroduce `Get-FileHash` into embedded GUI/engine payloads.
- Do not call Stage 3 V3 a full visual PASS while the central status panel is blank.
- Do not blindly add new status controls before auditing existing XAML/control names and visibility logic.
- Do not touch public release artifacts during matrix/runtime testing.
