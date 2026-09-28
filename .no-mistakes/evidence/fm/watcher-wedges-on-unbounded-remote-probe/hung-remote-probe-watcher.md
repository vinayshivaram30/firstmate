# Live repro: watcher vs a remote host that accepts ssh then hangs

Driver: `hung-remote-probe-watcher.sh` (same directory). Isolated FM_HOME, one
registered remote secondmate, fake `ssh` that accepts the connection and never
returns, real `bin/fm-watch.sh` supervising for 30s. FM_SECONDMATE_PROBE_TIMEOUT=5.

## Base commit 6b0f5a0 (liveness lib reverted) - the reported stall

    === state/.watch-triage.log ===
    (no triage log)
    === heartbeat ===
    watcher beacon age: 30s (watcher pid 10841 alive: yes)
    === ssh probes started: 1 ===
    LEAKED ssh pid 11129
    LEAKED ssh pid 11353

Watcher alive but beacon never refreshed after the first probe (30s and growing =
the "heartbeat is stale" / "TURN WOULD END BLIND" symptom); the probe's ssh and its
ProxyCommand-stand-in child outlive the watcher.

## Head ab806af - bounded probe

    === state/.watch-triage.log ===
    [2026-09-28T17:11:10+0530] secondmate rsm1 liveness: remote state probe exceeded its 5s bound; endpoint state unknown; route preserved on lab-host
    [2026-09-28T17:11:17+0530] secondmate rsm1 liveness: remote state probe exceeded its 5s bound; endpoint state unknown; route preserved on lab-host
    [2026-09-28T17:11:24+0530] secondmate rsm1 liveness: remote state probe exceeded its 5s bound; endpoint state unknown; route preserved on lab-host
    [2026-09-28T17:11:30+0530] secondmate rsm1 liveness: remote state probe exceeded its 5s bound; endpoint state unknown; route preserved on lab-host
    === heartbeat ===
    watcher beacon age: 4s (watcher pid 86092 alive: yes)
    === ssh probes started: 5 ===

Beacon fresh, cycle keeps turning, each hung probe abandoned as unknown with the
route preserved, no ssh process left behind, no relaunch/failover.
