# Two-PC P3 Slot Allocation Proof

Checkpoint: 2026-08-27

Scope: current AotR `game.dat`, focused on whether a second real network client can be forced into **P3 / slot index 2** using only two physical machines by occupying P2 with an AI player.

This checkpoint supersedes the earlier practical assumption that a 3-PC setup is required merely to prove the native P3 `LocalStrategicPlayer` path. A 3-human test remains useful for scale testing, but it is **not required** for the narrower P3 slot/local-player proof.

## Binary baseline

- file: `game.dat`
- size: `11,347,456`
- SHA256: `CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC`
- ImageBase: `0x00400000`

---

# Executive conclusion

### BEWIESEN

The native remote-join allocator scans player slots `0..7` and selects the first slot whose `PlayerType` field is exactly `0`.

The engine's PlayerType mapping is:

```text
0 = Open
1 = Closed
2 = Easy AI
3 = Medium AI
4 = Hard AI
5 = Brutal AI
6 = Network Human
```

Therefore this lobby layout:

```text
P1 / slot 0 = Network Human host
P2 / slot 1 = any AI type 2..5
P3 / slot 2 = Open
```

causes the next joining real client to skip slot 1 and select slot 2.

So a two-machine runtime proof is valid:

```text
PC1 -> P1 / slot 0 / Type 6
P2  -> AI / slot 1 / Type 2..5
PC2 -> P3 / slot 2 / Type 6
```

On PC2 the existing read-only observer should then report:

```text
LocalSlot = 2
```

and after LivingWorld creation:

```text
TheLivingWorldLogic + 0x98 != 0
```

for the local P3 LivingWorldPlayer.

---

## 1. PlayerType-to-lobby-role mapping

### BEWIESEN

PlayerInfo assignment function:

- VA `0x008014F1`
- RVA `0x004014F1`

The function writes the requested type into:

```text
PlayerInfo + 0x04
```

and selects the corresponding UI localization.

The exact type/localization mapping in this function is:

| PlayerType | Localization | Meaning |
| ---: | --- | --- |
| `0` | `GUI:Open` | open/free slot |
| `1` | `GUI:Closed` | closed slot |
| `2` | `GUI:EasyAI` | Easy AI |
| `3` | `GUI:MediumAI` | Medium AI |
| `4` | `GUI:HardAI` | Hard AI |
| `5` | `GUI:BrutalAI` | Brutal AI |
| `6` | network-player name path | real network human |

Relevant localization addresses:

```text
0x00C4E60C = GUI:Open
0x00C4E618 = GUI:EasyAI
0x00C4E624 = GUI:MediumAI
0x00C4E634 = GUI:HardAI
0x00C4E640 = GUI:BrutalAI
0x00C4E650 = GUI:Closed
```

The previously identified function at `0x008009DD` also returns true exactly for types `2..5`, independently confirming that these four values form the AI class.

---

## 2. Free-slot predicate is exactly `PlayerType == 0`

### BEWIESEN

Function:

- VA `0x004512D7`
- RVA `0x000512D7`

Bytes:

```text
33 C0
39 41 04
0F 94 C0
C3
```

Semantics:

```asm
xor eax,eax
cmp dword ptr [ecx+0x04],0
sete al
ret
```

Equivalent:

```text
return PlayerInfo.PlayerType == 0
```

This is the predicate used by the remote-join slot search.

Therefore:

```text
Open       / type 0 -> selectable as free
Closed     / type 1 -> not free
Easy AI    / type 2 -> not free
Medium AI  / type 3 -> not free
Hard AI    / type 4 -> not free
Brutal AI  / type 5 -> not free
Human      / type 6 -> not free
```

---

## 3. Remote-join allocator scans slots 0..7

### BEWIESEN

Relevant network/CustomMatch event handler region:

- scan begins around VA `0x009AC921`
- free-slot predicate call at VA `0x009AC934`
- loop terminator at VA `0x009AC941..0x009AC948`

Core behavior:

```text
slotIndex = 0
while slotIndex < 8:
    player = GameInfo[slotIndex]
    if player != null and player.PlayerType == 0:
        found slotIndex
        break
    slotIndex++
```

The actual predicate call is:

```asm
mov ecx, playerInfo
call 0x4512D7
```

and the loop terminates with:

```asm
inc [slotIndex]
cmp [slotIndex],8
jl  scan_next
```

So the allocator is explicitly eight-slot-capable.

---

## 4. The joining network client is then created as Type 6

### BEWIESEN

After a free slot is found, the same event handler creates a temporary PlayerInfo and calls:

- VA `0x009ACA4F`
- target `0x008014F1`

with:

```asm
push 6
call 0x8014F1
```

The resulting PlayerInfo is then copied into the selected active GameInfo slot through:

- `0x008016C3`

using the found `slotIndex`.

Thus the path is directly:

```text
find first PlayerType 0 slot
    -> selected slot index
    -> create PlayerInfo Type 6
    -> copy Type-6 player into that exact GameInfo slot
```

---

# Two-PC P3 runtime test

## Required lobby layout before PC2 joins

On PC1 / host:

```text
P1 = Human host
P2 = Easy/Medium/Hard/Brutal AI
P3 = Open
```

P4-P8 can remain whatever is appropriate for the scenario, provided P3 is the first open slot after P1/P2.

Then PC2 joins.

### Expected native allocation

```text
slot 0: Type 6    -> PC1
slot 1: Type 2..5 -> AI
slot 2: Type 6    -> PC2
```

The allocator cannot select slot 1 because an AI's PlayerType is not zero.

---

# Observer expectations

Run:

```text
tools/research/AOTR_P3_NATIVE_OBSERVER.ps1
```

on both machines.

## PC1 expected result

```text
LocalSlot = 0
```

Slots should contain approximately:

```text
0:T6:*local-PC1*
1:T2/T3/T4/T5
2:T6:PC2
```

## PC2 expected result

```text
LocalSlot = 2
```

Slots should contain approximately:

```text
0:T6:PC1
1:T2/T3/T4/T5
2:T6:*local-PC2*
```

After native LivingWorld player creation, PC2 should additionally reach:

```text
LWCurrent != 0
```

If both conditions hold:

```text
LocalSlot = 2
LWCurrent != 0
```

then P3 has been proven at runtime as a real native network human with its own local LivingWorldPlayer using only two physical PCs.

---

# What this test proves and does not prove

### A successful two-PC test proves

- an additional real network human can occupy slot 2/P3;
- remote slot allocation is not limited to P1/P2;
- GameInfo carries the P3 network player;
- the local-slot resolver can identify PC2 as slot 2;
- LivingWorld can select P3 as the local/current LivingWorldPlayer on PC2.

### It does not yet prove

- three simultaneous real humans are stable;
- P4-P8 scale identically at runtime;
- strategic commands from P3 remain synchronized without OOS;
- later battle/transition systems are 8-human safe.

Those remain separate tests.

---

# Updated research decision

The immediate development test no longer requires three physical PCs.

Use:

```text
P1 Human / P2 AI / P3 Human
```

with the two existing machines first.

Only after P3 reaches `LocalSlot=2` and a valid `LivingWorldPlayer` should the project move to strategic command synchronization/OOS analysis or to a true three-human scale test.
