# OWN_MP START/ACK P3 Timeout Root Cause

Checkpoint: 2026-08-28

## Runtime result

Three endpoints successfully joined the OWN_MP host:

```text
Host: 192.168.0.224
P3-VM: 192.168.0.57
P4/BMO: 192.168.0.139
Port: 42888
```

Host observed:

```text
JOIN ACCEPTED : P3-VM -> P3
JOIN ACCEPTED : BMO -> P4
SLOT MAP      : P1=HOST;P2=AI;P3=P3-VM;P4=BMO
ACK FAILED    : P3 P3-VM - connection aborted
ACK OK        : P4 BMO
```

## Root cause

### BEWIESEN in PoC code

`New-A8PConnectionIO` sets:

```powershell
$stream.ReadTimeout = 10000
```

After JOIN/ACCEPT, a client immediately executes:

```powershell
$start = $io.Reader.ReadLine()
```

and waits for `A8P_START`.

The host does not send `A8P_START` until all `$ExpectedClients` have joined.

Therefore the first client can only wait 10 seconds for later clients. If the second client joins after that window, the first client's `ReadLine()` times out, the client exits through `finally`, and its TCP socket closes. The host still retains the accepted client entry and later observes the closed connection when waiting for that client's ACK.

This exactly explains the observed asymmetry:

- first client P3 failed before START barrier completion;
- later client P4 remained connected and ACKed correctly.

## Classification

- P3 deterministic slot assignment: **PASS**
- P4 deterministic slot assignment: **PASS**
- three-endpoint JOIN transport: **PASS**
- START barrier V1: **FAIL due to PoC timeout bug**
- evidence of native/engine P3 limit: **NONE from this failure**

## Fix

Increase the pre-START read timeout substantially (research default: 300000 ms / 5 min) or implement an explicit lobby-wait state with heartbeat/keepalive.

For the immediate V1.1 retest:

```powershell
$stream.ReadTimeout = 300000
```

The host UI/log should also separate three counters:

```text
Remote barrier   : connected remote clients / expected remote clients
Network lobby    : host + remote clients / 8
Strategic mapped : P1 host + P2 reserved AI + remote strategic clients / 8
```

Example after only P3-VM joins:

```text
Remote barrier   : 1/2
Network lobby    : 2/8
Strategic mapped : 3/8
```

After P4/BMO joins:

```text
Remote barrier   : 2/2
Network lobby    : 3/8
Strategic mapped : 4/8
```

This avoids conflating START-barrier membership with total lobby capacity.
