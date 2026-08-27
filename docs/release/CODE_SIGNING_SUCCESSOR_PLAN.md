# Code signing plan for the successor to launcher 1.1.2

## Status

`REVIEW_REQUIRED / BLOCKED_ON_SIGNING_IDENTITY`

This document prepares the repository for trusted Authenticode signing of a successor to the frozen `1.1.2` launcher. It does **not** authorize modification or replacement of `v1.1.2`.

Related issues: #52, #53, #54, #50, #38.

## Why signing is required

A controlled Windows 11 Smart App Control test proved that the exact official `1.1.2` launcher is blocked on the Mark-of-the-Web path while the same EXE bytes run after removal of the zone marker. The release EXE is unsigned.

Microsoft's current Smart App Control guidance states that unknown code may still run when it is signed with a certificate issued through a trusted provider / CA chain in the Microsoft Trusted Root Program. For SAC compatibility, use an **RSA-based** code-signing certificate; current SAC signature checks do not support ECC signatures.

Primary references:

- https://learn.microsoft.com/windows/apps/develop/smart-app-control/code-signing-for-smart-app-control
- https://learn.microsoft.com/windows/apps/develop/smart-app-control/overview
- https://learn.microsoft.com/windows/apps/package-and-deploy/code-signing-options
- https://learn.microsoft.com/windows/win32/seccrypto/signtool
- https://learn.microsoft.com/windows/win32/seccrypto/time-stamping-authenticode-signatures

## Non-negotiable release rules

1. `v1.1.2` and its frozen EXE remain immutable.
2. A signature changes the PE bytes and therefore changes SHA256. A signed launcher requires a new release identity/version.
3. Never commit a PFX, private key, certificate password, HSM credential, Azure client secret, signing token, or equivalent secret.
4. Do not use a self-signed certificate for public distribution.
5. Do not disable Smart App Control or Defender as the release solution.
6. Do not claim that signing guarantees zero reputation warnings until the exact downloaded successor package passes the real user path.

## Candidate signing paths

### 1. Azure Artifact Signing

Microsoft recommends Azure Artifact Signing (formerly Trusted Signing) for non-Store distribution.

Current Microsoft guidance lists organization availability in the EU, while individual-developer availability is limited to the USA and Canada. Therefore a German individual account must not be assumed eligible. Use this path only after #54 confirms a legitimate eligible organization/signing identity.

For public distribution, the selected profile must provide public trust suitable for Win32 application signing and Smart App Control.

### 2. Traditional RSA OV code-signing certificate

If Artifact Signing eligibility is unavailable, obtain an RSA OV code-signing certificate from a CA that chains into the Microsoft Trusted Root Program.

Modern OV key-storage requirements generally use hardware/HSM-backed protection. The project must document who owns the certificate, who can request signing, and how signing approval is separated from ordinary development.

### 3. SignPath Foundation

SignPath Foundation can provide free signing for qualifying open-source projects, but eligibility is not established for this repository.

Current blockers / review points:

- no top-level OSI license is present;
- the repository includes AotR/BFME-derived payloads and other third-party material that this project cannot simply relicense;
- SignPath requires verifiable source/build provenance for signed artifacts and has additional OSS policy requirements.

Do **not** add a blanket open-source license over third-party assets merely to satisfy signing eligibility. Eligibility must be verified separately under #54.

References:

- https://signpath.org/
- https://signpath.org/terms.html

## Required signing characteristics

For a successor public release:

- signer key: RSA;
- file digest: SHA-256;
- timestamp: RFC 3161;
- timestamp digest: SHA-256;
- trusted public certificate chain;
- timestamp must be present so signature validity survives certificate expiry according to the timestamp policy.

For SignTool, the exact command depends on the selected provider. A traditional certificate example is conceptually:

```text
signtool sign /fd SHA256 /tr <RFC3161_TIMESTAMP_URL> /td SHA256 <provider-specific-certificate-options> "AotR 8P WotR Mod.exe"
```

Provider credentials/options must never be stored in this document or committed to the repository.

## Candidate verification

Run the Guardian verifier on the signed non-release candidate:

```powershell
pwsh -File .\tools\guardian\VERIFY_AUTHENTICODE_CANDIDATE.ps1 `
  -FilePath ".\AotR 8P WotR Mod.exe" `
  -ExpectedSha256 "<POST_SIGN_SHA256>" `
  -ExpectedSubjectContains "<EXPECTED_PUBLISHER>"
```

The verifier is read-only. It requires, by default:

- exact SHA256 if one is supplied;
- Authenticode status `Valid`;
- RSA signer key;
- timestamp certificate present;
- optional publisher-subject match;
- `signtool verify /pa /v` PASS when `-RequireSignTool` is requested.

## Release evidence to preserve

Before promotion record:

- unsigned candidate SHA256;
- signed candidate SHA256;
- build commit/source identity;
- signing provider/path;
- signer subject;
- issuer;
- certificate thumbprint and serial where appropriate;
- signature algorithm / RSA confirmation;
- timestamp certificate and timestamp evidence;
- Guardian verification report;
- final package ZIP SHA256;
- fresh ModDB/GitHub download hash;
- SAC/Explorer fresh-download test result;
- Defender/cloud protection result;
- launcher/runtime regression results.

## Required real-world acceptance

A successor is not distribution-ready merely because `Get-AuthenticodeSignature` says `Valid`.

The exact final ZIP must be downloaded through the public distribution path onto a Windows 11 system with Smart App Control enabled, extracted normally through Explorer, and started without manual `Unblock`, SAC disablement, Defender exclusions, or other trust bypasses.

The same exact candidate must also preserve the current runtime feature set and pass the existing Guardian release gates.
