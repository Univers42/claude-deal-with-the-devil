#!/usr/bin/env bash
# test_index.sh — the generated tables must equal the frontmatter, and a table
# that drifts must fail the gate.
#
# Every case runs against a fixture tree with its own README and frontmatter, and
# each negative control breaks one thing first and proves the check notices: a
# check that only ever passes is not a gate. The last case runs the real tree, so
# "the committed tables are current" is a claim, not an assumption.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok() {
  echo "ok   - $1"
  PASS=$((PASS + 1))
}
no() {
  echo "FAIL - $1"
  FAIL=$((FAIL + 1))
}

# A small valid payload: one skill per stage, one command per kind, one
# tombstone, and a README carrying the five blocks empty.
fixture() {
  local d="$1"
  mkdir -p "$d"/{commands,tools/lib} "$d"/skills/{demo,legacy,solid,rule,old}
  cp "$ROOT/tools/index.sh" "$d/tools/"
  cp "$ROOT/tools/lib/common.sh" "$d/tools/lib/"
  # shellcheck disable=SC2016  # the trigger phrases are markdown quotes
  printf -- '---\nname: demo\ndescription: Do the demo thing. Use when a demo is asked for. Auto-triggers on: "demo it"\nmetadata:\n  stage: beta\n  since: "1.0.0"\n---\n\n## Report\n\nok\n' \
    >"$d/skills/demo/SKILL.md"
  # No 'Use when' yet: the first sentence stands in and says so.
  printf -- '---\nname: legacy\ndescription: Still on the old description form. Auto-triggers on: "legacy"\nmetadata:\n  stage: beta\n  since: "1.0.0"\n---\n\n## Report\n\nok\n' \
    >"$d/skills/legacy/SKILL.md"
  printf -- '---\nname: solid\ndescription: Earned its stage. Use when the record exists. Auto-triggers on: "solid"\nmetadata:\n  stage: stable\n  since: "1.0.0"\n---\n\n## Report\n\nok\n' \
    >"$d/skills/solid/SKILL.md"
  printf -- '---\nname: rule\ndescription: Go norms. Use when editing Go. Auto-triggers on: "refactor go"\npaths:\n  - "**/*.go"\n  - "**/gen/*.pb.go"\nuser-invocable: false\nmetadata:\n  stage: rule\n  since: "1.0.0"\n---\n\n## Report\n\nok\n' \
    >"$d/skills/rule/SKILL.md"
  printf -- '---\nname: old\ndescription: Retired in 1.0.0; the demo skill replaced it.\ndisable-model-invocation: true\nmetadata:\n  stage: retired\n  since: "0.9.0"\n  retired-in: "1.0.0"\n  replaced-by: demo\n---\n\nRetired.\n' \
    >"$d/skills/old/SKILL.md"
  printf -- '---\ndescription: Do the demo thing. Usage: /devil:demo <a|b>\ndisable-model-invocation: true\nargument-hint: "<a|b>"\nmetadata:\n  kind: command\n  stage: beta\n  since: "1.0.0"\n---\n\nBody\n' \
    >"$d/commands/demo.md"
  printf -- '---\ndescription: Drive the demo arc. Usage: /devil:demo-flow\nmetadata:\n  kind: workflow\n  stage: beta\n  since: "1.0.0"\n---\n\nBody\n\n## Report\n\nok\n' \
    >"$d/commands/demo-flow.md"
  printf -- '---\ndescription: Retired in 1.0.0. Usage: /devil:oldcmd\ndisable-model-invocation: true\nmetadata:\n  kind: command\n  stage: retired\n  since: "0.9.0"\n  retired-in: "1.0.0"\n  replaced-by: demo\n---\n\nRetired.\n' \
    >"$d/commands/oldcmd.md"
  {
    echo '# Fixture'
    for k in skills rules commands workflows retired; do
      echo "<!-- devil:index:$k:start -->"
      echo
      echo '| empty |'
      echo
      echo "<!-- devil:index:$k:end -->"
    done
  } >"$d/README.md"
}

# run <dir> <mode> -> the tool's exit code, output discarded
run() { bash "$1/tools/index.sh" "$2" >/dev/null 2>&1; }

# block <dir> <kind> -> the current content of one generated block
block() { sed -n "/^<!-- devil:index:$2:start -->$/,/^<!-- devil:index:$2:end -->$/p" "$1/README.md"; }

# row <dir> <kind> <text> -> the block contains that row
row() { grep -qF "$3" <<<"$(block "$1" "$2")"; }

