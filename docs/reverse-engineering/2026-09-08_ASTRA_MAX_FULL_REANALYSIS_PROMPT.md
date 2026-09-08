# Astra Max full reanalysis prompt — AotR 8P WotR / OWN_MP

Use this prompt together with the locally generated `C:\AOTR_RESEARCH\ASTRA_CONTEXT.zip`.

Verified local context-pack identity from 2026-09-08:

- ZIP: `C:\AOTR_RESEARCH\ASTRA_CONTEXT.zip`
- ZIP SHA256: `3FBE6DD0BAFEA0BAE379A06F1F6245DEE0E632F9ECD8C634624F0A5A85968066`
- Host PowerShell: `7.6.5`
- Python after reset: not installed
- BFME_RESEARCH source: `D:\BFME_RESEARCH`
- BFME files indexed: `2252`
- BFME text files packed: `1497`
- BFME text bytes packed: `44143641`
- AotR research baseline: `f704fae949ccea70e2f80f87b8b9fe146b52404d`
- Research PR: `#70`

---

## COPY/PASTE PROMPT FOR ASTRA MAX

You are taking over a mature reverse-engineering / multiplayer architecture investigation for the **AotR 8P War of the Ring** mod.

I have attached `ASTRA_CONTEXT.zip`. Treat that archive as the primary evidence base. Do not start by proposing code or speculative patches. First reconstruct what has already been proven, then identify the smallest robust architecture for the remaining work.

### Primary goal

We want **8-player LAN strategic War of the Ring** where our own external network/session layer (**OWN_MP**) owns as much of the networking/control plane as practical, while the original AotR engine still owns as much of the actual game as practical.

Preferred direction:

- OWN_MP owns:
  - discovery
  - lobby/session identity
  - 8-slot map
  - player identity
  - Ready / START barrier
  - host authority
  - command sequencing
  - ACK / retry policy
  - OOS/state-hash detection
- AotR owns, wherever technically stable:
  - GameInfo / PlayerInfo representation
  - local-slot binding
  - LivingWorld player creation
  - strategic simulation
  - strategic UI
  - tactical battles
  - rendering / game systems

In short: **replace the network/control plane, not the game engine, unless evidence shows a particular native layer must remain.**

### Evidence discipline — mandatory

Use these labels exactly and conservatively:

- **BEWIESEN** = direct runtime, static binary, hash, packet, debugger, event-log, or deterministic A/B proof.
- **STARKER HINWEIS** = multiple consistent indicators, not yet conclusive.
- **HYPOTHESE** = pending / inferred.

Do not upgrade an inference to BEWIESEN just because it is architecturally convenient.

Do not silently overwrite or reinterpret prior proof. If two pieces of evidence appear inconsistent, call that out explicitly and identify the minimum test needed to resolve it.

### Canonical binary identity

All currently proven AotR virtual addresses / structures are tied to:

`game.dat SHA256 = CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC`

Canonical PlayerTemplate after the proven fix:

`playertemplate.ini SHA256 = 2D162EE705DE9D96A7B65140C22EBA6EBD0B8F155AE062C97F9884E37DC59F4D`

Do not generalize fixed virtual addresses to any other game.dat hash without revalidation.

### Required reading order

Do not attempt to read 1,497 BFME text files blindly.

Read in this order:

1. `00_ASTRA_HANDOFF.md`
2. `AOTR/PR70/PR70_TIMELINE.md`
3. `AOTR/DOCS_FROM_GITHUB/` reverse-engineering documents
4. Only then inspect specific files in `AOTR/TOOLS_FROM_GITHUB/` when a documented finding needs implementation/static-detail verification
5. Use `BFME_TEXT_INDEX.csv` to locate relevant BFME engine-family research, then open only the BFME packed files relevant to the specific seam being investigated

The packed BFME filenames are intentionally shortened to avoid Windows MAX_PATH problems. The index maps original path -> packed path -> hash. Treat BFME findings as **supporting engine-family evidence**, never as AotR-specific proof unless independently confirmed in AotR.

### Important proven state you should verify from the archive

The archive should support at least the following established chain. Do not simply trust this list; verify it against the supplied docs/timeline and correct it only if the evidence demands that.

1. The engine contains **8 PlayerInfo/GameInfo rows** and loops over all 8 in relevant GameInfo/LivingWorld paths.
2. Network-human `Type6 + endpoint` can map through GameInfo local endpoint resolution to a local slot beyond P2, and the LivingWorld setup path can create/select the corresponding local strategic player.
3. The former native join rejection was traced to a PlayerTemplate mismatch -> Component A mismatch -> B04 mismatch -> PATH_C reject.
4. The exact PlayerTemplate divergence was 22 semicolons across 11 faction blocks; fixing that canonicalized Component A/B04 and native join behavior.
5. Native join path `session vtable +0x40`, C54 GameInfo current publication, frontend State8 -> State9 behavior, `DE892C=current`, and postjoin `0x8472BF` cleanup were reproduced with controlled probes.
6. Normal native UI join and our controlled low-level join both later hit the same territory-selection crash family (`0xC000001D`, `StackHash_19d4`, same WER bucket). Therefore that territory crash is **not evidence that the controlled join is missing some arbitrary postjoin lifecycle call**.
7. OWN_MP already passed a real 3-endpoint transport/barrier PoC with deterministic slot requests and `JOIN -> ACCEPT -> START -> START_ACK -> START_COMMIT`.
8. Strategic 8P sync itself is **not yet proven**.

