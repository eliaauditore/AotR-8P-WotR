# AotR 8P WotR — Resolver Source Proof

Date: 2026-08-27 (Europe/Berlin)
Branch: `feature/robust-aotr-autodetect`
Status: GUI + ENGINE RESOLVERS SOURCE-IDENTIFIED

## STATUS

The V17 `START_SIGNAL_MVP` builder packaging has been decoded far enough to identify the actual embedded PowerShell GUI and engine payloads and the concrete AotR resolver functions in each.

This removes the previous uncertainty about where the two independent install resolvers live.

## PACKAGING LAYERS PROVEN

```text
V17 PowerShell builder
  -> Base64 outer template
  -> C# wrapper
  -> GuiGzipBase64
  -> EngineGzipBase64
  -> decoded PowerShell GUI / engine source
```

`GuiGzipBase64` and `EngineGzipBase64` are named directly by the C# wrapper.

Observed decoded START_SIGNAL_MVP payloads:

```text
GUI PowerShell:
  SHA256: E8C67486182DA952EA19214AAE9F60E5E9E410579FEF1C0722DA626CE5FFF1EF

ENGINE PowerShell:
  SHA256: D94460492ACD2B98CB8DF0929E302C2F626A97045AAEE9593A2B29E9424FEA5B
```

## GUI RESOLVER — SOURCE PROOF

Decoded source:

```text
GuiGzipBase64.decoded.txt
```

Relevant boundaries:

```text
line 83  : function Get-AotRInstallFromPath([string]$Path) {
line 170 : function Save-AotRInstall([string]$Path) {
line 177 : function Resolve-AotRInstall([switch]$PromptIfMissing) {
line 236 : $Install = Resolve-AotRInstall -PromptIfMissing
```

Current GUI behavior proven from source:

1. reads `%LOCALAPPDATA%\AotR 8P WotR Mod\launcher_config.json`;
2. checks legacy config fields `install_root`, `aotr_root`, `runtime`;
3. calls `Get-AotRInstallFromPath` for each;
4. checks `AOTR_HOME`;
5. enumerates all filesystem PowerShell drives using `Get-PSDrive -PSProvider FileSystem`;
6. probes a static candidate list;
7. returns immediately on the first valid result;
8. if requested, exposes a `FolderBrowserDialog` manual selection path;
9. saves only `{ install_root = $Path }` via `Save-AotRInstall`;
10. successful resolver paths currently save `$found.Runtime`, not a canonical standalone AotR root.

Current structural acceptance inside `Get-AotRInstallFromPath`:

```text
lotrbfme2ep1.exe
AND
game.dat OR zGameDats\game.dat
```

