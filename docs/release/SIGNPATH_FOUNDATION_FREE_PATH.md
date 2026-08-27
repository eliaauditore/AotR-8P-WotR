# SignPath Foundation free signing path

## Decision

The preferred zero-cost signing path for a successor to launcher 1.1.2 is **SignPath Foundation**, but the current repository/package is **not eligible as-is**.

This document is a Guardian eligibility and source-provenance gate. It does not grant a license to third-party AotR/BFME content and it does not modify any frozen release artifact.

## Current SignPath Foundation requirements

For the free Foundation certificate path, the signing project must use an OSI-approved license for all project components, contain no proprietary/non-open-source components, sign only binaries built from the project's own maintained source, use a verifiable trusted build/origin chain, and require manual approval for releases.

The project must also publish a code-signing policy, identify signing roles, use repository/source MFA, document privacy/network behavior, and provide appropriate install/uninstall guidance where applicable.

## Current repository verdict

### Whole AotR-8P-WotR repository/package

**NOT ELIGIBLE AS-IS / DO NOT APPLY YET**

Reason:

- there is currently no top-level OSI license;
- the repository/package contains AotR/BFME-derived payloads and other third-party/proprietary material that this project cannot simply relicense;
- those components must not be swept under an OSS license merely to satisfy signing eligibility.

### Current launcher V19 build chain

**NOT ORIGIN-CLEAN AS-IS**

`launcher-source/v19/BUILD_LAUNCHER_1_1_2_CLEAN_CANDIDATE.ps1` still requires a frozen 1.1.1 release directory as a donor. It extracts the skin, icon, GUI script, engine script, clean-row images and FINAL_STABLE_V7 content from the frozen donor executable before creating the 1.1.2 candidate. `prepare_final_stable_resource.py` then extracts the V7 shellcode resource from that recovered script.

That historical chain is valuable release/research evidence and must be preserved, but it is not the desired source-of-origin chain for a Foundation-signed successor.

## Zero-cost target architecture

Create a **launcher-only OSS signing project/source boundary** that contains only material we are legally able to publish under an OSI-approved license.

The signed artifact should be the launcher EXE only. Its complete build inputs must be source-controlled and attributable:

- launcher C# source;
- launcher GUI/engine PowerShell source;
- launcher-owned artwork/icon or separately licensed compatible replacements;
- launcher-owned runtime patch definitions represented as source/data only after provenance review;
- deterministic resource-generation scripts;
- deterministic build workflow;
- SignPath artifact configuration/policy.

AotR/BFME game/mod payloads must remain outside that OSS signing boundary unless their licensing explicitly permits inclusion.

## Provenance blockers to resolve before adding an OSS license

- [ ] Replace frozen-donor extraction of launcher GUI and engine with checked-in canonical source.
- [ ] Replace frozen-donor extraction of launcher skin/icon and row images with source-controlled assets whose ownership/license is documented.
- [ ] Trace `FINAL_STABLE_V7` and `v7_shellcode.bin` to their actual authored source/provenance.
- [ ] Determine whether any embedded shellcode/patch resource contains copied EA/AotR executable bytes versus original patch logic/data.
- [ ] Convert eligible patch resources into transparent source/data generation where possible.
- [ ] Prove a clean GitHub-hosted build can create the unsigned launcher without any donor EXE, local research path, manually supplied binary, or hidden CI input.
- [ ] Only after provenance is known, choose an OSI license for the launcher-owned source. Do **not** license third-party game/mod assets.

## Guardian release rules

- Frozen `v1.1.2` remains immutable.
- Historical donor builders remain `WORKING_REFERENCE / RESEARCH_REFERENCE`; do not delete them when the donor-free successor exists.
- The donor-free build is a **non-release successor candidate** until runtime, Defender and SAC fresh-download tests pass.
- No SignPath application should be submitted until the launcher-only source boundary passes the provenance audit.
- No private signing material or SignPath token may be committed to the repository.

## Related

- #38 Defender/reputation history
- #50 confirmed Smart App Control / Mark-of-the-Web behavior
- #52 trusted Authenticode master task
- #54 signing identity / free-path eligibility
