# Native join +0x40 first controlled call — negative host state

Checkpoint: 2026-08-28

## Client-side result

The VM satisfied the live join contract and the controlled remote-thread stub returned from the native `C54CE0 +0x40 -> 0x84CB34` call. Post-call client state remained pre-join: `session+0x44 = NULL`, session state remained `0`, and the discovered host Network GameInfo remained present in `session+0x10`.

## Host post-call result

Read-only host dump after the call:

- P1: Type6, `192.168.0.224:8086` (local host)
- P2: Type0, `{0,0}`
- P3: Type3, `{0,0}`
- P4: Type3, `{0,0}`
- P5-P8: Type1, `{0,0}`

No persistent Type6 entry for VM `192.168.0.57:8086` existed after the controlled call.

## Classification

### BEWIESEN runtime

- client-side native `+0x40` call returned;
- client did not enter committed/bound native join state;
- host had no persistent remote Type6 PlayerInfo for the VM after the call;
- P2 remained open Type0, so a free native slot still existed.

### NOT YET PROVEN

The post-call snapshot cannot distinguish between:

1. ID3 never reaching the host dispatcher;
2. ID3 reaching the host but being rejected before PATH_C slot commit;
3. PATH_C creating a remote Type6 only transiently and later clearing it before the snapshot.

## Next runtime split

Use `AOTR_WOTR_HOST_JOIN_TRANSIENT_WATCH.ps1` on the host while issuing exactly one fresh client `-Execute` call. It polls all eight host slots at high frequency and records any transient Type6 for `192.168.0.57:8086`.

If no transient commit is observed, the next diagnostic gate is packet/dispatcher arrival rather than further GameInfo slot analysis.
