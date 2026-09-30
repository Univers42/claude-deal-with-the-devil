#!/usr/bin/env bash
# oc-job.sh <label> <worktree> <agent> <body-file> [rows-file] — one verified OpenCode job:
# prompt = common rules ($OC_COMMON_PROMPT, optional) + body; run it (oc-run.sh); require the
# agent's return block to say `status: done`; optionally run a rows gate (gate.sh); only then
# commit and push the worktree's branch. Prints ≤40 lines: job rc, the return block, the gate summary.
#
# Exit: 0 done + gate green (+ pushed) · 1 gate red · 2 agent not done (blocked/partial/died)
#       · 3 another OpenCode job already works in this worktree (one agent per worktree).
# Env: OC_COMMON_PROMPT (file prepended to every body), OC_COMMIT_MSG (default "updated"),
#      OC_GIT_NAME / OC_GIT_EMAIL (default: git's configured identity), plus oc-run.sh's.
# Ponytail: `status: done` is the agent's own claim, and without a rows file nothing checks it
# before the push — pass rows, or re-run the gates yourself before merging the branch.
set -uo pipefail
[[ $# -ge 4 ]] || {
  echo "usage: oc-job.sh <label> <worktree> <agent> <body-file> [rows-file]" >&2
  exit 2
}
label=$1 wt=$2 agent=$3 body=$4 rows=${5-}
here=$(cd "$(dirname "$0")" && pwd)
for p in $(pgrep -f '/opencode run' || true); do
  [[ $(readlink "/proc/$p/cwd" 2>/dev/null) == "$(cd "$wt" && pwd -P)" ]] &&
    {
      echo "refused: pid $p already works in $wt"
      exit 3
    }
done
wf=$wt/target/wf
mkdir -p "$wf"
prompt=$wf/$label.prompt
cat ${OC_COMMON_PROMPT:+"$OC_COMMON_PROMPT"} "$body" >"$prompt"
"$here/oc-run.sh" "$label" "$wt" "$agent" "$prompt"
rc=$?
ret=$(jq -r 'select(.part.type=="text") | .part.text' "$wf/$label.jsonl" 2>/dev/null | tail -n 30)
echo "job rc=$rc"
echo "$ret"
[[ $rc -eq 0 ]] && grep -q 'status: done' <<<"$ret" || exit 2
if [[ -n $rows ]]; then
  (cd "$wt" && "$here/gate.sh" "target/gate-$label" "$rows") >/dev/null
  g=$?
  cat "$wt/target/gate-$label/summary.txt"
  [[ $g -eq 0 ]] || exit 1
fi
ident=()
[[ -n ${OC_GIT_NAME-} ]] && ident+=(-c "user.name=$OC_GIT_NAME")
[[ -n ${OC_GIT_EMAIL-} ]] && ident+=(-c "user.email=$OC_GIT_EMAIL")
cd "$wt" && git add -A && { git diff --cached --quiet ||
  git "${ident[@]}" commit -q -m "${OC_COMMIT_MSG:-updated}"; } && git push -q origin HEAD 2>&1 | tail -n 2
echo "committed $(git rev-parse --abbrev-ref HEAD) $(git rev-parse --short HEAD)"
