# AotR 8P WotR — Stage 2 Build Preflight Checkpoint

Date: 2026-08-27 (Europe/Berlin)
Branch: `feature/robust-aotr-autodetect`
Status: STAGE 1 COMPLETE / STAGE 2 BUILD NOT YET EXECUTED

## STATUS

Stage 1 robust-autodetect integration completed successfully on the Windows research machine.

The generated non-release builder passed GUI payload syntax, engine payload syntax, builder syntax, payload re-embed and roundtrip validation.

Stage 2 build preflight then inspected the exact generated builder read-only. No build was executed.

## STAGE 1 SUCCESS ARTIFACTS

Work root:

```text
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE1_20260827_003823
```

Patched GUI SHA256:

```text
D8C3E27E35F3EDA101EE74362C9E744BB942D6F06928B61D22036640C22E5F47
```

Patched engine SHA256:

```text
3A03D47B6A094A4892A146866DFEAD53858C500F812615672D66690D7812A873
```

Generated non-release builder:

```text
D:\BFME_RESEARCH\05_REVERSE_ENGINEERING\AOTR_8P_WOTR_MOD\AUTODETECT_V2_STAGE1_20260827_003823\BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V17_ROBUST_AUTODETECT_V2_NONRELEASE.ps1
```

Builder SHA256:

```text
6E5CA3D1FD7F6217F13630222589C309B6CEDD43F18A61672ED7A2ECC1880386
```

## STAGE 2 PREFLIGHT EVIDENCE

Builder parameters:

```text
PackageRoot       System.String                                ""
LauncherVersion   System.String                                "1.0.0"
UpdateManifestUrl System.String                                <main manifest URL>
UpdateBinaryUrl   System.String                                <main binary URL>
EmitGitHubBundle  System.Management.Automation.SwitchParameter
BundleOnly        System.Management.Automation.SwitchParameter
```

Key path derivation:

```text
$PackageRoot = [IO.Path]::GetFullPath($PackageRoot)
$Launcher    = Join-Path $PackageRoot "AotR 8P WotR Mod.exe"
$Icon        = Join-Path $PackageRoot "assets\launcher.ico"
$Skin        = Join-Path $PackageRoot "internal\assets\launcher_skin.png"
$Ui          = Join-Path $PackageRoot "payload\!!!WOTR_8P_UI_TEST.big"
$Paper       = Join-Path $PackageRoot "payload\data\ini\campaigns\scenarios\PaperScenario001.inc"
```

Temporary build output:

```text
$tempRoot = Join-Path $env:TEMP ("AotR8P_SINGLE_EXE_BUILD_" + [Guid]::NewGuid().ToString("N"))
$newExe   = Join-Path $tempRoot "AotR 8P WotR Mod.exe"
```

Observed post-build write paths include:

```text
_GITHUB_UPDATE under PackageRoot (when EmitGitHubBundle is used)
%LOCALAPPDATA%\AotR 8P WotR Mod\seed_backup
$PackageRoot\AotR 8P WotR Mod.exe
```

The builder contains these concrete write commands near the end:

```powershell
New-Item -ItemType Directory -Force -Path $backupRoot
Copy-Item -LiteralPath $Launcher -Destination $backup -Force
Copy-Item -LiteralPath $newExe -Destination $Launcher -Force
```

## CURRENT SAFETY CONCLUSION

`-PackageRoot` is a real isolation mechanism for package-relative assets and launcher output.

However, a build must NOT be started yet solely on that basis because the exact control flow of `-BundleOnly` has not yet been proven. In particular, the preflight output showed a backup/replace path that would require an existing `$PackageRoot\AotR 8P WotR Mod.exe` unless skipped by `BundleOnly`.

The next action is to inspect only the `BundleOnly` branch and surrounding lines before executing any build.

## NEXT PRACTICAL ACTION

Read-only source context around all `BundleOnly` references and the final backup/replace block. Determine whether:

1. `BundleOnly` skips `$Launcher` backup/replacement;
2. `EmitGitHubBundle` is required or implied;
3. a separate isolated seed launcher is needed in a test PackageRoot;
4. all required build inputs can be copied into a disposable test PackageRoot without touching release files.

Only after this proof should the first non-release EXE build execute.

## DO NOT REPEAT

- Do not build into the public release directory.
- Do not overwrite the public `AotR 8P WotR Mod.exe`.
- Do not assume `BundleOnly` semantics from its name.
- Do not assume `PackageRoot` alone suppresses `%LOCALAPPDATA%\AotR 8P WotR Mod\seed_backup`.
- Do not emit/update GitHub release artifacts during the first test build.
- Do not change update URLs to experimental values unless explicitly required by the isolated build design.
