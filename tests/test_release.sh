#!/usr/bin/env bash
# test_release.sh — release.sh must fail on the drift a version source drifts into.
#
# A gate that only ever passes is not a gate, so most cases below build a
# deliberately broken fixture repo and prove the check catches it:
#   - plugin.json and the changelog heading disagree
#   - the marketplace manifest carries a second `version`
#   - a retired asset is missing from the changelog, or named without its
#     replacement
# and three prove the refusals: a dirty tree, a level that does not exist, and
# bad usage.
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

# is <got> <want> <what it proves>
is() {
  if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (got '$1', want '$2')"; fi
}

# A fixture repo with the two manifests, a changelog and one retired skill,
# committed so the tree is clean enough to cut a release in it.
fixture() {
  local d="$1" ver="${2:-0.9.0}"
  mkdir -p "$d/tools/lib" "$d/.claude-plugin" "$d/skills/ghost"
  cp "$ROOT/tools/release.sh" "$d/tools/"
  cp "$ROOT/tools/lib/common.sh" "$ROOT/tools/lib/release-bump.sh" "$d/tools/lib/"
  chmod +x "$d/tools/release.sh"
  printf '{ "name": "devil", "version": "%s" }\n' "$ver" >"$d/.claude-plugin/plugin.json"
  printf '{ "name": "univers42", "plugins": [ { "name": "devil", "source": "./" } ] }\n' \
    >"$d/.claude-plugin/marketplace.json"
  changelog "$d" "$ver"
  printf -- '---\nname: ghost\ndescription: A retired skill.\nmetadata:\n  stage: retired\n  since: "0.9.0"\n  replaced-by: demo\n---\n\nRetired. Use demo.\n' \
    >"$d/skills/ghost/SKILL.md"
  git -C "$d" init -q
  git -C "$d" config user.name fixture
  git -C "$d" config user.email fixture@example.invalid
  git -C "$d" add -A
  git -C "$d" commit -q -m fixture
}

changelog() {
  cat >"$1/CHANGELOG.md" <<EOF
# Changelog

## [Unreleased]

### Added

- nothing yet

## [$2] - 2026-09-29

- fixture baseline
EOF
}

# The release note a retirement is required to carry.
retired_entry() { echo "- \`ghost\` is retired; use \`demo\` instead" >>"$1/CHANGELOG.md"; }

