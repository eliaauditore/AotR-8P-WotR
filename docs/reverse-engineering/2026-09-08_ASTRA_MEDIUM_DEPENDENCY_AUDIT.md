# Astra Medium dependency audit — OWN_MP -> GameInfo -> LivingWorld

Checkpoint: 2026-09-08

Scope: read-only Codex/Astra Medium audit over the reconstructed AotR/BFME research workspace. No game execution, process access, binary patching, build, debugger attach, or file mutation of research originals was performed.

## Result

`DEPENDENCY_AUDIT_RESULT=INCONCLUSIVE`

The small-adapter architecture remains plausible, but the currently recovered textual evidence does not expose enough of the LivingWorld entry contract to prove that normal native multiplayer peer/transport state is unnecessary.

### Classification counts

- Category A — GameInfo / PlayerInfo-local state: 5
- Category B — bounded native session identity/lifecycle state: 2
- Category C — broader native multiplayer startup state: 3
- Category D — unresolved contract: 8

Important qualification: Category-C entries are documented upstream dependencies of the normal startup path, not proven unavoidable dependencies of `0x00932EB8` itself.

## Strongest confirmed seam

Existing evidence still supports this candidate architecture:

`OWN_MP slot authority -> complete native GameInfo/PlayerInfo rows -> native local-slot resolution -> LivingWorldPlayer creation/local selection -> original strategic gameplay`

Known bounded identity dependency:

- C54 local-player test uses session virtual `+0x100`.
- The concrete accessor `0x008A0318` is exactly `lea eax,[ecx+0x48]; ret`.
- Therefore local identity retrieval itself does not perform peer lookup, socket activity, or packet processing.

This supports the possibility of retaining only a small native compatibility context while OWN_MP owns lobby/session authority and transport.

## First blocking dependency

The exact predicate and prerequisite state used near `0x00932EF2` to select the GameInfo receiver consumed by the virtual `+0x34` call at `0x00932F21` are not fully preserved in the current textual evidence.

The available documentation establishes that `0x00932EB8` selects between network/alternate GameInfo globals and then resolves local slot virtually, but does not contain the complete function body required to prove the selection contract.

After that boundary, the next important unresolved contracts are:

- construction-record argument passed into `0x006BB3B5`;
- derivation of the human/AI property argument;
- transitive prerequisites of constructor `0x006E3C8B`;
- exact upstream postconditions from normal State-14 network/bootstrap processing that downstream LivingWorld initialization actually consumes.

## Observer caveat — confirmed

`AOTR_P3_NATIVE_OBSERVER.ps1` does not observe the native local-slot resolver return value.

It:

- reads GameInfo from `DE7D6C`, not the GameInfo receiver selected by `0x00932EB8`;
- computes `$localSlot` itself from Type6 + GameInfo endpoint equality;
- does not capture EAX from `0x00932F21`;
- does not call/observe session virtual `+0x100`;
- omits the documented port-plus-eight fallback;
- keeps the last matching slot if duplicate identities exist, whereas the documented native scan returns the first match.

Therefore future runtime proof of native P3/P4 binding must observe the real resolver result or its direct native consumer, not only the observer's derived `LocalSlot` field.

## Next step

Best next step is static and read-only:

Obtain the complete canonical `game.dat` disassembly/byte window for `0x00932EB8` and resolve:

1. the exact GameInfo-selection predicate;
2. the selected receiver on each branch;
3. the argument-preparation chain leading into `0x006BB3B5`;
4. whether any broader peer/transport state is read directly in that consumer path.

Do not resume territory runtime testing or add more join lifecycle calls before this static dependency boundary is resolved.
