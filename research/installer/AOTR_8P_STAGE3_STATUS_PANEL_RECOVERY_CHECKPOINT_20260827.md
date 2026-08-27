# AotR 8P WotR — Stage 3 status-panel recovery checkpoint

## STATUS
Functional autodetect/preflight PASS; center status panel still visually incomplete. Recovery source identified.

## WHAT WE KNOW
- Current hash-fixed builder: `B244D987A99533DD3A79978032F64C261FF7EBBDDA1AAFA6BB0142FFA9BC2572`.
- Current GUI: `AA8893A160CF790644FF794F4E8E47B3D1E05E1022AD22FB784A071B91920D8E`.
- Stage 3 V3 EXE: `A91EA762439DC855DDD38D68BAC81B59031B2063CBCDB6E52D3B50A9D7926F48`.
- Fresh standalone autodetection passes and writes Config V2 correctly.
- Embedded `Get-FileHash` host failure is removed.
- Current GUI has Row1/2/3 FAIL overlays only; successful checks collapse them.
- Current screenshot shows the center status panel empty on success.
- `ReadyCleanPatch` is only a masking image; it is not a positive status panel.
- The previous exact-hash LAN_UI_POLISH recovery attempt failed because that exact builder is no longer present under `D:\BFME_RESEARCH\05_REVERSE_ENGINEERING`.

## RECOVERY SOURCE
A retained builder named `BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_RC4_STATUS_PANEL.ps1` is proven by its source header to add a `dynamic center health/status panel independent of baked skin text`. This is the correct recovery lineage for the missing status display.

## CURRENT HYPOTHESIS
The dynamic status panel existed in V18 RC4 and was lost when the robust-autodetect work was integrated from the V17 START_SIGNAL lineage. Recover the RC4 status-panel XAML/update functions into the current hash-fixed V17 builder without replacing the proven resolver, hash fix, engine, repair dispatcher, or release artifacts.

## SAFE TESTS COMPLETED
- Current GUI XAML/preflight status audit.
- Visual screenshot review.
- Legacy LAN_UI_POLISH exact-hash search: no match; no files modified.

## NEXT PRACTICAL ACTION
Run `AOTR_8P_STAGE3_STATUS_PANEL_RC4_RECOVERY_AUDIT_V2.ps1` to locate the RC4 status-panel builder by exact filename + source marker, decode both legacy and current GUI payloads, and print the status-panel implementation for exact recovery.

## DO NOT REPEAT
- Do not keep searching for LAN_UI_POLISH SHA `5F806FB0...` as the status-panel recovery source.
- Do not invent new status labels/coordinates before inspecting the retained RC4 status-panel implementation.
- Do not modify the proven Robust Autodetect V2 resolver.
- Do not reintroduce `Get-FileHash` into embedded GUI/engine payloads.
- Do not touch public release artifacts during recovery.
