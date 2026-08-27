# V18 Stage 5 environment checkpoint

## STATUS
PASS — 6/6 cases, 0 failures.

## WHAT WE KNOW
The current V18/1.0.10 Robust Autodetect V2 resolver passes the environment-position and config-write failure tests.

## EVIDENCE
User-run output on 2026-08-27 reported:
- launcher/package in Downloads-style location -> PASS, resolved `D:\Games\AotR\AgeoftheRing`
- launcher/package directly inside AotR root -> PASS
- deterministic config write/verify failure -> `A8P-INSTALL-004` PASS
- actual ACL no-write-rights -> `A8P-INSTALL-004` PASS
- real launcher config unchanged -> PASS
- Stage1 builder unchanged -> PASS
- Cases: 6
- Failures: 0
- STAGE 5: PASS

Report path:
`D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_V18_STAGE5_ENV_20260827_025436\V18_STAGE5_ENVIRONMENT_POSITION_WRITE_REPORT.txt`

## FILES / HASHES
- V18 Autodetect builder SHA256: `D1728E924A71383DDB953337C670887A638E0B836906904570503712E545BCF0`
- GUI SHA256: `CFAF397833536769D726B0DD0960D940AAA6896ED62BFEFA0764185C2CEA90DC`
- ENGINE SHA256: `94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA`
- Stage2 non-release EXE SHA256: `B85818E9349A76DB62DF288C23879BC2345A463D399A21105A2F75114557A944`

## SAFE TESTS COMPLETED
- Launcher outside install / Downloads-style position
- Launcher directly inside standalone AotR root
- Config write/verify failure path
- Real NTFS ACL deny/write failure path with ACL restoration
- Real config preservation
- Builder preservation

## NEXT PRACTICAL ACTION
1. Real equal-top two-installation picker interaction using one temporary structural candidate and the real D: installation; verify user selection is revalidated and saved to isolated Config V2.
2. Physical Removable/USB/exFAT drive enumeration and ordering/selection test if such a drive is available.

## DO NOT REPEAT
- No All-in-One discovery.
- No exe-only detection.
- No first-valid selection.
- Runtime copies are not real installs.
- No research/backup auto-preference.
- No blind EXE patch.
- No unproven repair actions.
- No network recursive scan.
- No unvalidated config save.
- No release build before remaining matrix/environment tests pass.
