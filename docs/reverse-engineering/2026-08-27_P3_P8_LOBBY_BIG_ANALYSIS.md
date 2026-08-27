# P3-P8 Native WotR Lobby BIG Analysis

Checkpoint: 2026-08-27

Scope: APT/BIG layer only. This checkpoint traces the additional real network-human path as far as the UI/FSCommand boundary and identifies Strategic-only player-count assumptions. It does **not** claim that the native `game.dat` transition from `CustomMatch::PlayGame` to LivingWorld/local strategic ownership is solved yet.

## Research target

Immediate target:

```text
Remote client P3 joins
  -> slot 2 / network human
  -> OnlineStrategic / MpGameSetup
  -> ready/start
  -> native WotR setup
  -> LivingWorldPlayer P3
  -> client P3 LocalStrategicPlayer
```

The correction from older notes is important: the first additional online human is **P3**, not P5.

## Input archives

| Archive | Size | SHA256 |
| --- | ---: | --- |
| `LanOpenPlay.big` | 340,272 | `4E761FF0BC81A67CAB242719D8C6AC5C666EDB362D63F27C800552336352630A` |
| `LanStrategic.big` | 351,376 | `41E248660A227EA8D2E764C36F73F8AAF1F16C4ACD3614CCA9A9F313FBBA377D` |
| `MpGameSetup.big` | 1,030,948 | `AA201F972714B1F8D59B9B65A2E59311508605D4EB6CA1FF201A7A6FCC368CDB` |
| `OnlineOpenPlay.big` | 1,223,284 | `D95985379CAABD3CAC8F68AFF6EC638731378EC80038C345F93610E991F5B59F` |
| `OnlineStrategic.big` | 103,152 | `CC29ADF25C39C64C8B31F7D9CA82E261CB157CBAC911AD32A547789913BE232A` |
| `LanLobby.big` | 589,736 | `AE49916CB1F391E8574362E34AC9FCEE7B7F5FB79AC3801F06452C045E2E5DB9` |

Relevant extracted payload hashes:

| Payload | Size | SHA256 |
| --- | ---: | --- |
| `OnlineStrategic.apt` | 59,227 | `37EC776C4FCC24E6B98E5F61188690CA44E762D7C461729D13025607763C0603` |
| `OnlineStrategic.const` | 7,148 | `BEBA5CF4BC40DBAE70E7EB1ABFB89F10BAE8B33B629A419E945005A98FF3FB76` |
| `OnlineOpenPlay.apt` | 161,042 | `F11F94BA0318EEE79CB2FC4283AFBA2B68216143E8404D84581924E1ACCA8D71` |
| `MpGameSetup.apt` | 234,316 | `C9876F4BBBD26DE06F025A578DA5B9EC58AD86EFC16B24A9B0303DDA2AC2F581` |
| `MpGameSetup.const` | 20,034 | `2D4F216253EA44F045FE84C56B05D7FBB93D1E0B730E02E2D8A9BB3C9775E614` |
| `LanStrategic.apt` | 76,007 | `579EA1755AED82C46A2E17A13B778F1F6301D82B2628AB29B768361AC4DEF6CA` |
| `LanLobby.apt` | 48,958 | `77B5A08F757C2E255EC8DE2B267F9165FDECB846755DBBEB69962D0253D1EA78` |

All six archives parse as EA `BIGF`. Their APT ActionScript streams were structurally decoded; no undecodable action stream was encountered in this pass.

## BEWIESEN: OnlineStrategic is a Strategic wrapper over shared online infrastructure

`OnlineStrategic` imports ordinary online UI/player components from `OnlineOpenPlay`, while importing Strategic setup/player components from `MpGameSetup`.

Important imports include:

```text
OnlineOpenPlay::MP_Button_Players
OnlineOpenPlay::MP_Button_Status
OnlineOpenPlay::MP_Button_Name
OnlineOpenPlay::MP_Button_OnlineMap

MpGameSetup::MpPlayerMatrix
MpGameSetup::MpPlayerMatrix_withKickButton
MpGameSetup::MpMapAndSettings

MpGameSetup::StrategicMapAndSettingsHostJoin
MpGameSetup::StrategicPlayerMatrix
MpGameSetup::StrategicPlayerMatrix_withKickButton
```

This is a strong structural match for:

```text
shared online backend
        +
Strategic-specific lobby composition
```

`OnlineStrategic` does not contain a separate Strategic networking implementation in ActionScript.

## BEWIESEN: Join uses the normal CustomMatch native command

In `OnlineStrategic.apt`, the Join button callback issues:

```text
CustomMatch::JoinGame
```

through the root `GameCode`/FSCommand bridge.

Relevant ActionScript path:

```text
JoinGame.DoButtonCallBack
  -> _root.HideButtonBar()
  -> _root.GameCode("CustomMatch::JoinGame")
```

