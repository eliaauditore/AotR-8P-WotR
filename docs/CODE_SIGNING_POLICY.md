# Code signing policy

## Scope

This policy governs Windows launcher binaries that are designated for maintainer or user field execution.

It does **not** grant ownership or an Open Source license over AotR, BFME, EA, or other third-party game/mod assets. Public payloads such as `payload_ui.big` and `payload_paper.inc` remain outside any future launcher-only OSS/signing scope unless their rights are separately established.

## Current release boundary

Public launcher promotion is explicit and guarded. A release may be signed or unsigned, but the exact public binary identity must be frozen in `manifest.json` and pass the applicable release checks before promotion.

Unsigned development and release-candidate binaries may be produced for CI, static analysis, hosted Defender scanning, and isolated automated lifecycle testing.

## Public unsigned-release rule

An unsigned launcher may be promoted as a normal public release when all of the following are true:

1. the repository owner or authorized release approver explicitly approves the unsigned release;
2. ProductVersion matches the intended public version;
3. the exact SHA256 of the promoted EXE is frozen in `manifest.json`;
4. hosted Microsoft Defender scanning of the exact candidate reports no threats;
5. the public release-consistency / Guardian checks pass;
6. no known Defender quarantine or malware-detection regression is present for the candidate;
7. users are not instructed to disable Defender, Smart App Control, add broad exclusions, or weaken Windows security controls.

A normal Windows SmartScreen / unknown-publisher reputation warning on an unsigned binary is acceptable under this rule when the file remains Defender-clean and Windows still offers the normal user-controlled execution path (for example, `More info` / `Run anyway`).

## Trusted field-candidate rule

`FIELD_CANDIDATE` remains the stricter designation for a trusted, signed Windows candidate. A launcher binary may be labeled `FIELD_CANDIDATE` only after the exact post-sign file passes all of the following:

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

A Defender-clean result is mandatory for an approved unsigned public launcher, but does not make that binary a trusted signed `FIELD_CANDIDATE`. Smart App Control / SmartScreen reputation can independently warn about unknown unsigned code.

Do not instruct maintainers or users to disable Smart App Control or Defender, add broad exclusions, or use security-policy bypasses as the normal release solution.

## Signing-provider status

Parent tracking issue: #52.

The free SignPath Foundation route additionally requires an OSS-compatible signed-binary boundary. That ownership/license cleanup is tracked separately in #88. Signing remains a desirable future hardening/reputation improvement, but it is not a mandatory blocker for an explicitly approved Defender-clean public release under the unsigned-release rule above.

## Roles

- Build/release integration: Project Guardian / repository maintainers.
- Public unsigned-release approval: repository owner/authorized release approver.
- Signing approval: repository owner/authorized release approver.
- Source review: normal protected-branch pull-request and Guardian checks.

No release request should bypass the repository's protected review/release process.

## Required provenance for each public candidate

Record at minimum:

- source commit SHA;
- exact public/candidate SHA256;
- ProductVersion;
- Defender/security scan result;
- release-consistency / Guardian result;
- whether the binary is signed or unsigned;
- release approver/decision context where appropriate.

For signed candidates, additionally record the signing provider/profile identifier where safe to publish, signer subject and issuer, certificate thumbprint/serial where appropriate, timestamp certificate presence, signing verification workflow run ID, and exact post-sign SHA256.
