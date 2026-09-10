# localRoot compact trace — standalone final direct capture

The prior FINAL RAW wrapper failed before launch because its RAW-output injection was applied at the V3 generator layer rather than the generated capture layer, producing a parser error where a second `param(...)` block appeared inside the temporary script.

That wrapper path is retired.

New tool:

`tools/research/AOTR_WOTR_LOCALROOT_COMPACT_FINAL_DIRECT.ps1`

Properties:

- standalone PowerShell script; no generator, nested runner, regex transform, or downloaded source transformation;
- compatible with Windows PowerShell 5.1 and PowerShell 7;
- exact game.dat SHA256 guard;
- exact 7-byte hook guard at `0x00A211DF`;
- 64 MiB remote scratch;
- in-stub filter requires the current `[DE3380]->+0x24` localRoot to equal original ECX;
- fixed 20-byte records: index / this / tag / len / preA;
- hook is restored before trace copy/output;
- raw trace is written directly to `.bin` without the 3.35M-record PowerShell parser;
- validates `bytes % 20 == 0` and `bytes/20 == callCount`;
- frees remote scratch and closes the process handle after output;
- game.dat on disk is never modified.

Expected saturated-prefix result based on prior Host/VM runs:

- records: 3,355,238
- bytes: 67,104,760
- overflow: 1
- localRoot vtable: `0x00BFD2A0`

This tool exists solely to materialize the already-proven compact trace prefix into a raw binary file without post-capture parser stalls.