# Issue #33 — canonical FINAL_1_1_1 builder default mismatch checkpoint

## Status
Release staging stopped safely before clone/commit/push.

## Observed guard failure
The PR #34 stager verified the accepted exact-final artifacts and then failed because the supplied builder did not contain a `LauncherVersion` default of `1.1.1`.

## Root cause
The accepted `BUILD_ISSUE33_STANDALONE_SKIN_RC2.ps1` is derived from the canonical `FINAL_1_1` builder. The RC2 build harness invokes that builder with `-LauncherVersion $CandidateVersion`. For the exact-final build, `CandidateVersion` was `1.1.1`, so the generated EXE/manifests are correctly versioned `1.1.1`, while the saved builder source still retains its inherited default `1.1`.

## Accepted runtime identity remains valid
- exact final EXE SHA256: `2141EA9690708EA7A61B7298AD90E0C76CC417FED996AC0CF3685276BA2A4024`
- accepted generated builder SHA256 before canonical-default correction: `B30EAFB0ABCE94DC22E5121FB7F9B3B9AF31A6D2FCDB5E5B14CB4056AF392560`
- skin SHA256: `BA044C14023AAF21FC4822D068C07E8991DC6CAEDAC6BCD5F1B50935BA9C7AC6`
- UI SHA256: `827988C328E010A598BFAD16C9BFF830C3F904EAF1640F162C8124E8C6ABA376`
- Paper SHA256: `3FF683843190A323DE9299C17DCD36AF24C5C00473119478E3FAF068BF904E43`

The exact final 1.1.1 runtime acceptance remains PASS: first boot, self-materialized skin, AUTO REPAIR provisioning/retry_launch isolation, explicit manual START, fresh game process, 15-second stability, and launcher handoff all passed.

## Corrective action
Create a canonical `FINAL_1_1_1` builder from the accepted B30E builder by changing exactly one source value: `LauncherVersion` default `1.1` -> `1.1.1`. Prove round-trip equivalence, parse it, then invoke it without a `-LauncherVersion` override in an isolated package. It must reproduce the exact accepted EXE SHA `2141EA...` and identical release manifests before it may be staged.

## Safety
No release branch or `main` write occurred from the failed stager. PR #34 remained at `f261a697f483dcd75abe564cc6054f4a5540b970` at the time of diagnosis. No force push was used.
