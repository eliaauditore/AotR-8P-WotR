# State8 entry breakpoint: exact bytes and RF-safe rerun requirement

Date: 2026-08-30

## Scope

This checkpoint reconciles the apparent register contradiction in the State8-before-native-join run and classifies a debugger-observer defect in `AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V5.ps1`.

## Runtime evidence from the affected run

Read-only extraction from `STATE8_PREJOIN_WATCH_20260830_222030_916.out.txt` reported:

- expected frontend owner: `0x0994D8F0`
- callback-entry events at `0x008496C2`: 2554
- completion-entry events at `0x0084944F`: 0
- every callback event had `ECX = 0x0994D8F0`
- callback-entry raw `ESI = 0x09AFD6A0`
- every callback snapshot read `owner+0x6A4 = 8`
- every callback snapshot read `owner+0x304 = 1`
- `session+0x44 = 0x09BA9638`
- current vtable `0x00C54B78`
- `DE892C = 0`
- native `session->vtable+0x40` returned successfully

The raw `ESI != owner` observation initially appeared to contradict the earlier static model.

## Exact canonical game.dat bytes — BEWIESEN static

Canonical image SHA256:

`CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC`

The PS5.1 pure-disk probe re-read the exact bytes:

```asm
0x008496C2  56                         push esi
0x008496C3  8B F1                      mov  esi,ecx
0x008496C5  83 BE A4 06 00 00 08       cmp  dword ptr [esi+0x6A4],8
0x008496CC  75 3D                      jne  0x0084970B
0x008496CE  E8 7C FD FF FF             call 0x0084944F
...
0x008496F5  C7 86 A4 06 00 00 09 ...  mov  dword ptr [esi+0x6A4],9
0x00849701  C7 86 A4 06 00 00 01 ...  mov  dword ptr [esi+0x6A4],1
0x0084970B  5E                         pop esi
0x0084970C  C3                         ret
```

Therefore the original static control-flow classification was correct:

1. function entry receives frontend owner in `ECX`;
2. entry saves caller `ESI`;
3. `mov esi,ecx` establishes owner in `ESI`;
4. State8 is checked at `owner+0x6A4`;
5. State8 passes to `call 0x84944F`;
6. success writes State9; failure path writes State1.

## Register contradiction resolved — BEWIESEN

The hardware execution breakpoint is placed at `0x8496C2`, the first instruction of the function.

A debugger snapshot at that EIP occurs before the watched instruction has executed. Consequently the raw register state at the entry trap is expected to be:

- `ECX = frontendOwner`
- `ESI = caller's pre-entry ESI`

Only after resuming does `0x8496C3: mov esi,ecx` make `ESI` equal to the owner used by the guard.

Therefore `ESI != owner` in the entry snapshots does **not** invalidate the State8 guard model.

## V5 watcher defect — BEWIESEN tooling fact

The V5 single-step handler reads DR6, logs DR0/DR1 hits, then calls a helper that only does:

```csharp
c.Dr6 = 0;
SetThreadContext(...);
```

V5 does not set x86 `EFLAGS.RF` before `ContinueDebugEvent`.

Because DR0 is an execution breakpoint at the current EIP, this creates a serious observer-interference risk: the watched instruction may be eligible to trap again instead of progressing through `push esi ; mov esi,ecx ; cmp ... ; call 0x84944F`.

The affected State8 run produced 2554 entry hits in roughly 1.1 seconds while never observing the statically unavoidable completion call despite State8 being 8 in every suspended snapshot. This pattern is consistent with an entry retrigger storm.

## Classification of the affected causal result

### Still valid

- native `session->vtable+0x40` returned successfully;
- backend/session current became a C54B78 GameInfo;
- the function entry at `0x8496C2` was reached with `ECX = proven frontend owner`;
- owner State8 was present in the suspended snapshots;
- canonical static State8 -> completion control flow is proven.

### Invalidated pending RF-safe rerun

The following must **not** be used as a negative proof from this run:

- `COMPLETION_84944F_HIT = NO`
- `DE892C stayed NULL` as evidence that State8-before-join is insufficient
- the callback hit count as a semantic call-frequency measurement

The watcher itself may have prevented the frontend thread from executing beyond the entry breakpoint.

## Corrective tooling

New watcher:

`tools/research/AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V6_RF.ps1`

V6:

- preserves DR0 `0x8496C2` and DR1 `0x84944F`;
- clears DR6 on a hardware hit;
- sets `EFLAGS.RF = 1` before continue;
- reads owner state through canonical `[0x00DE8D90]`, not a raw register assumption;
- logs raw ECX/ESI separately;
- has a 32-bit CompileOnly layout selftest;
- has a CompileOnly RF resume-policy selftest;
- does not patch game-memory bytes or call a game function.

RF-safe orchestrator:

`tools/research/AOTR_WOTR_STATE8_PREJOIN_NATIVE_JOIN_ORCHESTRATOR_V4_RF_FIX.ps1`

The V4 bootstrap CompileOnly-tests V6 before it allows the controlled runtime experiment to begin.

## Next gate

Use a **fresh game process** and reproduce the same one-variable ordering:

`owner+0x6A4: 1 -> 8` immediately before native `session->vtable+0x40`.

The decisive expected RF-safe sequence is:

```text
DR0 0x8496C2 entry
  ECX == frontend owner
  owner+0x6A4 == 8
  RF acknowledgement succeeds
then DR1 0x84944F
then native publisher path
then DE892C == session+0x44
then owner+0x6A4 == 9
```

If V6 instead progresses past DR0 but still never reaches DR1, the next investigation must identify a real state transition/race between entry and `cmp`; do not infer that from V5.
