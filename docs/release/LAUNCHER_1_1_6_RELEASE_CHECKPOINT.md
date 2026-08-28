# Launcher 1.1.6 release checkpoint

- Distribution: GitHub self-update channel only; no new ModDB package.
- Root cause: Windows PowerShell 5.1 preserves the JSON comment array as one `System.Object[]` when `ConvertFrom-Json` is wrapped directly by `@(...)`; the first `[internal]` comment therefore caused the aggregate object to be filtered out.
- Fix: parse comments first, then normalize with `@($parsedComments)` before filtering.
- Source RC run: `
33155923650
`.
- Source artifact ID: `
9679589813
`.
- Actions artifact SHA256: `
88349799FA9D20FC77F7F8F5EA6ECC41E9759CE2582005028E59FFEEF46C2B17
`.
- Launcher SHA256: `
E5FD1761FB84E452782AFD970225775CB55096C22628F1B9061344C282861431
`.
- Launcher size: `
1271296
` bytes.
- Embedded GUI SHA256: `
8A31D3EDC48B5915AC552EFB26DFF48CEABB1022D24C0A90834930117046A2AA
`.
- Embedded engine SHA256: `
E9E2452FF56A66D57FF63C0B1654CFE0C856F4D5FA66C558E8F237C9ABABF641
`.
- Release ZIP SHA256: `
871EAC9DEF6C4C0A5FF6CD368579C9BB08CE134E7E70673DE9F5B4573D8B060E
`.
- Manifest SHA256: `
0682B26B80CB05E29A58F231D10A2C2AE28CB905A8CA4938949AB6EE28E77193
`.
- Repair manifest SHA256: `
7EBA9B49E848F26FEC96234A8874FBF347E4B68E50C9EDEC3D8B39DEE15A79EC
`.
- Defender: `SCANNED_CLEAN`.
- Exact embedded MESSAGES E2E: master #78 resolved, public maintainer messages loaded, `latest > seen` before open, persistence verified in RC gate, and MarkRead advanced seen to latest.

The public candidate in this branch is copied from the exact tested Actions artifact; it is not rebuilt during promotion.
