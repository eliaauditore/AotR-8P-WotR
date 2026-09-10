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

## Callback-owner extraction

The valid combined log contains 1,708 callback-bound owner records. All 1,708 are identical in the relevant fields:

```text
Owner      = 0x090B6F08
Owner+6A4  = 1
Owner+304  = 1
Current    = C54B78
```

Counts:

```text
OWNER_6A4_EQ_8_COUNT = 0
OWNER_6A4_NE_8_COUNT = 1708
```

Therefore the state gate is directly runtime-observed, not only inferred from static control flow.

## Post-join State-8 sufficiency falsification

A controlled single-DWORD experiment was then run on the same already-low-level-joined process after the valid watcher had detached cleanly.

Preconditions:

- same game PID and canonical `game.dat` hash;
- same proven frontend owner;
- `owner+0x6A4 = 1`;
- `owner+0x304 = 1`;
- `session+0x44 = C54B78`;
- `DE892C = NULL`;
- proven V5 watcher armed and detached cleanly.

Mutation:

```text
owner+0x6A4 : 1 -> 8
```

Observed result:

```text
STATE8_WRITE_API_PASS       : YES
POSTWRITE_STATE_READBACK    : 8
CALLBACK_8496C2_HIT         : NO
COMPLETION_84944F_HIT       : NO
COMPLETION_AT_OWNER_STATE8  : NO
DE892C_EQUALS_CURRENT       : NO
WATCHER_CLEAN_EXIT          : YES
STATE8_SUFFICIENCY_PROVEN   : NO
FAILURE_STATE_RESTORED      : YES
```

The injected state remained at 8 during the observation window and was safely restored to 1 because no publication occurred.

### Classification

**BEWIESEN runtime:** writing State 8 *after* the low-level join has already completed is not sufficient to restart or trigger the callback/completion lifecycle. The callback is therefore not a continuously polling frontend function that can be unlocked after the fact.

This does **not** falsify State 8 as a required pre-join state. The normal frontend sets State 8 immediately before the native `session->+0x40` call, while the valid low-level path never does. The next causal test must therefore reproduce the ordering:

```text
frontendOwner+0x6A4 = 8
    -> immediately session->+0x40
    -> callback 0x8496C2
    -> completion 0x84944F
    -> DE892C=current
```

## Classification

### BEWIESEN — runtime

1. Low-level native join reaches the frontend callback entry `0x8496C2`.
2. All 1,708 callback-bound observations had `frontendOwner+0x6A4 = 1`.
3. The callback path does **not** reach `0x84944F` during this low-level join.
4. Backend/session join completion is therefore insufficient to trigger native frontend publication by itself.
5. `DE892C` stays `NULL` despite valid `C54B78` current GameInfo.
6. Post-join State-8 injection alone does not retrigger the callback lifecycle.

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

Therefore a callback hit at `0x8496C2` with State 1 and no execution of `0x84944F` identifies the `frontendOwner+0x6A4 == 8` state gate as the blocking condition on the low-level path.

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
        -> owner state is 1 on all observed callback hits
        -> state-8 gate does not pass
        -> 0x84944F not executed
        -> DE892C remains NULL

post-join State-8 injection
    already joined/current C54B78
        -> owner+0x6A4 1->8
        -> no new callback occurs
        -> no completion/publication
        -> restore 8->1
```

## Next gate

Do not manually write `DE892C` and do not directly call `0x8467EB`.

Before repeating a fresh join, resolve the frontend owner deterministically in the pre-join browser. A new read-only provenance scanner searches for direct references to the proven live owner pointer, first inside `game.dat` image memory and then across committed readable memory. This must be run on the still-live post-test process before restarting AotR.

Then run the smallest ordered causal test:

```text
watcher READY
-> owner+0x6A4 = 8
-> immediately native session+0x40 join
-> observe callback/completion/publication
```

The next mutation still targets the native frontend state machine, not the publication global.
