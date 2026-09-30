#!/usr/bin/env bash
# test_grill_prototype.sh: the two ported skills must keep the shape the kit
# promises, and the shape check must be able to fail.
#
# Nothing in the tree yet enforces a skill's frontmatter contract (that is
# `tools/skillcheck.sh`, not in this worktree), so these two skills could drift
# into a 460-byte description, an unquoted `since` YAML reads as a float, or a body
# that stops at the last step with no `## Report`. Each assertion below is run
# once against the real file and once against a copy of it with exactly that thing
# broken: a check that only ever passes is not a gate.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../tools/lib/common.sh
. "$ROOT/tools/lib/common.sh"
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

BUDGET=400

# violations <file>: one line per broken promise, nothing when the file is good.
violations() {
  local f="$1" desc n
  fm_block "$f" | grep -q '^tools:' && echo "uses 'tools:', not a skill field"
  grep -q '^## Report' "$f" || echo "no '## Report' heading"
  grep -qE '^Caveat:' "$f" || echo "no 'Caveat:' on the bounded read it prescribes"
  case "$(fm_meta "$f" stage)" in
  stable | beta | retired) ;;
  *) echo "metadata.stage is '$(fm_meta "$f" stage)', not stable/beta/retired" ;;
  esac
  fm_block "$f" | grep -qE '^  since: "[^"]+"$' || echo "metadata.since missing or unquoted"
  desc="$(fm_desc "$f")"
  case "$desc" in *"Use when"*) ;; *) echo "description has no 'Use when' clause" ;; esac
  case "$desc" in *'"'*) ;; *) echo "description names no trigger phrase" ;; esac
  n="$(printf '%s' "$desc" | wc -c)"
  [ "$n" -le "$BUDGET" ] || echo "description is $n bytes, over the $BUDGET budget"
  return 0
}

# clean <file> / broken <file> <label>: the real file, and a copy with <mutate>
# applied. `sed` is the mutation; the assertion is the same for both.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for s in grill prototype; do
  real="$ROOT/skills/$s/SKILL.md"
  out="$(violations "$real")"
  if [ -z "$out" ]; then
    ok "skills/$s keeps the skill contract"
  else no "skills/$s: $(tr '\n' '; ' <<<"$out")"; fi

  cp "$real" "$TMP/$s.md"
  sed -i 's/^  stage: beta$/  stage: golden/' "$TMP/$s.md"
  if violations "$TMP/$s.md" | grep -q "metadata.stage is 'golden'"; then
    ok "skills/$s: a stage outside the enum is reported"
  else
    no "skills/$s: an unknown metadata.stage passed"
  fi

  cp "$real" "$TMP/$s.md"
  sed -i 's/^  since: "\(.*\)"$/  since: \1/' "$TMP/$s.md"
  if violations "$TMP/$s.md" | grep -q "unquoted"; then
    ok "skills/$s: an unquoted since is reported (YAML would read 1.0 as a float)"
  else
    no "skills/$s: an unquoted since passed"
  fi

  cp "$real" "$TMP/$s.md"
  sed -i 's/^  Use when /  When /' "$TMP/$s.md"
  if violations "$TMP/$s.md" | grep -q "Use when"; then
    ok "skills/$s: a description without 'Use when' is reported"
  else
    no "skills/$s: a missing 'Use when' clause passed"
  fi

  cp "$real" "$TMP/$s.md"
  sed -i 's/^## Report$/## Done/' "$TMP/$s.md"
  if violations "$TMP/$s.md" | grep -q "'## Report'"; then
    ok "skills/$s: a body ending without '## Report' is reported"
  else
    no "skills/$s: a missing '## Report' passed"
  fi

  cp "$real" "$TMP/$s.md"
  sed -i 's/^allowed-tools:/tools:/' "$TMP/$s.md"
  if violations "$TMP/$s.md" | grep -q "'tools:'"; then
    ok "skills/$s: the Cursor field 'tools:' is reported"
  else
    no "skills/$s: a 'tools:' field passed"
  fi

  cp "$real" "$TMP/$s.md"
  sed -i 's/^Caveat: /Note: /' "$TMP/$s.md"
  if violations "$TMP/$s.md" | grep -q "Caveat"; then
    ok "skills/$s: a removed Caveat marker is reported"
  else
    no "skills/$s: a heuristic with no Caveat passed"
  fi
done

# The description budget is a real limit, so prove it fires on a plausible one:
# the same description with a fourth trigger phrase is what pushed it over.
cp "$ROOT/skills/grill/SKILL.md" "$TMP/long.md"
sed -i 's|^  Auto-triggers on: "grill me", "what have we decided", "ask me the hard questions"$|  Auto-triggers on: "grill me", "what have we decided", "ask me the hard questions",\n  "before we build this", "I do not know what we decided"|' "$TMP/long.md"
if violations "$TMP/long.md" | grep -q "over the"; then
  ok "a description past 400 bytes is reported"
else
  no "an over-budget description passed"
fi

# What /devil:prompt promised: it hands off to grill, and its spec names seams by
# contract. A prompt command that loses either has silently re-broken A16.
if grep -q 'run the `grill` skill' "$ROOT/commands/prompt.md"; then
  ok "commands/prompt.md routes its clarification phase to grill"
else
  no "commands/prompt.md no longer names the grill skill"
fi
if grep -qE '^\- \*\*Seams\*\*[:,] ' "$ROOT/commands/prompt.md"; then
  ok "commands/prompt.md emits a Seams section"
else
  no "commands/prompt.md has no Seams section"
fi
if grep -q 'never by' "$ROOT/commands/prompt.md"; then
  ok "commands/prompt.md says a seam is named by contract, not by path"
else
  no "commands/prompt.md does not say seams are not paths"
fi

# The one line the innovator agent owes the spike.
if grep -q '`prototype` skill' "$ROOT/agents/innovator.md"; then
  ok "agents/innovator.md points at the prototype skill"
else
  no "agents/innovator.md does not point at the prototype skill"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
