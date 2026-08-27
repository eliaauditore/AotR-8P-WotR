# AotR 8P V18 Stage 1 — Robust Autodetect V2 Success Checkpoint

## STATUS
PASS — Robust Autodetect V2 was integrated into the released launcher 1.0.10 / V18 production baseline without building an EXE or modifying release/game files.

## WHAT WE KNOW
- Released base commit: `1303e0a6b268b082e9352ded1461fa8d794f16d3`
- Released builder SHA256: `8BDD8745931B41AA2B062FB9ADCE8BBBD7EA2A33F4C0946C20A409D89639271A`
- Original V18 GUI SHA256: `46032AC5272ED491A9E3F497733148A4531E35DC7D1634DDC180CC48D6C9FA24`
- Original V18 ENGINE SHA256: `E5803FB7D7BDCD463587C99796A6B0EFD4D23D3D6C69BA102A83435D872F6E5F`
- Proven resolver donor commit: `7c4f7d958238926dfdaa15b2baeb73cd99b0dd45`
- V18 Stage 1 output builder SHA256: `D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0`
- V18 Stage 1 output GUI SHA256: `CFAF397833536769D726B0DD0960D940AAA6896ED62BFEFA0764185C2CEA90DC`
- V18 Stage 1 output ENGINE SHA256: `94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA`

## EVIDENCE
User-run PowerShell 7.6.5 integration output:
- Wrapper parser validation: PASS
- Integrator parser validation: PASS
- V18 robust-autodetect integration: PASS
- No EXE built
- No public/release/game files modified

Protected launcher 1.0.10 feature counts remained:
- ReportError: 6
- Messages: 11
- ReportReady: 13
- Fingerprint: 3
- AutoRepair: 4
- StatusRowsHost: 1
- StatusGameText: 6
- StatusCampaignText: 6
- StatusUiText: 6
- OverallStatusText: 9
- SetStatusChecking: 1
- GetFileHash: 0
- SyntheticHook: 0
- FINAL_STABLE_V7: 7

## FILES / HASHES / PATHS
Work root:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE1_20260827_022948`

Output builder:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE1_20260827_022948\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10_ROBUST_AUTODETECT_V2_NONRELEASE.ps1`

Report:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE1_20260827_022948\V18_STAGE1_AUTODETECT_V2_REPORT.txt`

## SAFE TESTS COMPLETED
- Released builder hash pin: PASS
- Original V18 GUI/ENGINE hash pins: PASS
- Donor resolver markers: PASS
- GUI parser validation after integration: PASS
- ENGINE parser validation after integration: PASS
- Builder parser validation after re-embed: PASS
- Roundtrip embedded GUI/ENGINE hashes: PASS
- Ticket/MESSAGES/Auto-Repair/status markers preserved: PASS
- Get-FileHash remains zero: PASS
- Synthetic test hook remains zero: PASS
- FINAL_STABLE_V7 preserved: PASS

## CURRENT HYPOTHESIS
The integrated V18 builder should now preserve the complete 1.0.10 ticket system and UI while adding the proven standalone-only candidate collection, hard validation, scoring/ranking, Config V2 persistence/revalidation, and GUI-authoritative install resolution.

## NEXT PRACTICAL ACTION
Build a non-release EXE from exact builder SHA `D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0` using `-BundleOnly -EmitGitHubBundle`, invalid test update URLs, and copied verified support assets. Then run isolated fresh-state GUI smoke before any release promotion.

## DO NOT REPEAT
- Do not use the old V17 branch as production base.
- Do not execute the obsolete V6 status-panel transplant.
- Do not modify public release artifacts for testing.
- Do not reintroduce Get-FileHash.
- Do not reintroduce synthetic ticket-test hooks.
- Do not treat runtime copies, All-in-One paths, BFME_RESEARCH, backups, checkpoints, or temp paths as preferred real installs.