There is no P3/P4/P5/P6/P7/P8 parameter and no Strategic-only join command at this layer.

`OnlineOpenPlay` uses the same `CustomMatch::JoinGame` path.

Therefore the Strategic wrapper does not introduce a new two-human join cap before native `CustomMatch::JoinGame` processing.

## BEWIESEN: CreateGame and PlayGame also use normal CustomMatch commands

The Strategic Create flow eventually issues:

```text
CustomMatch::CreateGame
```

The Strategic host Start button stores:

```text
gameCode = "CustomMatch::PlayGame"
```

and its callback invokes:

```text
_root.GameCode(gameCode)
```

The corresponding `PlayGame` ActionScript body in `OnlineStrategic` is structurally identical to the `OnlineOpenPlay` body for the start command path.

This moves the key unresolved boundary further into native code:

```text
CustomMatch::PlayGame
  -> native session/start transition
  -> WOTRMP-specific setup/serialization
```

not into a special Strategic ActionScript StartGame implementation.

## BEWIESEN: OnStartLobby is not a player mapper

`OnlineStrategic::OnStartLobby` only traces a Strategic marker, enables the lobby controls and shows the button bar.

Its relevant behavior is:

```text
trace("Strategic:OnStartLobby ...")
EnableComponents(Main.Controls)
ShowButtonBar(0)
```

No player ownership, peer mapping or local strategic player assignment occurs there.

`vStrategicRoot` is assigned to the Strategic root movie and provides the UI bridge used by Strategic callbacks such as CreateGame.

## BEWIESEN: StrategicPlayerMatrix already contains eight row objects

In `MpGameSetup.apt`:

```text
PlayerGroupMatrix        = character 321 @ APT 0x5970
PlayersListMatrix        = character 322 @ APT 0x5984
StrategicPlayerMatrix    = character 323 @ APT 0x5998
StrategicPlayerMatrix_withKickButton
                         = character 324 @ APT 0x59AC
```

`PlayersListMatrix` contains eight instances of `PlayerGroupMatrix`, named:

```text
~0
~1
~2
~3
~4
~5
~6
~7
```

So the APT asset itself already has physical row objects for slots 0-7.

Each row uses the common `PlayerGroupMatrix`, including its ComboBox gadgets and Ready control.

The row ComboBoxes register:

```text
_Init = "MpGameSetup::InitGadgets"
```

This is the same native UI-init namespace used by the general multiplayer player rows.

This evidence is consistent with the known current `game.dat` patch at RVA `0x00440A91` (`06 -> 08`, Player Slots / InitGadgets): the asset has eight target rows, while native initialization historically stopped short of all eight in Strategic use.

## BEWIESEN: the Strategic six-player assumption is UI-level and explicit

`StrategicPlayerMatrix` contains ActionScript that, when not in `InGame`, explicitly hides:

```text
PlayerList.~6
PlayerList.~7
```

That is a direct original six-visible-player assumption.

It is **not** a two-human check. It suppresses the final two total-player rows regardless of human/network semantics.

This aligns with the already-known Strategic 6->8 row/loop work rather than revealing a new online-human cap.

## BEWIESEN: Ready is index-based and has no ActionScript two-human cap

The Ready control is shared by each `PlayerGroupMatrix` row.

Its button path derives the row index from the parent row name and calls:

```text
MpGameSetup::OnReadyPress(index)
```

through `GameCodeNoPrefix`.

The eight parent rows are named `~0` through `~7`; the ActionScript does not special-case only indices 0/1.

Thus the APT Ready path is already structurally capable of addressing P3 and later rows. Any remaining restriction in `MpGameSetup::OnReadyPress` would have to be in the native consumer, not in this ActionScript wrapper.

## BEWIESEN: Strategic host kick UI has a separate six-player artifact

A second Strategic-only six-player assumption exists in the host kick controls.

```text
StrategicButton_KickGroup = character 285 @ APT 0x5518
Button_KickGroup          = character 362 @ APT 0x5D58
```

`StrategicButton_KickGroup` has kick buttons named:

```text
1 2 3 4 5
```

The normal OpenPlay `Button_KickGroup` has:

```text
1 2 3 4 5 6 7
```

Interpretation:

- original Strategic design assumes six total player rows (host + five other kickable slots);
- normal OpenPlay assumes eight total player rows (host + seven other kickable slots);
- this does not block P3, because P3's kick control is already present;
- after scaling to P7/P8, the Strategic host UI will need equivalent kick controls if full host-kick parity is desired.

This is a UI/control-surface limitation, not evidence that the network backend cannot carry those players.

## BEWIESEN: OnlineStrategic host/join composition uses the Strategic matrices

In `OnlineStrategic`:

Join composition uses:

