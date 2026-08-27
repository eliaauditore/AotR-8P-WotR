# P3 CustomMatch State 14 -> Native Game Bootstrap

Checkpoint: 2026-08-27

Scope: current AotR `game.dat` static analysis, focused on the final CustomMatch/connection transition immediately before native game/LivingWorld setup. This extends:

- `2026-08-27_P3_P8_LOBBY_BIG_ANALYSIS.md`
- `2026-08-27_P3_NATIVE_NETWORK_TO_LIVINGWORLD_PATH.md`

The purpose of this checkpoint is to determine whether a P3-specific or 2-human-only boundary still exists between StartGame validation and the already reconstructed GameInfo -> LivingWorldPlayer/local-player path.

## Binary baseline

Current AotR engine:

- size: `11,347,456`
- SHA256: `CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC`
- ImageBase: `0x00400000`
- relocations stripped / no dynamic-base relocation path

EA comparison:

- `game820.dat`
- SHA256: `BCF4C85EC72ECB9EB95A844FC0072434FDCEF49A5B2C59ABB77AC04AF29C277E`

## Executive conclusion

### BEWIESEN

No P1/P2-only restriction was found in the final native CustomMatch start path.

The currently reconstructed path is:

```text
MpGameSetup / OnlineStrategic PlayGame
    -> CustomMatch state 7
    -> StartGame validator 0x8431B8
       -> scans slots 0..7
       -> humanPlayers increments only for PlayerType 6
       -> WOTRMP requires humanPlayers > 1
    -> optional 6-second countdown / connecting screen
    -> validator second pass
    -> CustomMatch vfunc +0x48
       -> 0x9AB3A9
       -> CustomMatch state = 14
    -> CustomMatch update 0x9AFA30 / state 14
       -> connection/event processing
       -> final bootstrap variant A or B
    -> both variants scan slots 0..7 and process Type-6 players
    -> native GameInfo/network bootstrap
    -> previously proven GameInfo local-slot resolution 0..7
    -> LivingWorld setup 0..7
    -> local P3 LivingWorldPlayer -> TheLivingWorldLogic + 0x98
```

A runtime 3-PC test is still required. Static analysis now gives no justification for adding a speculative P3 patch before that test.

---

## 1. StartGame validator counts real network humans over all eight slots

### BEWIESEN

Validator:

- VA `0x008431B8`
- RVA `0x004431B8`

Inside the per-slot loop, the total participating-player count is incremented and then the human count is incremented only when `0x8009A7` reports `PlayerType == 6`.

Relevant VA:

- `0x008433F2` onward

Bytes:

```text
FF 45 E4
8B CF
E8 AB D5 FB FF
84 C0
74 03
FF 45 E0
```

Semantics:

```text
totalPlayers++
if PlayerInfo::isNetworkHuman() // exact predicate: type == 6
    humanPlayers++
```

The surrounding slot loop runs to `8`.

---

## 2. WOTRMP requires at least two humans, not at most two

### BEWIESEN

Relevant validator site:

- VA `0x008434C2`

Bytes:

```text
F6 86 A4 03 00 00 10
75 04
3A D3
74 49
83 7D E0 01
7F 43
```

The `0x10` bit is the previously identified `WOTRMP` mode flag.

The critical count check is:

```asm
cmp [humanPlayers], 1
jg  success
```

So WotR multiplayer requires:

```text
humanPlayers > 1
```

No maximum of two humans exists here.

The failure localization string used by this branch is:

```text
GUI:NeedHumanPlayers
```

---

## 3. Final validator success calls CustomMatch vfunc +0x48

### BEWIESEN

After the second validator pass / NAT-ready path, the code calls the CustomMatch interface with the human-player count and a true/start flag.

Relevant site:

- VA `0x00843874`

Bytes:

```text
FF 75 E0
8B 4E 58
88 9E C4 02 00 00
8B 01
6A 01
FF 50 48
```

The pointer used here resolves to the CustomMatch subobject whose vtable is `0x00C88A58`.

That vtable is installed in the CustomMatch constructor at:

- VA `0x009AF477`

```asm
mov dword ptr [parent+0x60], 0x00C88A58
```

