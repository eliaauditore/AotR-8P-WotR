# Normal client join frontend timeline — 2026-08-28

## Runtime control

Canonical `game.dat` SHA256:

`CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC`

A clean normal client join was observed read-only at 20 ms polling.

### BEWIESEN

Initial browser state:

- Session state `+0x28 = 0`
- `session+0x44 = NULL`
- `DE892C = NULL`
- `DE8930 = NULL`
- `DE7D6C = NULL`

Observed transition:

1. Session state changed `0 -> 1`.
2. About 539 ms later, `session+0x44` became a `C54B78` GameInfo pointer.
3. About 110 ms after that, `DE892C` became the exact same `C54B78` pointer.
4. About 127 ms later, session state changed `1 -> 0`.
5. Final state retained `session+0x44 == DE892C == C54B78`; `DE8930` and `DE7D6C` remained NULL.

This proves that the normal client lifecycle publishes `DE892C` asynchronously after session-current selection. A direct `DE892C` memory write is therefore not a faithful reproduction of the native path.

## Low-level native join comparison

The existing low-level join PoC reaches backend/session success and obtains a valid C54B78 current GameInfo, but remains with `DE892C = NULL`. Therefore the PoC bypasses a native frontend/publication stage that the normal UI join executes after session-current becomes valid.

## Post-join UI-switch control

A later read-only snapshot of a normal joined client showed:

- `DEA114 = 1`
- `DEA110 = NULL`
- both `DE7D40..DE7D57` UI switch-table entries all zero
- `session+0x44 == DE892C == C54B78`
- `DE7D6C = NULL`

Therefore `DEA110` and the `DE7D40..57` table are not persistent prerequisites for the final joined memory state. They may be transient during the join or unrelated to the missing publication step. The earlier hypothesis that a populated SLOT 1 table is required for successful final handoff is withdrawn.

## Next gate

Capture a high-frequency normal-join frontend timeline including `DEA110`, `DEA114`, both UI-table entries, `session+0x44`, and `DE892C` to determine whether those frontend structures are transient during the ~800 ms join handoff. Use `AOTR_WOTR_NORMAL_CLIENT_FRONTEND_TIMELINE_OBSERVER.ps1`.
