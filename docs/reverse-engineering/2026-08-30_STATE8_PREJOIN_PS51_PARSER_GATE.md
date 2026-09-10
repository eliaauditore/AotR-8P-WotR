# State8 pre-join PS5.1 parser gate

## Result

The first runtime attempt of `AOTR_WOTR_STATE8_PREJOIN_NATIVE_JOIN_ORCHESTRATOR_V2.ps1` was blocked by an explicit outer PowerShell parser gate before the script was executed.

Observed parser error:

```text
InvalidVariableReferenceWithDrive
Extent: $Stage:
```

Root cause: three interpolated error strings in V2 used `"$Stage: ..."`. Windows PowerShell parses `$Stage:` as a drive-qualified variable reference. Correct syntax is `"${Stage}: ..."`.

## Safety classification

**BEWIESEN tooling-only failure**

- the outer parser gate reported `ORCHESTRATOR SYNTAX FAILED - NOTHING EXECUTED`;
- V2 was never invoked;
- no debugger attach occurred;
- no `WriteProcessMemory` call occurred;
- no native `session->vtable+0x40` join call occurred;
- the current fresh VM `game.dat` process therefore does not require restart solely because of this parser failure.

## Correction

Added `tools/research/AOTR_WOTR_STATE8_PREJOIN_NATIVE_JOIN_ORCHESTRATOR_V3_PS51_FIX.ps1`.

V3 pins V2 commit `f138807b0b2eeed313a18b917465c8cd1f894210`, requires exactly three literal `$Stage:` tokens, replaces only those tokens with `${Stage}:`, parses the corrected temporary V2 with the local PowerShell parser, checks static one-variable mutation markers, and only then invokes the corrected V2 in the same 32-bit PowerShell process.

No game process is opened or modified by the V3 bootstrap before those parser/static gates pass.
