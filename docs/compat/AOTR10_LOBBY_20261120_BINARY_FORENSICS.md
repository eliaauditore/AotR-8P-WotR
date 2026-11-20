# AOTR 10 LAN WotR UI – verified asset evidence (2026-11-20)

Status: binary comparison completed; experimental screenshot test only, **not** production-ready.

## Facts observed in the user-supplied private diagnostics

- Public 8-player UI BIG SHA-256: 827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376.
- Embedded LanStrategic.apt: 76,007 bytes, SHA-256 DA556ADE4240E7AF2D204877A4D821861D2A721CF76D2507D485A3CDCBBCB5F72.
- Embedded MpGameSetup.apt: 236,576 bytes, SHA-256 968E66D733294C248902F2CEA4788CE32BD2E745D2049457ECC86EB8F435329E.
- The current LAN **upper settings/maps placement is already shifted -53.9** relative to vanilla! Thus blindly repeating the historical upper-panel shift is incorrect.
- Join upper-panel Y float at LanStrategic.apt offset 0xFEE4: vanilla -163.25; active -217.15.
- Host upper-panel Y float at 0xFFAC: vanilla -162.35; active -216.25.
- Join player matrix placement offset 0xFEA4: -78.55.
- Host player matrix placement offset 0xFF6C: 60.50.
- LAN movie frame 21 places JoinMain sprite 105, frame 41 places HostMain sprite 108. Each wrapper contains exactly one upper settings/movie placement and one player matrix.
- MpGameSetup PlayerList character 322 has eight rows (~0–~7), spaced 26.95 units apart. Black background and frame were intentionally extended for eight rows.

## Focused reversible local experiment

Hypothesis (not proven): Moving **only** the LAN player matrix upward by two row distances (-53.9) may reveal its header and bottom difficulty selectors without changing the already-moved upper settings panel.

Candidate changes within the original public BIG:
- Join PlayerMatrix offset 0xFEA4: -78.55 => -132.45.
- Host PlayerMatrix offset 0xFF6C: 60.5 => 6.6.

Only two four-byte float fields are touched. Verified with eight offline tests; other BIG members and positions are unchanged. The test is local-only and must be visually checked in-game before ANY public release. A temporary direct game boot does not execute the normal launcher RAM 8P patch, so it is suitable only for visual layout checks.

If the test fails or the direct boot cannot show the lobby, **do not publish**. Reconstruct the actually active rendering hierarchy, including the black background rectangle. Do not assert that game runtime or eight-human multiplayer works merely because eight UI rows are drawn.

## Parser correction

EA BIG has a mixed-endian header: bytes 4–7 contain the little-endian archive size; bytes 8–15 have big-endian member count and table offset. Earlier false-positive archive-length warnings were caused by decoding all three fields big-endian; this is corrected on the development branch.

All original game assets remain private. Public main, manifest.json, payload_ui.big, repair-manifest.json and the launcher remain unchanged.
