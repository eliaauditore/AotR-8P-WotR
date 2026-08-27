# AotR 8P WotR — V18 Robust Autodetect V2 Stage 6 Checkpoint

Date: 2026-08-27
Branch: `feature/robust-aotr-autodetect-v18`

## STATUS

**STAGE 6 PASS — 8/8 cases, 0 failures.**

The real equal-top installation picker is proven end-to-end against the exact resolver embedded in the current V18/1.0.10 robust-autodetect builder.

The only mandatory environment proof still pending is an **actual Removable / USB / exFAT secondary-drive selection case**, because no physical secondary drive was attached during Stage 6.

Release status: **READY EXCEPT PHYSICAL SECONDARY-DRIVE PROOF.**

Do not publish/replace the 1.0.10 production release yet.

## WHAT WE KNOW

Pinned current non-release integration:

- Builder SHA256: `D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0`
- GUI SHA256: `CFAF397833536769D726B0DD0960D940AAA6896ED62BFEFA0764185C2CEA90DC`
- ENGINE SHA256: `94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA`
- Built non-release EXE SHA256: `B85818E9349A76DB62DF288C23879BC2345A463D399A21105A2F75114557A944`
- Built EXE size: `691712` bytes
- Real standalone AotR root: `D:\Games\AotR\AgeoftheRing`

Stage 6 run:

- Work root: `D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE6_TIE_20260827_025728`
- Report: `D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE6_TIE_20260827_025728\V18_STAGE6_REAL_TIE_PICKER_AND_DRIVES_REPORT.txt`
- Stage6 runner SHA256 as downloaded by user: `27005E69CE89E6A4E8ECAAFCC95785509FFE37AE403FE380862137EF81EAE724`

## EVIDENCE

Stage 6 output proved:

