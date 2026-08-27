# P3 Native Network -> LivingWorld / LocalStrategicPlayer Path

Checkpoint: 2026-08-27

Scope: static analysis of the current AotR `game.dat` and comparison against EA `game820.dat`, following the first additional real WotR network human (P3 / slot index 2) from shared GameInfo/network serialization into `LivingWorldPlayer` creation and `TheLivingWorldLogic + 0x98`.

This document extends `2026-08-27_P3_P8_LOBBY_BIG_ANALYSIS.md`.

## Binary baseline

Current AotR binary:

- file: `game.dat`
- size: `11,347,456` bytes
- SHA256: `CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC`
- PE ImageBase: `0x00400000`

EA comparison binary:

- file: `game820.dat`
- size: `11,313,184` bytes
- SHA256: `BCF4C85EC72ECB9EB95A844FC0072434FDCEF49A5B2C59ABB77AC04AF29C277E`

Debug/source-string comparison binary:

- file: `game.other`
- size: `12,204,384` bytes
- SHA256: `1D6B68F6ACA69B3053D98F6B58F6F352E05530E04696AC3136F04CC8752C6790`

Uploaded `game2.dat` is only 36 bytes and is not a PE executable; it is not used as an engine-code comparison source.

For all addresses below, `VA = ImageBase + RVA`. In the main `.text` section of the current binary, raw file offset and RVA are identical.

## Executive conclusion

### BEWIESEN

The native EA path contains no P1/P2-only restriction between network `PlayerInfo` and LivingWorld local-player selection.

For an additional client occupying slot index 2 (P3), the native static path is:

```text
network/staging data for P3
    -> PlayerInfo[2]
       PlayerType = 6
       network endpoint = PlayerInfo + 0x38 / +0x3C
    -> GameInfo contains all eight player records
    -> virtual local-slot resolver scans slots 0..7
    -> P3 endpoint matches this client's local network endpoint
    -> localSlotIndex = 2
    -> LivingWorld setup loops slots 0..7
    -> slotIndex == localSlotIndex
    -> isLocal = true for slot 2
    -> create LivingWorldPlayer for slot 2
    -> append to TheLivingWorldLogic + 0x8C vector
    -> `0x006B42EF(newPlayer)`
    -> TheLivingWorldLogic + 0x98 = P3 LivingWorldPlayer
```

Therefore the native engine's static player/peer/local-strategic mapping supports P3 in the same mechanism as P1/P2.

This is **not yet a runtime 3-PC success proof**. Remaining runtime risk is primarily synchronization/OOS/authority after the transition, not a static two-human mapping limit in this path.

---

## 1. Network Human predicate is exactly `PlayerType == 6`

### BEWIESEN

Function:

- VA `0x008009A7`
- RVA `0x004009A7`

Bytes:

```text
33 C0 83 79 04 06 0F 94 C0 C3
```

Semantics:

```asm
xor eax,eax
cmp dword ptr [ecx+0x04], 6
sete al
ret
```

So the previously identified type 6 is directly testable as the real network-human type.

This exact code is byte-identical in `game.dat` and `game820.dat`.

---

## 2. A type-6 player carries an explicit network identity

### BEWIESEN

Function:

- VA `0x008009FB`
- RVA `0x004009FB`

Relevant bytes begin:

```text
83 79 04 06 75 15 FF 74 24 04 83 C1 38 E8 6F 7F E4 FF ...
```

Semantics:

1. require `PlayerType == 6`;
2. compare the identity stored at `PlayerInfo + 0x38` with the supplied identity;
3. return true only if they match.

Identity comparator:

- VA `0x0064897C`

It compares:

```text
DWORD + 0x00
WORD  + 0x04
```

This is a six-byte endpoint-like identity (network address + port semantics are independently supported by the network code below).

---

## 3. Generic local-slot finder scans all eight slots

### BEWIESEN

Function:

- VA `0x00800B8C`
- RVA `0x00400B8C`

Core behavior:

