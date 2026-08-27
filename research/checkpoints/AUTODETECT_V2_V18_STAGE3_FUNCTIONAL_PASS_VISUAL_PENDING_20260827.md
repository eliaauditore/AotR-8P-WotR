# AUTODETECT V2 V18 STAGE 3 CHECKPOINT

## STATUS
FUNCTIONAL PASS / VISUAL STATUS-PANEL PENDING

## WHAT WE KNOW
- Released 1.0.10 / V18 baseline was preserved.
- Robust Autodetect V2 was integrated into the released V18 GUI and ENGINE payloads.
- Stage 2 produced a non-release BundleOnly launcher.
- Stage 3 fresh isolated GUI smoke completed successfully.
- Fresh standalone discovery resolved the real standalone AotR root without AOTR_HOME and without manual browsing.
- Canonical Config V2 was written to isolated LOCALAPPDATA and validated.
- Real launcher config remained unchanged.
- Stage 2 EXE remained unchanged.
- No Get-FileHash host failure was present.

## EVIDENCE
Stage 2 EXE:
- SHA256: B85818E9349A76DB62DF288C23879BC2345A463D399A21105A2F75114557A944
- Bytes: 691712

Stage 3 work root:
- D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE3_SMOKE_20260827_023446

Isolated Config V2:
```json
{
  "schema": 2,
  "aotr_root": "D:\\Games\\AotR\\AgeoftheRing",
  "runtime": "D:\\Games\\AotR\\AgeoftheRing\\rotwk",
  "source_mod": "D:\\Games\\AotR\\AgeoftheRing\\aotr",
  "game_dat": "D:\\Games\\AotR\\AgeoftheRing\\rotwk\\game.dat",
  "validation": "aotr-standalone-v2",
  "score": 120,
  "last_verified_utc": "2026-08-27T00:34:49.6559861Z"
}
```

Stage 3 final assertions:
- Fresh standalone discovery: PASS
- Config V2: PASS
- Real launcher config: UNCHANGED
- Stage2 EXE: UNCHANGED
- AOTR_HOME: NOT USED
- Get-FileHash host failure: NO

## WHAT FAILED
- Nothing functional in Stage 3.
- Visual status-panel result is not yet evidenced because no screenshot was retained from the GUI run.

## CURRENT HYPOTHESIS
- Functional resolver/config integration is correct.
- The released V18 GUI already contains dynamic status controls, so the expected visual result should be:
  - AOTR INSTALLATION -> OK
  - 8P WOTR CAMPAIGN -> OK
  - 8-PLAYER WOTR UI -> OK
  - READY / COMPAT CHECK ON LAUNCH
- This must still be confirmed visually before calling full GUI PASS.

## FILES / HASHES / OFFSETS
- V18 Stage1 output builder SHA256: D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0
- V18 Stage1 output GUI SHA256: CFAF397833536769D726B0DD0960D940AAA6896ED62BFEFA0764185C2CEA90DC
- V18 Stage1 output ENGINE SHA256: 94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA
- V18 Stage2 EXE SHA256: B85818E9349A76DB62DF288C23879BC2345A463D399A21105A2F75114557A944
- UI payload SHA256: 827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376
- Paper payload SHA256: 3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43

## SAFE TESTS COMPLETED
- Released V18 baseline audit
- Robust Autodetect V2 integration and roundtrip validation
- Protected ticket/MESSAGES/status/SHA invariants
- BundleOnly non-release compile with invalid update URLs
- Fresh isolated LOCALAPPDATA discovery
- Config V2 write/readback
- Real config preservation
- AOTR_HOME removal/isolation
- Get-FileHash host-failure check

## NEXT PRACTICAL ACTION
1. Reopen exactly the same Stage 3 runtime package under the same isolated LOCALAPPDATA.
2. Capture screenshot of center status panel and footer/MESSAGES/version region.
3. Close launcher without launching the game.
4. If visual PASS, checkpoint FULL FUNCTIONAL + VISUAL PASS.
5. Then continue with cached-path revalidation / moved-install / multi-install tie / invalid-root matrix.

## DO NOT REPEAT
- No All-in-One Launcher.
- No V17 production basis.
- No status-panel transplant into old GUI.
- No first-valid candidate selection.
- Runtime directory is not a real standalone install.
- No BFME_RESEARCH / backup / checkpoint / temp auto-preference.
- No blind EXE patching.
- No release write before matrix proof.
- Do not call visual PASS without screenshot/observation evidence.