The GUI resolver does not hard-require sibling `aotr\` before accepting a candidate.

It also contains a bounded recursive fallback below a manually selected/custom folder:

```text
Get-ChildItem ... -Filter "lotrbfme2ep1.exe" -Recurse -Depth 6 ...
```

## ENGINE RESOLVER — SOURCE PROOF

Decoded source:

```text
EngineGzipBase64.decoded.txt
```

Relevant boundaries:

```text
line 140 : function Get-AotRInstallFromPath([string]$Path) {
line 238 : function Resolve-AotRInstall {
```

Current engine behavior proven from source:

1. reads the same launcher config path;
2. checks legacy config fields `install_root`, `aotr_root`, `runtime`;
3. calls its own independent `Get-AotRInstallFromPath` implementation;
4. checks `AOTR_HOME` independently;
5. enumerates filesystem PowerShell drives independently via `Get-PSDrive -PSProvider FileSystem`;
6. probes its own static candidate paths;
7. returns immediately on the first valid result.

The engine resolver therefore duplicates install discovery rather than consuming one canonical GUI-selected installation.

Its `Get-AotRInstallFromPath` also accepts runtime candidates primarily via:

```text
lotrbfme2ep1.exe
AND
game.dat OR zGameDats\game.dat
```

It derives `SourceMod` heuristically from runtime layout and may fall back to the runtime itself when sibling `aotr` is not found.

## CURRENT CONFIG V1 PROBLEM

The GUI writer is:

```powershell
[PSCustomObject]@{ install_root = $Path } | ConvertTo-Json | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
```

Resolver success currently calls:

```powershell
Save-AotRInstall $found.Runtime
```

Therefore Config V1 stores the detected runtime path rather than a canonical validated `AgeoftheRing` root.

This directly supports the Config V2 migration requirement.

## CONFIRMED ROOT CAUSE OF AUTODETECT WEAKNESS

The robust-autodetect design assumptions are now source-proven:

- GUI and engine have separate resolver implementations.
- Both use first-valid-match behavior.
- Both can enumerate mapped/network filesystem PS drives because they use broad `Get-PSDrive` enumeration.
- Neither current resolver uses the required standalone-AotR validation policy.
- Plain/custom RotWK-like layouts can pass if executable + game.dat exist.
- GUI Config V1 stores runtime path rather than canonical root.
- GUI and engine can theoretically select different installations.

## INTEGRATION BOUNDARIES

The safe replacement boundaries are now concrete.

GUI resolver block begins at:

```text
function Get-AotRInstallFromPath([string]$Path) {
```

and runs through the resolver/config-selection section ending immediately before normal post-resolution launcher logic after:

```text
$Install = Resolve-AotRInstall -PromptIfMissing
```

ENGINE resolver block begins at:

```text
function Get-AotRInstallFromPath([string]$Path) {
```

and includes:

```text
function Resolve-AotRInstall {
```

The exact end boundary should be taken from the decoded source before patching rather than guessed from this checkpoint.

## IMPLEMENTATION DIRECTION

Production V2 should:

```text
GUI
  -> shared robust candidate discovery / validation / scoring
  -> explicit ambiguity handling
  -> Config V2 canonical root

ENGINE
  -> consume Config V2
  -> hard-revalidate canonical root
  -> do not independently rediscover via AOTR_HOME/Get-PSDrive
```

This avoids the previous split-brain possibility where GUI and engine resolve different installations.

## FILES / HASHES

Authoritative development builder used for this proof:

```text
BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_START_SIGNAL_MVP.ps1
SHA256: 79D31C3DCE6833781BFECF5B87230B1C463483EA4F31A89D2431238D42A17C6F
```

Decoded payload hashes:

```text
GUI:
E8C67486182DA952EA19214AAE9F60E5E9E410579FEF1C0722DA626CE5FFF1EF

ENGINE:
D94460492ACD2B98CB8DF0929E302C2F626A97045AAEE9593A2B29E9424FEA5B
```

## SAFE TESTS COMPLETED

- V17 builder SHA checkpoint reproduced.
- outer Base64 template decoded read-only.
- C# wrapper identified.
- `GuiGzipBase64` identified and GZip-decoded.
- `EngineGzipBase64` identified and GZip-decoded.
- GUI resolver function boundaries identified.
- engine resolver function boundaries identified.
- Config V1 writer behavior identified.
- no public launcher EXE modified.
- no original builder modified.

## NEXT PRACTICAL ACTION

1. checkpoint exact decoded GUI + engine source hashes (done);
2. extract the exact engine resolver end boundary and current repair dispatcher/allowlist;
3. patch copies of decoded GUI + engine source only;
4. GUI: integrate robust resolver + Config V2 + ambiguity/manual selection;
5. engine: remove independent AOTR_HOME/drive discovery and consume GUI Config V2;
6. validate PowerShell syntax;
7. re-embed both patched payloads into a COPY of START_SIGNAL_MVP;
8. round-trip decode and hash-verify both embedded payloads;
9. compile NON-RELEASE test EXE only;
10. run full resolver test matrix before any release promotion.

## DO NOT REPEAT

- Do not search only the outer builder text for resolver markers; the real logic is nested in GZip Base64 GUI/engine payloads.
- Do not modify only the GUI resolver.
- Do not leave engine `AOTR_HOME` / `Get-PSDrive` rediscovery active after GUI Config V2 integration.
- Do not retain first-valid-match selection.
- Do not treat executable + game.dat alone as standalone AotR validation.
- Do not save only runtime path as the canonical install identity.
- Do not patch the public release EXE directly.