```text
if GameInfo is not active:
    return -1

for index = 0; index < 8; ++index:
    player = GameInfo[index]
    if player != null
       and player is type 6
       and player.identity == GameInfo.localIdentity:
           return index

return -1
```

The loop limit is explicitly `8`:

```asm
inc edi
cmp edi, 8
jl  0x800B9D
```

`GameInfo[index]` is itself bounded to `[0,8)` by `0x00800B55` / `0x00800B74`.

No P1/P2 special case exists.

This region is byte-identical in `game.dat` and `game820.dat`.

---

## 4. Derived network GameInfo path also scans all eight

### BEWIESEN

Important correction/refinement: the LivingWorld setup calls local-slot resolution virtually through vtable offset `+0x34`. Depending on the active GameInfo-derived class, this can resolve either to the generic `0x800B8C` implementation or to an override.

One relevant override is:

- VA `0x0084A43A`

It performs:

```text
for index = 0; index < 8; ++index:
    player = networkGameInfo[index]
    if player is local network player:
        return index
return -1
```

The per-player local test at `0x0084A3B5`:

1. requires `PlayerType == 6` via `0x8009A7`;
2. asks the network subsystem for the current local endpoint via vtable `+0x100`;
3. compares that endpoint with the player's `+0x38` identity using `0x64897C`;
4. includes a second endpoint comparison with port `+8` as a compatibility/fallback path.

Again the loop limit is explicitly `8`, not `2`.

Thus the virtual dispatch does not create a hidden P1/P2 limit.

---

## 5. Network-derived GameInfo records the local endpoint

### BEWIESEN

In a network GameInfo-derived constructor, after eight player-slot records are initialized, the engine asks the network subsystem for its local endpoint and stores it into the GameInfo identity fields.

Relevant site:

- VA `0x0084AF19`
- RVA `0x0044AF19`

Bytes:

```text
8B 0D 94 43 DE 00
8B 01
FF 90 00 01 00 00
8B 08
89 4E 38
8B 40 04
...
89 46 3C
```

Semantics:

```text
networkSubsystem->vfunc_0x100()
    -> endpoint pointer
GameInfo + 0x38 = endpoint DWORD
GameInfo + 0x3C = endpoint second field
```

A separate caller of the same network method compares the returned DWORD to `0x7F000001`, confirming that this data is network-address related.

The same code is byte-identical in `game820.dat`.

---

## 6. PlayerInfo assignment stores type and endpoint together

### BEWIESEN

Function:

- VA `0x008014F1`
- RVA `0x004014F1`

For requested type `6`:

```asm
cmp eax,6
jne ...
...
mov dword ptr [esi+0x04],6
```

At the end of the assignment, regardless of type-specific display handling, the supplied endpoint is copied into:

```asm
mov ecx,[endpoint]
mov [esi+0x38],ecx
mov eax,[endpoint+4]
mov [esi+0x3C],eax
```

Therefore a real network player's type-6 record and the endpoint later used by local-slot matching are populated in the same PlayerInfo construction/update path.

This function is byte-identical in current AotR and `game820.dat`.

---

## 7. Staging/GameInfo deserialization contains eight complete player records

### BEWIESEN

Deserializer:

- VA `0x0084B0EC`
- RVA `0x0044B0EC`

It constructs a temporary array of eight PlayerInfo records and parses exactly eight entries.

For a network-human record, the parser recognizes entry marker `'P'` (`0x50`). It parses player data including a DWORD and WORD endpoint, then calls the PlayerInfo assignment path with type `6`.

Relevant P-record section:

- VA `0x0084B3AF`
- RVA `0x0044B3AF`

The endpoint is assembled locally and then:

```asm
push endpoint
push player-name/string
push 6
mov ecx, playerInfo
call 0x8014F1
```

The parser then increments to the next temporary PlayerInfo by `0x1B8` bytes and checks:

```asm
cmp [playerIndex], 8
jb  parse_next
```

Relevant loop site:

- VA `0x0084B8CB`
- RVA `0x0044B8CB`

After parsing, another loop copies all eight temporary PlayerInfo objects into the active GameInfo through `0x8016C3`:

