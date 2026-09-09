# V19 donor-free successor

Status: `NON_RELEASE / ISSUE #68 ACTIVE`

This directory is the successor build path for the launcher after frozen `v1.1.2`.

## Hard safety boundary

Frozen launcher `1.1.2` is immutable:

- release commit: `131aacd19f8ea02399db6ad0dab69c4253fbe834`
- protected tag: `v1.1.2`
- runtime-tested EXE SHA256: `5B4D12B7BF43D72860E27C51A3D8AC7AC00CA53DB58499E41AC735F7B7ECED0E`

Nothing in this directory replaces, rebuilds or republishes that release.

The historical donor-based V19 builder under `launcher-source/v19/**` remains a protected provenance/reference path and is deliberately not deleted or rewritten.

## What donor-free means here

`BUILD_LAUNCHER_DONOR_FREE_CANDIDATE.ps1` accepts no `FrozenDonorRoot` and does not load/extract a previous launcher EXE.

Its signed-EXE inputs are version-controlled paths only:

- `launcher-source/v19/launcher.cs`
- `launcher-source/v19-successor/resources/launcher_gui.ps1`
- `launcher-source/v19-successor/resources/launcher_engine.ps1`
- `launcher-source/v19-successor/resources/launcher_skin.png`
- `launcher-source/v19-successor/resources/launcher.ico`
- `launcher-source/v19-successor/resources/final_stable_v7.ps1`
- `launcher-source/v19-successor/resources/v7_shellcode.bin`
- four maintained patch PNGs
- a native application manifest generated directly by the builder
- Windows/.NET Framework compiler/runtime system dependencies

The builder verifies every maintained resource by SHA256, verifies the V7 resource chain, compiles the nine managed resources plus PE icon/manifest, then verifies the exact embedded resource names and hashes in the resulting EXE.

## Five-file test package versus signed-launcher scope

The non-release builder also creates a complete five-file package for runtime parity testing. `payload_ui.big` and `payload_paper.inc` are copied from the repository root after exact SHA verification.

Those two AotR/BFME payloads are **not embedded into the EXE** and remain outside the launcher-only signing/OSS boundary.

## Ownership is not inferred from source control

Moving a byte into Git does not make it project-owned or open source.

`RESOURCE_OWNERSHIP.json` is the authoritative classification gate for this path. In particular:

- the Age of the Ring branded launcher skin is third-party AotR/BFME content and must be replaced/cleared before a Foundation OSS signing scope;
- icon and four visual cleanup patches remain `REVIEW_REQUIRED` until provenance is proven or replacements are created;
- FINAL_STABLE_V7 and the V7 shellcode remain `REVIEW_REQUIRED` for byte provenance and SignPath policy review;
- GUI/engine sources are now maintained directly but formal rights/license provenance still requires confirmation before an OSS grant.

Therefore **donor-free does not yet mean SignPath Foundation eligible**.

## Candidate identity

Default development identity:

`1.1.3-donorfree-dev1`

This is intentionally a successor/non-release version. It must never be written to root `manifest.json`, root `repair-manifest.json`, the protected `v1.1.2` tag/release, or ModDB.

## Acceptance sequence

1. Materialize the exact verified V19 clean provenance resources once into `resources/**`.
2. Build on GitHub-hosted Windows with no donor EXE/root and no local research path.
3. Record candidate EXE/ZIP hashes and resource-chain proof.
4. Run protected Guardian CI on the PR.
5. Run fresh standalone/runtime regression on the exact candidate: launcher, Auto-Repair/recheck, START, game handoff, 8P rows, zoom/drag and runtime patch path.
6. Separately resolve every `REVIEW_REQUIRED` or third-party resource before any OSI license or SignPath Foundation application.
7. Signing/release work remains under parent #52 and requires a new release identity.

Related: #68, #52, #54, #50, #38.