Vtable entry `+0x48` is:

```text
0x009AB3A9
```

---

## 4. `0x9AB3A9` transitions CustomMatch to state 14

### BEWIESEN

Function:

- VA `0x009AB3A9`

Because the function receives the CustomMatch subobject at `parent + 0x60`, this write:

```asm
mov dword ptr [esi+0x428], 0x0E
```

corresponds to:

```text
parent + 0x488 = 14
```

which is the same state field read by the CustomMatch update routine `0x9AFA30`.

When the start flag is true, this function also builds/posts an internal event whose type field is `0x0F`.

The exact source-level event name remains unassigned; it is therefore not labeled more strongly here.

---

## 5. State 14 is handled inside the normal CustomMatch update state machine

### BEWIESEN

CustomMatch update:

- VA `0x009AFA30`

State storage:

```text
CustomMatch + 0x488
```

The `>7` branch reduces the state value until the final branch corresponding to state `14` enters at:

- VA `0x009AFB71`

State 14 then uses the active GameInfo/network globals and performs connection/event processing through network virtuals including:

```text
+0x160
+0x164
+0x174
```

There is no player-index cutoff of two in this state.

---

## 6. State 14 dispatches into two final bootstrap variants

### BEWIESEN

After the connection/event work, State 14 inspects the active GameInfo field at `+0x5C`:

```asm
cmp dword ptr [ecx+0x5C], 1
jne variant_B
call 0x903887
...
variant_B:
call 0x904498
```

Relevant site:

- VA `0x009AFC47`

Bytes:

```text
83 79 5C 01
75 0A
E8 35 3C F5 FF
E9 86 01 00 00
E8 3C 48 F5 FF
```

Bootstrap variants:

```text
A: 0x00903887
B: 0x00904498
```

### Important naming rule

The exact source-level semantic name of `GameInfo + 0x5C` is **not yet proven**. Therefore this checkpoint does not claim that the branch means LAN/Online, host/client, load/new-game, or another specific distinction.

---

## 7. Both final bootstrap variants explicitly scan all eight slots

### BEWIESEN

Variant A:

- VA `0x00903887`

Variant B:

- VA `0x00904498`

Both begin with the same semantic structure:

```text
GameInfo + 0x11 = 1
index = 0
while index < 8:
    player = GameInfo[index]
    if player is PlayerType 6:
        process its network/peer state
    index++
```

The Type-6 predicate is again `0x8009A7`.

Variant A loop terminator:

```asm
inc [index]
cmp [index], 8
jl  loop
```

Variant B has the same `index < 8` limit.

This is direct evidence that P3/slot 2 enters the same final bootstrap machinery as P1/P2.

---

## 8. The final bootstrap uses the real network endpoint / GameInfo data

### BEWIESEN

Both variants copy/use the GameInfo network identity fields:

```text
GameInfo + 0x38
GameInfo + 0x3C
```

and call into the network/session/bootstrap objects before attaching the active GameInfo to the next game layer.

This is the same endpoint data already proven to identify the local P3 client in the local-slot resolver.

---

## 9. Transfer/bootstrap helper also handles additional Type-6 slots

### BEWIESEN

Variant B calls helper:

- VA `0x0084FD2E`

The helper starts at player index `1` and continues while:

```asm
cmp ebx, 8
jl  loop
```

For every entry it resolves `GameInfo[index]`, checks `PlayerType == 6`, and builds a bitmask for network players requiring the transfer/synchronization operation.

Therefore the helper includes:

```text
P2 / slot 1
P3 / slot 2
P4 / slot 3
...
P8 / slot 7
```

It does not stop after P2.

Its later branches process transfer feature bits in the GameInfo structure; these code paths are associated with the same subsystem that emits:

```text
GUI:CouldNotTransferHero
GUI:CouldNotTransferMap
```

The exact source-level names of every individual transfer helper remain unassigned.

---

## 10. Failure strings confirm this is final game/bootstrap transfer logic

### BEWIESEN

The two bootstrap functions contain the failure localizations:

```text
GUI:CouldNotTransferHero
GUI:CouldNotTransferMap
GUI:Error
```

