#!/usr/bin/env bash
# oc-run.sh <label> <worktree> <agent> <prompt-file> — one headless OpenCode job.
# Journal in <worktree>/target/wf/: <label>.jsonl (every event), .pid, .rc (on exit), .session-id,
# .stderr. Exits with opencode's own code.
#
# Env: OC (opencode binary; default: on PATH, else ~/.opencode/bin/opencode),
#      OC_MODEL (default opencode/space-bunny-free#max; the variant goes after '#'),
#      OC_TIMEOUT seconds (default 14400).
# Caveat: the hard timeout also kills a slow-but-alive job; resume it with
# `opencode run --session <id>` instead of relaunching from scratch.
set -uo pipefail
[[ $# -eq 4 ]] || {
  echo "usage: oc-run.sh <label> <worktree> <agent> <prompt-file>" >&2
  exit 2
}
label=$1 wt=$2 agent=$3 prompt=$4
OC=${OC:-$(command -v opencode || echo "$HOME/.opencode/bin/opencode")}
MODEL=${OC_MODEL:-opencode/space-bunny-free#max}
wf=$wt/target/wf
mkdir -p "$wf"
j=$wf/$label.jsonl
echo $$ >"$wf/$label.pid"
rm -f "$wf/$label.rc"
cd "$wt" || exit 1
timeout "${OC_TIMEOUT:-14400}" "$OC" run -m "$MODEL" --agent "$agent" --format json --auto \
  --title "$label" "$(cat "$prompt")" >"$j" 2>"$wf/$label.stderr"
rc=$?
echo "$rc" >"$wf/$label.rc"
jq -r '.. | .sessionID? // empty' "$j" 2>/dev/null | head -1 >"$wf/$label.session-id"
exit "$rc"
