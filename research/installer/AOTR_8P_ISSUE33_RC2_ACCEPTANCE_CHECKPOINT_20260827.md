# Issue #33 RC2 Acceptance Checkpoint — 2026-08-27

## STATUS
RC2 runtime acceptance PASS. Candidate remains non-release and published launcher 1.1 remains untouched.

## CANDIDATE
- Version: `1.1.1-issue33-rc2`
- EXE SHA256: `59865672D5E4F53579E61D9CE37FECD7C5E5BC77E81C6CB05D028A9554FD4E44`
- Embedded GUI SHA256: `23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C`
- Embedded ENGINE SHA256: `94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA`
- Materialized skin SHA256: `BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6`
- UI SHA256: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- Paper SHA256: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`

## ROOT CAUSE
The 1.1 C# bootstrapper invoked the embedded GUI while the GUI still loaded `internal\assets\launcher_skin.png` from disk. The public five-file release root did not ship `internal/`, so the standalone contract was broken.

## FIX
RC2 embeds the exact RC2 skin bytes as gzip+Base64 in the outer C# bootstrapper. An explicit `static Program()` runs before the entry point, verifies the embedded skin SHA256, and materializes/repairs `internal\assets\launcher_skin.png` relative to the EXE before the embedded GUI starts. GUI and ENGINE payload bytes remain unchanged.

## SAFE TESTS COMPLETED
1. RC2 build gate: PASS.
2. Isolated first boot from exactly five public files with no pre-existing `internal/`: PASS.
3. Candidate self-materialized the exact skin and GUI remained stable: PASS.
4. Two-phase START acceptance: PASS.
   - Phase A allowed AUTO REPAIR provisioning; `retry_launch` was observed (`Repair retry: True`) and deliberately excluded from manual START evidence.
   - Phase B established a clean process baseline, reopened the candidate, then used explicit manual START.
   - Fresh `lotrbfme2ep1.exe` PID: `12248`.
   - Stability window: `15 s` PASS.
   - Launcher handoff/exit: PASS.
   - Five public release artifacts remained byte-identical.

Local acceptance report supplied by operator:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\ISSUE33_STANDALONE_SKIN_RC2_20260827_051102\PACKAGE\_ISSUE33_RC2_START_ACCEPTANCE_V1_2_20260827_053352\ISSUE33_RC2_START_ACCEPTANCE_V1_2_REPORT.txt`

## HARNESS FAILURES THAT ARE NOT CANDIDATE FAILURES
- RC1 builder gate: incorrect assumption about C# `Main(...)` signature. No candidate published.
- START gate V1: StrictMode scalar `.Count` bug. No launcher/game started.
- START gate V1.1: AUTO REPAIR legitimately executed `retry_launch`, producing a game process before manual START. Gate design was ambiguous, not the candidate. V1.2 split provisioning and manual START into separate phases and passed.

## ROLLBACK / PRESERVED HISTORY
- Frozen failing 1.1 release commit: `bbd7eff483d2cdbf3e799f764433b49195dc55b6`
- Frozen failing 1.1 EXE SHA256: `9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4`
- Historical known-good 1.0.10 remains preserved.

## NEXT PRACTICAL ACTION
Open guarded Guardian-review PR from `fix/issue-33-standalone-skin` to `main`, require `release-consistency`, `ticket-system`, and `guardian-tools` green, then prepare an exact final replacement release version without mutating v1.1 in place.

## DO NOT REPEAT
- Do not ship a five-file standalone EXE that still requires a build-tree-only skin path.
- Do not count AUTO REPAIR `retry_launch` as the manual START acceptance event.
- Do not overwrite/rewrite v1.1, its tag, or its frozen failure hash.
