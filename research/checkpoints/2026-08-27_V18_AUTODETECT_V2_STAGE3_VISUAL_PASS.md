# V18 Robust Autodetect V2 — Stage 3 Visual PASS

## STATUS
FUNCTIONAL PASS / USER-CONFIRMED VISUAL PASS

## WHAT WE KNOW
- The non-release V18 / 1.0.10 test EXE launched successfully from the isolated runtime package.
- Fresh standalone discovery resolved `D:\Games\AotR\AgeoftheRing` without manual browse and without `AOTR_HOME`.
- Config V2 was written and validated in isolated `LOCALAPPDATA`.
- Real launcher config remained unchanged.
- Stage 2 EXE remained unchanged.
- No `Get-FileHash` host failure was observed.
- User explicitly confirmed the visual launcher state was clean (`alles sauber`).

## EVIDENCE
- Stage 2 EXE SHA256: `B85818E9349A76DB62DF288C23879BC2345A463D399A21105A2F75114557A944`
- Stage 2 EXE bytes: `691712`
- Stage 3 work root: `D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE3_SMOKE_20260827_023446`
- Isolated config root: `D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE3_SMOKE_20260827_023446\LOCALAPPDATA`
- Config V2 canonical root: `D:\Games\AotR\AgeoftheRing`
- Runtime: `D:\Games\AotR\AgeoftheRing\rotwk`
- Source mod: `D:\Games\AotR\AgeoftheRing\aotr`
- game.dat: `D:\Games\AotR\AgeoftheRing\rotwk\game.dat`
- Score: `120`
- Validation: `aotr-standalone-v2`

## VISUAL RESULT
User-confirmed PASS for the pinned EXE. This checkpoint records user observation rather than screenshot evidence.

Expected/confirmed clean visual state included:
- dynamic center status panel populated cleanly
- no `A8P-INSTALL-001`
- no `game.dat not found`
- V18 / 1.0.10 launcher UI retained
- MESSAGES / ticket-system visual structure retained

## SAFE TESTS COMPLETED
- Released V18/1.0.10 baseline audit: PASS
- Robust Autodetect V2 source integration: PASS
- Protected 1.0.10 feature-marker preservation: PASS
- Non-release BundleOnly build: PASS
- Fresh discovery in isolated state: PASS
- Config V2 write/readback: PASS
- Real launcher config unchanged: PASS
- Test EXE unchanged: PASS
- `AOTR_HOME` unused: PASS
- Get-FileHash hosted-runspace regression: NOT PRESENT
- Visual status panel: USER-CONFIRMED PASS

## CURRENT HYPOTHESIS
The V18 / 1.0.10 launcher plus Robust Autodetect V2 is ready for negative/edge-case matrix testing. No release promotion yet.

## NEXT PRACTICAL ACTION
Run controlled autodetect matrix cases, starting with isolated/synthetic negative cases and cache revalidation before any release promotion.

## DO NOT REPEAT
- Do not use the old V17 branch as production base.
- Do not re-run the obsolete status-panel transplant.
- Do not treat runtime-only RotWK as standalone AotR.
- Do not accept plain RotWK without sibling `aotr\`.
- Do not auto-prefer BFME_RESEARCH / backup / checkpoint / temp copies.
- Do not involve All-in-One Launcher.
- Do not release before matrix proof.
