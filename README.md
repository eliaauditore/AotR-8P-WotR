# AotR-8P-WotR

Current public launcher release: **1.1.2**.

## Windows 11 Smart App Control

On at least one confirmed Windows 11 system with Smart App Control enabled, the official 1.1.2 launcher was blocked when the downloaded ModDB ZIP propagated Mark-of-the-Web to the extracted EXE.

If Windows shows the Smart App Control block immediately after download, do **not** disable Defender or Smart App Control. Instead, right-click the downloaded ZIP -> **Properties** -> enable **Unblock / Zulassen** if shown -> **Apply** -> **Extract All / Alle extrahieren** -> start the launcher from the newly extracted folder.

The exact official 1.1.2 EXE was hash-verified during this test and launched normally after the ZIP was unblocked before extraction.

See [`docs/release/WINDOWS_SMART_APP_CONTROL_1_1_2.md`](docs/release/WINDOWS_SMART_APP_CONTROL_1_1_2.md) for the confirmed reproduction, hashes, safety boundaries, and long-term release requirements. Tracking issue: #50.