```asm
index = 0
...
call 0x8016C3
inc index
add tempPlayer,0x1B8
cmp index,8
jb ...
```

So the native lobby/staging serialization format and its consumer carry eight complete player records, including type-6 network-human endpoint identity.

This entire deserialization region is byte-identical in `game.dat` and `game820.dat`.

---

## 8. GameInfo slot copy accepts indices 0..7

### BEWIESEN

Function:

- VA `0x008016C3`
- RVA `0x004016C3`

It validates:

```asm
index >= 0
index < 8
```

then resolves:

```text
GameInfo.slot[index]
```

and copies the full supplied PlayerInfo into that slot.

There is only an index-0 special handling block for some flags when that entry is type 6; this does not prevent type 6 on indices 1..7.

---

## 9. LivingWorld setup asks GameInfo for the local slot

### BEWIESEN

LivingWorld setup function:

- VA `0x00932EB8`
- RVA `0x00532EB8`

It selects an active GameInfo pointer from the relevant global game/network context, then calls virtual method `+0x34`:

```asm
mov eax,[ecx]
call dword ptr [eax+0x34]
mov [localSlotIndex],eax
```

Relevant VA:

- `0x00932F1F` / call at `0x00932F21`

This is the local-slot index used immediately by the LivingWorld player-build loop.

As described above, known implementations of this virtual method scan all eight slots and match the current client by network identity.

---

## 10. LivingWorld setup loops slots 0..7 and computes `isLocal`

### BEWIESEN

The same function initializes slot index 0 and then, per slot:

```asm
push slotIndex
call 0x800B55             ; PlayerInfo[slotIndex]
...
mov eax,localSlotIndex
cmp slotIndex,eax
sete al
mov [isLocal],al
call 0x8009A7             ; is type-6 network human?
```

Relevant section:

- VA `0x00932F2F` onward

The loop terminates only at 8:

```asm
inc [slotIndex]
cmp [slotIndex],8
jl 0x932F2F
```

Relevant VA:

- `0x009330E2` .. `0x009330E9`

For P3 on its own client:

```text
slotIndex      = 2
localSlotIndex = 2
isLocal        = true
```

No branch distinguishes slots 0/1 from slots 2..7.

---

## 11. `isLocal` is passed directly into LivingWorldPlayer creation

### BEWIESEN

At VA `0x009330A6` the setup code prepares the call to `0x006BB3B5`.

Argument order includes:

```text
ARG1 = player construction record
ARG2 = isLocal
ARG3 = derived human/AI property
ARG4 = source PlayerInfo
```

The `isLocal` value pushed as ARG2 is the exact byte produced by `slotIndex == localSlotIndex` above.

Call:

- VA `0x009330B7`
- target `0x006BB3B5`

This region is byte-identical in current AotR and `game820.dat`.

---

## 12. LivingWorldPlayer creation appends every player and sets +0x98 only for local

### BEWIESEN

Function:

- VA `0x006BB3B5`
- RVA `0x002BB3B5`

It allocates `0x448` bytes and constructs a LivingWorldPlayer via `0x006E3C8B`.

It appends the new player pointer to the LivingWorld player vector:

```asm
mov ecx, TheLivingWorldLogic
add ecx,0x8C
call 0x90BE00
```

Then:

```asm
cmp byte ptr [ARG2_isLocal],0
je not_local
mov ecx,TheLivingWorldLogic
push newLivingWorldPlayer
call 0x6B42EF
```

Relevant VA:

- append: `0x006BB476` .. `0x006BB483`
- `isLocal` check: `0x006BB488`
- setter call: `0x006BB491`

`0x006B42EF` is the already identified EA setter for the current/active `LivingWorldPlayer*` at `TheLivingWorldLogic + 0x98`.

Thus the Lobby/GameInfo local slot is directly responsible for selecting the client's local/current LivingWorldPlayer.

---

## 13. LivingWorld initialization call chain

### STARKER HINWEIS / partially named statically

The player-build routine is called from `0x00933379`, which is reached during LivingWorld initialization through the chain:

