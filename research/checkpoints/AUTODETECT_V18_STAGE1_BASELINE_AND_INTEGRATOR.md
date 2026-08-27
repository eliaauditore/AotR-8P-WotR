# Robust AotR autodetect V18 / 1.0.10 checkpoint

## STATUS

Authoritative baseline moved from the older V17 development builder to the released launcher 1.0.10 V18 production builder. A V18-specific Stage 1 integrator is now prepared but has not yet built an EXE.

## WHAT WE KNOW

- Release commit: `1303e0a6b268b082e9352ded1461fa8d794f16d3`.
- Authoritative released builder path: `launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10.ps1`.
- Actual released builder SHA256: `8BDD8745931B41AA2B062FB9ADCE8BBBD7EA2A33F4C0946C20A409D89639271A`.
- Git blob SHA: `9d8975828106a572f43344e57891014860d489d4`.
- The older documented pre-promotion builder SHA `7D847B66CAF060F3E1C5FD539DA3DF6E97865421651608CDD98898342C1BB2E0` is not the SHA256 of the bytes stored in the release commit.
- Released embedded GUI SHA256: `46032AC5272ED491A9E3F497733148A4531E35DC7D1634DDC180CC48D6C9FA24`.
- Released embedded ENGINE SHA256: `E5803FB7D7BDCD463587C99796A6B0EFD4D23D3D6C69BA102A83435D872F6E5F`.
- Released GUI contains REPORT ERROR, MESSAGES/unread state, Auto-Repair/report state, dynamic status rows, .NET SHA256, and no synthetic test hook.
- Released ENGINE contains .NET SHA256 and FINAL_STABLE_V7 markers, with no Get-FileHash usage.
- Released GUI and ENGINE still use the old install resolver/config schema; Config V2 marker count is zero in both.

## EVIDENCE

User-executed release-pinned baseline audit passed all critical 1.0.10 preservation invariants and printed the old resolver source. It confirmed:

- GUI `Get-FileHash`: 0
- ENGINE `Get-FileHash`: 0
- GUI `StatusRowsHost`: present
- GUI `REPORT ERROR`: present
- GUI `MESSAGES`: present
- synthetic `A8P_TEST_FORCE_ERROR` / `A8P-TEST-001`: 0
- Config V2 / `aotr-standalone-v2`: 0 before integration

## WHAT FAILED

The first V18 baseline audit pinned the documented local/pre-promotion builder SHA `7D847B66...`, while the immutable released GitHub bytes hash to `8BDD8745...`. The audit correctly stopped. The pin was corrected only after direct release-path verification.

## CURRENT HYPOTHESIS

The robust autodetect/config V2 resolver previously proven on the V17 branch can be transplanted into V18 without rebuilding old GUI functionality because the V18 resolver boundaries remain structurally compatible. The safest implementation is to use the old proven Stage-1 integrator only as an immutable source donor for its `guiReplacement` and `engineReplacement` here-strings, never execute it.

## FILES / HASHES / OFFSETS

- V18 released builder SHA256: `8BDD8745931B41AA2B062FB9ADCE8BBBD7EA2A33F4C0946C20A409D89639271A`
- V18 GUI SHA256: `46032AC5272ED491A9E3F497733148A4531E35DC7D1634DDC180CC48D6C9FA24`
- V18 ENGINE SHA256: `E5803FB7D7BDCD463587C99796A6B0EFD4D23D3D6C69BA102A83435D872F6E5F`
- Resolver donor commit: `7c4f7d958238926dfdaa15b2baeb73cd99b0dd45`
- New V18 Stage 1 integrator commit: `0e3a4812e053dc78731f3a3a9877b4428ead7f2a`

Replacement boundaries:

- GUI start: `function Get-AotRInstallFromPath([string]$Path) {`
- GUI end: `$Install = Resolve-AotRInstall -PromptIfMissing`
- ENGINE start: `function Get-AotRInstallFromPath([string]$Path) {`
- ENGINE end: `function New-LinkedFile([string]$Source, [string]$Destination) {`

## SAFE TESTS COMPLETED

- Released builder byte hash verification: PASS.
- Released GUI/ENGINE payload extraction: PASS.
- 1.0.10 ticket/status/MESSAGES/SHA baseline: PASS.
- Existing resolver and lack of Config V2 confirmed: PASS.
- No EXE, manifest, config, cache, game, or release file changed by baseline audit.

## NEXT PRACTICAL ACTION

Run `research/installer/AOTR_8P_V18_STAGE1_INTEGRATE_ROBUST_AUTODETECT_V2.ps1` from commit `0e3a4812e053dc78731f3a3a9877b4428ead7f2a` under PowerShell 7.6.5. It must produce a new non-release builder only after:

- parser validation;
- exact released input hashes;
- exact GUI/ENGINE payload hashes;
- donor-marker validation;
- byte-identical prefix/suffix preservation outside resolver windows;
- unchanged REPORT ERROR / MESSAGES / Auto-Repair / status marker counts;
- Get-FileHash remaining zero;
- FINAL_STABLE_V7 marker count remaining unchanged;
- full re-embed roundtrip checks.

Do not build an EXE until Stage 1 passes.

## DO NOT REPEAT

- Do not use the old V17 builder as production base.
- Do not run the obsolete status-panel transplant V6.
- Do not replace V18 with an older whole GUI payload.
- Do not lose REPORT ERROR, MESSAGES, Auto-Repair, dynamic status rows, or FINAL_STABLE_V7.
- Do not use the stale `7D847B66...` value as the released GitHub builder byte hash.
- Do not involve All-in-One Launcher.
- Do not accept exe-only installs; standalone root requires `rotwk\lotrbfme2ep1.exe`, `game.dat` or `zGameDats\game.dat`, and sibling `aotr\`.
- Do not auto-prefer runtime, BFME_RESEARCH, backup, checkpoint, or temp copies.
- Do not perform recursive network scans.
- Do not invent repair action names or version thresholds.
- Do not modify release artifacts before non-release proof and matrix completion.
