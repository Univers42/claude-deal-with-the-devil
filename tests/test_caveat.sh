#!/usr/bin/env bash
# test_caveat.sh — the limitation marker gate, and the collision the rename fixed.
#
# The tool had no test, so nothing pinned the marker down. That is how a
# case-insensitive `grep -qi 'ponytail:'` came to accept a *minimalism* note
# (`ponytail: <ceiling>`) as if it stated what a heuristic gets wrong: a note
# about a ceiling silently silenced an unrelated finding in the same file. Case
# (4) is the negative control for that, and it is the reason the marker is now
# `Caveat:`, matched case-sensitively.
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

# fixture <dir> — a tree holding the real tool and library, plus one source file
# <name> whose body the caller supplies. The signal every case shares is
# `re.compile`, which the tool's CONSTRUCT pattern reads as an approximation.
fixture() {
  local d="$1" name="$2"
  mkdir -p "$d/tools/lib"
  cp "$ROOT/tools/caveat.sh" "$d/tools/"
  cp "$ROOT/tools/lib/common.sh" "$d/tools/lib/"
  printf '%s\n' "$3" >"$d/$name"
}

# scan <dir> [args...] — the tool's markdown, from inside the fixture tree.
# repo_root() falls back to the CWD outside git, so cd is the whole harness.
scan() {
  local d="$1"
  shift
  (cd "$d" && bash "$d/tools/caveat.sh" "$@" 2>&1)
}

# reports <dir> <file> — the tool names <file> as an unmarked signal.
reports() {
  grep -qF "$2" <<<"$(scan "$1" --summary)"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SIGNAL='import re

PAT = re.compile(r"a|b")
'

# --- 1. a signal with no marker is a finding, and --strict fails --------------
fixture "$TMP/bare" demo.py "$SIGNAL"
if reports "$TMP/bare" '`demo.py'; then ok "a signal with no marker is reported"; else
  no "a signal with no marker should be reported"
fi
scan "$TMP/bare" --strict >/dev/null
if [ $? -eq 1 ]; then ok "--strict exits 1 on a finding"; else no "--strict should exit 1"; fi

# --- 2. the marker silences it, and the file is counted as marked -------------
fixture "$TMP/marked" demo.py "# Caveat: re.compile over an import line, so a
# dynamic import is missed. Under-reports: read the real graph before deleting.
$SIGNAL"
out="$(scan "$TMP/marked" --strict --summary)"
rc=$?
# The tool and the library it sources carry their own markers, so assert on this
# fixture's file rather than on the tree total.
if [ "$rc" -eq 0 ] && ! grep -qF 'demo.py' <<<"$out" && grep -qF '(0 legacy' <<<"$out"; then
  ok "a Caveat: marker counts as marked and --strict exits 0"
else no "Caveat: marker not honoured (rc=$rc): $(tail -3 <<<"$out")"; fi

# --- 3. the legacy marker is accepted, counted separately, never a failure ----
fixture "$TMP/legacy" demo.py "# Ponytail: re.compile over an import line, so a
# dynamic import is missed. Under-reports: read the real graph before deleting.
$SIGNAL"
out="$(scan "$TMP/legacy" --strict --summary)"
rc=$?
if [ "$rc" -eq 0 ] && ! grep -qF '| `demo.py' <<<"$out" &&
  grep -qF '(1 legacy Ponytail:)' <<<"$out" &&
  grep -qF 'INFO: 1 file(s) marked with the legacy' <<<"$out"; then
  ok "a legacy Ponytail: marker is clean, INFO, and counted as legacy"
else no "legacy marker mishandled (rc=$rc): $(tail -4 <<<"$out")"; fi

# --- 4. the collision: a lowercase minimalism note is NOT a marker -----------
# `ponytail: <ceiling>` is what a minimalism skill writes about a size ceiling.
# It says nothing about what a heuristic gets wrong, so it must not count. The
# old case-insensitive match read it as a marker and passed this silently.
fixture "$TMP/collide" demo.ts "// ponytail: ceiling, upgrade path
export const PAT = re.compile('a');
"
if reports "$TMP/collide" '`demo.ts'; then
  ok "a lowercase ponytail: note does not silence the finding (the collision)"
else no "a lowercase ponytail: note wrongly counted as a marker"; fi
scan "$TMP/collide" --strict >/dev/null
if [ $? -eq 1 ]; then ok "--strict exits 1 on the collision fixture"; else
  no "--strict should exit 1 on the collision fixture"
fi

# --- 5. a lowercase caveat: is not a marker either ---------------------------
fixture "$TMP/lower" demo.sh "# caveat: this reads as a marker but is lowercase.
grep -E 'a|b' /dev/null
"
if reports "$TMP/lower" '`demo.sh'; then ok "a lowercase caveat: is not a marker"; else
  no "a lowercase caveat: wrongly counted as a marker"
fi

# --- 6. the real tree is clean ------------------------------------------------
if bash "$ROOT/tools/caveat.sh" --strict --summary >/dev/null 2>&1; then
  ok "this repo's own tree is clean (--strict)"
else
  no "this repo's own tree has an unmarked signal"
  bash "$ROOT/tools/caveat.sh" --strict --summary 2>&1 | head -12
fi

# --- 7. the word only survives where it has to -------------------------------
# The bare word is a retired name and a legacy marker spelling, so it belongs in
# the tool that accepts it, the test that pins it, the rule that documents it and
# the retired tombstone. skills/caveat/ is on the list because a skill that
# rewrites markers has to be able to name the one it must not touch. README.md is
# on it because the generated retired table is where a renamed asset stays
# visible: the row naming the tombstone and its replacement is the whole reason
# the table exists, and hiding the name would leave a dangling reference instead.
extra='skills/caveat/SKILL.md|CHANGELOG.md|README.md'
allow="tools/caveat.sh|tests/test_caveat.sh|rules/caveat.md|skills/ponytail/SKILL.md"
# dist/ is skipped on purpose: a generated harness copy inherits the word from
# the source it was generated from, that source is checked here, and
# `tools/export.sh --check` is what proves the copy still matches it. Grepping
# the copy would only prove the generator ran.
hits="$(cd "$ROOT" && grep -rniIl ponytail . --exclude-dir=.git --exclude-dir=target --exclude-dir=dist |
  sed 's|^\./||' | grep -vE "^($allow|$(echo "$extra" | tr '|' '\n' | paste -sd'|' -))$")"
if [ -z "$hits" ]; then ok "ponytail survives only in the allowlist"; else
  no "ponytail also appears in: $(echo "$hits" | tr '\n' ' ')"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
