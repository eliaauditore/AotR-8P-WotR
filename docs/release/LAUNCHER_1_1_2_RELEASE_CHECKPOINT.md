# Launcher 1.1.2 Release Checkpoint

## Status

`1.1.2` is staged from the exact RC7 artifact that passed real runtime acceptance. ModDB AV acceptance is **not yet complete**: Issue #38 remains the final distribution blocker until these exact release bytes pass current Defender/cloud protection in a clean Windows environment with no prior allow/exclusion for this launcher.

## Exact staged candidate

- Version: `1.1.2`
- Release branch: `release/1.1.2`
- Accepted development source: `59a18ed496b254f6854f2261c85422fdbafe1063`
- RC7 workflow run: `33098884873`
- RC7 artifact ID: `9657563731`
- RC7 public ZIP SHA256: `F67DFE9E2E4215982891D58302445AF95CF177A341E95D54E8D4C0F01EE1D097`
- Exact runtime-tested EXE SHA256: `5B4D12B7BF43D72860E27C51A3D8AC7AC00CA53DB58499E41AC735F7B7ECED0E`
- Manifest SHA256: `26851416B61745E0009550A924F54E8AF47992693A01728E348DBC530FEAC729`
- Repair manifest SHA256: `B2BEEBF586F95D2E2F6B4A86F142FEF40561E72C907A4BDB3FA5D597377855AA`
- UI SHA256: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- Paper SHA256: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`
- Canonical 1.1.2 builder SHA256: `27F45FF2CF4825D2A7ED443FF8166D2BECCB03800D55460BF9647BF5F4A41082`

## Runtime acceptance

RC7 was user-confirmed for standalone startup, Auto-Repair, post-repair full re-check, automatic launch only after a clean re-check, clean launcher handoff/exit, real game launch, 8-player WotR rows, strategic-map zoom and strategic-map drag. No `A8P-ENGINE-001` remained.

## Integrity evidence

The final source state passed Windows PowerShell 5.1 parsing, V7 source-chain verification, explicit child-shellcode parameter binding, embedded Engine/V7/Shellcode byte/hash verification, embedded cross-resource consistency, static cleanup, and hosted Defender scanning. Release-staging run `33100026999` independently rebuilt the exact pinned source through all permanent gates before staging and passed; its push was intentionally blocked by unrelated line-ending changes, not by any release-integrity failure.

## Release safety

`main` and protected `v1.1.1` remain untouched pending guarded PR merge. Historical RC failures remain preserved on the development branch. The legacy .NET Framework `csc.exe` build is byte-nondeterministic, so later recompiles must never silently replace the exact runtime-tested EXE above. Do not ask users to disable Defender, whitelist the launcher, or restore a quarantined release as the distribution solution.
