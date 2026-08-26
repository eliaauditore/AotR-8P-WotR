# AotR 8P WotR — Robust Autodetect V2 Stage 1 Success

Date: 2026-08-27 (Europe/Berlin)
Branch: `feature/robust-aotr-autodetect`
Status: STAGE 1 COMPLETE / NON-RELEASE BUILDER CREATED / NO EXE BUILT

## STATUS

The robust standalone AotR autodetect V2 integration completed successfully against the checkpointed `START_SIGNAL_MVP` builder after two tooling-only encoding fixes:

1. preserve the decompressed UTF-8 BOM while hashing/re-embedding embedded PowerShell payloads;
2. strip a leading U+FEFF only for `Parser.ParseInput()` syntax validation so a script-level `[CmdletBinding()]` / `param(...)` block remains parser-valid.

No public launcher EXE was modified and no executable build was run.

## INPUT CHECKPOINTS

Canonical source builder:

```text
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_START_SIGNAL_MVP.ps1
SHA256: 79D31C3DCE6833781BFECF5B87230B1C463483EA4F31A89D2431238D42A17C6F
```

Original embedded GUI payload:

```text
SHA256: E8C67486182DA952EA19214AAE9F60E5E9E410579FEF1C0722DA626CE5FFF1EF
```

Original embedded ENGINE payload:

```text
SHA256: D94460492ACD2B98CB8DF0929E302C2F626A97045AAEE9593A2B29E9424FEA5B
```

Stage 1 source integrator downloaded checkpoint:

```text
SHA256: 5518DDE7284F58C908FA99CE41A3F641D89A786C469EB1B4D2E56D94428062A6
```

Stage 1 V2.2 runtime hotfix generated locally:

```text
SHA256: 4F3D80458220803C3E7103E1559231CDDCF20DF2576392F55A58E8614113087F
```

## SUCCESS OUTPUT

Work root:

```text
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE1_20260827_003823
```

Patched GUI payload:

```text
SHA256: D8C3E27E35F3EDA101EE74362C9E744BB942D6F06928B61D22036640C22E5F47
```

Patched ENGINE payload:

```text
SHA256: 3A03D47B6A094A4892A146866DFEAD53858C500F812615672D66690D7812A873
```

Generated non-release builder:

```text
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE1_20260827_003823\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_NONRELEASE.ps1
SHA256: 6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386
```

Stage 1 local report:

```text
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE1_20260827_003823\STAGE1_REPORT.txt
```

## VALIDATION COMPLETED

```text
GUI syntax: PASS
ENGINE syntax: PASS
Builder syntax: PASS
```

The Stage 1 integrator also completed its embedded-payload re-embed / roundtrip validation before reporting `STAGE 1 COMPLETE`.

## WHAT CHANGED FUNCTIONALLY

GUI resolver now carries the robust standalone-AotR V2 logic and canonical Config V2 contract.

ENGINE no longer acts as an independent discovery authority. It consumes the GUI-selected schema-2 config and hard-revalidates the exact canonical standalone AotR root.

The public release launcher was not touched.

## ENCODING LESSON

The embedded PowerShell payload byte streams contain a UTF-8 BOM. A `StreamReader` with BOM detection consumes that BOM and therefore changes byte-derived checkpoint hashes even when the visible script text is otherwise identical.

For exact payload checkpointing/re-embedding:

```text
gzip -> raw bytes -> UTF8.GetString(raw bytes)
```

must be used so U+FEFF is retained in the in-memory string.

For PowerShell parser-only validation, a leading U+FEFF must be removed from the temporary parse string before calling `Parser.ParseInput()`, otherwise a top-level `[CmdletBinding()]` / `param(...)` can be reported as an unexpected attribute/token.

## NEXT PRACTICAL ACTION

Perform a read-only Stage 2 build preflight against the exact non-release builder SHA256 `6E5CA3D1...`.

Before executing the builder, prove:

- exact parameter names and defaults;
- exact output EXE path construction;
- any backup / copy / bundle / manifest side effects;
- that an isolated output root can be supplied or safely injected;
- that the public/release EXE path will not be overwritten;
- that the build can be labeled explicitly non-release/test.

Only after that preflight should a test EXE be compiled.

## DO NOT REPEAT

- Do not rerun source discovery for GUI/ENGINE resolver locations.
- Do not treat the BOM-normalized hash `CD1BB18A...` as a different GUI payload version.
- Do not remove the BOM from payloads merely to satisfy parser validation.
- Do not build directly into the public package/release directory.
- Do not publish or replace the public EXE from Stage 2.
- Do not modify the original `START_SIGNAL_MVP` builder.
