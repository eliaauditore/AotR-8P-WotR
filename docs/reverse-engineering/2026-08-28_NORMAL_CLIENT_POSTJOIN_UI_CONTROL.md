# Normal client post-join UI control — 2026-08-28

Read-only snapshot on canonical `game.dat` after a clean normal client join.

## Observed

- `DEA114 = 1`
- `DEA110 = NULL`
- `session+0x28 = 0`
- `session+0x44 = C54B78`
- `DE892C = same C54B78`
- `DE7D6C = NULL`
- `DE7D40..DE7D57` two 12-byte UI-table entries are all zero

## Classification

**BEWIESEN for this final joined memory state**

The final `session+0x44 == DE892C == C54B78` state does not require a persistent `DEA110` manager or populated `DE7D40..57` table. Therefore those structures cannot be treated as persistent proof of a completed frontend handoff.

**HYPOTHESE**

They may still be transient during the normal join transition and cleared before the post-join snapshot. A high-frequency timeline is needed before ruling out transient participation.

Tool added for this next gate:

`tools/research/AOTR_WOTR_NORMAL_CLIENT_FRONTEND_TIMELINE_OBSERVER.ps1`
