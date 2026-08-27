# AOTR 8P V18 release-builder hash mismatch checkpoint — 2026-08-27

## STATUS
The V18 / launcher 1.0.10 baseline audit correctly refused to continue because the documented local pre-promotion builder SHA256 did not match the immutable builder bytes stored in the actual release commit.

## WHAT WE KNOW
- Release commit: `1303e0a6b268b082e9352ded1461fa8d794f16d3`
- Authoritative released builder path: `launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10.ps1`
- Git blob SHA for that exact released file: `9d8975828106a572f43344e57891014860d489d4`
- Raw SHA256 of the released builder bytes, independently observed by the Windows audit download: `8BDD8745931B41AA2B062FB9ADCE8BBBD7EA2A33F4C0946C20A409D89639271A`
- Previously documented local pre-promotion builder SHA256: `7D847B66CAF060F3E1C5FD539DA3DF6E97865421651608CDD98898342C1BB2E0`
- The released file begins with an UTF-8 BOM (`U+FEFF`) before `#requires -version 5.1`.

## EVIDENCE
The baseline audit downloaded the builder directly from the immutable release-commit raw URL and computed `8BDD8745...`, then stopped before payload analysis because it was pinned to `7D847B66...`.

GitHub contents inspection for the same release commit confirms the exact file blob SHA `9d8975828106a572f43344e57891014860d489d4` and the BOM-prefixed first line.

## WHAT FAILED
Only the expected outer-builder SHA pin was stale. No builder, EXE, manifest, config, cache, game, or release file was modified.

## CURRENT HYPOTHESIS
`7D847B66...` represents the local pre-promotion builder checkpoint, while the file committed during release differs at byte representation and/or content. The exact reason for the byte-level difference is not yet proven. Do not reduce this to BOM or line endings without additional evidence.

## SAFE TESTS COMPLETED
- Release commit and path independently verified.
- Git blob identity captured.
- Released raw builder SHA captured from the Windows download.
- Baseline audit stopped before any patching.

## NEXT PRACTICAL ACTION
Re-run the corrected V18 baseline audit pinned to the actual released builder SHA `8BDD8745...`. Decode the embedded GUI and Engine, capture their SHA256 values, and verify the 1.0.10 preservation markers: REPORT ERROR, MESSAGES, Auto-Repair/report flow, dynamic status rows, zero Get-FileHash dependencies, and no synthetic test hook. Then port robust standalone AotR autodetection / Config V2 into this exact released V18 baseline.

## DO NOT REPEAT
- Do not use `7D847B66...` as the hash of the builder stored in release commit `1303e0a6...`.
- Do not run the obsolete V17 status-panel transplant.
- Do not patch the old `feature/robust-aotr-autodetect` branch as production baseline.
- Do not overwrite or regress REPORT ERROR, MESSAGES, Auto-Repair, dynamic status rows, or the existing .NET SHA256 implementation.
- Do not assume the byte-level reason for the 7D847/8BDD difference until proven.
