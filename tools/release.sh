#!/usr/bin/env bash
# release.sh — the version gate, and the bump that opens a release.
#
# A12: one version source. `.claude-plugin/plugin.json` carries it, CHANGELOG.md
# repeats it as a `## [x.y.z]` heading, and the marketplace manifest must not carry
# a `version` of its own (two sources drift, and auto-update reads the plugin one).
# The third check is the release-note gate: a retired asset its own changelog never
# names, or names without its replacement, is a tombstone nobody can follow.
#
# `bump <major|minor|patch>` edits plugin.json, opens `## [x.y.z] - <date>`
# under `## [Unreleased]`, re-exports each `dist/<harness>/` (its manifest copies the
# version), commits `chore(release): vX.Y.Z` and tags `vX.Y.Z`.
# It never pushes: the push is a human decision (binding rule 6).
#
# Usage: release.sh [--check] [--summary] | release.sh bump <major|minor|patch>
#   --check  the default with no argument · --summary  the totals line only
#
# Exit: 0 checks passed · 1 a check FAILED · 2 could not run / bad usage.
set -uo pipefail # not -e: a failed check is data, not a script error
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"

SUMMARY=0
BUMP=0
LEVEL=""
if [ "${1:-}" = bump ]; then
  BUMP=1
  LEVEL="${2:-}"
  shift $(($# > 1 ? 2 : 1))
fi
for a in "$@"; do
  case "$a" in
  --check) ;; # the default; accepted so `bump patch --check` reads correctly
  --summary) SUMMARY=1 ;;
  *)
    echo "release.sh: unknown arg '$a'" >&2
    exit 2
    ;;
  esac
done

ROOT="$(claude_root)"
cd "$ROOT" || exit 2
# Git resolves from the payload root, not the caller's cwd: the release commit
# belongs to the kit repo even when this is run from a host project.
GITROOT="$(cd "$ROOT" && repo_root)"
PLUGIN=".claude-plugin/plugin.json"
MARKET=".claude-plugin/marketplace.json"
LOG="CHANGELOG.md"
ROWS=""
FAILED=0

# row <status> <check> <detail>
row() {
  ROWS+="$1	$2	$3"$'\n'
  [ "$1" = FAIL ] && FAILED=$((FAILED + 1))
  return 0
}

# A bare x.y.z: no pre-release, no build metadata, no leading v.
# Caveat: the regex reads a string, not a file. A version split across JSON
# lines, `v0.9.0` or `0.9` is rejected here, and nothing here says whether the
# version was the one actually shipped.
semver() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

# A top-level string field of a JSON file, jq when installed else sed.
# Caveat: the sed read matches the first `"key": "..."` on a line anywhere in
# the file, so a nested or commented `"version"` is read as the plugin's, and a
# value broken across lines is not matched at all (it then reads as empty).
json_str() {
  local file="$1" key="$2"
  if have jq; then
    jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null
  else
    sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "$file" | head -1
  fi
}

# The newest released version: the first `## [x.y.z]` heading. An
# `## [Unreleased]` above it is expected and ignored.
# Caveat: matched line by line, so `### [1.0.0]`, `## [1.0.0](url)` or a
# differently bracketed heading reads as absent and the check FAILs as a
# mismatch rather than as a missing release.
changelog_heading() {
  grep -m1 -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$LOG" |
    sed -E 's/^## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/'
}

# The first line of the changelog carrying both needles, matched as substrings.
# Caveat: substring, not word, matching: `ghost` also satisfies `ghostly`, and
# a long line mentioning the asset in one clause and its replacement in another
# counts. It proves the two are named together, not that the entry explains it.
changelog_line_with() {
  awk -v a="$1" -v b="$2" '
    index($0, a) && index($0, b) { found = 1; exit }
    END { exit found ? 0 : 1 }
  ' "$LOG"
}

