#!/usr/bin/env bash
# oc-status.sh [root] — one line per OpenCode job journal under <root>/*/target/wf (default: the
# parent of the current git top-level, i.e. the directory holding the worktrees): worktree, label,
# state, minutes since the last event, session id, and the last text the model wrote (≤200 chars).
# Never prints a transcript. States: RUNNING · done(rc=N) · DEAD (process gone, no rc) · STALLED.
# Caveat: STALLED is mtime-based (>OC_STALL_MIN, default 30, minutes without a journal write); a
# job thinking silently for longer is reported stalled. Look at the session in the OpenCode UI
# (`opencode -s <id>`, from the worktree) before interrupting it.
set -uo pipefail
root=${1:-$(dirname "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")}
stall=${OC_STALL_MIN:-30}
now=$(date +%s)
for j in "$root"/*/target/wf/*.jsonl; do
  [[ -e $j ]] || continue
  base=${j%.jsonl}
  label=$(basename "$base")
  wt=$(basename "$(dirname "$(dirname "$(dirname "$j")")")")
  age=$(((now - $(stat -c %Y "$j")) / 60))
  if [[ -f $base.rc ]]; then
    state="done(rc=$(cat "$base.rc"))"
  elif [[ -f $base.pid ]] && kill -0 "$(cat "$base.pid")" 2>/dev/null; then
    state=RUNNING
    ((age > stall)) && state=STALLED
  else state=DEAD; fi
  sid=$(cat "$base.session-id" 2>/dev/null)
  [[ -n $sid ]] || sid=$(jq -r '.sessionID // empty' "$j" 2>/dev/null | head -1)
  last=$(jq -r '.. | objects | select(.type? == "text") | .text? // empty' "$j" 2>/dev/null | tail -c 200 | tr '\n' ' ')
  printf '%-8s %-26s %-12s %4sm %s | %s\n' "$wt" "$label" "$state" "$age" "${sid:--}" "$last"
done
