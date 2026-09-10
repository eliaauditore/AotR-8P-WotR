# Recovery host toolchain and Astra context pack

Date: 2026-09-08

## Host toolchain after PC reset

- PowerShell: 7.6.5
- Python: not installed
- No other auxiliary RE tooling assumed present
- `C:\AOTR_RESEARCH` recovered from GitHub and health-check PASS after mod initialization
- Existing `BFME_RESEARCH` preserved and treated read-only

## Astra context pack tooling

V1 failed to create the ZIP because `Compress-Archive -LiteralPath` was used with a wildcard.

V2 fixed ZIP creation and BFME root discovery, but failed while mirroring BFME text files because deeply nested source paths produced an overlong destination path under `C:\AOTR_RESEARCH\ASTRA_CONTEXT\BFME_RESEARCH_TEXT`.

V3 (`AOTR_BUILD_ASTRA_CONTEXT_PACK_V3_SHORTPATH_PWSH7.ps1`) is PowerShell-7-only and requires no Python or external tools. It:

- resolves BFME_RESEARCH read-only;
- inventories all BFME files;
- copies text-like files under short hashed packed filenames;
- writes `BFME_TEXT_INDEX.csv` mapping original path -> packed path -> SHA256;
- verifies packed copy hashes;
- builds `ASTRA_CONTEXT.zip` using .NET `System.IO.Compression.ZipFile`;
- verifies resulting ZIP size and SHA256.

No original BFME_RESEARCH or game/mod files are modified.
