# Issue #33 — canonical FINAL_1_1_1 builder reproduction gate ready

The exact-final runtime artifact remains accepted at EXE SHA256 `2141EA9690708EA7A61B7298AD90E0C76CC417FED996AC0CF3685276BA2A4024`.

The previous PR stager correctly stopped before any Git write because the accepted generated builder SHA `B30EAFB0ABCE94DC22E5121FB7F9B3B9AF31A6D2FCDB5E5B14CB4056AF392560` still inherits `LauncherVersion = 1.1` from the canonical FINAL_1_1 source. The exact-final EXE was nevertheless built as 1.1.1 because the build harness passed `-LauncherVersion 1.1.1` explicitly.

Valid next gate: `research/installer/AOTR_8P_ISSUE33_FINALIZE_AND_REPRO_FINAL_1_1_1_BUILDER_V1_1.ps1`.

The gate must:
1. pin the accepted B30E builder hash;
2. prove exactly one inherited default `1.1` exists and no `1.1.1` default exists;
3. change only that default to `1.1.1` and prove round-trip source equivalence;
4. parse the canonical builder;
5. rebuild in isolated LOCALAPPDATA without a `-LauncherVersion` override;
6. reproduce exact EXE SHA `2141EA...`, UI/Paper hashes and byte-identical final manifests;
7. perform no GitHub branch write.

Only after PASS may the resulting canonical builder SHA be pinned into the guarded PR #34 release stager.
