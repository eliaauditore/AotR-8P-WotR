# Astra Medium LivingWorld dependency V2 follow-up

Checkpoint: 2026-09-08

Scope: read-only analysis of the canonical static windows exported from `game.dat`. No game execution, debugger attach, process access, runtime mutation, binary patching, build, or external tooling was used.

## Result

`SMALL_ADAPTER_GATE=STILL_INCONCLUSIVE`

`DIRECT_NETWORK_STACK_DEPENDENCY=NOT_PROVEN`

The small-adapter hypothesis became stronger, but complete dependency closure is not yet available.

## Newly resolved points

### 0x00610A21 — bounded local mode predicate

**BEWIESEN static**

The helper is complete and returns exactly whether:

```text
this+0x114 == 1 OR this+0x114 == 2
```

It performs no calls and accesses no other object.

Combined with the prior `0x00932EB8` window, the GameInfo-selection rule is:

```text
setupThis+0x58 != 0          -> alternate record-array path
otherwise mode == 1 or 2    -> [DE892C]
otherwise mode == 3         -> alternate record-array path
otherwise                   -> [DE8930]
```

where `mode = dword[[DE412C]+0x114]`.

### 0x006B897F — LivingWorld player-collection reset

**BEWIESEN static**

The complete body ends at `0x006B89D3` and:

- iterates the LivingWorld player vector at `+0x8C/+0x90`;
- invokes each non-null player's first virtual method with argument `0`;
- passes the returned value, or zero for a null entry, to `0x0042F6A0`;
- calls `0x005FF9D3` with the vector and its begin/end pointers;
- clears `LivingWorld+0x98`.

This is strongly consistent with player destruction / collection cleanup. No peer-list or transport semantics are established by the visible body.

### 0x00933140 continuation — alternate construction + fallback

**BEWIESEN static**

The alternate path consumes records from `setupThis+0x30/+0x34` with stride `0x28`, then calls `0x006BB3B5` with a record pointer, complementary boolean flags, and `ARG4=NULL`.

After normal loop completion, helper `0x006B42CA` selects the vector's first player when the vector is non-empty and `LivingWorld+0x98` is still null.

Important correction: the selected-GameInfo null branch targets `0x00933176`, entering the epilogue and skipping this fallback.

Therefore a non-null `LivingWorld+0x98` alone is not proof that native endpoint-based local-slot resolution selected the intended P3/P4 player.

### 0x006BB4D0 continuation — factory completion

**BEWIESEN static**

If `dword[[DE412C]+0x114] != 3`, the newly constructed player receives a call to `0x006E48C2`. The factory then derives either `savedLivingWorldReceiver+0x18` or null and passes that pointer to `0x004822AD` with receiver `newPlayer+0x04`. It returns with `ret 0x10`.

Neither helper has yet been proven to require transport state.

### 0x006B4380 continuation — local-player setter completion

**BEWIESEN static**

The continuation operates on a stack temporary derived from the selected player's object chain and calls:

- `0x006DA95E`
- `0x006DA774`
- virtual `+0x64` on `[0x00DE42FC]`
- `0x006DABCB`

The identity and contract of the global virtual service remain unresolved.

## Current classification

For the five requested targets:

- Category A: 0
- Category B: 1
- Category C: 0
- Category D: 4

No supplied window establishes mandatory socket, packet, peer-list, transfer, remote-peer transport, or connection-processing work in the direct LivingWorld consumer path.

That absence is not yet proof that all unresolved callees are transport-free.

## First blocking helper

The first unconditional unresolved helper in the current dependency chain is:

```text
0x005FF9D3
```

It is called from `0x006B897F` with the LivingWorld vector and its begin/end pointers.

The exact next static probe is intentionally minimal: export only `0x005FF9D3..0x005FF9E3` (end exclusive) to recover the first instructions and determine the minimum next range without guessing a function extent.

Do not resume runtime territory/start testing or add native join lifecycle calls before this static dependency gate is classified.
