# V19 donor-free successor checkpoint

Date: 2026-08-28

Status: `NON_RELEASE / SOURCE-CHAIN BUILD PASS / RUNTIME REVIEW REQUIRED`

Parent: #68 / #52

## Frozen production boundary

Launcher 1.1.2 is unchanged and remains the current frozen release:

- release commit: `131aacd19f8ea02399db6ad0dab69c4253fbe834`
- tag: `v1.1.2`
- runtime-tested EXE SHA256: `5B4D12B7BF43D72860E27C51A3D8AC7AC00CA53DB58499E41AC735F7B7ECED0E`
- public/ModDB ZIP SHA256: `F67DFE9E2E4215982891D58302445AF95CF177A341E95D54E8D4C0F01EE1D097`

The donor-free work does not update root release files, the protected tag/release, or ModDB.

## Successor source path

Branch: `feature/v19-donor-free-successor`

Builder:

`launcher-source/v19-successor/BUILD_LAUNCHER_DONOR_FREE_CANDIDATE.ps1`

Default candidate version:

`1.1.3-donorfree-dev1`

The successor builder parameter surface is only:

- `OutputRoot`
- `LauncherVersion`

It has no `FrozenDonorRoot` parameter and does not perform frozen-launcher reflection extraction, associated-icon extraction, Base64/GZip donor recovery, or local research-path discovery.

The historical donor-based `launcher-source/v19/**` builder remains preserved as release/research provenance.

## Maintained repository resources

The following exact V19-clean bytes were materialized once from the previously verified provenance export and are now maintained directly under `launcher-source/v19-successor/resources/**`:

| Resource | SHA256 |
| --- | --- |
| `launcher_gui.ps1` | `135B1FDD64B84B0DE84BC7526F04157A790228DFC49FF5DD6253C89023D71EBD` |
| `launcher_engine.ps1` | `5DB2F749F10E84322BC471FFF04E25326EFF194FA440175FE9841ED13367F938` |
| `launcher_skin.png` | `BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6` |
| `launcher.ico` | `3F5784964233DC701B2E9ABA1DD2EF3DDCC47FB5955D0B986FF5D3046DFE1F1A` |
| `final_stable_v7.ps1` | `72D00490538BE2222F5BAAF3D8A1648A86071D3A098946A7B8751E7D337300E2` |
| `v7_shellcode.bin` | `60EECE4660C3BA0AD183EB82B82DCDACF3ECA6DC892C8FAFCD629A92170ED45A` |
| `row1cleanpatch.png` | `D4DC9A47F0E2FD9715D92F8DD4C3831B9AB95F8CA34E98937F019B7574294177` |
| `row2cleanpatch.png` | `58B9A7173CE1C9C30C85EE76D15D54E3D40B3E7E14E25D0C1FE5D8EFD89E6D8E` |
| `row3cleanpatch.png` | `7F86C02BC02D2E57D66202AF9C526D6FAE13CFC9B7CB1EFF1BB61C165B25278C` |
| `readycleanpatch.png` | `35DCBCBE6E625C5C06EC36BAB3CA51A6F4EE29DA3DFF4CAEEDD69BC87D873DF3` |

Materialization provenance:

- source workflow run: `33123908148`
- source artifact: `9667562167` / `v1.1.1-launcher-provenance`
- artifact digest: `sha256:c19970b6c90ed41911d4e334b0c5660f5ee6477fae8cee417ad419f37ae71ba9`
- materialization run: `33125767173` — PASS
- materialized-resource commit: `b1171a8b7ef66eba42e5f95fc577bc9d367f6c47`

The one-shot materializer was removed immediately after the resource commit. Future successor builds consume only repository files.

## Git byte-preservation correction

The first hosted build correctly passed the donor-free AST/extraction check but failed before compilation because Windows Git checkout converted a byte-pinned PowerShell resource's line endings:

- expected GUI SHA: `135B1FDD...`
- checkout-observed GUI SHA: `1DEDFD94...`

This was a build-source checkout/harness issue, not a launcher/resource semantic failure.

