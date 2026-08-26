# AotR 8P WotR — Packaging Layer Checkpoint

Date: 2026-08-27 (Europe/Berlin)
Branch: `feature/robust-aotr-autodetect`
Status: OUTER BUILDER + FIRST EMBEDDED LAYER PROVEN / RESOLVER STILL NESTED

## STATUS

Read-only inspection proved that the V17 PowerShell builder does not contain the live launcher resolver logic as ordinary cleartext source.

The builder contains a Base64-encoded `$template` beginning at builder line 84. Decoding that template in memory produces a C# source layer with exactly 589 lines.

For the release-line `LAN_UI_POLISH` builder:

```text
Builder SHA256: 5F806FB048BF7761252AC9D7B557B0177D71C3E9FFEA1E9003CD4DC300867E2C
First decoded layer: 174649 bytes / 589 lines
```

For the development-line `START_SIGNAL_MVP` builder:

```text
Builder SHA256: 79D31C3DCE6833781BFECF5B87230B1C463483EA4F31A89D2431238D42A17C6F
First decoded layer: 181925 bytes / 589 lines
```

The first decoded layer contains only one direct `Age of the Ring` marker, in `TryCreateDesktopShortcut`, and no direct `AgeoftheRing`, `rotwk`, `lotrbfme2ep1.exe`, `game.dat`, `zGameDats`, `_AotR8P_WotR_Runtime`, `AOTR_HOME`, or repair-action markers.

Therefore the actual GUI/engine resolver and repair logic is still nested inside the first decoded C# layer, likely as another encoded/compressed payload or generated source/resource block.

## WHAT WE KNOW

Packaging hierarchy currently proven:

```text
V17 PowerShell builder
  -> Base64 `$template`
     -> C# wrapper source (589 lines)
        -> nested launcher payload/source still to be decoded
           -> expected GUI + engine + config + repair resolver logic
```

The first decoded C# layer is not itself sufficient evidence for resolver implementation.

The release and development builders both decode to 589 C# lines, but different byte lengths. That is consistent with the same wrapper structure carrying different nested payload data.

## EVIDENCE

Release first-layer audit:

```text
Decoded: 174649 bytes / 589 lines
Marker counts:
Age of the Ring = 1
Candidate declaration:
TryCreateDesktopShortcut
Direct hit line 568:
"Age of the Ring - 8 Player War of the Ring"
```

Development first-layer audit:

```text
Decoded: 181925 bytes / 589 lines
Marker counts:
Age of the Ring = 1
Candidate declaration:
TryCreateDesktopShortcut
Direct hit line 568:
"Age of the Ring - 8 Player War of the Ring"
```

No repair action hits were exposed in either first decoded layer.

## WHAT FAILED

The first embedded-template audit searched the decoded C# layer for resolver vocabulary but did not recurse into large nested encoded/compressed payloads.

This was not a false result: it proved that one more packaging layer exists.

## CURRENT HYPOTHESIS

The 589-line C# wrapper likely stores the real launcher code in one or more large encoded string/resource payloads and reconstructs or executes it at runtime.

The next safe step is recursive passive decoding/decompression only. No decoded content is to be executed.

## SAFE TESTS COMPLETED

- builder read-only hash verification;
- outer `$template` Base64 extraction;
- in-memory UTF-8 decoding;
- first-layer source marker inventory;
- no builder, launcher, game, config, registry, Git, or payload files modified.

## NEXT PRACTICAL ACTION

Run `AOTR_8P_RECURSIVE_EMBEDDED_AUDIT_V1.ps1` against both:

```text
LAN_UI_POLISH release source
START_SIGNAL_MVP development source
```

The helper recursively attempts Base64 decoding and passive GZip/Deflate decompression in memory, inventories nested nodes, and reports resolver/repair markers without executing decoded content.

## DO NOT REPEAT

- Do not search only the outer PowerShell builder for resolver strings.
- Do not stop after decoding the first `$template` Base64 layer.
- Do not interpret `TryCreateDesktopShortcut` as the AotR resolver.
- Do not execute any decoded nested payload during analysis.
- Do not write decoded payloads into the release or game directories.
