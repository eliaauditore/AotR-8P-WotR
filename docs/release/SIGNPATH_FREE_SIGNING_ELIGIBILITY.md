# SignPath Foundation free-signing eligibility

Status: REVIEW_REQUIRED / preparation only

## Goal

Make a future launcher successor eligible for a SignPath Foundation free Open Source signing application without modifying or rewriting the frozen 1.1.2 release.

## Confirmed blockers in the current build chain

The current V19 1.1.2 build path is not yet a clean Source -> Binary provenance chain suitable for a SignPath Foundation application:

- `launcher-source/v19/BUILD_LAUNCHER_1_1_2_CLEAN_CANDIDATE.ps1` consumes the frozen 1.1.1 EXE as a donor.
- It extracts embedded GUI, engine, launcher skin, icon and clean-patch image resources from the donor artifact.
- It derives `final_stable_v7.ps1` and `v7_shellcode.bin` through the donor/resource transformation chain.
- The resulting EXE embeds launcher skin, GUI script, engine script, FINAL_STABLE_V7 and V7 shellcode resources.
- The repository also contains AotR/BFME-related release payloads that must not be casually relicensed under an OSI license.

Therefore a top-level LICENSE on the current repository would not, by itself, make the project eligible and must not be added as a shortcut.

## Free-signing target architecture

A SignPath candidate should be a separately scoped launcher project/repository containing only material that the project is allowed to license as Open Source and that is needed to build the signed launcher binary.

Required properties:

1. No frozen EXE donor input.
2. Every embedded launcher resource has a source-controlled origin.
3. Every source-controlled resource has an explicit provenance classification: `OWN_SOURCE`, `THIRD_PARTY_OSS`, `PROPRIETARY`, or `UNKNOWN`.
4. `PROPRIETARY` and `UNKNOWN` material must not be included in the SignPath-signed binary unless eligibility and rights are explicitly established.
5. Build scripts and CI configuration are source controlled and determine the artifact without hidden/manual donor inputs.
6. The signed artifact is the launcher binary only; AotR/BFME payload distribution remains outside the launcher OSS license/signing scope unless separately cleared.
7. The launcher project uses an OSI-approved license only after ownership/provenance review is complete.
8. A public Code signing policy, privacy statement, team roles and manual signing approval workflow are documented before application.

## Provenance audit required before repository split

Audit these embedded resources first:

- `launcher-source/v19/launcher.cs`
- launcher GUI PowerShell
- launcher engine PowerShell
- launcher skin PNG
- launcher icon
- row/ready clean-patch PNG resources
- `final_stable_v7.ps1`
- `v7_shellcode.bin`

For each resource record:

- exact source path or generation recipe
- current hash
- author/origin
- whether it contains or derives from EA/BFME/AotR proprietary material
- whether it can legally and technically be placed under the launcher OSS license
- whether SignPath Foundation policy is compatible with its function

## Guardian rules

- Do not modify `v1.1.2` or its release artifacts.
- Do not add a blanket OSS license over the current mixed repository.
- Do not delete donor/history artifacts while provenance is being reconstructed.
- Do not apply to SignPath Foundation until the Source -> Binary chain is reproducible from the scoped OSS repository.
- Do not claim SignPath acceptance in advance; the Foundation makes the eligibility decision.

Related: #52, #54, #50, #38.
