# Native join call PoC bounded observer fix

The first controlled `+0x40` call returned, but the PowerShell wrapper remained in the post-call observation stage longer than the requested window. The native call itself had already returned before this stage.

A local patch helper was added to replace the DateTime-deadline loop with an explicit bounded poll count (`ObserveSeconds * 4`, 250 ms each). This does not change the native call stub or its safety gates; it only guarantees deterministic termination of the PowerShell observation wrapper.