1. Temporary structural second install was hard-valid, auto-eligible, and score 120.
2. Current physical drive classification returned:
   - `C:\` — Fixed / Rank 0 / Fixed / NTFS / NVMe
   - `D:\` — Fixed / Rank 0 / Fixed / NTFS / NVMe
3. Network/unsupported drive types were excluded.
4. Fixed drives were ordered before secondary drives.
5. No physical Removable/USB/exFAT drive was present (`Physical secondary : 0`).
6. Equal-top picker opened with at least two score-120 candidates.
7. User selected real `D:\Games\AotR\AgeoftheRing`.
8. Selection was revalidated and saved as isolated Config V2.
9. Resolver reported `A8P-INSTALL-002` during the tie path, as expected.
10. Temporary structural second installation was removed.
11. Real launcher config remained unchanged.
12. Stage1 builder remained byte-identical.

Final Stage 6 result:

```text
Cases              : 8
Failures           : 0
Physical secondary : 0
STAGE 6: PASS
```

## PRIOR COMPLETED PROOFS

### Stage 1 — V18/1.0.10 integration

PASS. Robust Autodetect V2 was ported into the released V18/1.0.10 base without regressing protected features.

Protected feature counts remained:

- REPORT ERROR: 6
- MESSAGES: 11
- ReportReady: 13
- Fingerprint: 3
- AutoRepair: 4
- StatusRowsHost: 1
- StatusGameText: 6
- StatusCampaignText: 6
- StatusUiText: 6
- OverallStatusText: 9
- SetStatusChecking: 1
- Get-FileHash: 0
- SyntheticHook: 0
- FINAL_STABLE_V7: 7

### Stage 2 — non-release build

PASS.

- EXE SHA256: `B85818E9349A76DB62DF288C23879BC2345A463D399A21105A2F75114557A944`
- No installed launcher/public release/game files modified.

### Stage 3 — fresh GUI discovery / Config V2

PASS, including user-confirmed visual status-panel PASS.

Proved:

- Fresh standalone discovery
- Config V2 canonical save
- Real launcher config unchanged
- Stage2 EXE unchanged
- No `AOTR_HOME`
- No Get-FileHash host failure
- Dynamic status panel visually clean
- MESSAGES / 1.0.10 UI retained

### Stage 4 — core autodetect matrix

PASS: **29/29, 0 failures**.

Includes:

- full canonical score 120
- minimal valid score 95
- zGameDats layout
- runtime/aotr/parent path normalization
- German-style path
- plain RotWK rejection
- missing aotr/exe/game.dat rejection
- runtime-copy rejection
- All-in-One rejection
- BFME_RESEARCH/backup/checkpoint/temp de-prioritization
- canonical dedupe
- score ranking
- equal-top tie
- stale/moved Config V2 recovery + rewrite
- engine as Config V2 consumer only
- real config unchanged

### Stage 5 — environment position + write failures

PASS: **6/6, 0 failures**.

Includes:

- launcher/package in Downloads-style location
- launcher/package directly inside AotR root
- deterministic Config write/verify failure -> `A8P-INSTALL-004`
- actual Windows ACL no-write -> `A8P-INSTALL-004`
- real launcher config unchanged
- Stage1 builder unchanged

## WHAT FAILED

No product/autodetect failure is known at this checkpoint.

Historical helper/harness issues were fixed and must not be confused with launcher failures:

- `$key:` parser interpolation in early Stage1 integrator wrapper
- Stage4 invalid regex `\True`
- missing Stage4 harness `$packageRoot`
- Stage5 fragile wrapper cleanup patch target

These were test-helper defects only.

## CURRENT HYPOTHESIS

Robust Autodetect V2 on V18/1.0.10 is functionally release-ready **except** for direct proof with an actually attached Removable/USB/exFAT drive.

The current resolver code already classifies any drive as secondary when at least one of the following is true:

- DriveType is Removable
- detected BusType is USB/SD/MMC
- filesystem is exFAT

Secondary drives receive Rank 1; normal Fixed drives receive Rank 0.

The remaining proof must verify this behavior against a real attached secondary device rather than only source/matrix assertions.

## FILES / HASHES / OFFSETS

Current builder:

`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE1_20260827_022948\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10_ROBUST_AUTODETECT_V2_NONRELEASE.ps1`

SHA256:

`D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0`

Current non-release EXE:

`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE2_BUILD_20260827_023209\PACKAGE\_GITHUB_UPDATE\AotR 8P WotR Mod.exe`

SHA256:

`B85818E9349A76DB62DF288C23879BC2345A463D399A21105A2F75114557A944`

## SAFE TESTS COMPLETED

- Released V18 baseline audit
- Robust resolver source transplant only
- parser validation
- payload/hash locality checks
- non-release BundleOnly build
- fresh isolated GUI discovery
- Config V2 save/readback
- visual status-panel confirmation
- full 29-case resolver matrix
- stale/moved cache recovery
- equal-top tie source/matrix proof
- real equal-top picker interaction
- launcher position tests
- deterministic write-failure test
- real ACL no-write test with restore
- current physical drive enumeration

## NEXT PRACTICAL ACTION

When an actual removable/USB/exFAT drive is available:

1. Attach it.
2. Run a read-only physical-drive audit first and confirm the resolver classifies it as `RemovableUsbOrExFat`, Rank 1.
3. Only after classification is proven, perform a controlled secondary-drive candidate test using a disposable structural AotR test root on that device or an already existing valid standalone test copy.
4. Confirm Fixed drives remain ahead of secondary drives.
5. Confirm a valid secondary candidate is discoverable and selectable when appropriate.
6. Remove only the disposable test root afterward.
7. Persist the exact drive type/filesystem/bus type/result as the final autodetect matrix checkpoint.
8. Only then move to final release-candidate promotion / public release prep.

## DO NOT REPEAT

- Do not involve All-in-One Launcher.
- Do not use exe-only detection.
- Do not make GUI-only fixes; engine remains Config V2 consumer.
- Do not revert to first-valid discovery.
- Do not treat `_AotR8P_WotR_Runtime` as a real installation.
- Do not auto-prefer BFME_RESEARCH/backups/checkpoints/temp copies.
- Do not perform recursive network scans.
- Do not save unvalidated config.
- Do not invent version thresholds or new repair-manifest actions.
- Do not rerun old V6 status-panel transplant.
- Do not rebuild from the obsolete `feature/robust-aotr-autodetect` branch.
- Do not publish the production release until the physical secondary-drive proof is completed or explicitly waived with a documented decision.
