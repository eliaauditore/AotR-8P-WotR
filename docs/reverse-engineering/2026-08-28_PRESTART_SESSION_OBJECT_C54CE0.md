# Pre-start native session object / GameInfo provenance (2026-08-28)

## Proven static

- `0x007871FC` is a tree/map-style lookup-or-insert helper.
- It calls lookup helper `0x0073D1FA`.
- Tree nodes use at least:
  - `+0x08` child link
  - `+0x0C` child link
  - `+0x10` key
- `0x007871FC` returns `node + 0x14`, i.e. the value slot.
- Therefore `0x00787CD9: mov [eax],edi` stores the newly constructed standalone `0x1080` Network-GameInfo pointer as the map value.

## Runtime pointer-xref classification

Current pre-start Network GameInfo pointer was `0x095755A0`.

Seven private-memory references were found. None of the seven surrounding layouts matched the recovered map-node shape closely enough to classify as the `node+0x14` value slot used by `0x007871FC`.

Two reference sites instead resolve cleanly as separate 12-byte polymorphic objects with vtable `0x00C508A0`:

- object `0x0923BA60`: `+4 = 5`, `+8 = 0x095755A0`
- object `0x09558D58`: `+4 = 2`, `+8 = 0x095755A0`

Static constructors allocate/initialize exactly 12 bytes for the `0x00C508A0` type.

## C54CE0 native network/session candidate

Static constructor at `0x0084C76D` writes `0x00C54CE0` to `[this]` and initializes object fields. Destructor/lifecycle path at `0x0084E62C` restores the same vtable before cleanup.

Runtime object `0x095875B8` begins with exactly `0x00C54CE0` and contains:

- `+0x10 = 0x095755A0` current Network GameInfo
- `+0x44 = 0x095755A0` current Network GameInfo
- `+0x48 = 0xC0A800E0` -> `192.168.0.224`
- `+0x4C = 0x00001F96` -> decimal `8086`

Classification: **strong runtime+static evidence** that `0x095875B8` is a native pre-start network/session object directly associated with the current Network GameInfo and host endpoint identity.

This does not yet prove exact semantic field names or ownership of the object.

## Correction

Earlier caution that `0x095875B8` might merely be `ref-0x10` from a map node is resolved by the constructor evidence: `0x00C54CE0` is explicitly written to `[this]`, and runtime `0x095875B8` starts with this vtable. Therefore it is a genuine object base candidate.

## Next step

Use `tools/research/AOTR_WOTR_SESSION_OBJECT_RUNTIME_OWNER_SCAN.ps1` to:

1. locate all live MEM_PRIVATE `0x00C54CE0` instances,
2. mark which instance holds current Network GameInfo at `+0x10/+0x44`,
3. classify all `0x00C508A0` 12-byte wrapper objects,
4. scan exact private-memory references to the matching `0x00C54CE0` object to recover its owner/global/provenance.
