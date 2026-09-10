# Map node layout and C508A0 wrapper classification

Static analysis of `0x007871FC` / `0x0073D1FA` proves a tree/map-like container where lookup walks nodes using `+0x08` and `+0x0C` child links and compares the key at `+0x10`. `0x007871FC` returns `node+0x14`, the value slot.

Applying that layout to the seven private-memory references to the current pre-start Network GameInfo (`0x095755A0`) shows that none can currently be safely classified as the expected map value node from the standalone `0x1080` creation path.

Two references instead align exactly with a separately proven 12-byte polymorphic type using vtable `0x00C508A0`:

- `0x0923BA60`: vtable `0x00C508A0`, field `+4 = 5`, field `+8 = 0x095755A0`
- `0x09558D58`: vtable `0x00C508A0`, field `+4 = 2`, field `+8 = 0x095755A0`

Static code at `0x0081D375..0x0081D399` and `0x00847118..0x00847132` allocates exactly `0x0C` bytes and initializes `[obj]=0x00C508A0`, `[obj+4]=0`, `[obj+8]=0` before later use.

This strengthens the conclusion that the current live pre-start Network GameInfo is referenced by several native wrapper/session objects, while the particular `0x00787C09` map-value lifecycle has not yet been linked to this live instance.