`.gitattributes` now marks the successor `.ps1`, `.bin`, `.png` and `.ico` resources as `-text`, preventing checkout transformations. The next hosted build consumed the exact pinned resource bytes and passed.

## Hosted donor-free candidate build

Workflow:

`Build V19 Donor-Free Successor`

Run: `33126002235`

Head used for successful build: `66cbc7f35b30112fbee873bbf2adec201cbad387`

Artifact:

- artifact ID: `9668367064`
- artifact name: `v19-donor-free-successor-dev1`
- artifact digest: `sha256:239f270afed61fd6913c407661487dfc9da0a80d0044d620cadc10563c5a1a5d`

Candidate:

- version: `1.1.3-donorfree-dev1`
- EXE SHA256: `8AFE4D434CB58ED68A55602E568F1FAFCFEF59551D80DF73CE6CF5FC9FE7A36F`
- EXE size: `1,258,496`
- manifest SHA256: `CFAD2FF18F001977CCEA55085618E10B9447C84C90724C68324412221A2925B8`
- repair-manifest SHA256: `53C92A7DE8896B02F48AC3FB9A7849E8D47FB5993BE966D8DF3C7DBEF9D9A2B9`
- UI SHA256: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- Paper SHA256: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`
- non-release ZIP SHA256: `B211245C65B2ED26B7186437AF2DDD680AE7F8FC8F607EDC1B59A7AAA0357B04`
- `frozen_donor_root_used`: `false`

Hosted build gates passed:

- Windows PowerShell 5.1 builder parse: PASS
- parameter surface contains no `FrozenDonorRoot`: PASS
- donor extraction primitives absent: PASS
- all maintained resource SHA256 checks: PASS
- GUI/Engine/FINAL_STABLE PowerShell 5.1 parsing: PASS
- V7 resource chain: PASS
- C# compile: PASS
- compiled ProductVersion: PASS
- exact nine managed embedded-resource names: PASS
- all nine embedded resource bytes match maintained repo resource hashes: PASS
- legacy donor/Base64/resource-recovery tokens in compiled EXE: absent
- complete five-file non-release package: PASS
- repository remained clean after build: PASS

The candidate EXE is not expected to be byte-identical to frozen 1.1.2 because the candidate version differs and the legacy .NET Framework `csc.exe` path is known to be byte-nondeterministic. Runtime/behavioral parity is the next acceptance criterion.

## Ownership / SignPath classification

`launcher-source/v19-successor/RESOURCE_OWNERSHIP.json` is authoritative for this branch.

Important current blockers:

- `launcher_skin.png`: `THIRD_PARTY_AOTR_BFME_CONTENT`; exclude or replace before launcher OSS/SignPath Foundation scope.
- `launcher.ico`: `REVIEW_REQUIRED`.
- four cleanup patch PNGs: `REVIEW_REQUIRED`, likely visual derivatives until proven/replaced.
- `final_stable_v7.ps1`: `REVIEW_REQUIRED` for reverse-engineered byte provenance/policy.
- `v7_shellcode.bin`: `REVIEW_REQUIRED` for authored generation/provenance and SignPath policy.
- GUI/Engine are now maintained source files but formal rights/license provenance still requires confirmation before an OSS grant.
- `payload_ui.big` and `payload_paper.inc`: third-party AotR/BFME content outside the signed launcher scope.

Therefore this checkpoint proves **donor-free build provenance**, not SignPath Foundation eligibility.

## Next gate

Do not merge/release this candidate as production yet.

Next required evidence on the exact EXE `8AFE4D43...`:

1. fresh standalone launcher start;
2. health rows / Auto-Repair + clean re-check behavior;
3. manual START and launcher handoff;
4. fresh game process stability;
5. 8-player WotR rows;
6. strategic-map zoom/drag;
7. V7/runtime patch activation / no `A8P-ENGINE-001`;
8. Defender/reputation/SAC follow-up under #38/#50 as appropriate;
9. resolve ownership/policy blockers before any SignPath Foundation application under #52.