Variant A contains the hero-transfer failure path.

Variant B contains both hero-transfer and map-transfer failure paths.

This is strong contextual evidence that State 14 has already left ordinary lobby editing and is performing the final multiplayer game-data/bootstrap transfer.

---

## 11. Correction: `0x917A47` is `AptMessenger::CloseScreen`

### BEWIESEN

Earlier provisional notes treated `0x917A47` too strongly as a game-start controller.

Registration code at `0x91883F` binds the string:

```text
AptMessenger::CloseScreen
```

to function pointer:

```text
0x917A47
```

Therefore the countdown path calling `0x917A47` first closes the Messenger/overlay screen. It is not by itself the native game-start transition.

This correction is important because the actual transition is the validator -> CustomMatch state 14 path documented above.

---

## 12. Cross-binary evidence

### BEWIESEN

The following regions are byte-identical between current AotR `game.dat` and EA `game820.dat`:

| Region | Result |
| --- | --- |
| State-14 core `0x9AFB71..0x9AFC61` | identical |
| bootstrap A `0x903887..0x903AC0` | identical |
| bootstrap B `0x904498..0x904802` | identical |
| transfer helper `0x84FD2E..0x84FF42` | identical |

So these 8-slot behaviors are inherited from the EA engine and are not AotR-specific additions.

---

# Current P3 static proof chain

Combining the three checkpoints now gives:

```text
OnlineStrategic / MpGameSetup row ~2
    -> native JoinGame / type 6
    -> 8-slot staging serialization
    -> GameInfo PlayerInfo[2]
    -> StartGame validator scans 0..7
    -> humanPlayers includes P3
    -> WOTRMP only requires >1 human
    -> state 14
    -> final bootstrap scans 0..7
    -> transfer helpers include slot 2
    -> active GameInfo survives into game setup
    -> local-slot finder scans 0..7 and matches endpoint
    -> PC3 localSlotIndex = 2
    -> LivingWorld setup scans 0..7
    -> isLocal=true for slot 2
    -> create P3 LivingWorldPlayer
    -> set TheLivingWorldLogic + 0x98 to P3
```

## Current classification

### BEWIESEN

The native static engine path is capable of carrying a third real network human through the known lobby, validator, connection, bootstrap, GameInfo, and local LivingWorld player-selection layers.

### NOT YET PROVEN

A real 3-PC WotR session remains necessary to prove:

- all three clients reach the same strategic state at runtime;
- PC3 actually receives `localSlotIndex = 2` in a live session;
- `TheLivingWorldLogic + 0x98` becomes non-null on PC3 and refers to its local LivingWorldPlayer;
- no OOS/authority failure occurs immediately after LivingWorld start;
- native strategic commands from P3 remain synchronized.

---

# Runtime observer

A read-only observer has been added at:

```text
tools/research/AOTR_P3_NATIVE_OBSERVER.ps1
```

It performs **no memory writes**.

It verifies the exact `game.dat` SHA256 before using static offsets and records:

```text
runtime byte RVA 0x00440A91
runtime byte RVA 0x0044692B
GameInfo pointer
GameInfo slot pointers 0..7
PlayerType per slot
network endpoint per Type-6 slot
local GameInfo endpoint
calculated localSlot
TheLivingWorldLogic pointer
LivingWorld player vector +0x8C/+0x90
current local LivingWorldPlayer +0x98
current LivingWorldPlayer unique ID +0x14
```

## Expected 3-PC proof

On PC1:

```text
LocalSlot = 0
```

On PC2:

```text
LocalSlot = 1
```

On PC3:

```text
LocalSlot = 2
```

All clients should show slots 0, 1 and 2 as `Type 6` with distinct network endpoints, and after LivingWorld setup each client should receive a non-null local/current LivingWorldPlayer.

If PC3 reaches `LocalSlot=2` but fails before `TheLivingWorldLogic+0x98` is populated, the remaining fault is after GameInfo identity resolution.

If PC3 reaches a valid `+0x98` and the session then OOSes, the remaining research target moves decisively to strategic synchronization/authority rather than player-count or LocalStrategicPlayer assignment.
