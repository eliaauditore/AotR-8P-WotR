# AotR 8P WotR — Main-PC Builder Discovery Result

Date: 2026-08-27 (Europe/Berlin)
Branch: `feature/robust-aotr-autodetect`
Status: DISCOVERY COMPLETE / SOURCE LINEAGE NOT YET PROVEN

## STATUS

The read-only main-PC source audit successfully located the known V17 launcher builders in the canonical research workspace.

The previously recorded checkpoint hashes for `START_SIGNAL_MVP` and `GLOBAL_LOBBY_MVP` were reproduced exactly. The full `MULTIPLAYER_EXACT` SHA256 was recovered. `LAN_UI_POLISH` was also located both as a working copy and inside a directory explicitly named for release `1.0.9`.

No builder has been selected as the robust-autodetect integration base yet. Selection remains evidence-driven.

## WHAT WE KNOW

Canonical research workspace root observed:

```text
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD
```

A separately created autodetect source checkpoint exists at:

```text
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_SOURCE_CHECKPOINT_20260827_000809
```

This checkpoint contains byte-identical copies of at least `START_SIGNAL_MVP` and `LAN_UI_POLISH`; it is not to be mistaken for the live working source.

A release-specific source copy exists at:

```text
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\RELEASE_1_0_9_UI_POLISH_20260822_183040
```

That directory contains `BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_LAN_UI_POLISH.ps1`, strongly tying that builder variant to the public `1.0.9` release lineage. This is strong evidence, but the generated EXE ancestry still needs to be checked before calling it mathematically proven.

Source inspection on 2026-08-27 also established that both the `LAN_UI_POLISH` release-source copy and `START_SIGNAL_MVP` working copy declare the same builder parameter default:

```powershell
[string]$LauncherVersion = "1.0.0"
```

Therefore the builder source's parameter default cannot be used to identify the actual produced launcher release. The public `1.0.9` version was evidently supplied externally at build invocation and/or by surrounding release tooling. This makes source lineage, release-directory evidence, hashes and generated-artifact ancestry more authoritative than that default value.

## EVIDENCE

### START_SIGNAL_MVP — working copy

```text
Path:
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_START_SIGNAL_MVP.ps1

Length: 258905
LastWriteTime: 2026-08-23 15:12:04
SHA256: 79D31C3DCE6833781BFECF5B87230B1C463483EA4F31A89D2431238D42A17C6F
CheckpointMatch: EXACT_MATCH
```

### START_SIGNAL_MVP — autodetect checkpoint copy

```text
Path:
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_SOURCE_CHECKPOINT_20260827_000809\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_START_SIGNAL_MVP.ps1

Length: 258905
LastWriteTime: 2026-08-23 15:12:04
SHA256: 79D31C3DCE6833781BFECF5B87230B1C463483EA4F31A89D2431238D42A17C6F
CheckpointMatch: EXACT_MATCH
```

The working copy and checkpoint copy are byte-identical by SHA256.

### GLOBAL_LOBBY_MVP

```text
Path:
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_GLOBAL_LOBBY_MVP.ps1

Length: 257283
LastWriteTime: 2026-08-23 14:59:13
SHA256: BAC0A4E8381919DA80B6FB98CEB258343DD481BE4F940EBDB401579ACDE99473
CheckpointMatch: EXACT_MATCH
```

### MULTIPLAYER_EXACT

```text
Path:
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_MULTIPLAYER_EXACT.ps1

Length: 253487
LastWriteTime: 2026-08-23 14:16:45
SHA256: 082967B350022B7E1202A812DBFB3EB5655EBEE28EF10EF87D3CD81B4BFAA25B
CheckpointMatch: PREFIX_AND_LENGTH_MATCH
```

This recovers the previously incomplete full SHA256.

### LAN_UI_POLISH — working copy

```text
Path:
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_LAN_UI_POLISH.ps1

Length: 249043
LastWriteTime: 2026-08-22 18:30:40
SHA256: 5F806FB048BF7761252AC9D7B557B0177D71C3E9FFEA1E9003CD4DC300867E2C
CheckpointMatch: NO_KNOWN_CHECKPOINT
```

### LAN_UI_POLISH — autodetect checkpoint copy

```text
Path:
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_SOURCE_CHECKPOINT_20260827_000809\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_LAN_UI_POLISH.ps1

Length: 249043
LastWriteTime: 2026-08-22 18:30:40
SHA256: 5F806FB048BF7761252AC9D7B557B0177D71C3E9FFEA1E9003CD4DC300867E2C
CheckpointMatch: NO_KNOWN_CHECKPOINT
```

### LAN_UI_POLISH — release 1.0.9 source copy

