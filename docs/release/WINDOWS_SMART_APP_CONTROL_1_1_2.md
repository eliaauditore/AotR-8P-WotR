# Windows 11 Smart App Control — launcher 1.1.2

## Status

A real Windows 11 system with Smart App Control enabled was observed blocking the **official released launcher 1.1.2** before launcher startup when the executable carried Mark-of-the-Web (`Zone.Identifier`, `ZoneId=3`) inherited from the downloaded ModDB ZIP.

This is tracked in GitHub Issue #50.

The affected EXE was verified byte-for-byte against the frozen release identity:

- Version: `1.1.2`
- EXE SHA256: `5B4D12B7BF43D72860E27C51A3D8AC7AC00CA53DB58499E41AC735F7B7ECED0E`
- Authenticode status: `NotSigned`

The test therefore did **not** indicate that ModDB altered the executable.

## Confirmed user-facing workaround

If Windows 11 Smart App Control blocks the launcher immediately after downloading the official ZIP, use the Windows Explorer unblock control on the **ZIP before extraction**:

1. Keep the downloaded ZIP intact.
2. Right-click the downloaded ZIP and choose **Properties**.
3. In the Security section at the bottom, enable **Unblock / Zulassen** if Windows shows that option.
4. Select **Apply** and **OK**.
5. Right-click the same ZIP and choose **Extract All / Alle extrahieren**.
6. Start `AotR 8P WotR Mod.exe` from the newly extracted folder.

On the confirmed test system, this exact Explorer path allowed the launcher and game to start normally.

## What was proven

Two controlled A/B tests were performed against the exact official 1.1.2 EXE:

- EXE carrying `Zone.Identifier` / `ZoneId=3` -> Smart App Control blocked execution.
- Copy of the same EXE after removing only `Zone.Identifier` -> identical SHA256, launcher started, game started.
- Copy of the official ZIP after removing the ZIP `Zone.Identifier` before extraction -> extracted EXE had no `Zone.Identifier`, identical SHA256, launcher started, game started.
- The same ZIP-before-extraction process was then repeated through the normal Windows Explorer **Properties -> Unblock -> Extract All** path -> launcher and game started.

The executable bytes remained unchanged throughout the tests.

## Safety boundaries

This support path does **not** require disabling Windows Defender, Smart App Control, reputation-based protection, or adding broad antivirus exclusions.

Do not silently modify, rebuild, repack, or replace the frozen 1.1.2 release artifact to address this issue. Any binary or signing change requires a new version/hash and the normal release acceptance process.

`Unblock-File` was used only for controlled diagnosis. The documented user-facing workaround is the standard Windows Explorer **Properties -> Unblock** action on the downloaded ZIP.

## Long-term release requirement

The preferred successor-release path is to improve Windows trust/reputation, including evaluation of Authenticode code signing, then validate a fresh internet-download -> extract -> launch flow on Windows 11 with Smart App Control enabled without requiring the user to disable security features or manually unblock files.
