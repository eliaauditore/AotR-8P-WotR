# Native join call PoC - PowerShell 7 UIntPtr interop fix

Checkpoint: 2026-08-28

The first controlled runtime execution of `AOTR_WOTR_NATIVE_JOIN_CALL_POC.ps1` passed every native pre-call safety gate on the VM:

- exact `game.dat` SHA256 matched;
- session singleton and `C54CE0` vtable matched;
- vtable `+0x40` resolved to `0x0084CB34`;
- session state `+0x28 = 0`;
- `session+0x44 = NULL` pre-join;
- local endpoint was `192.168.0.57:8086`;
- exactly one remote Network GameInfo matched host `192.168.0.224:8086`;
- selected `arg1 = 0x09B47E38`.

Execution then stopped before any remote allocation or native call because PowerShell 7 could not convert the literal cast `[UIntPtr]0x1000` for `VirtualAllocEx`:

```text
Cannot convert value "4096" of type System.Int32 to type System.UIntPtr.
```

This is a PowerShell interop bug in the PoC wrapper, not a native engine failure.

Hotfix tool:

`tools/research/PATCH_AOTR_WOTR_NATIVE_JOIN_CALL_POC_PS7_UINTPTR.ps1`

It makes exactly two local-script replacements:

- `[UIntPtr]0x1000` -> `[UIntPtr]::new([uint64]0x1000)`
- `[UIntPtr]$stubBytes.Length` -> `[UIntPtr]::new([uint64]$stubBytes.Length)`

The patcher validates that each old expression occurs exactly once before editing. It does not modify `game.dat` or process memory.
