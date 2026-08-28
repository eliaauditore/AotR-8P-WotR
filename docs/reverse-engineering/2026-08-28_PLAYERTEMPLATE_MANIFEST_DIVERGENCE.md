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

The VM source-path file:

`C:\AgeoftheRing\aotr\data\ini\playertemplate.ini`

was patched by removing only the 22 proven comment characters.

Post-patch evidence:

- length: `33,211`
- SHA-256: `2D162EE705DE9D96A7B65140C22EBA6EBD0B8F155AE062C97F9884E37DC59F4D`

This proves that this VM copy is now byte-identical to Host.

The mirrored VM runtime-path copy under `_AOTR_8P_WOTR_RUNTIME\data\ini\playertemplate.ini` must still be re-hashed before the runtime A/B test. Do not claim complete runtime synchronization until the actually loaded copy/copies are confirmed identical.

## Classification

### BEWIESEN

- Among every file present on the VM, only three shared paths differed from Host in the captured manifests.
- The only differing shared game-data file was `playertemplate.ini`, present in two mirrored locations.
- The complete byte delta inside `playertemplate.ini` is exactly 22 semicolons.
- Those semicolons comment out `StartingUnit3 = PvPModePing` and its zero offset in 11 PlayerTemplate blocks on VM while Host has them active.
- Removing only those 22 semicolons produces the exact Host file length and SHA-256.
- The VM `aotr\data\ini\playertemplate.ini` source-path copy has now been patched to the exact Host SHA-256.

### STARKER HINWEIS

The exact file delta explains the previously observed serializer sequence shift: Host serializes `StartingUnit3/PvPModePing` where VM skips those commented directives and reaches later `StartingUnit*` entries first.

This makes `playertemplate.ini mismatch -> Component-A mismatch -> B04 mismatch -> PATH_C Reason4` the leading causal chain, but the lower links remain unproven until the controlled rerun.

### HYPOTHESE still to test

- Correcting the actually loaded VM PlayerTemplate copy/copies will make Component-A match Host.
- Matching Component-A will make B04 match.
- Matching B04 will remove the prior `PATH_C Reason4` reject.

## Next gate

1. Hash both VM PlayerTemplate locations after the source-path patch.
2. Ensure the actually loaded runtime copy is the Host SHA-256 without changing any unrelated file.
3. Rerun the same Component-A/B04 capture.
4. Retry the native ID3 join.
5. Record whether `PATH_C Reason4` disappears or persists.
