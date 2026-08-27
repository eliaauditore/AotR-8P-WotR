# Launcher 1.1 Release Checkpoint

Checkpoint date: 2026-08-27

Purpose: preserve the exact launcher 1.1 production identity and the already-completed robustness/promotion evidence in one versioned location. This checkpoint does not replace older detailed research records and does not claim tests that were not recorded.

## Frozen production identity

- Release version: `1.1`
- Release commit: `bbd7eff483d2cdbf3e799f764433b49195dc55b6`
- Release tag: `v1.1`
- Launcher EXE SHA256: `9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4`
- Launcher EXE size at Stage 10 production checkpoint: `691712` bytes
- Canonical repository builder: `launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1.ps1`
- Canonical builder commit: `7072e19bd43a350da0344b1b5e32ab9d052b3404`
- Final local builder SHA256 recorded by the robustness completion work: `2E19020B0B0C73C29E8C1F4FC4A13FD940A7C6FA9A2CA6274BF08B55A34FF665`

Approved release payload hashes:

- `payload_ui.big`: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- `payload_paper.inc`: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`

Recorded final production component hashes from the robustness completion work:

- GUI: `23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C`
- engine: `94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA`
- skin: `BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6`

## Robustness resolver matrix

Before final production promotion, the Stage 4 resolver matrix covered the intended path-selection classes, including:

- canonical internal/fixed-drive installation;
- alternate / USB-like candidates;
- multiple-candidate ranking and tie behavior;
- cached Config V2 including stale/moved rediscovery behavior;
- operation without `AOTR_HOME`;
- rejection/deprioritization rules for All-in-One, research and runtime copies.

Recorded Stage 4 core result:

- cases: `29`
- failures: `0`
- result: `PASS`

This validates the robustness resolver behavior exercised by that test matrix. Historical scripts and detailed evidence remain preserved under `research/installer/**`.

## Stage 10 production gate

Recorded result: `PASS`.

The production build produced the exact final EXE SHA256 used by the release:

`9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4`

The Stage 10 record also tied that build to the final GUI/skin identities above.

## Stage 11 final five-file promotion gate

Recorded result: `PASS`.

The exact final production EXE above was launched in an isolated runtime/config environment before promotion. Recorded observations included:

- exact production EXE identity matched the final hash;
- launcher process completed successfully (`exit code 0` recorded for the gate run);
- launcher displayed version `1.1`;
- custom top bar with minimize/close controls was present;
- status panel was present;
- `MESSAGES` UI was present;
- minimize/close behavior was exercised;
- isolated Config V2 behavior was exercised;
- the real config remained unchanged;
- repository/release-root mutation outside the controlled promotion set was not performed.

Recorded release metadata identities for the Stage 11 gate:

- manifest SHA256: `61B559D2AEAB72DE2ECB9BF0F2F1E437D2742C34947CA9B414CD7390AAEAA38A`
- repair manifest SHA256: `684B8B4F39EE7ADB97D4C0837036F742D67C28B0EFC86A2006043BB2B3C36685`

The gate concluded that launcher 1.1 was ready for five-file production promotion.

## Repository integrity gate

After the release was promoted, `Validate Release Consistency` independently verified the repository release set:

- launcher version is `1.1`;
- `repair-manifest.json` targets the same launcher version;
- EXE SHA256 matches `manifest.json`;
- UI SHA256 matches `manifest.json`;
- PaperScenario SHA256 matches `manifest.json`;
- a FINAL builder matching version 1.1 exists;
- repair-manifest actions are within the Guardian-approved known action set.

Result: `PASS`.

The `v1.1` tag and GitHub Release were subsequently created against the frozen release commit without rebuilding or replacing the production files.

## Evidence boundary

The evidence above proves the exact final 1.1 artifact identity, the 29/29 robustness resolver matrix, the Stage 10 production build gate, the Stage 11 exact-final-EXE launcher/config promotion gate, and repository hash/metadata consistency.

A separate versioned record showing the exact final 1.1 EXE hash being used for a complete **START -> AotR/game process -> 8P runtime/FINAL_STABLE_V7** in-game smoke path was not found during the Guardian audit. Therefore this checkpoint does **not** claim that specific exact-final-hash in-game run.

The previously validated 1.0.10 normal-launch/runtime path remains a historical rollback reference; it is not silently substituted as proof for an unrecorded 1.1 in-game run.

## Retention / rollback

Keep:

- launcher 1.1 release commit/tag/hash as `STABLE / WORKING_REFERENCE`;
- launcher 1.0.10 final release evidence as `HISTORICAL_ROLLBACK / WORKING_REFERENCE`;
- V17 / launcher 1.0.9 material as `RESEARCH_REFERENCE / ARCHIVE`;
- `research/installer/**` as `RESEARCH_REFERENCE / KEEP`.

Do not rewrite or delete historical checkpoints merely because launcher 1.1 is current.
