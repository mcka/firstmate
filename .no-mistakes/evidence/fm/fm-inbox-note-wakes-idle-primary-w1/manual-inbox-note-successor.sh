#!/usr/bin/env bash
# Manual E2E: a real fm-inbox.sh note against a real handling-successor fm-watch.sh.
set -u
ROOT=${1:?repo root}
. "$ROOT/tests/wake-helpers.sh"
TMP_ROOT=$(fm_test_tmproot manual-inbox-successor)
dir=$(make_case home); dir=$(cd "$dir" && pwd -P); mkdir -p "$dir/data" "$dir/config"
note() { FM_HOME="$dir" FM_STATE_OVERRIDE="$dir/state" FM_DATA_OVERRIDE="$dir/data" FM_CONFIG_OVERRIDE="$dir/config" "$ROOT/bin/fm-inbox.sh" note "$1"; }
watch() { env PATH="$dir/fakebin:$PATH" FM_HOME="$dir" FM_STATE_OVERRIDE="$dir/state" FM_POLL=1 FM_SIGNAL_GRACE=0 \
  FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 FM_SECONDMATE_LIVENESS_SECS=99999999 FM_WATCH_HANDLING_SUCCESSOR="$1" "$ROOT/bin/fm-watch.sh"; }
echo "\$ fm-inbox.sh note 'first note'"; note "first note" >/dev/null
echo "\$ fm-watch.sh   (plain watcher, primary between turns)"; watch 0
echo "  .watch-queue-handed = $(cat "$dir/state/.watch-queue-handed" 2>/dev/null)"
echo "\$ FM_WATCH_HANDLING_SUCCESSOR=1 fm-watch.sh &   (successor started by Stop hook)"
watch 1 > "$dir/succ.out" 2>&1 & pid=$!
sleep 4; kill -0 $pid && echo "  after 4s: successor still blocking (already-handed note not re-announced)"
echo "\$ fm-inbox.sh note 'captain: please check PR 42'"; t0=$(date +%s); note "captain: please check PR 42" >/dev/null
wait $pid; rc=$?; t1=$(date +%s)
echo "  successor exited rc=$rc after $((t1-t0))s (FM_POLL=1) with:"; sed 's/^/    /' "$dir/succ.out"
echo "  .watch-queue-handed = $(cat "$dir/state/.watch-queue-handed")  queue rows still queued: $(grep -c . "$dir/state/.wake-queue")"
echo "\$ FM_WATCH_HANDLING_SUCCESSOR=1 fm-watch.sh &   (next successor, same rows still queued)"
watch 1 > "$dir/succ2.out" 2>&1 & pid=$!
sleep 5; if kill -0 $pid; then echo "  after 5s: still blocking, no repeat wake for the same row sequence"; kill -TERM $pid; wait $pid 2>/dev/null; fi
echo "  output: '$(cat "$dir/succ2.out")'"
