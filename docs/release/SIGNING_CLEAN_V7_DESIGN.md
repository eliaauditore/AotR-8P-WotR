# Signing-Clean V7 Design

Status: RESEARCH / NON-RELEASE
Parent: #88 / #52

## Goal

Remove literal proprietary `game.dat` instruction bytes from the future trusted-signed launcher input boundary without weakening runtime compatibility checks or changing the proven V7 layout.

This document does not authorize field execution or release promotion.

## Historical blocker

The V19-clean launcher still contains five literal `game.dat` compatibility instruction sequences in Engine / FINAL_STABLE_V7, and the 1577-byte V7 shellcode begins with the exact 12 bytes overwritten at the Raw Wheel hook.

Historical compatibility windows are identified in the clean implementation only by length + SHA256:

| Role | Length | SHA256 |
|---|---:|---|
| Raw Wheel hook | 12 | `0D40841FEA16CCBF82D3ACF45F5D4F3E88DCEE25DEE3E8979CFC861D9DEBEB98` |
| Strategic Map handler | 8 | `AA4F89C4B315D0CDE15CD3A90DF96C069E83EB4419AFB5AB9429B4630C98D731` |
| Zoom Update | 16 | `13DB5AB30A882A36D343C74FD28182A5383740BAFD4A39061229B2DF552EE6F0` |
| Camera Global reference | 6 | `8D9A0E5FCD6B9396376D74BDCD71348F16619D3A688753683957208D39C99E51` |
| Cancel/Release callback | 16 | `4884272792A6E35438C4261E8D1F10905C24516654A148A0B6611B0B77B7BE7C` |

The clean source must not contain the literal instruction byte arrays themselves.

## Runtime compatibility validation

Replace byte-array equality with a read-only hash contract:

1. Read exactly the known window length from the target process.
2. SHA-256 the bytes in memory.
3. Compare only to the pinned digest.
4. Abort before any RAM write if any digest differs.

This retains an exact compatibility gate while removing copied instruction sequences from source/resources.

## Raw Wheel trampoline semantic reimplementation

The original 12-byte overwritten behavior computes the signed high 16-bit word of the local 32-bit value at `[ebp-4]` and stores the sign-extended result at `[esi+0x0C]`.

The signing-clean trampoline uses a different 12-byte instruction sequence implementing the same operation and preserving the flag-producing shift:

```text
lea   eax,[ebp-4]
mov   eax,[eax]
shr   eax,16
cwde
mov   [esi+0x0C],eax
```

Canonical clean 12-byte prefix SHA256:

`C2134A124371FD3DBB4BB7F5A20D46DE8CDAE3BF46EA6F248DD53A9488069811`

The sequence remains exactly 12 bytes so all existing V7 offsets remain stable.

## Clean-shellcode requirements

- total length remains 1577 bytes;
- offset `0x000..0x00B` is the clean semantic prefix above;
- no full historical compatibility byte sequence may occur anywhere in the cleaned shellcode;
- all bytes after the rewritten prefix remain pinned during the first research proof so the experiment changes one semantic variable only;
- future signable builds consume only the cleaned resource, never the historical donor shellcode;
- the historical shellcode remains research provenance outside the OSS signing boundary.

## Verification without re-embedding proprietary bytes

The verifier must not contain historical instruction arrays. To prove the clean shellcode contains none of them, use sliding windows over the binary and compare SHA256 values for window lengths 6, 8, 12 and 16 against the five forbidden digests above.

## Safety

- Frozen 1.1.2 and public 1.1.6 are immutable.
- No unsigned result is a Windows field candidate.
- No public release artifact is modified.
- No local SAC/Defender bypass is allowed.
- Full V7 runtime regression remains mandatory after trusted signing exists.
