# Native join PoC Windows PowerShell 5.1 UIntPtr blocker

Date: 2026-08-28

## Status

**BEWIESEN:** the low-level native join test discussed in this checkpoint did **not** reach `session->vtable+0x40`.

The PoC failed first at its temporary remote allocation call because Windows PowerShell 5.1 could not convert the literal `4096` to `System.UIntPtr` for:

```powershell
[A8PNativeJoinCall]::VirtualAllocEx(...,[UIntPtr]0x1000,...)
```

Observed error:

```text
Der Wert "4096" vom Typ "System.Int32" kann nicht in den Typ "System.UIntPtr" konvertiert werden.
```

Therefore the simultaneous execution watcher result

```text
CALLBACK_8496C2_HIT=NO
COMPLETION_84944F_HIT=NO
SESSION ... CURRENT=0
DE892C=0
```

is **NOT** evidence that the low-level join bypasses those callbacks. The native join call never executed in that run.

## Compatibility fix

Added:

`tools/research/AOTR_WOTR_NATIVE_JOIN_CALL_POC_PS51_WRAPPER.ps1`

The wrapper creates only a temporary copy of the existing research PoC and changes the two non-zero PowerShell-side `UIntPtr` casts to explicit constructor calls:

```powershell
[UIntPtr]::new([uint32]0x1000)
[UIntPtr]::new([uint32]$stubBytes.Length)
```

No `game.dat` bytes are changed by the wrapper. The underlying PoC's existing controlled runtime behavior and safety gates remain unchanged.

## Next test

Repeat the dual execution watcher on `0x8496C2` and `0x84944F`, then execute the native join through the PS5.1 compatibility wrapper. Only that rerun can classify whether the low-level join reaches the State-8 completion callback chain.
