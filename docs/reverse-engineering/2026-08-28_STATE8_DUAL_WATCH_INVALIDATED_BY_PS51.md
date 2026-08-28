# State-8 dual-watch no-hit invalidated by pre-call PS5.1 failure

Date: 2026-08-28

The simultaneous runtime watcher on `0x008496C2` and `0x0084944F` reported no hits, but the paired native join PoC failed before its temporary code page was allocated.

The failure occurred at the PowerShell-side `UIntPtr` conversion used for `VirtualAllocEx`, so `session->vtable+0x40` was never invoked. Consequently:

- `CALLBACK_8496C2_HIT=NO` is non-diagnostic for this run.
- `COMPLETION_84944F_HIT=NO` is non-diagnostic for this run.
- `session+0x44` remaining NULL is expected because the join call never executed.
- `DE892C` remaining NULL is likewise expected.

Do not use this trace to reject the State-8 frontend-completion hypothesis.

Repeat the same dual watcher only after the PS5.1-compatible native join wrapper successfully reaches `NATIVE +0x40 CALL RETURNED = YES` / a valid post-call native observation.
