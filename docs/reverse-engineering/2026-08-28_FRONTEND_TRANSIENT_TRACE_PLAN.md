# Frontend transient trace plan — 2026-08-28

The post-join normal client control shows `DEA110=NULL` and both `DE7D40..57` table slots cleared even though `session+0x44 == DE892C == C54B78`.

Therefore the next control must observe these structures during the transition rather than only after it.

Use `tools/research/AOTR_WOTR_NORMAL_CLIENT_FRONTEND_TIMELINE_OBSERVER.ps1` at 5 ms polling while performing exactly one normal UI join from the browser.

Trace set:

- session state `+0x28`
- session list head `+0x10`
- session current `+0x44`
- `DE892C`, `DE8930`, `DE7D6C`
- `DEA110`, `DEA114`
- both 12-byte UI-table entries at `DE7D40` and `DE7D4C`
- frontend globals `DE412C`, `DE4B04`

Decision:

- if manager/table become nonzero only transiently, trace their exact timing relative to `Current` and `DE892C`;
- if they remain zero throughout a normal join, remove them from the missing-handoff model and return to the normal join caller/owner lifecycle;
- do not patch `DE892C` directly.
