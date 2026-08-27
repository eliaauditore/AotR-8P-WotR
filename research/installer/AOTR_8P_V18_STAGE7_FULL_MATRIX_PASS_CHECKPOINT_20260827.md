# AotR 8P WotR — V18 Robust Autodetect Full Matrix PASS

## STATUS
FULL MATRIX PASS / RELEASE-CANDIDATE READY

## WHAT WE KNOW
The robust standalone AotR autodetection / Config V2 port into the released V18 / launcher 1.0.10 base has now passed all planned functional, visual, synthetic, environment, picker, write-failure, and physical USB tests.

## RELEASE BASE
- Release commit: `1303e0a6b268b082e9352ded1461fa8d794f16d3`
- V18 Stage1 robust-autodetect builder SHA256: `D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0`
- Embedded GUI SHA256: `CFAF397833536769D726B0DD0960D940AAA6896ED62BFEFA0764185C2CEA90DC`
- Embedded ENGINE SHA256: `94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA`
- Non-release test EXE SHA256: `B85818E9349A76DB62DF288C23879BC2345A463D399A21105A2F75114557A944`
- Non-release test EXE bytes: `691712`

## COMPLETED STAGES
### Stage 1 — Integration
- V18/1.0.10 robust-autodetect / Config V2 integration: PASS
- Ticket system / MESSAGES / REPORT ERROR / Auto-Repair / dynamic status panel protected
- Get-FileHash regression protection preserved

### Stage 2 — Non-release build
- BundleOnly build: PASS
- Built EXE SHA256: `B85818E9349A76DB62DF288C23879BC2345A463D399A21105A2F75114557A944`

### Stage 3 — Fresh-state GUI smoke
- Fresh standalone discovery: PASS
- Config V2: PASS
- Real launcher config: UNCHANGED
- Stage2 EXE: UNCHANGED
- AOTR_HOME: NOT USED
- Get-FileHash host failure: NO
- Visual status-panel / MESSAGES result: user-confirmed PASS

### Stage 4 — Core autodetect matrix
- Cases: 29
- Failures: 0
- Core matrix: PASS
- Report: `D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE4_MATRIX_20260827_024929\V18_STAGE4_AUTODETECT_MATRIX_CORE_REPORT.txt`

Covered, among others:
- canonical/full root and score 120
- minimal standalone and score 95
- `zGameDats\game.dat`
- runtime/aotr/parent normalization
- German-style path
- plain RotWK rejected
- missing aotr/exe/game.dat rejected
- 8P runtime copy rejected
- All-in-One path rejected
- BFME_RESEARCH/backup/checkpoint/temp not auto-eligible
- canonical dedupe
- score ranking
- equal-top tie detection
- stale/moved Config V2 rediscovery + rewrite
- engine remains config-consumer only
- real launcher config unchanged

### Stage 5 — Environment position + write failures
- Cases: 6
- Failures: 0
- Stage 5: PASS
- Report: `D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE5_ENV_20260827_025436\V18_STAGE5_ENVIRONMENT_POSITION_WRITE_REPORT.txt`

Covered:
- launcher/package in Downloads-style location resolves real AotR
- launcher/package directly inside AotR root resolves real AotR
- deterministic config write/verify failure -> `A8P-INSTALL-004`
- actual Windows ACL no-write-rights -> `A8P-INSTALL-004`
- real launcher config unchanged
- Stage1 builder unchanged

### Stage 6 — Real equal-top picker + drive audit
- Cases: 8
- Failures: 0
- Stage 6: PASS
- Report: `D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE6_TIE_20260827_025728\V18_STAGE6_REAL_TIE_PICKER_AND_DRIVES_REPORT.txt`

Covered:
- temporary second structurally valid score-120 candidate
- exact real equal-top picker interaction
- user selected real `D:\Games\AotR\AgeoftheRing`
- selection revalidated and Config V2 saved
- resolver emitted `A8P-INSTALL-002`
- temporary candidate removed
- physical drive ordering verified for C:/D: fixed NVMe
- real launcher config unchanged
- Stage1 builder unchanged

### Stage 7 — Physical USB/FAT32/USB-bus proof
- Cases: 8
- Failures: 0
- Stage 7: PASS
- Report: `D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE7_USB_20260827_030357\V18_STAGE7_PHYSICAL_USB_SELECTION_REPORT.txt`

Physical device under test:
- Drive: `I:`
- Resolver type: `RemovableUsbOrExFat`
- Rank: `1`
- DriveType: `Removable`
- FileSystem: `FAT32`
- BusType: `USB`

Passed:
- physical `I:` classified `RemovableUsbOrExFat` rank 1
- Fixed drives remain ordered before physical USB/exFAT
- temporary USB standalone root validates score 120
- bounded physical USB search discovers temporary root
- physical USB equal-top picker selection revalidated and saved
- resolver emitted `A8P-INSTALL-002`
- temporary USB test tree removed
- real launcher config unchanged
- Stage1 builder unchanged

Temporary USB candidate used:
`I:\A8P_STAGE7_USB_b7d925eb656b4b788979954564e3ae98\AgeoftheRing`

## EVIDENCE / SAFETY
- No game start during Stages 4–7.
- No public release changed.
- No real launcher config changed.
- No real AotR game files modified.
- Temporary synthetic / USB test trees were removed after their tests.
- Stage1 builder remained hash-identical.

## CURRENT HYPOTHESIS
No remaining functional blocker is known in the planned robust standalone autodetect / Config V2 scope. The current V18 robust-autodetect candidate is suitable for final pre-release/promotion validation.

## NEXT PRACTICAL ACTION
Do NOT modify the resolver further without new evidence. Next step is release-promotion preparation on the pinned V18 robust-autodetect candidate, including final release metadata/version decision and a final production build/manifest verification before replacing public 1.0.10 assets.

## DO NOT REPEAT
- no All-in-One integration
- no exe-only detection
- no first-valid shortcut
- no treating `_AotR8P_WotR_Runtime` as real installation
- no research/backup auto-preference
- no blind EXE patching
- no unproven repair-manifest actions
- no recursive network scan
- no unvalidated config save
- no invented version thresholds
- no resolver redesign after full matrix PASS without new evidence
