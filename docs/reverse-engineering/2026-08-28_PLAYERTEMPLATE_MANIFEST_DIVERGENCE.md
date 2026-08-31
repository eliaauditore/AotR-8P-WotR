# Host/VM manifest comparison — PlayerTemplate is the only shared game-data mismatch

Date: 2026-08-28

Two complete AotR data manifests were compared:

- Host manifest: 11,348 files
- VM manifest: 3,701 files
- All 3,701 VM paths exist on Host
- Host has 7,647 additional paths
- VM has 0 unique paths

Among the 3,701 shared paths, exactly 3 files differ by length and/or SHA-256:

| Relative path | Host length | VM length | Host SHA-256 | VM SHA-256 |
| --- | ---: | ---: | --- | --- |
| `_AOTR_8P_WOTR_RUNTIME\AOTR8P_V4_SOURCE.txt` | 34 | 23 | `3DE7C8D1FEE9E8E24D557B8A307AB1DA15628800DB1A070E6CBED7B30F834144` | `38D9D4A36FDBE6AB0071D851128B9BB7654AA995A3270B1193DD3C70034851B7` |
| `_AOTR_8P_WOTR_RUNTIME\data\ini\playertemplate.ini` | 33,211 | 33,233 | `2D162EE705DE9D96A7B65140C22EBA6EBD0B8F155AE062C97F9884E37DC59F4D` | `D29FD3CE56F6489719C49ABEE3881C556E3CF2E62146EFA8192E7105A0C817B9` |
| `aotr\data\ini\playertemplate.ini` | 33,211 | 33,233 | `2D162EE705DE9D96A7B65140C22EBA6EBD0B8F155AE062C97F9884E37DC59F4D` | `D29FD3CE56F6489719C49ABEE3881C556E3CF2E62146EFA8192E7105A0C817B9` |

The two PlayerTemplate copies were internally identical on each machine at manifest-capture time, but Host and VM differed from one another.

This lines up directly with the targeted localRoot payload/caller capture. The first proven divergent serializer payloads are PlayerTemplate-style text lines:

Host around call 50,156:

- `StartingUnit3 = PvPModePing`
- `StartingUnitOffset3 = X:0 Y:0 Z:0`
- later `StartingUnit5 = Dove_white_in_game`

VM around call 50,156:

- `StartingUnit5 = Dove_white_in_game`
- `StartingUnitOffset5 = X:300 Y:0 Z:0`
- later `StartingUnit6 = Dove_white_in_game`

Both machines used the same serializer callers:

- length DWORD: return VA `0x00A1F58D`, RVA `0x0061F58D`
- payload bytes: return VA `0x00A1F59F`, RVA `0x0061F59F`

## Exact textual / byte delta

A direct targeted comparison showed the same semantic delta in 11 PlayerTemplate blocks.

Host has these directives active:

```ini
StartingUnit3 = PvPModePing ;{{CameraToggle}}
StartingUnitOffset3 = X:0 Y:0 Z:0 ;{{CameraToggle}}
```

VM has the same directives commented out:

```ini
;StartingUnit3 = PvPModePing ;{{CameraToggle}}
;StartingUnitOffset3 = X:0 Y:0 Z:0 ;{{CameraToggle}}
```

This occurs twice per block across 11 blocks, for exactly 22 additional semicolon bytes on VM.

A normalization test removed only those 22 semicolons from the complete VM file in memory:

- VM original length: `33,233`
- semicolons removed: `22`
- normalized length: `33,211`
- normalized SHA-256: `2D162EE705DE9D96A7B65140C22EBA6EBD0B8F155AE062C97F9884E37DC59F4D`

The normalized VM SHA-256 is exactly the Host SHA-256. Therefore there is no additional hidden byte difference in this file: the complete Host/VM PlayerTemplate delta is exactly these 22 comment characters.

## Controlled A/B preparation

The VM PlayerTemplate copies were synchronized by removing only the 22 proven comment characters.

Post-sync evidence for both VM locations:

- `C:\AgeoftheRing\aotr\data\ini\playertemplate.ini`
- `C:\AgeoftheRing\_AOTR_8P_WOTR_RUNTIME\data\ini\playertemplate.ini`
- length: `33,211`
- SHA-256: `2D162EE705DE9D96A7B65140C22EBA6EBD0B8F155AE062C97F9884E37DC59F4D`

Both VM copies are therefore byte-identical to Host for this file.

## Runtime A/B result after PlayerTemplate sync

The existing read-only `AOTR_WOTR_B04_RUNTIME_COMPONENT_SPLIT.ps1` probe was rerun with Host and VM in the same WotR network state after the PlayerTemplate sync.

Host:

- `B04 = 0xD0B40E9B`
- `component A = 0x792B9B94`
- `component B = 0x57887307`
- `B38 = 0x000EFFF1`
- `LISTCOUNT = 8`
- `FLAG = 0`
- `ACC = 0x00000008`

