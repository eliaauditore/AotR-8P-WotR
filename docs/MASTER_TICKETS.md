# Master Tickets, Clustering, and Launcher Messages

This document defines how repeated player reports for the same AotR 8P WotR failure are grouped without losing the original evidence.

## Core model

There are three identifiers with different jobs:

- `A8P-TICKET-XXXX` identifies one individual player report.
- `A8P-FP-XXXXXXXXXXXX` identifies one normalized error class/root-cause candidate.
- `master-ticket` identifies the canonical GitHub issue used to diagnose and communicate about that fingerprint.

Multiple ticket IDs may therefore share one fingerprint and one master ticket.

Example:

```text
A8P-TICKET-0012  \
A8P-TICKET-0027   > A8P-FP-91A0D33C114E -> MASTER A8P-TICKET-0012
A8P-TICKET-0049  /
```

The individual reports are not deleted or destructively merged. They preserve each player's versions, hashes, repair attempts, logs, and other evidence.

## Automatic clustering

`.github/workflows/issue-cluster.yml` runs after issue changes.

When a report has a valid support fingerprint:

1. all repository issues containing the exact same fingerprint are collected;
2. an existing `master-ticket` is preferred;
3. if no master exists, the oldest matching report becomes the master;
4. the master stays open and receives an `Error cluster` block listing every affected `A8P-TICKET-*` report;
5. additional reports receive `cluster-member` and `duplicate`;
6. additional reports are closed with GitHub's duplicate reason so the normal open-issue backlog shows the master instead of six copies of the same failure;
7. every child report receives a visible link to the master;
8. when two or more reports share the fingerprint, the master is automatically marked `confirmed`.

If a new report arrives for a previously closed master fingerprint, the workflow may reopen that master and return it to triage. This treats a recurrence as a regression of the same error class instead of silently creating a second canonical issue.

## Maintainer replies are broadcast

Comments from repository maintainers on a `master-ticket` are automatically mirrored to every clustered player report, including reports that were already closed as duplicates.

Example maintainer reply:

```text
Should be fixed now. Please recheck with the latest launcher build.
```

The workflow copies that update to every `A8P-TICKET-*` report in the same fingerprint cluster.

Replies containing words such as `recheck`, `retest`, `should be fixed`, `please test again`, or `please verify` also apply `needs-retest` to the master and its clustered reports.

A maintainer can keep a comment from being broadcast by including:

```text
<!-- no-broadcast -->
```

or starting the comment with:

```text
[internal]
```

This allows internal diagnostic notes on the public master issue without pushing them into every player-facing report.

## Launcher Messages design

The future launcher should not store a global read/unread flag in GitHub because unread state is different for every player.

Instead, the launcher keeps a small local support state, for example:

```json
{
  "schema": 1,
  "fingerprint": "A8P-FP-91A0D33C114E",
  "master_issue": 12,
  "last_seen_message_id": 123456789,
  "last_checked": "2026-08-26T10:00:00Z"
}
```

Recommended behavior:

1. after a reportable Auto-Repair failure, the launcher already knows the fingerprint;
2. it resolves the matching `master-ticket` from the public GitHub repository and caches the master issue number;
3. on launcher startup and when the user presses **Messages**, it checks for newer maintainer comments on that master;
4. if the newest relevant comment ID is greater than `last_seen_message_id`, the **Messages** button shows a red notification dot;
5. opening Messages displays the maintainer update and advances `last_seen_message_id` locally;
6. no read receipt, account identifier, device identifier, or background telemetry needs to be sent to the repository.

The launcher should not poll GitHub every few seconds. Resolve/cache the master once, check at launcher startup, after a failure, and on manual refresh to stay well within public GitHub API limits.

## Intended launcher UI

After Auto-Repair is exhausted:

```text
AUTO-REPAIR FAILED
A8P-RUNTIME-001
A8P-FP-91A0D33C114E

[ RETRY ]   [ REPORT ERROR ]

                         Messages  ●
```

The red dot appears only when a newer master-ticket maintainer update exists than the locally stored `last_seen_message_id`.

A simple Messages view can show:

```text
A8P-FP-91A0D33C114E
Master: A8P-TICKET-0012

Maintainer:
Should be fixed now. Please recheck with the latest launcher build.

[ MARK READ ]   [ OPEN MASTER TICKET ]
```

## Why this is preferable to six independent tickets

The master model gives maintainers one diagnosis thread, one fix state, and one place to close/reopen the error class, while preserving all original reports as evidence.

The resulting workflow is:

```text
Player A report -- A8P-TICKET-0012 --\
Player B report -- A8P-TICKET-0027 ----> same fingerprint ----> MASTER
Player C report -- A8P-TICKET-0049 --/                         |
                                                               |
                                     Diagnose / fix / repair rule
                                                               |
                                      Maintainer master reply
                                                               |
                         +----------------+----------------+
                         |                |                |
                      Player A         Player B         Player C
                      gets update      gets update      gets update
```

This also maps cleanly to Auto-Repair evolution: once the master root cause is deterministic and safely repairable, the master issue can drive a new `repair-manifest.json` rule. Future users with the same fingerprint then recover automatically before they ever need to submit another report.