# outside <file> -> every line that is not inside a marked block, so the two
# versions of a README can be compared for the prose a rewrite must not touch
outside() {
  awk '/^<!-- devil:index:.*:start -->$/ { s = 1; next }
       /^<!-- devil:index:.*:end -->$/ { s = 0; next }
       !s { print }' "$1"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- 1. a clean payload is written once, then current -------------------------
fixture "$TMP/clean"
if run "$TMP/clean" --check; then
  no "an unwritten fixture should drift (the blocks start empty)"
else
  ok "an unwritten fixture fails --check, so the gate is not vacuous"
fi
if run "$TMP/clean" --write && run "$TMP/clean" --check; then
  ok "--write then --check is green"
else
  no "--write should bring --check to green"
  bash "$TMP/clean/tools/index.sh" --check 2>&1 | head -5
fi

# --- 2. the columns each carry the metadata they claim to --------------------
if row "$TMP/clean" skills '| `demo` | beta | a demo is asked for |'; then
  ok "a beta skill shows its stage and the text between 'Use when' and the triggers"
else no "the skills block is missing the beta row with its Use when text"; fi
if row "$TMP/clean" skills '| `solid` | stable |'; then
  ok "a stable skill shows stable"
else no "the skills block is missing the stable row"; fi
if row "$TMP/clean" skills '| `legacy` | beta | Still on the old description form (no Use when yet) |'; then
  ok "a beta description with no 'Use when' falls back to its first sentence, and says so"
else no "the fallback for a missing 'Use when' is wrong or missing"; fi
if row "$TMP/clean" rules '| `rule` | `**/*.go`, `**/gen/*.pb.go` |'; then
  ok "a stage rule skill lands in the rules table with its globs joined"
else no "the rules block is missing the rule skill or its globs"; fi
if ! row "$TMP/clean" skills '`rule`'; then
  ok "a rule skill is listed once, under rules, not in both tables"
else no "a rule skill also appears in the skills table"; fi
if row "$TMP/clean" commands '| `demo` | beta | Do the demo thing. (you run it) | /devil:demo <a\|b> |'; then
  ok "a user-only command is marked, and a pipe in a cell is escaped"
else no "the commands block lost the user-only marker or the pipe escape"; fi
if row "$TMP/clean" workflows '| `demo-flow` | beta | Drive the demo arc. | /devil:demo-flow |'; then
  ok "a kind: workflow command lands in the workflows table"
else no "the workflows block is missing the workflow row"; fi
if row "$TMP/clean" retired '| `old` | 1.0.0 | `demo` |' && row "$TMP/clean" retired '| `oldcmd` | 1.0.0 | `demo` |'; then
  ok "a retired skill and a retired command both name their replacement, in one order"
else no "the retired block is missing a tombstone or its replacement"; fi
if [[ "$(block "$TMP/clean" retired | grep -c '^| `')" == 2 ]]; then
  ok "a rule skill and a stable skill are not listed as retired"
else no "the retired block lists the wrong number of rows"; fi

# --- 3. a hand-edited row is drift, and --write puts it back -----------------
fixture "$TMP/hand"
run "$TMP/hand" --write
sed -i 's/| `demo` | beta |/| `demo` | stable |/' "$TMP/hand/README.md"
if ! run "$TMP/hand" --check; then
  ok "a hand-edited cell makes --check exit 1"
else no "a hand-edited cell should make --check exit 1"; fi
# Captured, not piped: --check exits 1 by design, and under pipefail that status
# would become the pipeline's own and hide the diff this case is looking for.
drift="$(bash "$TMP/hand/tools/index.sh" --check 2>&1)"
if grep -q '^-.*stable' <<<"$drift"; then
  ok "--check prints the diff, not just a verdict"
else no "--check printed no diff of the drift"; fi
if run "$TMP/hand" --write && run "$TMP/hand" --check && row "$TMP/hand" skills '| `demo` | beta |'; then
  ok "--write overwrites the edit and --check is green again"
else no "--write should restore the generated row"; fi

# A row added by hand is drift too: --write removes what the frontmatter dropped.
sed -i 's/| `solid` |/| `ghost` | stable | x |/' "$TMP/hand/README.md"
if run "$TMP/hand" --write && ! row "$TMP/hand" skills '`ghost`'; then
  ok "--write deletes a row the tree no longer has"
else no "--write left a hand-added row behind"; fi

# --- 4. --write is idempotent, and touches nothing outside the blocks ---------
cp "$TMP/hand/README.md" "$TMP/hand/README.before"
if bash "$TMP/hand/tools/index.sh" --write | grep -q 'nothing written' &&
  cmp -s "$TMP/hand/README.before" "$TMP/hand/README.md"; then
  ok "a second --write changes nothing"
else no "--write is not idempotent"; fi
fixture "$TMP/prose"
run "$TMP/prose" --write
outside "$TMP/prose/README.md" >"$TMP/prose/before"
sed -i '/^| Skill |/a | `kept` | beta | a row the README owns |' "$TMP/prose/README.md"
run "$TMP/prose" --write
if ! row "$TMP/prose" skills '`kept`'; then
  ok "--write owns the whole block, not just the rows it generated"
else no "--write preserved a hand-added row inside a block"; fi
if outside "$TMP/prose/README.md" | diff -q - "$TMP/prose/before" >/dev/null; then
  ok "--write leaves every byte outside the blocks alone"
else no "--write disturbed the prose around a block"; fi

# --- 5. a block with no markers is a finding, not a silent pass --------------
fixture "$TMP/nomarker"
run "$TMP/nomarker" --write
sed -i '/devil:index:retired:end/d' "$TMP/nomarker/README.md"
if ! run "$TMP/nomarker" --check; then
  ok "a missing end marker makes --check exit 1"
else no "a half-open block should make --check exit 1"; fi

# --- 6. the router prints the same rows, and says how to invoke them ---------
out="$(bash "$TMP/clean/tools/index.sh" --router)"
if grep -qF 'Type `/devil:<name>` to run a command; skills load by themselves when their conditions match.' <<<"$out"; then
  ok "--router opens with the one line on how to invoke things"
else no "--router printed no preamble"; fi
for h in '## Skills' '## Rule skills' '## Commands' '## Workflows' '## Retired'; do
  grep -qF "$h" <<<"$out" || no "--router is missing the $h table"
done
ok "--router prints all five tables"
if grep -qF '| `demo` | beta | a demo is asked for |' <<<"$out" &&
  grep -qF '| `old` | 1.0.0 | `demo` |' <<<"$out"; then
  ok "--router rows are the generated rows, not a summary of them"
else no "--router rows differ from the generated ones"; fi

# --- 7. the real tree's committed tables are current -------------------------
if bash "$ROOT/tools/index.sh" --check >/dev/null 2>&1; then
  ok "this repo's README tables match its frontmatter"
else
  no "this repo's README tables have drifted from its frontmatter"
  bash "$ROOT/tools/index.sh" --check 2>&1 | head -15
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
