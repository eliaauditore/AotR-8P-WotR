# OWN_MP 3-Endpoint Transport Proof and START/ACK Next Step

Checkpoint: 2026-08-28

## Runtime result

### BEWIESEN

The project-owned multiplayer transport was run simultaneously across three real Windows endpoints:

```text
Host desktop
  -> room: P3-Test
  -> TCP/UDP port: 42888
  -> TCP: LISTENING
  -> UDP: RESPONDING

VM client
  -> joined successfully as P3-VM
  -> received lobby name and Room ID
  -> TCP OK
  -> UDP OK

Laptop client
  -> joined successfully as BMO
  -> TCP OK
  -> UDP OK

Host final state
  -> Players: 3 / 8
  -> Joined: P3-VM, BMO
```

Observed Room ID for this run:

```text
d6653a0193044612b2c5c3b355f3050a
```

This proves that the current project-owned transport is not limited to a two-endpoint local proof. A physical host, VMware guest, and separate laptop can coexist in the same OWN_MP room through the same host listener.

## Important native WotR lobby correction

The practical two-machine native P3 plan documented earlier cannot be constructed through the current native WotR lobby UI.

Runtime UI observation:

```text
P1 / row 1 = host human
P2 / row 2 = the only row offering Open for a remote human
P3 / row 3 and below = strategic AI choices; Open is not offered
```

Therefore the engine-level finding that the native remote allocator can scan slots 0..7 remains valid, but the native WotR lobby does not expose the required P3=Open state. The blocker is earlier in the native WotR lobby/game-mode path.

The immediate development path therefore returns to the project-owned transport rather than depending on the native WotR lobby to create P3/P4 humans.

## Current proof boundary

### BEWIESEN

- project-owned lobby host/client transport works;
- three simultaneous Windows endpoints work;
- TCP port 42888 works across the tested LAN/VM topology;
- UDP reachability/PING-PONG works;
- host tracks 3/8 participants;
- a shared room identifier is transferred to clients.

### NOT YET PROVEN

- OWN_MP participant -> deterministic strategic slot mapping;
- P3/P4 -> `GameInfo` PlayerType 6 injection/creation;
- P3/P4 local endpoint -> native local-slot resolver;
- P3/P4 -> local `LivingWorldPlayer`;
- strategic command sync/OOS behavior.

## Deterministic START/ACK barrier PoC

New research tool:

```text
tools/research/AOTR_OWN_MP_START_ACK_POC.ps1
```

The PoC intentionally performs no game-memory writes and no AotR launch. It is the next network-layer proof only.

Current test topology is explicit:

```text
P1 = HOST
P2 = AI (reserved)
P3 = VM client
P4 = laptop client
```

Clients request their strategic slot in the JOIN frame, so assignment does not depend on join order.

Protocol v1:

```text
Client -> Host
A8P_JOIN|1|<name>|<build>|<requestedSlot>

Host -> Client
A8P_ACCEPT|1|<roomId>|<lobby>|<assignedSlot>|<build>

Host -> all clients
A8P_START|1|<roomId>|<nonce>|<slotMap>

Client -> Host
A8P_START_ACK|1|<roomId>|<nonce>|<slot>|<name>|<build>

Host -> all clients after every valid ACK
A8P_START_COMMIT|1|<roomId>|<nonce>
```

If any expected ACK is missing or invalid, the host emits an abort rather than committing the barrier.

## Expected three-endpoint proof

Host:

```text
-Mode Host -ExpectedClients 2
```

VM:

```text
-Mode Client -PlayerName P3-VM -RequestedSlot 3
```

Laptop:

```text
-Mode Client -PlayerName BMO -RequestedSlot 4
```

Success requires the host to print:

```text
SLOT MAP: P1=HOST;P2=AI;P3=P3-VM;P4=BMO
ACK OK: P3 P3-VM
ACK OK: P4 BMO
START/ACK BARRIER: PASS
ACKs: 2/2
```

and both clients to print `START/ACK CLIENT: PASS` for their assigned strategic slot.

Only after this barrier is proven should the PoC gain a game-launch/runtime bridge. The next bridge target is to carry this canonical slot map into the existing `GameInfo` / local-slot / LivingWorld observer chain without modifying the release `game.dat` on disk.
