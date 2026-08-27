# AotR 8P WotR - V18 Robust Autodetect Stage 4 Core Matrix PASS

Date: 2026-08-27
Branch: feature/robust-aotr-autodetect-v18

## STATUS
PASS - 29/29 core autodetect matrix cases, 0 failures.

## AUTHORITATIVE BUILD INPUTS
- Builder SHA256: D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0
- GUI SHA256: CFAF397833536769D726B0DD0960D940AAA6896ED62BFEFA0764185C2CEA90DC
- ENGINE SHA256: 94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA
- Test EXE SHA256: B85818E9349A76DB62DF288C23879BC2345A463D399A21105A2F75114557A944

## EVIDENCE
User-run Stage 4 core matrix result:
- Cases: 29
- Failures: 0
- Report: D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE4_MATRIX_20260827_024929\V18_STAGE4_AUTODETECT_MATRIX_CORE_REPORT.txt

## CORE CASES PROVEN
- full canonical standalone root hard-valid and score 120
- minimal standalone root valid and score 95
- zGameDats\game.dat accepted
- runtime directory resolves canonical root
- aotr directory resolves canonical root
- parent folder resolves AgeoftheRing child
- German-style Spiele\AotR parent path resolves structurally
- plain RotWK without aotr rejected
- missing aotr rejected
- missing lotrbfme2ep1.exe rejected
- missing game.dat rejected
- AotR8P WotR runtime copy hard-rejected
- All-in-One path hard-rejected
- BFME_RESEARCH not auto-eligible
- backup path not auto-eligible
- checkpoint path not auto-eligible
- temp/tmp path not auto-eligible
- canonical candidate dedupe works
- score-first ranking works
- equal top candidates remain explicit tie
- stale/moved Config V2 is revalidated, rediscovered, and rewritten
- A8P-INSTALL-007 path exists
- engine has no independent AOTR_HOME discovery
- engine has no independent drive discovery
- engine enforces Config V2 marker
- real launcher config unchanged
- all remaining harness assertions passed, total 29/29

## PREVIOUSLY PROVEN
- V18 1.0.10 protected ticket/MESSAGES/Auto-Repair/status-panel features preserved
- fresh discovery PASS
- Config V2 PASS
- visual status panel user-confirmed PASS
- Get-FileHash host failure absent
- public release/game files untouched

## PENDING OUTSIDE CORE MATRIX
- launcher located in Downloads vs directly inside AotR install
- actual removable/USB/exFAT drive behavior and Fixed-before-Removable ordering
- actual config write failure / no-write-rights path (A8P-INSTALL-004)
- real two-installation equal-top picker behavior
- final release packaging/promotion only after environment cases pass

## DO NOT REPEAT
- no All-in-One discovery
- no exe-only detection
- no first-valid selection
- runtime copy is not a real installation
- no BFME_RESEARCH/backup/checkpoint/temp auto-preference
- no blind EXE patching
- no unproven repair actions
- no network recursive scan
- no unvalidated config save
- no old V17 production baseline
