# State-8 orchestrator readiness fix — 2026-08-28

## Observed failure

`AOTR_WOTR_LOWLEVEL_JOIN_COMPLETION_ORCHESTRATOR.ps1` started the dual execution watcher but timed out waiting for `DEBUG_ATTACH=OK` / `ARMED_THREADS` in redirected stdout.

The watcher process had not reported an error. Its redirected output only contained the static PowerShell header.

## Root cause

The original watcher calls the C# method `Watch()` synchronously and only emits the returned string with `Write-Output` after `Watch()` returns. `DEBUG_ATTACH=OK` and `ARMED_THREADS=...` were appended to the C# method's internal `StringBuilder`, so those markers were not available in redirected stdout while the watcher was active.

Therefore the orchestrator's stdout-polling readiness gate could never succeed during the active watch window.

## Fix

Added:

- `tools/research/AOTR_WOTR_STATE8_COMPLETION_DUAL_EXEC_WATCH_V2.ps1`
- `tools/research/AOTR_WOTR_LOWLEVEL_JOIN_COMPLETION_ORCHESTRATOR_V2.ps1`

V2 watcher writes a dedicated sidecar readiness file immediately from C# after DR0/DR1 are armed on the existing game threads:

```text
STATUS=READY
ARMED_THREADS=<n>
PID=<game pid>
```

The V2 orchestrator waits only for this sidecar signal. It launches the low-level native join PoC only when `STATUS=READY` and `ARMED_THREADS>0` are observed. If readiness fails, the join is not started and helper processes are cleaned up.

## Classification

**BEWIESEN tooling root cause:** redirected watcher stdout was not a live readiness channel because the relevant C# log string is returned only when `Watch()` ends.

**Safety property:** the failed V1 orchestrator run did not launch the low-level join; therefore it produced no game-join runtime evidence and left the browser pre-join state untouched.
