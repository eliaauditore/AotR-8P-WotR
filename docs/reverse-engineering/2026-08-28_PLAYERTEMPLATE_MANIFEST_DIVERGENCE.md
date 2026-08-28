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

The two PlayerTemplate copies are internally identical on each machine, but Host and VM differ from one another.

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

## Classification

### BEWIESEN by manifest comparison

- Among every file present on the VM, only three shared paths differ from Host.
- The only differing shared game-data file is `playertemplate.ini`, present in two mirrored locations.
- Host and VM therefore do not have identical AotR data despite matching `game.dat` SHA-256.

### STARKER HINWEIS / near-closure

The runtime divergence and the manifest divergence both point to PlayerTemplate data. Exact textual diff of the two `playertemplate.ini` files is the remaining direct confirmation step before treating this file mismatch as the concrete source of Component-A/B04 divergence.

## Next gate

Compare the Host and VM `playertemplate.ini` contents directly, especially the block containing `StartingUnit*`, `StartingUnitOffset*`, `PvPModePing`, and `Dove_white_in_game`. If the runtime lines map exactly to the differing file text, synchronize the VM file to the Host/reference build, rerun the B04 component snapshot, and then retry the native ID3 join.
