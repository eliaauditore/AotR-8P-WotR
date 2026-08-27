# AotR 8P WotR — Stage 3 dynamic status panel donor checkpoint

## STATUS
Recovered V18 GUI evidence has identified one unique structural donor for the missing middle launcher status panel. A hash-pinned GUI-only transplant helper has been prepared but has not yet been executed.

## WHAT WE KNOW
- Current robust-autodetect/hash-host builder SHA256: `B244D987A99533DD3A79978032F64C261FF7EBBDDA1AAFA6BB0142FFA9BC2572`.
- Current embedded GUI SHA256: `AA8893A160CF790644FF794F4E8E47B3D1E05E1022AD22FB784A071B91920D8E`.
- Current embedded Engine SHA256: `D045567058775DE4EBB56266DC5751D5A57BA7C236B8056DC41EC2CD7C5931E6`.
- Fresh standalone autodetection is already proven PASS against `D:\Games\AotR\AgeoftheRing` with Config V2 score 120.
- The false `A8P-INSTALL-001 / game.dat not found` condition was traced to hosted `Get-FileHash` availability and has been fixed; GUI and Engine both contain zero `Get-FileHash` occurrences in the current builder.
- The remaining visual defect is the empty middle health/status panel.

## EVIDENCE
Four historical V18 GUI payloads were recovered directly from V18 RC test EXEs. Donor selector V5.2 found one unique structural donor:
- Donor file: `GUI_4_46032AC5272E.ps1`
- Donor SHA256: `46032AC5272ED491A9E3F497733148A4531E35DC7D1634DDC180CC48D6C9FA24`
- Evidence score: 113

Only this donor contains the complete dynamic status implementation:
- `StatusRowsHost`
- `StatusGameText`
- `StatusCampaignText`
- `StatusUiText`
- `OverallStatusText`
- `Set-StatusChecking`
- `Set-StatusCheck`
- `Set-OverallStatus`

The donor's `Invoke-Preflight` updates the three status rows for game.dat, campaign payload, and 8-player UI and sets an overall READY / COMPAT CHECK / REPAIR REQUIRED message.

## WHAT FAILED
- The older LAN_UI_POLISH exact-hash builder is no longer present under the research root.
- The named V18 RC4 STATUS_PANEL builder source is also no longer present under the research root.
- These missing builder sources are no longer blockers because the embedded V18 GUI payloads were recovered from existing test EXEs.

## CURRENT HYPOTHESIS
The empty center panel is caused by a regression where the current V17-derived GUI retained the fail overlays but lost the V18 dynamic status panel XAML/bindings/update helpers. Restoring only those proven donor blocks should fix the visual panel without touching resolver, hashing, engine, repair dispatcher, or release artifacts.

## FILES / HASHES / OFFSETS
Input builder:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE3_HASHFIX_V2_20260827_012753\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_HASHFIX_V2_NONRELEASE.ps1`

Input hashes:
- Builder `B244D987A99533DD3A79978032F64C261FF7EBBDDA1AAFA6BB0142FFA9BC2572`
- GUI `AA8893A160CF790644FF794F4E8E47B3D1E05E1022AD22FB784A071B91920D8E`
- Engine `D045567058775DE4EBB56266DC5751D5A57BA7C236B8056DC41EC2CD7C5931E6`
- Donor GUI `46032AC5272ED491A9E3F497733148A4531E35DC7D1634DDC180CC48D6C9FA24`

Prepared helper:
`research/installer/AOTR_8P_STAGE3_STATUS_PANEL_TRANSPLANT_V6.ps1`

## SAFE TESTS COMPLETED
- Stage 3 hash-host V2 patch: PASS.
- Non-release build: PASS; EXE SHA256 `A91EA762439DC855DDD38D68BAC81B59031B2063CBCDB6E52D3B50A9D7926F48`.
- Fresh isolated standalone discovery: PASS.
- Config V2 canonical root: `D:\Games\AotR\AgeoftheRing`.
- `Get-FileHash` host failure in isolated log: NO.
- Historical V18 GUI EXE recovery: 4 unique payloads recovered.
- Structural donor selection: unique donor YES (`GUI_4_46032AC5272E.ps1`).

## NEXT PRACTICAL ACTION
Run `AOTR_8P_STAGE3_STATUS_PANEL_TRANSPLANT_V6.ps1`. If it passes, persist the new builder/GUI hashes, build a new non-release package from that builder, then repeat the isolated fresh GUI smoke test and visually verify the three status rows plus overall status.

## DO NOT REPEAT
- Do not search further for the missing LAN_UI_POLISH or RC4 STATUS_PANEL builder source unless new evidence requires it.
- Do not replace the complete current GUI with the historical donor GUI.
- Do not modify the autodetect resolver.
- Do not reintroduce `Get-FileHash` in embedded GUI or Engine.
- Do not modify Engine during this GUI-only transplant.
- Do not change repair-manifest action names.
- Do not touch public/release EXEs.
- Do not touch game files.
