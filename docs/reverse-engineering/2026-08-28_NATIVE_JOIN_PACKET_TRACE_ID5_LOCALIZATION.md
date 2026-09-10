# AotR WotR native Join packet trace — host PATH_C failure localization

Date: 2026-08-28

Branch: `research/own-mp-start-ack-3endpoint`

This checkpoint records the two-machine `pktmon` evidence collected around exactly one controlled client call to the native C54CE0 vtable `+0x40` Join Request method (`0x0084CB34`).

## Preconditions already proven

Client VM:

- local endpoint `192.168.0.57:8086`
- session state `+0x28 = 0`
- `session+0x44 = NULL`
- discovered host Network GameInfo exists in the session GameInfo list
- its row0 is Type6 at `192.168.0.224:8086`
- the controlled `+0x40` call returns successfully

Host:

- local endpoint `192.168.0.224:8086`
- current Network GameInfo has P1 Type6 local, P2 Type0/open, P3/P4 AI, P5-P8 closed
- a 20-second / 20-ms transient watcher around one controlled client call observed no slot mutation and no client Type6 commit

## Packet-level result

The VM capture contains exactly one anomalous extra complete broadcast sweep shortly after the controlled call:

- source `192.168.0.57:8086`
- destinations `255.255.255.255:8086..8093`
- VM-local timestamp start approximately `05:40:43.915493`
- eight destination ports are covered
- common UDP payload SHA-256 prefix observed during analysis: `c3fcb3eb3967278f`
- the payload contains the stable local marker region `B9 9F F2 C5 3A 29 2D F9`

Normal periodic VM broadcast sweeps in the same capture use `B9 9F F2 C4 3A 29 2D F9` at the corresponding position.

The exact anomalous `C5` payload is also present in the host capture on the same eight destination ports (host-local timestamp approximately `05:40:43.421129..05:40:43.421946`; the two machine clocks are offset).

### Classification

**BEWIESEN runtime packet-level:** the controlled native Join Request produces native UDP traffic and that traffic reaches the host capture. Therefore the hypotheses that `CreateRemoteThread` prevents the native sender from emitting traffic, or that VMware/bridging drops the join broadcast before the host, are falsified for this experiment.

## Unique host-to-client reply

About 0.21 seconds after the anomalous VM sweep, the VM capture contains the only direct host-to-VM unicast packet family in the captured interval:

- source `192.168.0.224:8086`
- destination `192.168.0.57:8086`
- VM-local timestamp approximately `05:40:44.128374`
- UDP payload SHA-256 prefix `1790c1f20bfeb105`
- payload marker region `B9 9F F2 C3 3A 25 2D E8`

Multiple pktmon records correspond to capture-layer observation of the same payload; this does not imply three independent native replies.

### Classification

**STARKER HINWEIS runtime:** the host processes the controlled join traffic far enough to emit a direct response to the requesting endpoint.

This response is strongly consistent with native message ID `0x05` rather than success ID `0x04`, because:

1. the host transient watcher observed no Type6 slot commit;
2. the client never acquired a non-NULL `session+0x44` / native joined state;
3. static PATH_C analysis already proves five writes of message ID `0x05` before the common sender and exactly one ID `0x04` success write after the first-free selection succeeds.

Known PATH_C exact message-buffer writes before common send `0x0098AF02 -> 0x0084C257`:

- `0x0098A87D` -> ID `0x05`
- `0x0098A95A` -> ID `0x05`
- `0x0098AB5C` -> ID `0x05`
- `0x0098ABF6` -> ID `0x04` success
- `0x0098ADE8` -> ID `0x05`
- `0x0098AE96` -> ID `0x05`

## Wire marker hypothesis

Observed wire marker values are consistent with a transformation equivalent to `wireByte XOR 0xC6 = native message ID` for several packet classes:

- `C5 XOR C6 = 03` — controlled Join Request
- `C3 XOR C6 = 05` — unique host direct failure-like response
- `C4 XOR C6 = 02` — normal periodic VM broadcast class

Other captured host marker values such as `C7` and `D5` would decode to `01` and `13`, both within the dispatcher's proven `0x00..0x13` range.

This is **STARKER HINWEIS**, not yet a static proof of the transport codec. The next functional localization does not depend on proving this transform first.

## New failure boundary

The earlier statement "PATH_C was not reached" was too strong. The transient watcher only proved that PATH_C did not perform a visible slot commit. Given the unique direct host response and the known PATH_C ID5 failure branches, the current best boundary is:

`client 0x84CB34 -> 0x84C257 -> 0x8D925A -> UDP broadcast -> host receive/dispatch -> PATH_C validation/failure branch -> direct response`

with failure **before the Type6 slot commit**.

## Next probe

Use `tools/research/AOTR_WOTR_PATH_C_ID5_FAILURE_BRANCH_PROBE.ps1` to map each of the five ID5 writes to its exact predecessor predicates and helper calls. Do not spend another iteration on VMware/broadcast transport unless that focused control-flow evidence contradicts this packet result.

No release files were modified. The packet capture and the next probe are research-only.