```text
MpGameSetup::StrategicMapAndSettingsHostJoin
MpGameSetup::StrategicPlayerMatrix
```

Host composition uses:

```text
MpGameSetup::StrategicPlayerMatrix_withKickButton
MpGameSetup::StrategicMapAndSettingsHostJoin
```

The player-row implementation underneath those matrices is the common eight-row `PlayersListMatrix` / `PlayerGroupMatrix` described above.

## LAN differential supports the same architecture

`LanStrategic` imports and composes the same Strategic `MpGameSetup` components:

```text
StrategicPlayerMatrix
StrategicPlayerMatrix_withKickButton
StrategicMapAndSettingsHostJoin
```

while `LanOpenPlay` uses the normal:

```text
MpPlayerMatrix
MpPlayerMatrix_withKickButton
MpMapAndSettings
```

In `LanLobby`, selecting OpenPlay vs War of the Ring routes to the corresponding `LanOpenPlay` / `LanStrategic` screen. No ActionScript string resembling a separate `Strategic::*` network command was found in `LanStrategic`.

This is additional evidence that Strategic identity at the APT layer is primarily screen/component selection while common native multiplayer machinery handles players.

## No Strategic-specific FSCommand namespace found in these APTs

Across the decoded ActionScript:

`OnlineStrategic` contains only the trace marker:

```text
Strategic:OnStartLobby ...
```

and the UI variable:

```text
vStrategicRoot
```

as Strategic-named ActionScript strings.

No emitted command such as:

```text
Strategic::JoinPlayer
Strategic::PlayGame
Strategic::SetPlayer
```

was found.

The important emitted command namespaces remain shared/native namespaces such as:

```text
CustomMatch::JoinGame
CustomMatch::CreateGame
CustomMatch::PlayGame
MpGameSetup::InitGadgets
MpGameSetup::OnReadyPress
```

## Current P3 path after BIG analysis

The path can now be narrowed to:

```text
P3 remote client
  -> OnlineStrategic Join button
  -> CustomMatch::JoinGame
  -> [native CustomMatch consumer]
  -> native free-slot allocation (already independently found to scan 0..7)
  -> slot 2 / PlayerType 6
  -> common MpGameSetup player row ~2
  -> MpGameSetup::InitGadgets
  -> MpGameSetup::OnReadyPress(2) when ready
  -> host CustomMatch::PlayGame
  -> [UNRESOLVED NATIVE BOUNDARY]
  -> WOTRMP setup / serialization / peer mapping
  -> LivingWorldPlayer[2]
  -> client-local strategic player selection
```

## Classification

### BEWIESEN

- OnlineStrategic uses the shared `CustomMatch` Join/Create/PlayGame command path.
- The Strategic APT layer does not introduce a two-human join/start limit.
- The shared player-list asset contains slots `~0` through `~7`.
- Ready dispatch is row-index based and can encode index 2 and beyond.
- Original Strategic UI deliberately hides rows `~6` and `~7` outside `InGame`.
- Original Strategic host kick UI only provides kick controls 1-5, whereas normal OpenPlay provides 1-7.

### STARKER HINWEIS

If a correctly joined P3 reaches slot 2 as `PlayerType = 6` but fails to become a functioning Strategic human after StartGame, the next likely barrier is **after** `CustomMatch::PlayGame` in native code, not in these APT/BIG wrappers.

The remaining high-value areas are:

```text
CustomMatch::PlayGame native handler
WOTRMP mode handoff
session-player -> strategic-player serialization
network peer/player ID mapping
local-slot -> LocalStrategicPlayer selection
LivingWorld setup and initial strategic state sync
```

### HYPOTHESE

The original EA design appears to have intentionally constrained the visible Strategic lobby to six total players while retaining much of the common eight-slot multiplayer infrastructure underneath it. The discovered Strategic six-row and five-kick-control artifacts support this, but they do not by themselves prove that the complete native WotR runtime can successfully synchronize eight real online humans.

## Next native reverse-engineering targets

Use the current AotR `game.dat` only after exact hash verification:

```text
Size   11,347,456
SHA256 CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC
```

Priority native XREF/consumer targets:

```text
CustomMatch::JoinGame
CustomMatch::PlayGame
MpGameSetup::InitGadgets
MpGameSetup::OnReadyPress
WOTRMP / mode flag 0x10
```

Then connect those consumers to the already-known Strategic runtime facts:

```text
TheLivingWorldLogic + 0x8C/+0x90  player vector
TheLivingWorldLogic + 0x98        current LivingWorldPlayer*
0x6B42EF                           EA current-player setter
0x800B8C                           local-slot finder (scans 8)
```

No new byte patch is justified by this checkpoint alone. The next step is native control-flow reconstruction and, only after exact bytes/function semantics are verified, a minimal P3 runtime instrumentation test.
