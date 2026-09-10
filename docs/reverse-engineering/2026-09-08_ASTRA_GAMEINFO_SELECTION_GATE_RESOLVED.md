# Astra Medium follow-up — GameInfo selection gate resolved

Checkpoint: 2026-09-08

Scope: read-only static analysis of canonical `game.dat` byte windows exported from the exact SHA256 baseline `CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC`.

No game execution, debugger attach, process access, memory write, file patch, build, Python, or external RE tool was used.

## Result

`SMALL_ADAPTER_GATE=STILL_INCONCLUSIVE`

`DIRECT_NETWORK_STACK_DEPENDENCY=NOT_PROVEN`

The previous first blocker — exact GameInfo receiver selection before `0x00932F21` — is now resolved statically. The small compatibility-adapter architecture remains plausible, but several helper contracts remain unresolved.

## BEWIESEN — GameInfo selection rule in `0x00932EB8`

At entry, `EDI` receives incoming `ECX` (`setupThis`). Before selection, the function calls `0x006B897F` with `ECX=[0x00DE4950]`.

The decoded selection path is:

```text
if byte[setupThis+0x58] != 0:
    goto 0x00933109

context = [0x00DE412C]
AL = call 0x00610A21(this=context)

if AL != 0:
    selected = [0x00DE892C]
else:
    if dword[context+0x114] == 3:
        goto 0x00933109
    selected = [0x00DE8930]

if selected == NULL:
    goto 0x00933175

ECX = selected
[EBP-0x18] = selected
EAX = [ECX]
call [EAX+0x34]          ; 0x00932F21
[EBP-0x20] = EAX        ; native localSlot result
```

Thus the receiver at `0x00932F21` is exactly the GameInfo object loaded from the selected global (`DE892C` or `DE8930`) on this branch. It is not loaded from `DE7D6C` or session virtual `+0xE0` at that point.

Semantic names for `0x00610A21` and `context+0x114 == 3` remain unassigned.

## BEWIESEN — C54 local-slot resolver contract refinement

`0x0084A43A`:

- initializes result to `-1`;
- requires `byte[GameInfo+0x10] != 0`;
- scans indices `0..7`;
- resolves each embedded row through `0x84A419`;
- calls `0x84A3B5`;
- returns the first matching index.

`0x84A3B5`:

- requires Type6;
- requires non-NULL `[DE4394]` session receiver;
- obtains local endpoint through session virtual `+0x100`;
- compares endpoint with the row;
- retries with a copied endpoint whose 16-bit port is increased by 8 after the first mismatch.

The concrete endpoint getter is already proven as bounded state: `0x008A0318 = lea eax,[ecx+0x48]; ret`.

Therefore the visible local-identity resolver has a bounded session dependency and contains no direct packet/peer/transport work.

## BEWIESEN — immediate `0x006BB3B5` argument preparation

For each eligible row, the setup code derives:

- `ARG1 = &constructionRecord`;
- `ARG2 = isLocal`, where `isLocal = (slotIndex == nativeLocalSlot)`;
- `ARG3 = (Type6 predicate result == 0)`;
- `ARG4 = source PlayerInfo`.

The visible setup also performs several lookups and row-derived field preparations before the factory call. Those helper contracts are not yet fully classified.

## STARKER HINWEIS — no direct broader network dependency yet

The newly decoded consumer windows expose GameInfo/PlayerInfo state, bounded session endpoint identity, construction preparation, LivingWorld allocation/append and local-player selection machinery.

No direct peer enumeration, packet queue, socket send/receive, or transport processing is established in these windows.

This is not proof that such dependencies are absent inside unresolved callees.

## Remaining unknowns

The first remaining dependency contract is the mandatory pre-selection call `0x006B897F`.

Additional unresolved targets:

- `0x00610A21` selection-helper semantics;
- alternate/NULL setup continuation at `0x00933140..0x009331A0`;
- factory continuation at `0x006BB4D0..0x006BB520`;
- local-player setter continuation at `0x006B4380..0x006B43E0`.

## Next exact static gate

Export and decode exactly these canonical VA ranges (end exclusive):

```text
0x006B897F..0x006B8A7F
0x00610A21..0x00610B21
0x00933140..0x009331A0
0x006BB4D0..0x006BB520
0x006B4380..0x006B43E0
```

Tool:

`tools/research/AOTR_LIVINGWORLD_DEPENDENCY_WINDOWS_V2_PWSH7.ps1`

This remains a static/read-only gate. Do not resume territory runtime testing or add further native join lifecycle calls yet.
