# Launcher Error Reporting Contract

This document defines the launcher-side handoff into the GitHub ticket system.

## Required user flow

The launcher must **not** create a ticket for every launch failure.

Required order:

1. User presses **Launch**.
2. Launch fails and the launcher identifies the failure/error code.
3. The launcher runs the configured Auto-Repair plan from `repair-manifest.json`.
4. The launcher retries as allowed by that plan.
5. Only if repair is exhausted and launch still fails, the final error panel may expose **REPORT ERROR**.
6. Pressing **REPORT ERROR** opens a prefilled GitHub issue in the user's browser.
7. The user reviews the report and submits it to GitHub.

There is no background telemetry and no automatic issue creation.

## Why the button opens GitHub instead of posting silently

The public launcher must not contain a repository write token or GitHub secret. Embedding such a credential would allow anyone to extract and abuse it.

Therefore the safe public workflow is:

`Launcher -> prefilled GitHub issue page -> user presses Submit -> GitHub Issue`

The user may need to sign in to GitHub. No paid service or external secret is required.

## GitHub endpoint

Base URL:

```text
https://github.com/eliaauditore/AotR-8P-WotR/issues/new
```

Launcher reports should select the classic template:

```text
template=launcher-auto-report.md
```

The launcher should URL-encode and prefill at least:

- title
- complete final error text
- launcher version
- AotR version
- Windows version
- language
- stable `A8P-*` error code
- `A8P-FP-*` fingerprint when already available
- repair plan
- each attempted repair action and result
- expected/actual file hashes
- support-bundle JSON

Recommended title:

```text
[Launcher Report] A8P-RUNTIME-001 - Direct Launch Failed
```

## Ticket IDs

GitHub's issue number is the canonical durable sequence source.

The triage workflow converts it to a padded project ID:

```text
GitHub issue #6 -> A8P-TICKET-0006
GitHub issue #42 -> A8P-TICKET-0042
```

GitHub uses one shared number space for issues and pull requests, so gaps are expected. This is intentional: the ID remains globally unique, race-free, and directly traceable to GitHub.

`A8P-TICKET-*` identifies the individual ticket.

`A8P-FP-*` identifies the error class and can therefore be shared by many tickets reporting the same underlying failure.

## Fingerprint fallback

If a submitted issue contains an `A8P-*` error code and an Exact/Original Error section but no valid fingerprint, the GitHub triage workflow computes a fallback fingerprint as:

```text
SHA256(UPPERCASE_ERROR_CODE + "|" + normalized_exact_error)
```

The first 12 hexadecimal characters become:

```text
A8P-FP-XXXXXXXXXXXX
```

The launcher should eventually generate the same canonical fingerprint before opening the browser so the user can see it in the error panel and issue preview.

## Privacy requirements

Do not include by default:

- Windows username
- computer/device name
- IP address
- MAC address
- Discord/GitHub identity
- personal absolute paths such as `C:\Users\Name\...`
- secrets, tokens, cookies, or credentials

Paths should be reduced to project-relative or role-based values where possible.

## Launcher UI requirement for v1.0.10+

The final failure panel should preserve the current error text and Auto-Repair result, then expose a secondary action similar to:

```text
AUTO-REPAIR FAILED
A8P-RUNTIME-001
A8P-FP-1A2B3C4D5E6F

[ RETRY ]   [ REPORT ERROR ]
```

`REPORT ERROR` must remain hidden during the initial failure and while Auto-Repair is still running. It becomes available only when the repair plan has been exhausted or no safe repair action exists.

## Source/build requirement

The current public launcher is a Single-EXE containing embedded GUI and engine logic. Editing old external `internal/launcher_gui.ps1` files does not update the running launcher.

The authoritative launcher builder must therefore be versioned in the repository before remote-only launcher releases can be produced reliably. Until that migration is complete, server-side ticketing can be updated remotely, while producing a new Windows launcher EXE still requires the canonical local build inputs and Windows build toolchain.
