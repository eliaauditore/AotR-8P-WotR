# AOTR 8P Stage 3 Preflight Root-Cause Checkpoint — 2026-08-27

## STATUS
Fresh standalone autodetection is proven PASS. The visible `A8P-INSTALL-001 / game.dat not found` failure is downstream of successful resolver/config creation.

## WHAT WE KNOW
- Stage 3 fresh discovery created canonical Config V2 without cache, without `AOTR_HOME`, and without manual folder selection.
- Canonical root: `D:\Games\AotR\AgeoftheRing`
- Runtime: `D:\Games\AotR\AgeoftheRing\rotwk`
- Source mod: `D:\Games\AotR\AgeoftheRing\aotr`
- game.dat: `D:\Games\AotR\AgeoftheRing\rotwk\game.dat`
- Score: 120
- Validation marker: `aotr-standalone-v2`
- The downstream GUI `Invoke-Preflight` checks the correct `$GameDat` path, then executes `Get-Sha256 $GameDat` inside a `try { ... } catch {}`.
- The embedded `Get-Sha256` implementation delegates to `Get-FileHash`.
- User screenshot visibly shows the runtime error beginning with German PowerShell text `Die Benennung "Get-FileHash" ...`, proving the embedded host does not resolve that cmdlet.
- The empty preflight catch suppresses the real exception and leaves `$gameOk = $false`, causing the misleading `game.dat not found` UI and `A8P-INSTALL-001` classification.

## EVIDENCE
Stage 3 source audit on embedded GUI (2644 lines):
- line 619: `$GameDat = $Install.GameDat`
- line 622: `function Get-Sha256([string]$Path)`
- line 623: `(Get-FileHash ...).Hash.ToUpperInvariant()`
- line 1616: verifies `$GameDat` exists
- line 1619: `$gameHash = Get-Sha256 $GameDat`
- line 1624: empty `catch {}`
- line 1630: misleading `game.dat not found`
- line 1703: `Enter-RepairMode "game.dat not found"`

Definition audit proved that `Known931GameSize`, `Known931GameSha256`, and `CompatCachePath` are all defined, so this is not a StrictMode undefined-variable failure.

## CURRENT HYPOTHESIS / ROOT CAUSE
Confirmed root cause: embedded GUI runtime depends on `Get-FileHash`, but the hosted PowerShell environment does not provide/resolve that cmdlet. Preflight swallows the resulting command-not-found exception and misreports the failure as a missing game.dat.

## FIX STRATEGY
Replace embedded `Get-Sha256` implementation with a pure .NET `System.Security.Cryptography.SHA256` + `System.IO.FileStream` implementation. Do not change the already-proven resolver logic.

Patch helper:
- `research/installer/AOTR_8P_STAGE3_EMBEDDED_GETFILEHASH_FIX_V1.ps1`
- It pins the current Stage-1 builder and embedded GUI/engine hashes.
- It replaces only the exact proven `Get-Sha256` block when `Get-FileHash` is present.
- It refuses broad/unproven replacement.
- It removes remaining `Get-FileHash` references from embedded GUI/engine, parser-validates them, re-embeds, and performs roundtrip hash checks.
- It writes a new non-release builder in a timestamped work root.

## FILES / HASHES
Input builder SHA256:
`6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386`

Input GUI payload SHA256:
`D8C3E27E35F3EDA101EE74362C9E744BB942D6F06928B61D22036640C22E5F47`

Input engine payload SHA256:
`3A03D47B6A094A4892A146866DFEAD53858C500F812615672D66690D7812A873`

Stage-2 test EXE SHA256:
`0EE6D45F01270F6C81DF2D5A828FE373C66202806EC742FDF7B9C64F6FBA7F0B`

## SAFE TESTS COMPLETED
- Stage-2 isolated non-release build PASS.
- Stage-3 complete disposable runtime PASS.
- Fresh autodetect + Config V2 PASS.
- Real launcher config modified: NO.
- Public release modified: NO.
- Source audit/decode only PASS.
- Definition audit PASS.

## NEXT PRACTICAL ACTION
Run `AOTR_8P_STAGE3_EMBEDDED_GETFILEHASH_FIX_V1.ps1`, capture exact output builder/GUI/engine hashes, then build a new non-release test EXE using the same verified seed/support donor inputs and rerun Stage-3 fresh discovery/preflight.

## DO NOT REPEAT
- Do not change resolver discovery/ranking: fresh detection is proven.
- Do not diagnose this as missing `game.dat`: the canonical config proves it exists and was resolved.
- Do not add `Get-FileHash` module imports as the primary fix; remove the hosted-runspace dependency instead.
- Do not patch release/public EXE directly.
- Do not merge/release before the new test EXE passes preflight and the broader detection matrix.