```text
0x006BE09E
    -> 0x006B90A7
       -> scenario/player collection path
          -> 0x007B9669
             -> 0x00933379
                -> 0x00932EB8
```

This establishes that the GameInfo-to-LivingWorld player creation occurs as part of the native LivingWorld startup/selection path.

The exact source-level EA function names for every intermediate node are not yet assigned, so this call-chain naming remains conservative.

---

## 14. Cross-binary evidence

### BEWIESEN

The following relevant code regions are byte-identical between current AotR `game.dat` and EA `game820.dat`:

| Region | Current RVA range | Result |
| --- | --- | --- |
| type-6 predicates / generic local-slot logic | `0x004009A7..0x00400C20` | identical |
| PlayerInfo type + endpoint assignment | `0x004014F1..0x0040167E` | identical |
| GameInfo slot copy | `0x004016C3..0x00401718` | identical |
| network GameInfo local endpoint construction | `0x0044AEA1..0x0044AF40` | identical |
| eight-player staging deserializer | `0x0044B0EC..0x0044B9CF` | identical |
| network post-deserialize/local-slot checks | `0x0044BF80..0x0044C160` | identical |
| LivingWorld player construction | `0x002BB3B5..0x002BB4B0` | identical |
| GameInfo -> LivingWorld setup | `0x00532EB8..0x00533180` | identical |
| LivingWorld startup stage | `0x002BE09E..0x002BE15D` | identical |
| CustomMatch state-machine region | `0x005AFA30..0x005AFC20` | identical |
| start-game validator region | `0x004431B8..0x00443900` | identical |
| WOTRMP mode parser | `0x004161F0..0x004162C0` | identical |

This strongly indicates the 8-slot identity/local-player machinery is native EA behavior, not an AotR-added accident.

`game.other` additionally contains original source/debug strings including:

```text
...\GameLogic\System\LivingWorld\LivingWorldLogic.cpp
multiplayerStartIndex
multiplayerIsLocal
livingWorldPlayerID
isScenarioMultiplayer
Player_2_Start
Player_3_Start
...
Player_8_Start
```

These strings are supporting source-level context, not by themselves proof of runtime behavior.

---

## 15. Status of the original P3 research question

### BEWIESEN statically

The following path now has static native support for P3:

```text
P3 network record / slot 2
    -> PlayerType 6
    -> peer endpoint stored in PlayerInfo[2]
    -> eight-player GameInfo serialization/deserialization
    -> local network endpoint matching
    -> localSlotIndex = 2 on PC3
    -> LivingWorld setup iterates slot 2
    -> isLocal = true
    -> LivingWorldPlayer P3 created
    -> TheLivingWorldLogic + 0x98 = P3
```

No fixed `2`, no `slot < 2`, and no P1/P2-only branch was found in this complete identity-to-LivingWorld mapping.

### What is NOT yet proven

A successful real 3-PC WotR match is still required to prove runtime stability.

The remaining risk area is now narrower:

```text
StartGame / countdown / network start handshake
    -> all peers enter the same WOTRMP transition
    -> LivingWorld state creation
    -> strategic command synchronization
    -> no OOS / authority mismatch after P3 begins acting
```

The next runtime research should therefore instrument/verify P3 rather than patch a speculative human-count limit.

---

## 16. Recommended next test

Do **not** patch a new player-count comparison yet.

Use a 3-PC / 3-real-human WotR test with P3 as slot index 2 and observe at minimum:

```text
GameInfo local slot on PC1 = 0
GameInfo local slot on PC2 = 1
GameInfo local slot on PC3 = 2

LivingWorld vector size >= 3
PC1: TheLivingWorldLogic+0x98 -> P1
PC2: TheLivingWorldLogic+0x98 -> P2
PC3: TheLivingWorldLogic+0x98 -> P3
```

Then exercise one native strategic action from P3 (BUILD is ideal because its backend owner-resolution path is already understood) and compare resulting resources/state across all peers.

If an OOS occurs, capture the first divergence point. The static evidence no longer supports treating `max two humans` as the primary hypothesis.
