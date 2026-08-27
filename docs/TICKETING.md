# AotR 8P WotR GitHub Ticket System

GitHub Issues is the canonical support and defect tracker for the AotR 8 Player War of the Ring project.

## Workflow

**Player Report → GitHub Issue → Triage → Fingerprint / error class → Master Ticket → Diagnosis → Fix or repair-manifest extension → Retest → Closed**

1. **Player Report** — The player chooses the issue form that matches the problem and provides versions, exact errors, hashes, logs, and a support fingerprint when available.
2. **GitHub Issue** — The report becomes a durable ticket that can be searched by `A8P-*` error code or `A8P-FP-*` fingerprint.
3. **Triage** — New issues start with `needs-triage`. Automation classifies obvious launcher, multiplayer, payload, UI, paper, compatibility, engine, and auto-repair cases.
4. **Fingerprint / error class** — Reports with the same stable fingerprint are treated as candidates for one root-cause class even if the visible wording differs.
5. **Master Ticket** — Exact fingerprint matches are clustered. One canonical issue stays open as `master-ticket`; individual reports remain preserved as closed `cluster-member` evidence.
6. **Diagnosis** — Compare environment, file hashes, repair actions, logs, and reproduction steps across the entire cluster.
7. **Fix or repair-manifest extension** — Fix source/packaging code when the defect belongs there. If the problem is safe and deterministic to repair locally, add or extend a stable repair rule.
8. **Retest** — Reproduce the original failure, execute the fix/repair path, and ask all affected reports to verify the result.
9. **Closed** — Close the master only after the fix is verified or the error class is intentionally resolved.

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

## Ticket IDs

Every GitHub issue receives a padded project reference such as `A8P-TICKET-0007`. The ticket ID identifies one individual report and is distinct from the support fingerprint.

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

## Master-ticket clustering

Reports with the exact same `A8P-FP-*` value are automatically grouped by `.github/workflows/issue-cluster.yml`.

- the oldest matching report becomes the master unless a master already exists;
- the master receives `master-ticket` and stays in the active backlog;
- later matching reports receive `cluster-member` + `duplicate` and are closed as duplicates;
- no report is deleted: its versions, hashes, logs, repair attempts, and ticket ID remain available as evidence;
- the master contains an automatically maintained list of all affected ticket IDs;
- two or more matching reports automatically mark the master `confirmed`;
- a new recurrence can reopen a previously closed master.

A maintainer may split a report back out manually if later evidence proves that an identical fingerprint was too broad and actually covered two different root causes.

Maintainer comments on the master are mirrored to all clustered reports. This lets one reply such as `Should be fixed now. Please recheck.` reach every affected player report. Retest-style messages also apply `needs-retest`.

Full behavior and the future launcher Messages/red-dot model are documented in [`MASTER_TICKETS.md`](MASTER_TICKETS.md).

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

1. identify the canonical master issue and stable fingerprint;
2. define or reuse the `A8P-*` error code;
3. encode deterministic detection;
4. add the smallest safe action sequence to `repair-manifest.json`;
5. emit each action and result into `repair_attempts`;
6. retry only where the rule explicitly allows it;
7. verify hashes/runtime state after repair;
8. add regression evidence to the master issue/PR;
9. release the launcher/manifest update;
10. broadcast a retest request to the cluster and confirm future reproductions repair automatically.

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

The canonical label catalog is versioned in `.github/labels.yml`. GitHub workflows create missing labels as needed.

Triage and lifecycle labels include:

- `bug`, `feature`
- `launcher`, `multiplayer`, `sync`
- `payload`, `ui`, `paper`
- `auto-repair`, `compatibility`, `engine`
- `master-ticket`, `cluster-member`
- `needs-triage`, `needs-logs`, `needs-retest`
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
- **Launcher Auto-Repair Failure** — prefilled launcher handoff after Auto-Repair is exhausted.

Blank issues are disabled so support data stays structured.

## Launcher integration status — 1.0.10

The launcher-side ticket flow has been validated end-to-end on Windows before release promotion:

- normal production launch path passed compatibility checks, 8-player runtime patches, FINAL_STABLE_V7 activation, game start, and clean launcher exit;
- a controlled synthetic failure validated bounded Auto-Repair, one automatic retry, and `REPORT ERROR` without modifying game files;
- launcher-generated issue #22 became `A8P-TICKET-0022` with stable fingerprint/master metadata;
- a maintainer master-ticket reply was detected by the launcher, produced the red `MESSAGES` unread indicator, rendered correctly, and cleared locally after being read;
- the synthetic test hook was removed from the production builder before the final normal-launch regression;
- approved final launcher version: `1.0.10`;
- approved final EXE SHA256: `6A80E0F7B862ABE3E0F19C3DF5ED9EE9EE730F246CF603ED00A39D1EE7DFF2F8`.

Release artifacts are promoted separately so the current public launcher cannot be changed merely by merging documentation/source-validation work.
