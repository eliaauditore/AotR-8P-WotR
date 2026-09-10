# localRoot compact trace — first Host/VM divergence

Date: 2026-08-28

Two complete compact RAW traces were compared record-for-record. Each trace contains 3,355,238 fixed 20-byte records:

`index / this / tag / len / preA`

The trace previously emitted with SHA256 `F8FA99B3362CED24BD1AA3C4C3F74A562F92B0A9D138057B921BF7B9F42557BC` came from the run whose console output showed `Image : D:\Games\AotR\AgeoftheRing\rotwk\game.dat`; it is therefore treated as the Host trace despite its accidental `VM` label.

The newer VM trace has SHA256 `9E332FB00C41F2829195B6B107043A371D9448C0C420FE06D7875C73F07DAAFD`.

## Direct comparison

Records 1 through 50,155 have identical compact fields `index`, `tag`, `len`, and `preA` on both machines.

The first visible compact-record divergence is record 50,156:

| Field | VM | Host |
| --- | --- | --- |
| index | 50156 | 50156 |
| this | `0x001AF914` | `0x001AF914` |
| tag | `0x00000000` | `0x00000000` |
| len | 39 (`0x27`) | 29 (`0x1D`) |
| preA | `0xBD5604D4` | `0xBD5604CA` |

The first raw-byte difference in the two 67,104,760-byte files is byte offset 1,003,112, which is the `len` field at offset `+0x0C` of record 50,156.

## Earlier causal input recovered from the accumulator transition

Record 50,155 itself has identical compact metadata on both machines:

- tag `0x00726177` (existing trace display renders this as `.raw`)
- len `4`
- preA `0xDEAB0256`

However, `preA` in record 50,156 is the accumulator state *after* record 50,155 was consumed. Because record 50,155 has exactly four payload bytes and the proven updater is:

`A_next = ROL1(A_prev) + DWORD(payload) mod 2^32`

its 4-byte payload can be recovered exactly from the next record's `preA`:

- VM record 50,155 payload DWORD = `0x00000027` = 39
- Host record 50,155 payload DWORD = `0x0000001D` = 29

This is independently consistent with record 50,156 immediately following with `len=39` on VM and `len=29` on Host.

The surrounding trace confirms this repeated serializer pattern: a `tag=0x00726177, len=4` record contains the DWORD length of the immediately following `tag=0` payload record. Examples immediately before the divergence are 38→38, 28→28, 38→38 on both machines.

## Classification

### BEWIESEN runtime

- Component-A input streams are identical through the state before record 50,155.
- The first actual divergent input is the four-byte payload of call/record 50,155.
- That payload is a variable-length value: VM `39`, Host `29`.
- Record 50,156 is the corresponding variable-length payload call and therefore differs in length by exactly 10 bytes.
- Component A begins diverging at this precise serializer field, not in the earlier 50,154 calls.

### Next narrow gate

Capture only calls 50,155 and 50,156 (plus a tiny surrounding window) with payload bytes and caller return address. The purpose is no longer to find *where* divergence begins; that boundary is now proven. The remaining task is to identify the concrete 39-byte VM / 29-byte Host value and the serializer/caller that supplies it.