# Retired assets as `<name> <replaced-by>` lines. Skills and commands are the two
# kinds that carry a tombstone body.
# Caveat: only `skills/*/SKILL.md` and `commands/*.md` are read, so a retired
# agent or rule is invisible here, and the values come from fm_meta, which is
# itself line-oriented YAML (its caveat is in lib/common.sh).
retired_pairs() {
  local f name
  for f in skills/*/SKILL.md commands/*.md; do
    [ -e "$f" ] || continue
    [ "$(fm_meta "$f" stage)" = retired ] || continue
    name="$(basename "$f" .md)"
    [ "${f##*/}" = SKILL.md ] && name="$(basename "$(dirname "$f")")"
    printf '%s %s\n' "$name" "$(fm_meta "$f" replaced-by)"
  done
}

# --- the three checks -------------------------------------------------------

check_version() {
  local v h
  v="$(json_str "$PLUGIN" version)"
  h="$(changelog_heading)"
  if ! semver "$v"; then
    row FAIL version "plugin.json version \`$v\` is not x.y.z"
  elif [ "$v" = "$h" ]; then
    row PASS version "plugin.json \`$v\` == first \`## [$h]\` heading"
  else
    row FAIL version "plugin.json \`$v\` != first changelog heading \`${h:-none}\`"
  fi
}

# How many plugins[] entries carry their own version key.
# Caveat: exact under jq. The sed fallback counts lines, not entries, and reads
# a `version` quoted inside a description string as a violation, while an
# unquoted `version: 1.0.0` in the file would be missed.
market_versions() {
  if have jq; then
    jq -r '[.plugins[]? | select(has("version"))] | length' "$MARKET" 2>/dev/null
  else
    grep -c '"version"' "$MARKET" 2>/dev/null || true
  fi
}

check_marketplace() {
  local n
  n="$(market_versions)"
  case "$n" in
  "" | *[!0-9]*) row FAIL marketplace "marketplace.json unreadable (no plugins list)" ;;
  0) row PASS marketplace "no plugins[] entry carries a version" ;;
  *) row FAIL marketplace "$n version key(s) in marketplace.json; plugin.json is the source" ;;
  esac
}

check_retired() {
  local pairs name repl
  pairs="$(retired_pairs)"
  if [ -z "$pairs" ]; then
    row PASS retired "no retired asset to record"
    return
  fi
  while read -r name repl; do
    [ -n "$name" ] || continue
    if [ -z "$repl" ]; then
      row FAIL "retired/$name" "no metadata.replaced-by; a tombstone must name its successor"
    elif changelog_line_with "$name" "$repl"; then
      row PASS "retired/$name" "named on one changelog line with its replacement \`$repl\`"
    else
      row FAIL "retired/$name" "changelog never names it and \`$repl\` on one line"
    fi
  done <<<"$pairs"
}

# --- the bump: tools/lib/release-bump.sh -----------------------------------
# shellcheck source=lib/release-bump.sh
. "$DIR/lib/release-bump.sh"

# A missing manifest or changelog is exit 2, never a vacuous pass.
preflight() {
  local f
  for f in "$PLUGIN" "$MARKET" "$LOG"; do
    [ -f "$f" ] && continue
    echo "release.sh: missing $f — nothing to check" >&2
    return 1
  done
  git -C "$GITROOT" rev-parse --git-dir >/dev/null 2>&1 && return 0
  echo "release.sh: $GITROOT is not a git repository; a bump needs a commit and a tag" >&2
  return 1
}

# --- run --------------------------------------------------------------------

if [ "$BUMP" = 1 ]; then
  bump "$LEVEL"
  [ $? -eq 2 ] && exit 2
fi
preflight || exit 2

check_version
check_marketplace
check_retired

PASSED="$(printf '%s' "$ROWS" | grep -c '^PASS' || true)"
if [ "$SUMMARY" = 1 ]; then
  echo "**$FAILED failed, $PASSED passed.**"
  [ "$FAILED" -eq 0 ] || exit 1
  exit 0
fi

echo "# Release check"
echo
echo "| Status | Check | Detail |"
echo "|---|---|---|"
printf '%s' "$ROWS" | while IFS='	' read -r s c d; do
  [ -n "${s:-}" ] || continue
  echo "| $s | \`$c\` | $d |"
done
echo
echo "**$FAILED failed, $PASSED passed.** \
plugin.json is the version source; \`bump <level>\` cuts a release and never pushes."

[ "$FAILED" -eq 0 ] || exit 1
exit 0
