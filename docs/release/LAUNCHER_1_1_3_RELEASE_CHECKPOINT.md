# Launcher 1.1.3 Update-Channel Release Checkpoint

## Status

`1.1.3` is accepted for the GitHub self-update channel from the exact RC1 bytes runtime-tested by the maintainer on 2026-08-28.

This release intentionally does **not** publish a new ModDB package. Existing installed launchers update themselves from GitHub on startup.

## Frozen identity

- Version: `1.1.3`
- Accepted RC1 workflow run: `33144974815`
- Accepted RC1 artifact ID: `9675406724`
- EXE SHA256: `41CE4281105E61D4595621D0D0C9CFE70CEBA7EB692F1E4ED1C7703899B9FE21`
- EXE size: `1267200`
- Candidate ZIP SHA256: `3043CF13DFCA95F4AF502E34B459C14D0C22154EC7340A08AE4DD40268CA9BCB`
- Manifest SHA256: `F9FBC62C35000477021DEE49759001E2356B965D05EB15BC9C7813041103E647`
- Repair manifest SHA256: `71CBC5936A20582B62501AAACEFA6F7DC5CE2E9C19749DF21385734B9481ED8B`
- UI SHA256: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- Paper SHA256: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`

## Acceptance

Maintainer real-runtime acceptance for exact RC1: PASS â€” launcher, game launch, 8-player WotR behavior and existing runtime functionality all work.

Hosted Defender scan for the exact EXE: `SCANNED_CLEAN`.

Runtime chain remains pinned:
- Engine: `5DB2F749F10E84322BC471FFF04E25326EFF194FA440175FE9841ED13367F938`
- FINAL_STABLE_V7: `72D00490538BE2222F5BAAF3D8A1648A86071D3A098946A7B8751E7D337300E2`
- V7 shellcode: `60EECE4660C3BA0AD183EB82B82DCDACF3ECA6DC892C8FAFCD629A92170ED45A`

## 1.1.3 change

Adds accountless direct support reporting after exhausted Auto-Repair:
`SEND REPORT -> HTTPS backend -> GitHub ticket -> existing fingerprint/master-ticket workflows`.

Browser/manual fallbacks remain available through `OPEN GITHUB` and `COPY REPORT`.

Production direct-report endpoint: `https://a8p-direct-report.vercel.app/api/report`.

## Update-channel behavior

The standalone launcher calls `TrySelfUpdate` before opening the GUI. If `main/manifest.json` advertises a newer semantic version, it downloads the EXE from `launcher_url`, verifies the exact SHA256 from the manifest, starts the verified helper, replaces the old launcher, and relaunches the updated executable.

Therefore users who already have the launcher do not need a new ModDB download for 1.1.3.

## Release safety

`v1.1.2` and its frozen release bytes/source remain untouched. The canonical 1.1.2 V19 builder is preserved; 1.1.3 development is separated under `launcher-source/v20`.
