#!/usr/bin/env bash
# Manual end-to-end demo: a handling-successor watcher must exit within one poll
# when a captain inbox note lands in its home queue, and only once per note.
set -u
REPO=${1:?repo root}
. "$REPO/tests/wake-helpers.sh"
TMP_ROOT=$(fm_test_tmproot fm-inbox-demo)
dir=$(make_case demo); dir=$(cd "$dir" && pwd -P); state="$dir/state"; mkdir -p "$dir/data" "$dir/config"
run_watch() {
  env PATH="$dir/fakebin:$PATH" FM_HOME="$dir" FM_STATE_OVERRIDE="$state" \
    FM_POLL=1 FM_SIGNAL_GRACE=0 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 \
    FM_SECONDMATE_LIVENESS_SECS=99999999 FM_WATCH_HANDLING_SUCCESSOR=1 \
    "$REPO/bin/fm-watch.sh" > "$dir/out" 2>&1 &
  W=$!
}
note() { FM_HOME="$dir" FM_STATE_OVERRIDE="$state" FM_DATA_OVERRIDE="$dir/data" FM_CONFIG_OVERRIDE="$dir/config" "$REPO/bin/fm-inbox.sh" note "$1"; }
waitexit() { local i=0; while kill -0 "$W" 2>/dev/null && [ $i -lt "$1" ]; do sleep 0.1; i=$((i+1)); done; ! kill -0 "$W" 2>/dev/null; }
echo "### 1. start a handling-successor watcher (FM_WATCH_HANDLING_SUCCESSOR=1, FM_POLL=1) on an empty home"
run_watch; sleep 3; kill -0 $W && echo "watcher pid $W still blocking after 3s (expected: nothing to report)"
echo; echo "### 2. captain runs: bin/fm-inbox.sh note 'please look at the release notes'"
t0=$(date +%s); note "please look at the release notes"
echo "queue rows now:"; cut -f2-4 "$state/.wake-queue" | sed 's/^/  /'
if waitexit 50; then echo "watcher exited after $(( $(date +%s) - t0 ))s with wake line:"; sed 's/^/  > /' "$dir/out"; else echo "FAIL: watcher still blocking"; fi
echo "state/.watch-queue-handed = $(cat "$state/.watch-queue-handed")   state/.wake-queue.seq = $(cat "$state/.wake-queue.seq")"
echo; echo "### 3. restart a handling successor with the same note still queued (unacknowledged)"
run_watch; sleep 4
if kill -0 $W; then echo "watcher pid $W still blocking after 4s: the same row did NOT cause a second exit"; kill -TERM $W; wait $W 2>/dev/null; else echo "FAIL: second exit:"; cat "$dir/out"; fi
echo "durable queue unchanged (drain/ack untouched):"; cut -f2-4 "$state/.wake-queue" | sed 's/^/  /'
echo; echo "### 4. away mode (state/.afk present): a new note is left to the daemon"
: > "$state/.afk"; run_watch; sleep 2; note "away note" >/dev/null; sleep 4
if kill -0 $W; then echo "away-mode watcher still blocking 4s after the note: left to daemon"; kill -TERM $W; wait $W 2>/dev/null; else echo "FAIL: exited:"; cat "$dir/out"; fi