### Do not reopen closed areas without new evidence

Unless the archive contains a regression, do not spend the main analysis budget on:

- broad PlayerTemplate re-investigation
- B04 root-cause hunting
- arbitrary DE892C / DE8930 writes
- UI-table branches already eliminated by positive controls
- repeated State8-only join tests
- broad reinstall/sync advice
- speculative raw global mutation
- blaming remote-thread identity for the territory crash when native UI join reproduces the same crash family

### Core architecture questions

Answer these from the evidence:

1. **What is the smallest stable seam between OWN_MP and AotR?**
   - At which exact lifecycle point should OWN_MP stop emulating native networking and hand a canonical 8-slot state to the game?
   - Which native objects/functions must exist for the engine to remain internally coherent?

2. **Can native lobby/network ownership be bypassed after canonical GameInfo materialization?**
   - Distinguish what the engine needs as persistent runtime state from what is only needed to reach that state.

3. **What is the safest local-player binding path for P3-P8?**
   - Prefer native constructors/setters/lifecycle over raw pointer patching.
   - Identify the narrowest function/object boundary we need to prove next.

4. **What should the strategic command bridge look like?**
   - capture a semantic local strategic command
   - canonicalize it
   - host assigns sequence number
   - distribute to clients
   - ACK / retry / duplicate suppression
   - execute through the same native semantic command path on each client
   - state/OOS hash at deterministic barriers

5. **What role should the original engine network layer retain, if any?**
   - none
   - tactical battle only
   - strategic command transport only
   - session bootstrap only
   - some hybrid
   Support the recommendation from evidence, not preference.

6. **How should the territory-selection crash be treated?**
   - Separate baseline/current-build crash investigation from multiplayer architecture unless the evidence directly connects them.
   - Do not add random lifecycle calls to the join PoC merely to chase this crash.

7. **What can BFME research tell us?**
   - Search for equivalent LivingWorld, GameInfo, command, network-message, strategic-order, or synchronization machinery.
   - Clearly label any cross-engine extrapolation as BFME-derived inference until AotR-specific validation exists.

### Required deliverable

Produce one structured report with the following sections:

#### A. Executive architecture decision
A concise recommendation for the most promising OWN_MP <-> AotR split and why it minimizes fragility.

#### B. Proven dependency graph
Show the proven chain from:

`OWN_MP slot identity -> native representation -> local slot -> LivingWorld local player -> strategic command source -> native strategic execution`

Mark each edge BEWIESEN / STARKER HINWEIS / HYPOTHESE.

#### C. Seam table
For every important boundary, include:

- boundary / object / function
- what is proven
- what is not proven
- whether OWN_MP should own it
- whether AotR should own it
- next evidence needed

#### D. What we can stop reverse-engineering
List areas where the current proof is already sufficient for architecture work, so we do not waste time reopening them.

#### E. Top 3 next probes
Rank by **information gain / execution risk / chance of invalidating the architecture**.

For each probe give:

- exact hypothesis
- exact observation or call boundary
- mutation policy
- preconditions
- expected A/B outcomes
- what each outcome would prove
- why this probe is superior to the alternatives

#### F. Single best next probe
Choose exactly one next experiment.

It must fit this workflow:

`1 hypothesis -> 1 probe -> 1 command/workflow -> 1 result -> 1 interpretation -> 1 GitHub checkpoint`

Do not combine several unresolved variables in that probe.

#### G. Strategic synchronization design
Propose a minimal deterministic protocol for semantic WotR commands, including at least:

- player/slot identity
- command type
- canonical payload
- host sequence ID
- ACKs
- duplicate suppression
- deterministic apply point
- reconnect / dropped-peer policy
- state hash / OOS detection

Distinguish what can be designed now from what first requires command-path RE proof.

#### H. Failure conditions
Identify concrete findings that would make the desired architecture much more expensive or force a different split, e.g. hidden native network state deeply coupled into LivingWorld simulation, nondeterministic strategic logic, inaccessible semantic command boundary, or tactical/strategic state transitions that cannot be reproduced externally.

### Constraints for your recommendation

- Preserve the canonical game.dat / PlayerTemplate proof chain.
- Do not propose broad binary replacement or reinstall as a research step.
- Do not propose direct writes to unrelated globals.
- Prefer read-only/static probes first where they can discriminate the hypothesis.
- When runtime mutation is eventually necessary, mutate exactly one controlled seam with explicit preconditions and rollback/cleanup.
- Host currently has PowerShell 7.6.5 and no Python after the system reset. Do not make Python a prerequisite for the **next probe** unless you can show that it materially reduces risk or is necessary. If an external tool is truly justified, name exactly one and explain why.
- VM tooling should remain compatible with Windows PowerShell 5.1 unless explicitly re-established otherwise.

### Final instruction

Do not merely summarize the archive. I want you to use the combined AotR + BFME evidence to look for an architectural shortcut we may have missed.

The central question is:

> **Given everything already proven, what is the minimum native AotR state/lifecycle we need to preserve so that our own 8-player LAN/network authority can drive the original War of the Ring game reliably?**

End your report with one line only in this exact format:

`BEST_NEXT_PROBE=<short name>`
