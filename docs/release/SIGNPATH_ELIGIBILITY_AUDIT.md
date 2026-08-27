# SignPath Foundation eligibility audit

## Status

`REVIEW_REQUIRED / BLOCKED_ON_REPRODUCIBLE_OSS_SOURCE`

The project is pursuing the free SignPath Foundation route first for a signed successor to launcher 1.1.2.

## Confirmed SignPath Foundation constraints

The SignPath Foundation OSS program requires, among other things:

- an OSI-approved open-source license for all components of the project;
- no proprietary project components;
- only the project team's own binaries may be signed;
- signed binaries must be built from source code maintained by the project team;
- binary artifacts must be built from source in a verifiable way;
- every release signing request requires manual approval;
- a code-signing policy, team roles, and privacy statement must be published.

Reference: https://signpath.org/terms.html

## Current AotR 8P WotR blocker

The current canonical 1.1.2 V19 builder is not a fully source-hermetic build.

`launcher-source/v19/BUILD_LAUNCHER_1_1_2_CLEAN_CANDIDATE.ps1` requires a frozen 1.1.1 package as `FrozenDonorRoot` and verifies/extracts material from the frozen 1.1.1 EXE, including:

- launcher GUI script;
- launcher engine script;
- launcher skin;
- launcher icon;
- FINAL_STABLE_V7 resource;
- additional embedded GUI resources.

The builder then transforms those extracted resources and compiles the successor executable.

This is valid internal release provenance, but it is not yet the clean repository-source-to-binary chain expected for SignPath Foundation signing.

## Required free-path preparation

Before applying for SignPath Foundation signing:

1. Produce a donor-free launcher source tree where every byte intentionally embedded into the launcher is represented by maintained repository source/resource files or by clearly allowed system/upstream dependencies.
2. Identify which launcher-owned files the maintainer can legally license under an OSI-approved license.
3. Keep AotR/BFME third-party game/mod payloads outside the signable launcher OSS project boundary; do not relicense them.
4. Determine whether runtime patch resources (including V7 shellcode/patch logic) are project-owned source and acceptable under SignPath Foundation policy.
5. Add an OSS license only after ownership scope is explicitly confirmed. Do not place an OSS license over third-party AotR/BFME assets.
6. Add a SignPath-compliant code-signing policy, privacy statement, and team-role mapping.
7. Build a non-release successor from the donor-free source chain and verify behavior against frozen 1.1.2.
8. Only after the above, submit the project for SignPath Foundation review.

## Release boundary

- Frozen `v1.1.2` remains `WORKING_REFERENCE` and must not be modified in place.
- No signing key, PFX, token, certificate secret, or credential belongs in GitHub.
- A signed binary is a new version/hash and requires complete Guardian regression and fresh Windows 11 SAC/Defender testing.

Related: #52, #54, #50, #38.
