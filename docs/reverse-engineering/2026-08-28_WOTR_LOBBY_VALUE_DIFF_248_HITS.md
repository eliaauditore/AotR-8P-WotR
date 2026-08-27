# WotR Lobby Live Value Diff — First Result

Checkpoint: 2026-08-28

## Runtime test

Native WotR lobby remained open on the host. The read-only value-diff scanner captured every aligned writable-memory DWORD equal to `3`, then the user changed exactly one visible lobby row from `Soldier` to `Captain`, and the scanner checked the same addresses for value `4`.

Observed baseline:

```text
PID             : 24252
Image           : D:\Games\AotR\AgeoftheRing\rotwk\game.dat
SHA256          : CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC
Expected change : DWORD 3 -> 4
Baseline regions: 607
Baseline bytes  : 655,986,688
Value addresses : 173,535
```

Result:

```text
Transitions 3->4: 248
```

## Classification

### BEWIESEN

- the differential scanner works against the exact supported game.dat hash;
- at least 248 aligned writable-memory DWORDs changed from 3 to 4 during the observation interval;
- the first single forward transition is not selective enough to identify the native lobby field;
- no write target is justified from this result alone.

### Interpretation

The large hit count contains runtime churn and unrelated values that happened to follow the same numeric transition. Many hits occur in repeated/cloned memory contexts, so a one-directional value scan is insufficient.

## Next gate

Use a reverse-confirmed triple-state differential on one row:

```text
A: P3 Soldier  -> DWORD 3
B: P3 Captain  -> DWORD 4
C: P3 Soldier  -> DWORD 3
```

A candidate survives only if the exact same aligned DWORD follows `3 -> 4 -> 3`, with short stability checks in state B and C.

New read-only tool:

```text
tools/research/AOTR_WOTR_LOBBY_TRIPLE_DIFF_V2.ps1
```

If multiple P3 survivors remain, repeat the same test on P4. Structural comparison between the P3 and P4 survivor addresses is the next intended filter.

No `WriteProcessMemory` is used.