```text
Path:
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\RELEASE_1_0_9_UI_POLISH_20260822_183040\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_LAN_UI_POLISH.ps1

Length: 249043
LastWriteTime: 2026-08-22 18:30:40
SHA256: 5F806FB048BF7761252AC9D7B557B0177D71C3E9FFEA1E9003CD4DC300867E2C
CheckpointMatch: NO_KNOWN_CHECKPOINT
```

All three observed `LAN_UI_POLISH` copies are byte-identical by SHA256.

### LauncherVersion source inspection

`LAN_UI_POLISH` release-source copy:

```text
line 7: [string]$LauncherVersion = "1.0.0"
lines 17-20: numeric-version validation
lines 2029-2030: LauncherVersion injected into generated source/template
line 2095: launcher_version = $LauncherVersion
line 2122: generated_for_launcher = $LauncherVersion
```

`START_SIGNAL_MVP` working copy:

```text
line 7: [string]$LauncherVersion = "1.0.0"
lines 17-20: numeric-version validation
lines 2110-2111: LauncherVersion injected into generated source/template
line 2176: launcher_version = $LauncherVersion
line 2203: generated_for_launcher = $LauncherVersion
```

Interpretation: the default is shared builder scaffolding and does not prove produced release version or branch ancestry.

## WHAT FAILED

Nothing failed in builder discovery.

The first source-comparison output did not surface the resolver sections in the pasted terminal excerpt; only the final version-marker section was captured. This is an output/presentation issue, not evidence that resolver markers are absent. The next query should print the resolver/action evidence in smaller explicit blocks.

The audit also revealed that duplicate builder names are expected because checkpoint/release copies are present. Therefore file name and LastWriteTime alone are insufficient for source selection.

## CURRENT HYPOTHESIS

Current evidence supports two different concepts that must not be conflated:

1. **Public 1.0.9 release ancestry candidate:** `LAN_UI_POLISH`, because an identical builder is stored under `RELEASE_1_0_9_UI_POLISH_20260822_183040`.
2. **Newest known development-line candidate:** `START_SIGNAL_MVP`, because it is the newest checkpointed V17 working builder currently found and has an exact known hash.

The identical `LauncherVersion = "1.0.0"` default in both builders neither proves nor disproves ancestry. It should be ignored for builder selection unless the actual build invocation is recovered.

The robust autodetect integration base should be chosen only after source-level lineage comparison. If later development builders contain all current release behavior plus subsequent features, the integration base may be the newest canonical descendant rather than the historical 1.0.9 release builder.

## FILES / HASHES / OFFSETS

No binary offsets are involved in this stage.

Known builder SHA256 values are recorded above. In particular, the previously incomplete `MULTIPLAYER_EXACT` hash is now:

```text
082967B350022B7E1202A812DBFB3EB5655EBEE28EF10EF87D3CD81B4BFAA25B
```

Newly checkpointed `LAN_UI_POLISH` SHA256:

```text
5F806FB048BF7761252AC9D7B557B0177D71C3E9FFEA1E9003CD4DC300867E2C
```

## SAFE TESTS COMPLETED

- read-only recursive V17 builder discovery under approved research roots;
- SHA256 calculation;
- size and LastWriteTime capture;
- checkpoint comparison;
- duplicate-copy identification by exact SHA256;
- read-only source search for version markers;
- no launcher, builder, game, registry, config, or payload files modified by the audit.

## NEXT PRACTICAL ACTION

Inspect source markers in both:

1. the `LAN_UI_POLISH` release-1.0.9 copy;
2. the `START_SIGNAL_MVP` working copy.

Print these in compact, separate blocks rather than one large terminal dump:

```text
candidate resolver functions
AOTR_HOME / AgeoftheRing / lotrbfme2ep1.exe hits
runtime / game.dat / zGameDats hits
repair action occurrences and enclosing functions
config markers
```

Then compare the two source variants to establish ancestry and select the canonical integration base.

## DO NOT REPEAT

- Do not treat `AUTODETECT_SOURCE_CHECKPOINT_20260827_000809` as the live builder workspace.
- Do not choose a builder because it is merely the newest file.
- Do not assume the public 1.0.9 source and newest development source are the same thing.
- Do not use the builder's default `LauncherVersion = "1.0.0"` as release identification.
- Do not edit any of the checkpoint/release copies.
- Do not patch the public EXE to test resolver ideas.
- Do not integrate robust autodetect until both GUI and engine resolver locations are proven in the chosen builder.

## OPEN RISKS

- `LAN_UI_POLISH` is strongly associated with release 1.0.9 by directory naming and byte-identical source, but generated-EXE ancestry has not yet been independently verified.
- `START_SIGNAL_MVP` may be a newer experimental/development descendant; exact feature ancestry relative to public 1.0.9 still needs source comparison.
- the actual invocation that supplied `LauncherVersion = 1.0.9` has not yet been recovered.
- the internal repair dispatcher/allowlist is still unproven until the builder inspection is completed.
