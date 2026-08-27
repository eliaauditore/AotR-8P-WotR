# Launcher 1.1.2 Release Checkpoint

## Status

`1.1.2` is **RELEASED** from the exact RC7 artifact that passed real runtime acceptance.

The maintainer explicitly waived the remaining pristine/current Windows Defender acceptance gate on 2026-08-27 and authorized publication with the residual AV/reputation risk documented. Issue #38 remains open for post-release AV/reputation monitoring; this release does **not** claim universal Defender cleanliness.

## Frozen release identity

- Version: `1.1.2`
- Exact release commit: `131aacd19f8ea02399db6ad0dab69c4253fbe834`
- Protected release tag: `v1.1.2`
- GitHub Release: `https://github.com/eliaauditore/AotR-8P-WotR/releases/tag/v1.1.2`
- Accepted development source: `59a18ed496b254f6854f2261c85422fdbafe1063`
- RC7 workflow run: `33098884873`
- RC7 artifact ID: `9657563731`
- Exact public / ModDB ZIP SHA256: `F67DFE9E2E4215982891D58302445AF95CF177A341E95D54E8D4C0F01EE1D097`
- Exact runtime-tested EXE SHA256: `5B4D12B7BF43D72860E27C51A3D8AC7AC00CA53DB58499E41AC735F7B7ECED0E`
- Manifest SHA256: `26851416B61745E0009550A924F54E8AF47992693A01728E348DBC530FEAC729`
- Repair manifest SHA256: `B2BEEBF586F95D2E2F6B4A86F142FEF40561E72C907A4BDB3FA5D597377855AA`
- UI SHA256: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- Paper SHA256: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`
- Canonical 1.1.2 builder SHA256: `27F45FF2CF4825D2A7ED443FF8166D2BECCB03800D55460BF9647BF5F4A41082`

The GitHub Release asset `AotR_8P_War_of_the_Ring_1.1.2_ModDB_Official.zip` was published without rebuilding or repacking the frozen RC7 package. GitHub reports the server-side asset digest `sha256:f67dfe9e2e4215982891d58302445af95cf177a341e95d54e8d4c0f01ee1d097`.

## Runtime acceptance

The exact frozen RC7 bytes were user-confirmed for:

- standalone launcher start: PASS
- Auto-Repair: PASS
- full post-repair health re-check: PASS
- automatic launch only after a clean re-check: PASS
- launcher -> game handoff / automatic launcher close: PASS
- real game launch: PASS
- 8-player WotR rows: PASS
- strategic-map zoom: PASS
- strategic-map drag: PASS
- no remaining `A8P-ENGINE-001`: PASS

A temporary Defender execution-harness launch once lacked 8 rows / zoom / drag; controlled A/B retesting proved this was a temporary harness/context problem and not a regression in the frozen RC7 bytes.

## Integrity evidence

The final source state passed Windows PowerShell 5.1 parsing, V7 source-chain verification, explicit child-shellcode parameter binding, embedded Engine/V7/Shellcode byte/hash verification, embedded cross-resource consistency, static cleanup, and hosted Defender scanning.

Protected-main checks passed before promotion:

- `release-consistency`: PASS
- `ticket-system`: PASS
- `guardian-tools`: PASS

The one-shot release publisher independently downloaded artifact `9657563731`, required ZIP SHA256 `F67DFE9...`, verified the exact five-file public package and all recorded component hashes, created protected tag `v1.1.2` at exact release commit `131aacd...`, and published that exact ZIP to GitHub Release. The publisher workflow was then removed in a dedicated cleanup change.

## AV / reputation risk acceptance

An earlier, different 1.1.2 candidate with EXE SHA256 `ABB63269B48CB4FA52BBED7897FF07A6FCE5200E3EFF7CEBCAB28A84C8168818` was locally detected as `Trojan:Win32/Wacatac.C!ml` even though hosted Defender had scanned it clean.

The final 1.1.2 EXE `5B4D12B7...` is a different binary and passed hosted Defender scanning plus complete real runtime acceptance, but it did not receive pristine-environment Defender acceptance before release. The maintainer deliberately waived that remaining gate and accepted the residual risk.

Therefore:

- do not advertise `100% Defender clean` or equivalent;
- do not instruct users to disable Defender, add exclusions, whitelist, or restore detections as a normal installation step;
- if current Defender detects the exact final hash `5B4D12B7...`, preserve the detection evidence and track it under Issue #38.

## Release safety

Protected `v1.1.1` remains immutable and untouched. Historical failed/experimental RCs remain preserved on the development branch and in issue history. The legacy .NET Framework `csc.exe` build path is byte-nondeterministic, so later recompiles must never silently replace the exact frozen 1.1.2 release binary.

The final ModDB upload must use the exact same ZIP bytes as the GitHub Release asset: SHA256 `F67DFE9E2E4215982891D58302445AF95CF177A341E95D54E8D4C0F01EE1D097`. Any later binary change requires a new release version rather than silently replacing 1.1.2.
