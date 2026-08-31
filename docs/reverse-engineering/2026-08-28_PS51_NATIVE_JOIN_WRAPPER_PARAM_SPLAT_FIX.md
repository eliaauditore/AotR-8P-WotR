# PS5.1 native-join wrapper parameter splat fix

## Status

**BEWIESEN:** The PS5.1 compatibility wrapper itself started successfully, but the patched native-join PoC did not execute because the wrapper forwarded named parameters through array splatting.

Observed failure:

```text
Argument transformation for parameter "ProcessId" failed.
Value "-ProcessId" cannot be converted to System.Int32.
```

Cause:

```powershell
$invoke = @(
    '-ProcessId', [string]$ProcessId,
    ...
)
& $temp @invoke
```

For a script invocation, this array was treated positionally. The literal string `-ProcessId` became the first positional value for the target script's `[int]$ProcessId` parameter.

## Fix

The wrapper now uses named hashtable splatting:

```powershell
$invoke = @{
    ProcessId          = [int]$ProcessId
    ExpectedRemoteIp   = [string]$ExpectedRemoteIp
    ExpectedRemotePort = [int]$ExpectedRemotePort
    ObserveSeconds     = [int]$ObserveSeconds
}
if ($Execute) { $invoke['Execute'] = $true }

& $temp @invoke
```

The existing PS5.1 `UIntPtr` compatibility substitutions remain unchanged.

## Test classification

The failed attempt is **not** evidence about the `0x8496C2 -> 0x84944F` frontend completion path because the native `session->vtable+0x40` call never executed.
