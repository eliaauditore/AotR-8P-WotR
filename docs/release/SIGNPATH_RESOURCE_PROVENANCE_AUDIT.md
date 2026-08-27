# SignPath resource provenance audit

Status: ACTIVE / REVIEW_REQUIRED

This audit records the **current technical origin** of resources embedded into the V19 launcher. It does not make legal ownership claims. Ownership/licensing must be confirmed separately before any OSS license or SignPath Foundation application.

## Current V19 provenance matrix

| Resource | Current build origin | Current provenance status | Free-signing action required |
| --- | --- | --- | --- |
| `launcher-source/v19/launcher.cs` | version-controlled C# template | SOURCE_CONTROLLED / RIGHTS_REVIEW_REQUIRED | confirm authorship/license eligibility; preserve as direct source input |
| launcher GUI PowerShell | extracted from frozen 1.1.1 EXE field `GuiGzipBase64`, then transformed by `prepare_clean_resources.py` and Issue43 transform | DONOR_DERIVED / RIGHTS_REVIEW_REQUIRED | recover/check in authoritative source text; stop extracting from donor EXE |
| launcher engine PowerShell | extracted from frozen 1.1.1 EXE field `EngineGzipBase64`, then transformed by `prepare_clean_resources.py` | DONOR_DERIVED / RIGHTS_REVIEW_REQUIRED | recover/check in authoritative source text; stop extracting from donor EXE |
| launcher skin PNG | extracted from frozen 1.1.1 EXE field `Issue33SkinGzipBase64` | DONOR_DERIVED / RIGHTS_REVIEW_REQUIRED | identify original source/author; check in only if rights permit |
| launcher icon | extracted from frozen 1.1.1 EXE using `ExtractAssociatedIcon` | DONOR_DERIVED / RIGHTS_REVIEW_REQUIRED | identify original source/author; replace with clearly owned asset if provenance cannot be established |
| row1/row2/row3/ready clean-patch PNGs | Base64 values extracted from donor-derived GUI script | DONOR_DERIVED / RIGHTS_REVIEW_REQUIRED | identify how images were created and whether they contain AotR/BFME artwork; replace with owned assets if needed |
| `final_stable_v7.ps1` | decoded from `FinalStableV7Base64` inside donor-derived engine script, then transformed by `prepare_final_stable_resource.py` | DONOR_DERIVED / RIGHTS_REVIEW_REQUIRED | recover/check in authoritative source script and remove donor extraction from build |
| `v7_shellcode.bin` | decoded from `$ShellcodeBase64` inside donor-derived FINAL_STABLE_V7 by `prepare_final_stable_resource.py` | DONOR_DERIVED_BINARY / POLICY_REVIEW_REQUIRED | reconstruct a source-controlled generation path or explicit authoritative binary source with documented authorship; review SignPath policy compatibility of runtime patch behavior |
| `payload_ui.big` | separate release payload, not compiled into launcher by the V19 C# resource list | OUTSIDE_SIGNED_LAUNCHER_SCOPE | keep outside launcher OSS signing scope unless separately cleared |
| `payload_paper.inc` | separate release payload, not compiled into launcher by the V19 C# resource list | OUTSIDE_SIGNED_LAUNCHER_SCOPE | keep outside launcher OSS signing scope unless separately cleared |

## Confirmed current build behavior

The V19 builder accepts a frozen 1.1.1 release directory and verifies exact hashes for the donor EXE and public payloads. It then:

1. loads the donor EXE as a .NET assembly;
2. extracts embedded GUI, engine and skin constants;
3. extracts the donor icon;
4. extracts clean-patch PNG Base64 values from the GUI;
5. decodes FINAL_STABLE_V7 from the engine;
6. extracts the V7 shellcode from FINAL_STABLE_V7;
7. transforms the scripts/resources;
8. compiles the new launcher with those resources embedded.

This chain is useful historical/release evidence and must be preserved, but it should not be the signing build for a SignPath Foundation application.

## Required free-signing conversion

Create a new successor build path in which every input to the signed EXE is either:

- direct, version-controlled source owned/licensable by the launcher project; or
- deterministically generated from such source by version-controlled build scripts.

The new path must not require a previous release EXE to recover source/resources.

### Minimum conversion checklist

- [ ] authoritative GUI script checked into source control
- [ ] authoritative engine script checked into source control
- [ ] authoritative FINAL_STABLE_V7 source checked into source control
- [ ] V7 shellcode provenance/generation documented and reviewed
- [ ] launcher skin provenance established or replaced with owned asset
- [ ] launcher icon provenance established or replaced with owned asset
- [ ] clean-patch image provenance established or replaced with owned assets
- [ ] donor-free build reproduces required launcher behavior
- [ ] donor-free build gets fresh non-release runtime regression
- [ ] only after rights review: choose OSI license for launcher-only scope
- [ ] only after donor-free provenance passes: create separate launcher-only OSS repository/signing scope
- [ ] document SignPath Code signing policy, privacy statement, roles and approvals
- [ ] submit SignPath Foundation application

## Guardian boundary

The donor-based V19 pipeline remains a protected working/research reference. Do not delete it when the donor-free signing pipeline is introduced. A donor-free build is a successor path, not a rewrite of release history.

Related: #65, #52, #54, #50, #38.
