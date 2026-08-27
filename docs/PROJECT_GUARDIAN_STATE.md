# Project Guardian State

Snapshot: 2026-08-27

This document records the current cross-component integration baseline. It is not a feature roadmap and does not replace detailed reverse-engineering checkpoints.

## STABLE

### Production launcher

- Version: `1.1`
- Release commit: `bbd7eff483d2cdbf3e799f764433b49195dc55b6`
- Canonical 1.1 builder commit: `7072e19bd43a350da0344b1b5e32ab9d052b3404`
- Launcher EXE SHA256: `9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4`
- Authoritative repository builder: `launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1.ps1`
- Release Consistency workflow on the canonical 1.1 builder commit: `PASS`

The automated integrity gate confirms that the versioned 1.1 EXE, manifests, payload hashes, FINAL builder presence and known repair-action set are internally consistent.

Important distinction: repository/file integrity is proven, but the Project Guardian has not found a versioned checkpoint that explicitly ties the exact final 1.1 EXE hash above to the complete normal-launch/runtime regression matrix. Until such evidence is recorded, the exact-final-EXE runtime regression remains `REVIEW_REQUIRED` rather than being inferred from hash consistency alone.

### Approved payload hashes

- `payload_ui.big`: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- `payload_paper.inc`: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`

## COMPLETED / INTEGRATED

### Robust AotR auto-detection

- Pull request: `#21`
- Former branch: `feature/robust-aotr-autodetect`
- Status: `COMPLETED / INTEGRATED`
- Ownership: Launcher / Robustness
- Research location: `research/installer/**`

Before final integration, Guardian PR #28 synchronized the robustness branch to the current 1.1 production baseline without rebasing or rewriting its research history. After that sync the branch was `67` commits ahead / `0` behind `main`, with all branch-only changes confined to additions under `research/installer/**`.

PR #21 was then merged as a research/documentation integration. The merge did not replace the 1.1 EXE, manifests, payloads, canonical launcher builder, ticket workflows or Guardian release files.

Historical statements inside robustness checkpoints that refer to 1.0.9, 1.0.10, V17 or earlier V18 states remain valid evidence of the state when those experiments were performed. Do not silently rewrite them as if they described the current release.

## CROSS-COMPONENT OWNERSHIP

| Component | Primary owner | Guardian rule |
| --- | --- | --- |
| Launcher path/install detection | Launcher / Robustness | Integrated in the 1.1 workstream; future changes start from current production baseline |
| Auto-Repair / launcher process handling | Launcher / Robustness | Cross-component because ticket reporting consumes repair results |
| GitHub ticket creation/triage/clustering | Ticket System | Do not change launcher runtime unless coordinated |
| `REPORT ERROR` / support bundle / Messages | Ticket System + Launcher integration | Regression gate for future launcher builds |
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

Local equivalents of the launcher builder, runtime patch inputs, `game.dat`, BIG/APT payload sources and packaging scripts are also shared integration surfaces even when they are newer than GitHub.

## SOURCES OF TRUTH

1. `main` is the source of truth for currently versioned project/release files.
2. The exact release commit and SHA256 checkpoints identify a release artifact independently of later documentation/research merges to `main`.
3. Local reverse-engineering workspaces may contain newer research and experimental artifacts; they are additional evidence, not automatically production truth.
4. Reproducible runtime tests override older assumptions when the test conditions and tested hash are documented.
5. Historical working builds and failed experiments remain references unless explicitly classified otherwise.

## CURRENT INTEGRATION GATES

A future launcher build must demonstrate at minimum:

- clean normal launch from a fresh isolated package;
- existing compatibility checks still pass;
- existing 8-player runtime patches and FINAL_STABLE_V7 still activate correctly;
- robust install detection does not select runtime/research/backup copies as production installs;
- ambiguous top candidates fail safely instead of choosing arbitrarily;
- Auto-Repair remains bounded and does not modify files while the game or another launcher/update operation owns them;
- `REPORT ERROR` appears only after repair exhaustion;
- support fingerprint/bundle behavior remains intact;
- launcher `MESSAGES` behavior remains intact;
- release EXE and payload hashes match the manifests;
- the exact final EXE hash used for release is tied to the recorded runtime regression result;
- rollback to the 1.1 working reference remains possible, with 1.0.10 retained as a historical rollback reference.

## CLEANUP CLASSIFICATION

Current policy:

- launcher 1.1 release EXE/manifests/payloads: `KEEP / WORKING_REFERENCE`
- `BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1.ps1`: `KEEP / WORKING_REFERENCE`
- launcher 1.0.10 final builder/release evidence: `WORKING_REFERENCE / HISTORICAL_ROLLBACK`
- V17 / 1.0.9 validated material: `RESEARCH_REFERENCE / ARCHIVE`, not delete-on-sight
- `research/installer/**`: `RESEARCH_REFERENCE / KEEP`
- merged feature/fix branches: `REVIEW_REQUIRED` before any branch deletion
- unknown local or GitHub artifacts: `REVIEW_REQUIRED`

## OPEN GUARDIAN RISKS

### HIGH

- `main` currently lacks branch protection/rulesets. Direct release-changing pushes can bypass PR review despite the consistency workflow running afterward.

### MEDIUM

- Only tag `v1.0.9` currently exists; no `v1.0.10` or `v1.1` release tag is present.
- No GitHub Release record currently exists for 1.1.
- No versioned checkpoint was found that explicitly proves the complete runtime regression against exact final 1.1 EXE SHA256 `9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4`.

### LOW

- The canonical 1.1 builder inherits a top source comment that still says `V18 FINAL 1.0.10`, while its actual `LauncherVersion` parameter is `1.1`. This is non-functional source-comment metadata. Do not mutate the canonical released builder solely to cosmetically correct the comment; record/fix it in the next deliberate builder revision instead.

See Guardian issue `#25` for repository-protection and release-metadata follow-up.
