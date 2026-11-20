# AotR 10.x: War of the Ring eight-player lobby layout compatibility

Status: **investigation / no production fix yet** (2026-11-20)

## Reported real-game behavior

The existing public 8P War of the Ring launcher opens Age of the Ring 10.
Eight player rows are visible and map zoom/drag still work. However the
upper map/rules/settings panel overlaps the lower player header/list, and
lower row controls cannot be accessed fully. This is visual user evidence,
**not** proof that an eight-human network match synchronizes successfully.

Official AotR version 10 also made substantial changes to War of the Ring.
The 10.x game UI must be inspected before applying an old coordinate patch.

## Existing technical evidence

- Legacy APT character 321: PlayerGroupMatrix
- Legacy APT character 322: PlayersListMatrix (eight row instances)
- Legacy APT character 323/324: StrategicPlayerMatrix variants
- Legacy APT character 188: MpMapAndSettings
- Legacy APT character 235/278: Strategic map/settings containers
- A previous **-53.9** Y adjustment corresponded to two row heights,
  but the historical tests **did not prove** the active online parent.
- Blindly changing character 278 or 235 had no visible effect.
- The historical attempt involving character 188 was invalidated by a
  missing PaperScenario payload, not verified as a UI fix.

See the project's legacy technical handoff and
docs/reverse-engineering/2026-08-27_P3_P8_LOBBY_BIG_ANALYSIS.md.

## Safe next step: UI archive evidence

Run the read-only diagnostic in tools/compat:

- Windows PowerShell: START-AOTR10-UI-DIAGNOSE.ps1
- Python module: aotr10_ui_diagnose.py
- Tests: test_aotr10_ui_diagnose.py

The script scans likely game installations and checks named BIG archives and
generic BIGF/BIG4 archives containing MpGameSetup, OnlineStrategic, or
LanStrategic APT/CONST assets. It builds a **local private ZIP** with
checksums, relevant files and archive indices. It never modifies a game file.

**Do not upload game archives to public GitHub issues or pull requests.**
The developer may review the ZIP privately. Inspect REPORT.json for
identifying folder names before sharing.

## Acceptance criteria for any future proposed UI patch

1. Identify the *active* AotR 10 lobby timeline/parent for upper panel.
2. Explicitly preserve player list, row dimensions, eight-player payload,
   game.dat RAM patch, Zoom/Drag behavior and PaperScenario001.inc.
3. Produce a separately hash-verified test payload; never silently replace
   public payload_ui.big, manifest.json or launcher EXE.
4. Compare UI screenshots before/after in both offline and online lobby.
5. Test bottom row's difficulty/options controls and game start.
6. Only after real-game validation, consider an explicit opt-in release
   and update manifest hashes. No automatic public distribution before this.
