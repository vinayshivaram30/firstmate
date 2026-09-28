#!/usr/bin/env bash
# Operator-level repro: a real bin/fm-watch.sh supervising one remote secondmate
# whose host accepts the ssh connection and then hangs inside the remote command.
# Prints the watcher's own triage log and heartbeat freshness, the two things the
# turn-end guard reads ("TURN WOULD END BLIND" comes from a stale beacon).
set -u
ROOTDIR=${1:?worktree}
cd "$ROOTDIR"
. tests/lib.sh
. tests/wake-helpers.sh
TMP_ROOT=$(fm_test_tmproot fm-hung-probe-evidence)
dir="$TMP_ROOT/case"; home="$TMP_ROOT/case-mate"
mkdir -p "$dir/state" "$dir/config" "$dir/data" "$dir/fakebin" "$home"
printf 'codex\n' > "$dir/config/crew-harness"
cat > "$dir/state/rsm1.meta" <<EOF
window=remote:rsm1
kind=secondmate
harness=claude
remote_host=lab-host
remote_backend=herdr
remote_herdr_session=fm-remote
remote_target=fm-remote:w1:p1
home=/remote/rsm1-home
EOF
printf -- '- rsm1 - Remote mate (host: lab-host; root: /remote/root; home: /remote/rsm1-home; scope: remote work; projects: alpha; added 2026-01-01)\n' > "$dir/data/secondmates.md"
cat > "$dir/fakebin/tmux" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$dir/fakebin/tmux"
cat > "$dir/fakebin/ssh" <<'SH'
#!/usr/bin/env bash
# accepts the connection, then never returns - keepalives are answered forever
sleep 600 &
printf '%s %s\n' "$$" "$!" >> "${FM_FAKE_SSH_PIDS:?}"
wait
SH
chmod +x "$dir/fakebin/ssh"
: > "$dir/ssh.pids"
make_fake_crew_state "$dir/fakebin" >/dev/null
env PATH="$dir/fakebin:$PATH" FM_HOME="$dir" FM_ROOT_OVERRIDE="$ROOT" \
  FM_STATE_OVERRIDE="$dir/state" FM_CREW_STATE_BIN="$dir/fakebin/fm-crew-state.sh" \
  TMUX='' FM_BACKEND=tmux FM_SSH_BIN="$dir/fakebin/ssh" FM_FAKE_SSH_PIDS="$dir/ssh.pids" \
  FM_SECONDMATE_LIVENESS_SECS=1 FM_SECONDMATE_PROBE_TIMEOUT="${FM_SECONDMATE_PROBE_TIMEOUT:-5}" \
  FM_POLL=1 FM_SIGNAL_GRACE=0 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 \
  bin/fm-watch.sh > "$dir/watch.out" 2> "$dir/watch.err" &
pid=$!
sleep 30
echo "=== state/.watch-triage.log ==="
cat "$dir/state/.watch-triage.log" 2>/dev/null || echo "(no triage log)"
echo "=== heartbeat ==="
now=$(date +%s)
if [ -f "$dir/state/.last-watcher-beat" ]; then
  beat=$(stat -f %m "$dir/state/.last-watcher-beat")
  echo "watcher beacon age: $((now-beat))s (watcher pid $pid alive: $(kill -0 $pid 2>/dev/null && echo yes || echo no))"
else
  echo "no beacon written"
fi
echo "=== ssh probes started: $(wc -l < "$dir/ssh.pids" | tr -d ' ') ==="
kill -TERM "$pid" 2>/dev/null || true; sleep 2
while read -r a b; do for p in "$a" "$b"; do kill -0 "$p" 2>/dev/null && echo "LEAKED ssh pid $p"; kill -KILL "$p" 2>/dev/null; done; done < "$dir/ssh.pids"
rm -rf "$TMP_ROOT"
