# AotR 8P WotR GitHub Ticket System

GitHub Issues is the canonical support and defect tracker for the AotR 8 Player War of the Ring project.

## Workflow

**Player Report → GitHub Issue → Triage → Fingerprint / error class → Diagnosis → Fix or repair-manifest extension → Retest → Closed**

1. **Player Report** — The player chooses the issue form that matches the problem and provides versions, exact errors, hashes, logs, and a support fingerprint when available.
2. **GitHub Issue** — The report becomes a durable ticket that can be searched by `A8P-*` error code or `A8P-FP-*` fingerprint.
3. **Triage** — New issues start with `needs-triage`. Automation classifies obvious launcher, multiplayer, payload, UI, paper, compatibility, engine, and auto-repair cases.
4. **Fingerprint / error class** — Reports with the same stable fingerprint are treated as candidates for one root-cause class even if the visible wording differs.
5. **Diagnosis** — Compare environment, file hashes, repair actions, logs, and reproduction steps. Confirm whether the problem is deterministic and whether multiple reports are true duplicates.
6. **Fix or repair-manifest extension** — Fix source/packaging code when the defect belongs there. If the problem is safe and deterministic to repair locally, add or extend a stable repair rule.
7. **Retest** — Reproduce the original failure, execute the fix/repair path, and verify launch plus relevant multiplayer behavior.
8. **Closed** — Close only after the fix is verified or the report is intentionally classified as duplicate / cannot reproduce / not planned.

## Stable error codes

The existing `repair-manifest.json` is the starting vocabulary for launcher repair classes:

- `A8P-INSTALL-001`
- `A8P-PAYLOAD-UI-001`
- `A8P-PAYLOAD-PAPER-001`
- `A8P-LEGACY-001`
- `A8P-PROCESS-001`
- `A8P-RUNTIME-001`
- `A8P-GAMEPROC-001`
- `A8P-PERMISSION-001`
- `A8P-COMPAT-001`
- `A8P-ENGINE-001`

Do not recycle an existing ID for a materially different failure class. New stable IDs should remain machine-readable and should map to deterministic detection logic.

## Support fingerprint

Canonical format:

`A8P-FP-XXXXXXXXXXXX`

The 12-character suffix should be uppercase hexadecimal derived from a normalized, non-personal error signature. The fingerprint is an **error-class key**, not a machine identifier.

Recommended normalized inputs include:

- stable `A8P-*` error code;
- failing subsystem/action;
- normalized exception/error family;
- relevant expected/actual integrity state;
- game/launcher compatibility class when it changes root cause.

Do **not** include username, home path, IP/MAC address, machine name, Discord/GitHub account, or another personal identifier in fingerprint material.

A future launcher implementation can hash the canonical signature (for example SHA-256) and use the first 12 uppercase hexadecimal characters.

## Duplicate handling

Search both the `A8P-*` code and the fingerprint before diagnosing a new report. The same fingerprint is strong duplicate evidence, but do not auto-close solely on the fingerprint if environment differences could indicate separate root causes.

For a duplicate:

1. link the canonical issue;
2. preserve any new logs/hash evidence;
3. apply `duplicate`;
4. close with the duplicate reason.

## From manual fix to repair-manifest rule

A recurring manual fix becomes an auto-repair candidate only when all of the following are true:

1. the failure can be detected without guesswork;
2. the repair action is safe, bounded, and reversible or reconstructable;
3. the action does not destroy user-created data;
4. success/failure can be verified after the action;
5. repeating the action is idempotent or otherwise safe;
6. the original failure and the post-repair state can be represented in the support bundle;
7. the rule is tested against a clean install and at least one intentionally broken state.

Implementation path:

1. identify the canonical issue and stable fingerprint;
2. define or reuse the `A8P-*` error code;
3. encode deterministic detection;
4. add the smallest safe action sequence to `repair-manifest.json`;
5. emit each action and result into `repair_attempts`;
6. retry only where the rule explicitly allows it;
7. verify hashes/runtime state after repair;
8. add regression evidence to the issue/PR;
9. release the launcher/manifest update;
10. confirm a future reproduction repairs automatically.

`protected` repair classes (for example compatibility-sensitive conditions) should remain conservative until an automatic change is proven safe.

## Support bundle

The future launcher support bundle is specified by [`support-bundle.schema.json`](support-bundle.schema.json) and illustrated by [`support-bundle.example.json`](support-bundle.example.json).

Minimum goals:

- portable JSON;
- no secrets;
- no personal identifiers by default;
- exact launcher/AotR/Windows/language context;
- expected and actual file integrity;
- selected repair plan;
- result of each repair action;
- final error;
- optional multiplayer role/failure phase.

The bundle can later be attached to an Auto-Repair or Multiplayer issue and parsed directly during ChatGPT-assisted triage.

## Labels

The canonical label catalog is versioned in `.github/labels.yml`. The `Issue Triage` workflow creates missing labels on an issue event and can also synchronize them through manual `workflow_dispatch`.

Triage labels:

- `bug`, `feature`
- `launcher`, `multiplayer`, `sync`
- `payload`, `ui`, `paper`
- `auto-repair`, `compatibility`, `engine`
- `needs-triage`, `needs-logs`
- `duplicate`, `confirmed`, `cannot-reproduce`, `fixed`
- `priority:critical`, `priority:high`, `priority:medium`, `priority:low`

Priority guidance:

- **critical** — launch blocker, data/state corruption, or widespread severe multiplayer failure;
- **high** — major defect with significant impact and no good workaround;
- **medium** — important defect with a workaround or limited scope;
- **low** — minor impact, cleanup, or low urgency.

## Issue forms

- **Bug Report** — general launcher/mod defects.
- **Multiplayer / Sync Problem** — LAN, Network WotR, mismatch, OOS, `Starting...`, Direct Launch Failed, language/version/hash divergence.
- **Auto-Repair Failure** — launcher recognized a condition but its repair plan did not recover.
- **Feature Request** — improvements that are not defect reports.

Blank issues are disabled so support data stays structured.
