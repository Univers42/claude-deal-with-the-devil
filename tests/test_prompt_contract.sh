#!/usr/bin/env bash
# test_prompt_contract.sh — the two things prompt.md and innovator.md promised
# the rest of the kit, asserted where nothing else can.
#
# `tools/skillcheck.sh` owns the frontmatter contract of every asset (stage enum,
# quoted `since`, A14 description, report heading, `tools:`, the byte budget), and
# `tests/test_skillcheck.sh` proves each of those fails on a fixture. What no tool
# checks is content: that `/devil:prompt` still hands its clarification phase to
# the `grill` skill and still names seams by contract, and that `innovator` still
# points the spike at the `prototype` skill. A16 is a decision about prose, so it
# needs a test.
#
# Every case runs twice, against the real file and against a copy with that text
# deleted: a grep that only ever matches is not a check.
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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# has <label> <file> <text>: the file says it, and a copy without it does not
has() {
  local label="$1" f="$2" pat="$3" copy="$TMP/broken.md"
  if ! grep -qF -- "$pat" "$f"; then
    no "$label"
    return 0
  fi
  grep -vF -- "$pat" "$f" >"$copy"
  if grep -qF -- "$pat" "$copy"; then
    no "$label: matched a copy with the text removed, so the case cannot fail"
    return 0
  fi
  ok "$label"
}

has "commands/prompt.md routes its clarification phase to the grill skill" \
  "$ROOT/commands/prompt.md" 'run the `grill` skill'
has "commands/prompt.md emits a Seams section" \
  "$ROOT/commands/prompt.md" '- **Seams**:'
has "commands/prompt.md says a seam is named by contract, not by path" \
  "$ROOT/commands/prompt.md" 'never by'
has "agents/innovator.md hands the spike to the prototype skill" \
  "$ROOT/agents/innovator.md" 'the `prototype` skill'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
