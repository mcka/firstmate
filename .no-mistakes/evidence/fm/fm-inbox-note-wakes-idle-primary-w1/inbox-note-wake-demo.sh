#!/usr/bin/env bash
# Manual end-to-end demo: an idle primary's handling successor watcher wakes on a
# captain inbox note written by bin/fm-inbox.sh note, exactly once per row.
# Usage: inbox-note-wake-demo.sh <repo-root>
set -u
R=$1
. "$R/tests/wake-helpers.sh"
WATCH="$R/bin/fm-watch.sh"
TMP_ROOT=$(fm_test_tmproot fm-inbox-wake-demo)
dir=$(make_case demo); dir=$(cd "$dir" && pwd -P); state=$dir/state
mkdir -p "$dir/data" "$dir/config"
ts() { date '+%H:%M:%S'; }
run_watch() { env PATH="$dir/fakebin:$PATH" FM_HOME="$dir" FM_STATE_OVERRIDE="$state" \
  FM_POLL=1 FM_SIGNAL_GRACE=0 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 \
  FM_SECONDMATE_LIVENESS_SECS=99999999 FM_WATCH_HANDLING_SUCCESSOR=1 "$WATCH" > "$1" 2>&1 & }
note() { FM_HOME="$dir" FM_STATE_OVERRIDE="$state" FM_DATA_OVERRIDE="$dir/data" \
  FM_CONFIG_OVERRIDE="$dir/config" "$R/bin/fm-inbox.sh" note "$1"; }

echo "[$(ts)] start handling successor watcher (primary idle between turns)"
run_watch "$dir/w1.out"; pid=$!
sleep 3
kill -0 $pid 2>/dev/null && echo "[$(ts)] watcher pid $pid is blocking (no rows queued)"
echo "[$(ts)] captain writes: fm-inbox.sh note 'please check the release branch'"
note "please check the release branch"
start=$(date +%s)
for i in $(seq 1 100); do kill -0 $pid 2>/dev/null || break; sleep 0.1; done
if kill -0 $pid 2>/dev/null; then echo "[$(ts)] FAIL: watcher still blocking after 10s"; kill $pid; else
  echo "[$(ts)] watcher exited after ~$(( $(date +%s) - start ))s with stdout:"; sed 's/^/    /' "$dir/w1.out"; fi
echo "durable queue (unchanged, not drained by the watcher):"; sed 's/^/    /' "$state/.wake-queue"
echo "state/.watch-queue-handed = $(cat "$state/.watch-queue-handed")  state/.wake-queue.seq = $(cat "$state/.wake-queue.seq")"
echo "[$(ts)] start the next successor with the same row still queued (unacknowledged)"
run_watch "$dir/w2.out"; pid=$!
sleep 6
if kill -0 $pid 2>/dev/null; then echo "[$(ts)] next successor still blocking after 6 polls: no repeat wake for the same row"; else echo "[$(ts)] FAIL: repeat wake: $(cat "$dir/w2.out")"; fi
kill -TERM $pid 2>/dev/null; wait $pid 2>/dev/null
