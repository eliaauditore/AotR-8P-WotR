# AotR WotR — State-8 callback gate runtime proof (2026-08-28)

## Context

The native low-level join PoC invokes the real session join method (`session->vtable+0x40`, baseline `0x0084CB34`) without using the normal frontend owner join path.

Prior work had already proven:

- the low-level join succeeds at session/backend level;
- `session+0x44` becomes the joined `C54B78` GameInfo;
- `DE892C` remains `NULL`;
- normal UI join later publishes the same current GameInfo through `0x84944F -> 0x8467EB -> 0x846827 (DE892C=current)`;
- normal frontend code sets `frontendOwner+0x6A4 = 8` immediately before the native `session->+0x40` join;
- callback entry `0x008496C2` checks that state and only calls `0x0084944F` when the state is 8.

## Valid dual hardware-exec runtime test

Final combined result:

```text
TOOLING_SELFTEST_PASS     : YES
PREFLIGHT_PASS            : YES
JOIN_RETURNED             : YES
JOIN_STATE_OBSERVED       : YES
CURRENT_C54B78            : YES
DE892C_STAYED_NULL        : YES
WATCHER_CLEAN_EXIT        : YES
TEST_VALID_FOR_STATE8     : YES
CALLBACK_8496C2_HIT       : YES
COMPLETION_84944F_HIT     : NO
```

Additional watcher evidence:

- x86 `DEBUG_EVENT` CLR layout self-test passed (`size=96`, thread handle offset `12`, exception address offset `24`);
- pre-existing threads were hardware-breakpoint armed;
- newly-created threads were armed via the `CREATE_THREAD_DEBUG_EVENT` handle;
- teardown disarmed all remaining threads and detached cleanly;
- callback `0x8496C2` was hit repeatedly;
- completion `0x84944F` was never hit.

## Classification

### BEWIESEN — runtime

1. Low-level native join reaches the frontend callback entry `0x8496C2`.
2. The callback path does **not** reach `0x84944F` during this low-level join.
3. Backend/session join completion is therefore insufficient to trigger native frontend publication by itself.
4. `DE892C` stays `NULL` despite valid `C54B78` current GameInfo.

### BEWIESEN — static control flow

The relevant callback handler is:

```asm
0x8496C2  push esi
           mov  esi,ecx
           cmp  [esi+0x6A4],8
           jne  0x84970B
           call 0x84944F
           ...
```

Therefore a callback hit at `0x8496C2` with no execution of `0x84944F` identifies the `frontendOwner+0x6A4 == 8` state gate as the blocking condition on the low-level path.

## Current model

```text
normal frontend join
    frontendOwner+0x6A4 = 8
        -> session->+0x40
        -> session+0x44 = C54B78
        -> callback 0x8496C2
        -> state==8 passes
        -> 0x84944F
        -> 0x8467EB(current,0)
        -> 0x846827: DE892C=current
        -> frontend lobby handoff

low-level PoC
    session->+0x40 directly
        -> session+0x44 = C54B78
        -> callback 0x8496C2 DOES execute
        -> state-8 gate does not pass
        -> 0x84944F not executed
        -> DE892C remains NULL
```

## Next gate

Do not manually write `DE892C` and do not directly call `0x8467EB`.

Next work should identify and reproduce the smallest native frontend state transition that establishes `frontendOwner+0x6A4 = 8` before the low-level join, then re-run the already validated watcher to confirm:

```text
CALLBACK_8496C2_HIT   = YES
COMPLETION_84944F_HIT = YES
DE892C                 = current C54B78
```

The next mutation should target the native frontend state machine, not the publication global.