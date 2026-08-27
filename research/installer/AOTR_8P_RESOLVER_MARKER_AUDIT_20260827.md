# AotR 8P WotR — Resolver Marker Audit

Date: 2026-08-27 (Europe/Berlin)
Branch: `feature/robust-aotr-autodetect`
Status: MARKER PASS COMPLETE / RESOLVER IDENTIFICATION CONTINUES

## RESULT

The first structured marker pass was run against both:

- release-line `V17_LAN_UI_POLISH`
- development-line `V17_START_SIGNAL_MVP`

The helper found identical counts for the currently searched repair/runtime markers in both builders:

```text
check_launcher_update  1
clear_compat_cache     1
repair_payloads        3
repair-manifest        3
reset_install          1
reset_runtime          5
retry_launch           9
runtime                8
```

`CandidateResolverFunctions` was empty for both builders because none of the resolver-evidence terms currently used by the helper (`AOTR_HOME`, `AgeoftheRing`, `lotrbfme2ep1.exe`, `_AotR8P_WotR_Runtime`, `zGameDats`, `game.dat`, `aotr_root`, `source_mod`) appeared as literal hits in this pass.

## INTERPRETATION

This is a useful negative result, not proof that no auto-detection exists.

Confirmed project behavior already shows that the launcher has AotR auto-detection and that GUI and engine resolve AotR separately. Therefore the current source representation is likely using one or more of:

- different variable/function names;
- path fragments assembled dynamically rather than literal full strings;
- broader `AotR` / `rotwk` terminology not included in the first helper term set;
- embedded source/template blocks whose resolver symbols differ from the expected names;
- generated code or encoded/escaped source fragments.

The identical repair-marker counts also suggest that the repair subsystem scaffolding is unchanged between these two builder variants at the searched-marker level. This does not yet prove byte-identical repair code.

## NEXT PRACTICAL ACTION

Perform a broader read-only source vocabulary pass on both builders. Search compactly for:

```text
AotR
rotwk
lotrbfme
install
resolve
path
root
registry
HKLM
HKCU
AppData
Test-Path
Get-ChildItem
Resolve-Path
template
source
gui
engine
```

Then inspect only the functions/source blocks containing the strongest AotR/rotwk/path-resolution evidence.

## DO NOT REPEAT

- Do not conclude that auto-detection is absent because the initial literal marker set returned no resolver function.
- Do not invent resolver function names.
- Do not edit either builder yet.
- Do not modify only one resolver once identified; GUI and engine both remain in scope.
