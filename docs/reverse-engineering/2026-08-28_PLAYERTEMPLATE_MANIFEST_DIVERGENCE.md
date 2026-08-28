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

Both active/source VM copies are therefore byte-identical to Host for this file.

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

Before this file correction, runtime had already proven component B equal while component A differed between Host and VM. After changing only the proven PlayerTemplate delta, component A now equals Host and therefore B04 equals Host as well.

## Classification

### BEWIESEN

- Among every file present on the VM, only three shared paths differed from Host in the captured manifests.
- The only differing shared game-data file was `playertemplate.ini`, present in two mirrored locations.
- The complete byte delta inside `playertemplate.ini` is exactly 22 semicolons.
- Those semicolons comment out `StartingUnit3 = PvPModePing` and its zero offset in 11 PlayerTemplate blocks on VM while Host has them active.
- Removing only those 22 semicolons produces the exact Host file length and SHA-256.
- Both VM PlayerTemplate copies are now byte-identical to Host.
- Before correction, component B matched while component A differed between Host and VM.
- After changing only PlayerTemplate, Host and VM have identical component A, component B, B04, B38 and associated component-B object state.
- Therefore this A/B experiment closes the causal links `playertemplate.ini mismatch -> Component-A mismatch -> B04 mismatch` for the tested state.

### STARKER HINWEIS

The exact file delta explains the previously observed serializer sequence shift: Host serializes `StartingUnit3/PvPModePing` where the old VM file skipped those commented directives and reached later `StartingUnit*` entries first.

The remaining leading chain is now narrowed to:

`PlayerTemplate mismatch -> Component-A mismatch -> B04 mismatch` **BEWIESEN**, followed by `B04 mismatch -> PATH_C Reason4 reject` still requiring the controlled native join rerun.

### HYPOTHESE still to test

- With B04 now matching, the prior PATH_C Reason4 reject will disappear.
- If the join still fails, either a different PATH_C predicate fires or a later validation/state transition remains divergent.

## Next gate

1. Keep all files unchanged.
2. Perform exactly one controlled native ID3 join from VM using the existing `AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1`.
3. Observe whether Host returns the prior ID5/Reason4 failure or reaches the ID4 success/Type6 slot-commit path.
4. Record `session+0x44`, slot mutation, direct response class and, if needed, the PATH_C branch reached.
5. If Reason4 disappears but another failure remains, investigate only that next branch.
