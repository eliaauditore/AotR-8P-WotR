# AotR 8P WotR — Stage 1 BOM Checkpoint

Date: 2026-08-27 (Europe/Berlin)
Branch: `feature/robust-aotr-autodetect`

## STATUS

Stage 1 integration aborted safely before modifying any builder copy because the GUI payload checkpoint hash did not match.

Observed:

```text
Expected GUI SHA256:
E8C67486182DA952EA19214AAE9F60E5E9E410579FEF1C0722DA626CE5FFF1EF

Observed by Stage 1 V2:
CD1BB18A7843281D7FDD76EC76D6BFA5FD53A54DAA3CA9F2E2E465A87E1FF992
```

The source builder itself still matched the required checkpoint:

```text
START_SIGNAL_MVP SHA256:
79D31C3DCE6833781BFECF5B87230B1C463483EA4F31A89D2431238D42A17C6F
```

## ROOT CAUSE

The recursive source audit computed the GUI/engine checkpoint from the exact decompressed UTF-8 byte stream. The payload begins with a UTF-8 BOM.

Stage 1 V2 used `StreamReader(..., detectEncodingFromByteOrderMarks = $true)`. `StreamReader` consumes the UTF-8 BOM while decoding, so hashing the re-encoded returned string produces a different hash even though the payload content is otherwise the same.

Therefore:

- `E8C674...` is the exact BOM-preserving GUI payload checkpoint;
- `CD1BB1...` is the same GUI text after BOM removal by `StreamReader`;
- this was an extractor/checkpoint representation bug, not evidence of a different launcher source revision.

## FIX

Added:

```text
research/installer/AOTR_8P_STAGE1_BOM_HOTFIX_V2_1.ps1
```

The hotfix:

1. requires the exact original Stage 1 V2 script SHA256:
   `5518DDE7284F58C908FA99CE41A3F641D89A786C469EB1B4D2E56D94428062A6`;
2. replaces only `Convert-GzipBase64ToText`;
3. decompresses GZip into raw bytes first;
4. uses `Encoding.UTF8.GetString(rawBytes)` so the BOM survives as U+FEFF and re-encodes byte-identically;
5. parser-validates the hotfixed Stage 1 script;
6. writes only a temporary corrected runtime copy and executes that copy;
7. does not modify the canonical builder before Stage 1's own guards succeed.

## DO NOT REPEAT

- Do not change the expected GUI checkpoint to `CD1BB1...`; that would normalize away a real byte-level difference instead of fixing extraction.
- Do not use `StreamReader` with BOM detection when byte-exact payload hashes are part of the guard.
- Do not bypass the payload hash guard.
- If the V2.1 hotfix does not reproduce `E8C674...` and `D944604...`, stop and inspect rather than continuing to build.
