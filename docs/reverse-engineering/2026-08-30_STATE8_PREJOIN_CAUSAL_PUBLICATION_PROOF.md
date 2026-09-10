# State8-before-native-join causal frontend publication proof — 2026-08-30

## Status

**BEWIESEN runtime (causal A/B under the tested native-join conditions):** setting only `frontendOwner+0x6A4` from `1` to `8` immediately before the already-proven native `session->vtable+0x40` join changes the low-level join outcome from backend-only (`session+0x44=C54B78`, `DE892C=NULL`, owner state `1`) to the normal frontend-published shape (`session+0x44=C54B78`, `DE892C==session+0x44`, owner state `9`).

This closes the practical frontend handoff blocker for the low-level native join PoC.

## Successful RF-safe rerun

Game PID: `8920`

Canonical `game.dat`:

- path: `C:\AgeoftheRing\rotwk\game.dat`
- SHA256: `CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC`

Fresh precondition:

- `[DE8D90] = 0x0994D8F0` (frontend owner)
- `owner+0x6A4 = 1`
- `owner+0x304 = 1`
- session `0x09AFD6A0`, vtable `0x00C54CE0`
- `session+0x44 = NULL`
- `DE892C = NULL`

Controlled mutation contract:

- exactly one authorized game-state write before join: `owner+0x6A4: 1 -> 8`
- no write to `DE892C`, `DE8930`, session current, GameInfo rows, or PlayerInfo

Native join result:

- native `+0x40` returned
- `session+0x44 = 0x09BA9638`
- current vtable `0x00C54B78`
- `DE892C = 0x09BA9638`
- P1 Type6 endpoint `192.168.0.224:8086`
- P2 Type6 endpoint `192.168.0.57:8086` (local VM)
- P3-P8 Type1
- `owner+0x6A4 = 9`
- `owner+0x304 = 1`

Therefore:

`DE892C == session+0x44 == 0x09BA9638` and the owner state advanced to `9` without any direct publication write by the experiment.

## A/B comparison

Earlier valid low-level native join without frontend State8 preparation:

- native `+0x40` returned
- current became C54B78
- `DE892C` stayed NULL
- owner state observed as `1`

State8-before-join run:

- same native join primitive
- same canonical runtime
- only controlled lifecycle change: owner state `1 -> 8` immediately before `+0x40`
- current became C54B78
- `DE892C` became exactly current
- owner state became `9`

**Conclusion:** State8 preparation is sufficient to restore the missing native frontend publication lifecycle in the tested low-level join path.

## Exact static control flow already revalidated

Canonical bytes around the state-8 handler are:

```asm
0x008496C2  push esi
0x008496C3  mov  esi,ecx
0x008496C5  cmp  dword ptr [esi+0x6A4],8
0x008496CC  jne  0x0084970B
0x008496CE  call 0x0084944F
...
0x008496F5  mov  dword ptr [esi+0x6A4],9
```

This is consistent with the successful runtime end state, but the exact `0x8496C2`/`0x84944F` execution was **not captured by the V6 hardware watcher** in this rerun. Do not overclaim the breakpoint observation.

## Watcher note

V5 was invalid for negative control-flow conclusions because it cleared DR6 without setting EFLAGS.RF on execution-breakpoint hits and produced a 2,554-hit entry retrigger pattern.

V6 added RF-safe resume semantics and passed its compile-only layout/resume-policy selftest, but reported zero runtime hits despite the successful publication/state9 outcome. Therefore the watcher remains a tooling/debugger instrumentation question, not a blocker for the causal A/B proof above.

The automatic orchestrator verdict `JOIN_RETURNED_NO_CALLBACK` refers only to missing watcher hits and must **not** be interpreted as a failed native frontend handoff.

## Next gate

Do not repeat the same State8/native-join experiment.

Next steps:

1. preserve/inspect the successful client frontend state;
2. confirm the visible joined/Ready UI path (or equivalent frontend state) before pressing Start;
3. then resume the paused local-slot/LivingWorld proof using the native-published GameInfo;
4. only after that move into Ready/start barrier and strategic control phases.