VM:

- `B04 = 0xD0B40E9B`
- `component A = 0x792B9B94`
- `component B = 0x57887307`
- `B38 = 0x000EFFF1`
- `LISTCOUNT = 8`
- `FLAG = 0`
- `ACC = 0x00000008`

The complete comparison keys are identical:

`B04=D0B40E9B;A=792B9B94;B=57887307;B38=000EFFF1;LISTCOUNT=8;FLAG=0;ACC=00000008`

Before this file correction, runtime had already proven component B equal while component A differed between Host and VM. After changing only the proven PlayerTemplate delta, component A equals Host and therefore B04 equals Host as well.

## Controlled native Join rerun — SUCCESS

With files left unchanged after the PlayerTemplate synchronization, the same controlled native `C54CE0 +0x40` Join Request was executed exactly once from the VM.

VM pre-call contract:

- `game.dat` SHA-256: `CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC`
- session vtable: `0x00C54CE0` PASS
- vtable `+0x40`: `0x0084CB34` PASS
- session state `+0x28 = 0` PASS
- session `+0x44 = NULL` before call
- local endpoint: `192.168.0.57:8086`
- exactly one remote GameInfo matched Host `192.168.0.224:8086`

The native call returned successfully.

VM post-call state:

- `session+0x44`: `0x00000000 -> 0x09448408`
- current object vtable: `0x00C54B78` (expected Network GameInfo vtable)
- P1: Type6 `192.168.0.224:8086`
- P2: Type6 `192.168.0.57:8086` LOCAL
- P3/P4 remain Type3
- P5-P8 remain Type1
- `NATIVE_JOIN_STATE_OBSERVED = YES`

Simultaneously, the read-only Host transient watcher observed the authoritative slot transition:

- P2 changed from `type=0 endpoint={0,0}`
- to `type=6 endpoint=192.168.0.57:8086`
- `Any slot change = True`
- `Client Type6 seen = True`
- `HOST_PATH_C_COMMIT_OBSERVED = YES`

This is the success behavior that was absent before the PlayerTemplate correction.

## Root-cause closure

### BEWIESEN

- Among every file present on the VM, only three shared paths differed from Host in the captured manifests.
- The only differing shared game-data file was `playertemplate.ini`, present in two mirrored locations.
- The complete byte delta inside `playertemplate.ini` was exactly 22 semicolons.
- Those semicolons commented out `StartingUnit3 = PvPModePing` and `StartingUnitOffset3 = X:0 Y:0 Z:0` in 11 PlayerTemplate blocks on VM while Host had them active.
- Removing only those 22 semicolons produced the exact Host length and SHA-256.
- Both VM PlayerTemplate copies were synchronized to the Host SHA-256 without modifying unrelated files.
- Before correction, component B matched while component A differed between Host and VM, producing a B04 mismatch.
- After changing only PlayerTemplate, Host and VM had identical component A, component B, B04, B38 and related object state.
- With B04 aligned, the same controlled native Join Request that previously failed now succeeds.
- Host commits the client as Type6 in P2 and VM enters native joined state with non-NULL `session+0x44`.

Therefore, for the reproduced Host/VM state, the causal chain is closed:

`playertemplate.ini mismatch -> PlayerTemplate serializer divergence -> Component-A mismatch -> B04 mismatch -> PATH_C validation rejection -> no Type6 commit`

and after the one-file correction:

`PlayerTemplate match -> Component-A match -> B04 match -> PATH_C success path -> Host P2 Type6 commit -> VM native joined state`

The earlier PATH_C failure had been localized to the B04/Reason4 comparison path; the successful one-variable A/B rerun closes that final link for this test case.

## Reproducible fix

For installations exhibiting the old VM state, the relevant `playertemplate.ini` must match the canonical Host/reference content:

- canonical length: `33,211`
- canonical SHA-256: `2D162EE705DE9D96A7B65140C22EBA6EBD0B8F155AE062C97F9884E37DC59F4D`
- `StartingUnit3 = PvPModePing ;{{CameraToggle}}` active
- `StartingUnitOffset3 = X:0 Y:0 Z:0 ;{{CameraToggle}}` active
- applied consistently to both the source path and `_AOTR_8P_WOTR_RUNTIME` mirror used by this installation layout

Do not treat broad reinstall/synchronization as the demonstrated fix. The controlled experiment changed only this proven PlayerTemplate delta.

## Next gate

The PlayerTemplate/B04 native-join blocker is closed. Preserve this working state and hashes.

Next research should continue from the now-successful native joined state rather than revisiting the old Reason4 failure. The immediate candidate is observing the downstream GameInfo/local-slot/LivingWorld handoff after the successful P2 Type6 commit, while keeping this PlayerTemplate baseline frozen.
