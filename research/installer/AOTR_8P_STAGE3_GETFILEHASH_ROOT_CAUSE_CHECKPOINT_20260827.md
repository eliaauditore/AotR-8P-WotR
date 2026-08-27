# AOTR 8P STAGE 3 Get-FileHash ROOT-CAUSE CHECKPOINT — 2026-08-27

## STATUS
Fresh standalone autodetection is proven PASS. A downstream GUI preflight failure remains in the first Robust Autodetect V2 test EXE. Root cause is now isolated to `Get-FileHash` not being available in the embedded PowerShell host/runspace.

## WHAT WE KNOW
- Stage 3 Fresh Discovery V2 passed with isolated LOCALAPPDATA, no AOTR_HOME, no manual selection.
- Canonical config written:
  - `aotr_root = D:\Games\AotR\AgeoftheRing`
  - `runtime = D:\Games\AotR\AgeoftheRing\rotwk`
  - `source_mod = D:\Games\AotR\AgeoftheRing\aotr`
  - `game_dat = D:\Games\AotR\AgeoftheRing\rotwk\game.dat`
  - `schema = 2`
  - `validation = aotr-standalone-v2`
  - `score = 120`
- GUI downstream preflight wraps game.dat item/hash/cache checks in `try { ... } catch {}` and then reports `game.dat not found` whenever that block fails.
- Screenshot/runtime evidence exposed a command-not-found message beginning with German text for `Get-FileHash`.
- GUI embedded source contains exactly one `Get-FileHash` dependency inside `Get-Sha256`.
- Engine embedded source contains exactly three `Get-FileHash` dependencies:
  1. Engine `Get-Sha256` wrapper.
  2. UI deployment source hash.
  3. UI deployment active hash.

## EVIDENCE
Input Stage-1 patched builder SHA256:
`6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386`

Input GUI payload SHA256:
`D8C3E27E35F3EDA101EE74362C9E744BB942D6F06928B61D22036640C22E5F47`

Input Engine payload SHA256:
`3A03D47B6A094A4892A146866DFEAD53858C500F812615672D66690D7812A873`

Engine source proof:
- line 121: `return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()`
- line 912: `$sourceHash = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash`
- line 913: `$activeHash = (Get-FileHash -LiteralPath $uiActive -Algorithm SHA256).Hash`

## WHAT FAILED
`AOTR_8P_STAGE3_EMBEDDED_GETFILEHASH_FIX_V1.ps1` safely refused to patch because it only supported the GUI-shaped `Get-Sha256` wrapper and detected three differently structured Engine occurrences. No builder, EXE, config, game, or release files were modified.

## CURRENT HYPOTHESIS
The embedded host/runspace does not import/provide `Get-FileHash`. GUI preflight calls it indirectly through `Get-Sha256`, throws command-not-found, swallows the exception, and misreports `game.dat not found`. Engine would encounter the same host dependency later unless all three Engine occurrences are removed.

## SAFE PATCH PREPARED
`research/installer/AOTR_8P_STAGE3_EMBEDDED_GETFILEHASH_FIX_V2.ps1`

The V2 patch is intentionally narrow:
- Requires exactly 1 GUI `Get-FileHash` occurrence.
- Requires exactly 3 Engine `Get-FileHash` occurrences.
- Replaces GUI `Get-Sha256` with pure .NET SHA256 over a file stream.
- Replaces Engine `Get-Sha256` with the same .NET SHA256 implementation.
- Rewrites only the two proven Engine UI deployment hash lines to call `Get-Sha256`.
- Requires 0 remaining `Get-FileHash` occurrences in both payloads.
- Parser-validates GUI, Engine and builder.
- Performs full write/redecode roundtrip.
- Verifies the original input builder remains byte-identical.
- Does not modify the proven autodetect resolver.
- Does not modify public/release EXEs or game files.

## NEXT PRACTICAL ACTION
Run the V2 targeted hash-host fix. Capture output builder SHA256 plus output GUI/Engine SHA256. If all checks pass, pin those hashes in a new non-release Stage-2-style build runner and rebuild the test EXE. Then repeat the same isolated Stage-3 Fresh Discovery test.

## DO NOT REPEAT
- Do not change the Robust Autodetect V2 resolver; it is already proven PASS.
- Do not treat the `game.dat not found` text as proof that game.dat is absent.
- Do not broad-regex-patch Engine source.
- Do not depend on `Get-FileHash` inside embedded GUI/Engine runspaces.
- Do not touch public/release artifacts during this fix.
