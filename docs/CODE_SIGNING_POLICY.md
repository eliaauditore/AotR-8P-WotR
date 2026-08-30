# Code signing policy

## Scope

This policy governs Windows launcher binaries that are designated for maintainer or user field execution.

It does **not** grant ownership or an Open Source license over AotR, BFME, EA, or other third-party game/mod assets. Public payloads such as `payload_ui.big` and `payload_paper.inc` remain outside any future launcher-only OSS/signing scope unless their rights are separately established.

## Current release boundary

The public launcher remains frozen until a guarded promotion explicitly changes it.

Unsigned development and release-candidate binaries may be produced for CI, static analysis, hosted Defender scanning, and isolated automated lifecycle testing. They are **not** normal Windows field candidates.

## Field-candidate rule

A launcher binary may be labeled `FIELD_CANDIDATE` only after the exact post-sign file passes all of the following:

1. `Get-AuthenticodeSignature` returns `Valid`.
2. A signer certificate is present.
3. The signer public key is RSA. Smart App Control currently does not accept ECC signatures for this purpose.
4. A timestamp certificate is present.
5. `signtool verify /pa /v` succeeds under the normal Windows Authenticode policy.
6. The exact post-sign SHA256 is frozen in the acceptance checkpoint before field execution.
7. ProductVersion matches the intended candidate version.
8. Defender/security scanning required by the release ticket passes.
9. The candidate is downloaded/extracted through the intended distribution path and tested without disabling Smart App Control, Defender, exclusions, or other Windows security controls.

Signing workflows must use SHA-256 file digest and RFC 3161 timestamping with SHA-256. The signing implementation must not commit or expose private keys, PFX files, certificate passwords, HSM credentials, Azure/SignPath signing tokens, or equivalent secrets.

## Verification implementation

Repository verifier:

`launcher-source/signing/VERIFY_TRUSTED_FIELD_CANDIDATE.ps1`

Reusable/manual verification workflow:

`.github/workflows/verify-trusted-field-candidate.yml`

The workflow consumes an already-created signed GitHub Actions artifact and verifies the exact post-sign file. It does not perform signing itself.

## Smart App Control / Defender policy

A Defender-clean result does not by itself qualify an unsigned binary for field execution. Smart App Control can independently block unknown unsigned code.

Do not instruct maintainers or users to disable Smart App Control or Defender, add broad exclusions, or use security-policy bypasses as the normal release solution.

## Signing-provider status

Parent tracking issue: #52.

The free SignPath Foundation route additionally requires an OSS-compatible signed-binary boundary. That ownership/license cleanup is tracked separately in #88. Until that work is complete, this policy and verifier are provider-neutral and can also be used with a traditional publicly trusted RSA code-signing certificate or another eligible trusted signing service.

## Roles

- Build/release integration: Project Guardian / repository maintainers.
- Signing approval: repository owner/authorized release approver.
- Source review: normal protected-branch pull-request and Guardian checks.

No signing request should bypass the repository's protected review/release process.

## Required provenance for each signed candidate

Record at minimum:

- source commit SHA;
- unsigned pre-sign SHA256;
- signing provider/profile identifier where safe to publish;
- signer subject and issuer;
- signer certificate thumbprint/serial where appropriate;
- timestamp certificate presence;
- post-sign SHA256;
- ProductVersion;
- signing verification workflow run ID;
- Defender/security scan result;
- field-test environment/result.

The post-sign hash, not the unsigned pre-sign hash, is the binary identity used for field acceptance and eventual release promotion.
