# Project Guardian State

Snapshot: 2026-08-27

This document records the current cross-component integration baseline. It is not a feature roadmap and does not replace detailed reverse-engineering checkpoints.

## STABLE

### Production launcher

- Version: `1.0.10`
- Main release commit: `1303e0a6b268b082e9352ded1461fa8d794f16d3`
- Launcher EXE SHA256: `6A80E0F7B862ABE3E0F19C3DF5ED9EE9EE730F246CF603ED00A39D1EE7DFF2F8`
- Authoritative repository builder: `launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_0_10.ps1`
- Validated local Windows builder SHA256: `7D847B66CAF060F3E1C5FD539DA3DF6E97865421651608CDD98898342C1BB2E0`

Validated production behavior includes the existing 8-player runtime path, FINAL_STABLE_V7, bounded Auto-Repair, `REPORT ERROR`, support fingerprints/bundles, ticket integration, launcher `MESSAGES`, and the normal-launch regression recorded in the V18 launcher checkpoint.

### Approved payload hashes

- `payload_ui.big`: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- `payload_paper.inc`: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`

## ACTIVE

### Robust AotR auto-detection

- Pull request: `#21`
- Branch: `feature/robust-aotr-autodetect`
- Status: `REVIEW_REQUIRED`
- Ownership: Launcher / Robustness

The branch was created from a pre-1.0.10 baseline and contains historical assumptions that the public launcher is 1.0.9 and that the authoritative builder is not present in `main`. Those assumptions are no longer current.

Before any production integration, robustness work must be reconciled against the V18/1.0.10 baseline and regression-tested without removing the 1.0.10 ticket-system, Auto-Repair, status-panel, Messages, or 8-player runtime behavior.

Research files already produced on the branch remain valuable and must not be discarded solely because their starting baseline became stale.

## CROSS-COMPONENT OWNERSHIP

| Component | Primary owner | Guardian rule |
| --- | --- | --- |
| Launcher path/install detection | Launcher / Robustness | Must integrate from current production launcher baseline |
| Auto-Repair / launcher process handling | Launcher / Robustness | Cross-component because ticket reporting consumes repair results |
| GitHub ticket creation/triage/clustering | Ticket System | Do not change launcher runtime unless coordinated |
| `REPORT ERROR` / support bundle / Messages | Ticket System + Launcher integration | Stable in 1.0.10; regression gate for future launcher builds |
| `game.dat`, WotR network/player logic, RAM patches | Reverse Engineering | Experimental results must remain isolated from release baseline until integration review |
| APT/UI/BIG research | Reverse Engineering | Preserve hashes and working references |
| Research checkpoints | Documentation / owning research task | Never delete based on filename/age alone |
| Cross-component release integration | Project Guardian | No direct promotion before consistency/regression review |

## CRITICAL SHARED FILES

Changes to any of the following require cross-task review before release integration:

- `AotR 8P WotR Mod.exe`
- `launcher-source/**`
- `manifest.json`
- `repair-manifest.json`
- `payload_ui.big`
- `payload_paper.inc`
- `.github/workflows/**`
- `.github/ISSUE_TEMPLATE/**`
- `.github/labels.yml`

Local equivalents of the launcher builder, runtime patch inputs, `game.dat`, BIG/APT payload sources, and packaging scripts are also shared integration surfaces even when they are newer than GitHub.

## SOURCES OF TRUTH

1. `main` is the source of truth for the currently versioned production release.
2. The exact release commit and SHA256 checkpoints identify the known working build.
3. Local reverse-engineering workspaces may contain newer research and experimental artifacts; they are additional evidence, not automatically production truth.
4. Reproducible runtime tests override older assumptions when the test conditions are documented.
5. Historical working builds and failed experiments remain references unless explicitly classified otherwise.

## CURRENT INTEGRATION GATES

A future launcher/robustness build must demonstrate at minimum:

- clean normal launch from a fresh isolated package;
- existing compatibility checks still pass;
- existing 8-player runtime patches and FINAL_STABLE_V7 still activate correctly;
- robust install detection works without selecting runtime/research/backup copies as production installs;
- ambiguous top candidates fail safely instead of choosing arbitrarily;
- Auto-Repair remains bounded and does not modify files while the game or another launcher/update operation owns them;
- `REPORT ERROR` appears only after repair exhaustion;
- support fingerprint/bundle behavior remains intact;
- launcher `MESSAGES` behavior remains intact;
- release EXE and payload hashes match the manifests;
- rollback to the 1.0.10 working reference remains possible.

## CLEANUP CLASSIFICATION

Current policy:

- `main` 1.0.10 release files: `KEEP / WORKING_REFERENCE`
- V18 final builder: `KEEP / WORKING_REFERENCE`
- V17 / 1.0.9 validated material: `RESEARCH_REFERENCE / ARCHIVE`, not delete-on-sight
- merged feature/fix branches: `REVIEW_REQUIRED` before any branch deletion
- `release/1.0.10`: `WORKING_REFERENCE` until a deliberate release-retention policy exists
- PR #21 research artifacts: `ACTIVE / RESEARCH_REFERENCE`
- unknown local or GitHub artifacts: `REVIEW_REQUIRED`

## OPEN GUARDIAN RISKS

- `main` currently lacks branch protection/rulesets.
- A `v1.0.10` tag/GitHub Release record has not yet been established.
- PR #21 must be reconciled against the V18/1.0.10 production baseline before merge.
- Release consistency should be enforced automatically so EXE/payload/manifest drift cannot be promoted silently.

See Guardian issue `#25` for the repository-protection and release-metadata task.