# Read the version back with grep, so the suite needs no jq and the assertion
# stays independent of the tool's own reader.
# Caveat: substring matching on a hand-written fixture file; it reads the first
# `"version"` on any line, which is all a two-key fixture can contain.
version_of() { grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$1" | head -1 | cut -d'"' -f4; }

run() { bash "$1/tools/release.sh" --check >/dev/null 2>&1; }

# rc <fixture> <subcommand> [args...] — the tool's exit code, its output dropped.
# The tool resolves its own payload root, so no cwd juggling is needed.
rc() {
  local d="$1" sub="$2"
  shift 2
  bash "$d/tools/release.sh" "$sub" "$@" >/dev/null 2>&1
  echo $?
}

# A fixed release date keeps the heading this test asserts on reproducible.
export RELEASE_DATE=2030-01-02

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- 1. the clean fixture passes --------------------------------------------
fixture "$TMP/clean"
retired_entry "$TMP/clean"
is "$(rc "$TMP/clean" --check)" 0 "clean fixture exits 0"

# --- 2. plugin.json disagreeing with the changelog fails --------------------
fixture "$TMP/mismatch"
sed -i 's/"version": "0.9.0"/"version": "0.9.1"/' "$TMP/mismatch/.claude-plugin/plugin.json"
if run "$TMP/mismatch"; then no "a version/heading mismatch should fail"; else
  ok "version/heading mismatch fails"
fi

# --- 3. a second version in the marketplace manifest fails ------------------
fixture "$TMP/market"
sed -i 's|"source": "./"|"source": "./", "version": "0.9.0"|' \
  "$TMP/market/.claude-plugin/marketplace.json"
if run "$TMP/market"; then no "a version in marketplace.json should fail"; else
  ok "marketplace.json carrying a version fails (plugin.json is the source)"
fi

# --- 4. a retired asset missing from the changelog fails -------------------
fixture "$TMP/unrecorded"
if run "$TMP/unrecorded"; then no "an unrecorded retired skill should fail"; else
  ok "retired skill absent from the changelog fails"
fi

# --- 5. a retired asset named WITHOUT its replacement still fails -----------
fixture "$TMP/half"
echo "- \`ghost\` is retired" >>"$TMP/half/CHANGELOG.md"
if run "$TMP/half"; then no "a retirement without its replacement should fail"; else
  ok "retired skill named without its replacement fails"
fi

# --- 6. bump patch cuts the release -----------------------------------------
fixture "$TMP/bump"
retired_entry "$TMP/bump"
git -C "$TMP/bump" add -A
git -C "$TMP/bump" commit -q -m "record the retirement"
is "$(rc "$TMP/bump" bump patch)" 0 "bump patch on a clean tree exits 0"
is "$(git -C "$TMP/bump" log -1 --format=%s)" "chore(release): v0.9.1" "HEAD is the release commit"
if git -C "$TMP/bump" rev-parse -q --verify refs/tags/v0.9.1 >/dev/null 2>&1; then
  ok "tag v0.9.1 exists"
else
  no "tag v0.9.1 was not created"
fi
is "$(version_of "$TMP/bump/.claude-plugin/plugin.json")" "0.9.1" "plugin.json says 0.9.1"
if grep -q '^## \[0.9.1\] - 2030-01-02$' "$TMP/bump/CHANGELOG.md"; then
  ok "changelog opened 0.9.1 on the given date (RELEASE_DATE)"
else
  no "changelog did not open 0.9.1 on the given date"
fi
is "$(rc "$TMP/bump" --check)" 0 "--check still passes on the bumped repo"

# --- 6b. bump re-exports every dist/<harness>/ in the release commit ------
# A stub export.sh copies the version it reads, the way the real generators do.
fixture "$TMP/dist"
retired_entry "$TMP/dist"
mkdir -p "$TMP/dist/dist/stub"
cat >"$TMP/dist/tools/export.sh" <<'STUB'
#!/usr/bin/env bash
root="$(cd "$(dirname "$0")/.." && pwd)"
grep -o '"version": "[^"]*"' "$root/.claude-plugin/plugin.json" >"$root/dist/$1/version"
STUB
bash "$TMP/dist/tools/export.sh" stub
git -C "$TMP/dist" add -A
git -C "$TMP/dist" commit -q -m "stub dist"
is "$(rc "$TMP/dist" bump minor)" 0 "bump minor with a dist exits 0"
is "$(git -C "$TMP/dist" show HEAD:dist/stub/version)" '"version": "0.10.0"' \
  "the release commit carries the re-exported dist"
is "$(git -C "$TMP/dist" status --porcelain)" "" "nothing is left uncommitted"
rm "$TMP/dist/tools/export.sh"
git -C "$TMP/dist" commit -qam "drop the generator"
is "$(rc "$TMP/dist" bump patch)" 0 "no export.sh: the dist is left alone (negative control)"
is "$(git -C "$TMP/dist" show HEAD:dist/stub/version)" '"version": "0.10.0"' \
  "without the generator the dist keeps its old version"

# --- 7. a dirty tree is refused ---------------------------------------------
fixture "$TMP/dirty"
echo "stray" >>"$TMP/dirty/CHANGELOG.md"
is "$(rc "$TMP/dirty" bump patch)" 2 "bump on a dirty tree exits 2"

# --- 8. a level that does not exist is refused ------------------------------
fixture "$TMP/level"
is "$(rc "$TMP/level" bump huge)" 2 "bump huge exits 2"
is "$(rc "$TMP/level" bump)" 2 "bump with no level exits 2"

# --- 9. bad usage is exit 2, not a silent pass ------------------------------
is "$(rc "$TMP/level" --nope)" 2 "an unknown flag exits 2"

# --- 10. the real tree is clean ---------------------------------------------
if bash "$ROOT/tools/release.sh" --check >/dev/null 2>&1; then
  ok "this repo's own version source is consistent"
else
  no "this repo's own version source is inconsistent"
  bash "$ROOT/tools/release.sh" 2>&1 | head -10
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
