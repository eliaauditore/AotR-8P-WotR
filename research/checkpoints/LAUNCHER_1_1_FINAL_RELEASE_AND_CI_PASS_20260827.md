# Launcher 1.1 Final Release and CI PASS — 2026-08-27

## STATUS

**RELEASED / LIVE / CI PASS**

Launcher 1.1 is live on `main` and the release-consistency workflow is green.

Final live main commit:

`7072e19bd43a350da0344b1b5e32ab9d052b3404`

Release commit introducing the 1.1 root release bytes:

`bbd7eff483d2cdbf3e799f764433b49195dc55b6`

Canonical FINAL_1_1 builder follow-up commit:

`7072e19bd43a350da0344b1b5e32ab9d052b3404`

## WHAT WE KNOW

Launcher 1.1 preserves the released V18 / launcher 1.0.10 feature set while adding robust standalone AotR autodetection / Config V2 and the minimal topbar polish.

The fake maximize/restore visual is removed. The real minimize control is immediately left of close and remains functional. No maximize behavior was added.

The resolver full matrix was completed and frozen before release.

The exact production launcher was smoke-tested in an isolated runtime before promotion.

The five release-root files were validated as one release set before promotion.

The second main commit added only the canonical `launcher-source/...FINAL_1_1.ps1` builder required by CI; release-root bytes were not changed by that commit.

## EVIDENCE

Stage 10 production build: PASS.

Stage 11 final five-file promotion gate: PASS.

Stage 12 promotion branch staging: PASS.

Stage 13 V1.6 direct canonical builder staging: PASS.

GitHub compare for `bbd7eff... -> 7072e19...` showed exactly one added path:

`launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1.ps1`

GitHub Actions run:

- Workflow: `Validate Release Consistency`
- Run ID: `33032288517`
- Head SHA: `7072e19bd43a350da0344b1b5e32ab9d052b3404`
- Status: `completed`
- Conclusion: `success`

## WHAT FAILED

The first post-release consistency run on `bbd7eff...` failed only because no canonical FINAL builder matching version `1.1` existed under `launcher-source/`.

Release hashes themselves were already reported OK in that failed CI run.

Stage 13 harness versions V1 through V1.5 contained harness-only assumptions/patching defects and are obsolete:

- V1: checked `aotr-standalone-v2` in the outer builder text instead of embedded GUI payload.
- V1.1: fixed Config V2 validation layer but still assumed the wrong LauncherVersion default.
- V1.2: wrapper patch target mismatch.
- V1.3: wrapper-on-wrapper structure was still wrong.
- V1.4: dynamically produced runtime script had quote/here-string parser corruption.
- V1.5: direct runner draft caught before user execution because replacement quoting would have emitted backslashes.

**Only Stage 13 V1.6 direct is valid.**

## CURRENT HYPOTHESIS

No open release defect remains from the launcher 1.1 promotion path.

The release consistency workflow now validates the live launcher 1.1 metadata, hashes, repair actions, and presence of the canonical FINAL_1_1 builder.

## FILES / HASHES / OFFSETS

Final live launcher EXE SHA256:

`9F2D79FC951082158D7E712E3DDDDE3A050A69CDA4A372CBF43039CB379942E4`

Final live manifest SHA256:

`61B559D2AEAB72DE2ECB9BF0F2F1E437D2742C34947CA9B414CD7390AAEAA38A`

Final live repair-manifest SHA256:

`684B8B4F39EE7ADB97D4C0837036F742D67C28B0EFC86A2006043BB2B3C36685`

UI payload SHA256:

`827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`

Paper payload SHA256:

`3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`

Final production GUI SHA256:

`23880AF22E3D0121EE79FE14CAA21799BFBE105397E4C66DC21E641D50DAD09C`

Final production ENGINE SHA256:

`94A71026D6A35998D0338DA0FDF9D478DDD92A76C382F23E109B13286F3F5AAA`

Final production skin SHA256:

`BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6`

Generated production builder before canonical default patch SHA256:

`0F8303B0E177391AC68AD6EBE03353A1A9312BFF460F937448BEE4D43FA51E82`

Canonical FINAL_1_1 builder SHA256:

`2E19020B0B0C73C29E8C1F4FC4A13FD940A7C6FA9A2CA6274BF08B55A34FF665`

Canonical builder path:

`launcher-source/BUILD_AOTR_8P_SINGLE_EXE_UPDATE_CHANNEL_V18_FINAL_1_1.ps1`

Topbar geometry:

- Old Minimize visual/hit: x=726..773
- Final Minimize visual/hit: x=777..824
- Close remains: x=825..899
- No maximize/restore control or behavior added

## SAFE TESTS COMPLETED

- V18 baseline audit
- robust autodetect Stage 1 integration
- isolated non-release build
- fresh isolated GUI smoke
- Stage 4–7 full resolver matrix, 51/51 explicit assertions PASS
- physical USB FAT32 detection/selection PASS
- RC1 visual smoke
- RC2 topbar visual smoke PASS
- exact final production EXE isolated smoke PASS
- final five-file promotion gate PASS
- atomic promotion branch staging PASS
- live main fast-forward without force PASS
- canonical FINAL_1_1 builder staging PASS
- second live main fast-forward without force PASS
- GitHub `Validate Release Consistency` PASS

## NEXT PRACTICAL ACTION

Launcher 1.1 release work is complete. Return to the multiplayer / WotR reverse-engineering roadmap from the frozen project state rather than making further launcher changes without new evidence.

## DO NOT REPEAT

- Do not run the old V6 status-panel transplant.
- Do not use Stage 13 V1–V1.5.
- Do not change the frozen resolver without new evidence.
- Do not add maximize behavior; the window is intentionally non-resizable.
- Do not invent repair actions outside the proven dispatcher.
- Do not treat `_GITHUB_UPDATE` alone as a complete runnable development runtime; the launcher skin is an external runtime dependency.
- Do not rebuild/publish launcher 1.1 merely because the old Stage13 failed harnesses exist; final release and CI are already PASS.
