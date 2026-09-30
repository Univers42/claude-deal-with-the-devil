#!/usr/bin/env bash
# export.sh — generate one harness's dialect of this kit from the Claude sources.
#
# Why a generator instead of a second hand-kept copy: a hand-kept copy is a second
# source of truth, and two sources of truth for one agent roster is how a README
# ends up describing agents that do not exist. The canonical sources stay
# `agents/`, `commands/`, `skills/` and `rules/`; this is the one place that knows
# a harness's dialect, and `--check` is what stops the two from drifting.
#
# Usage: export.sh <harness>          write dist/<harness>/
#        export.sh --check <harness>  regenerate into a temp dir, diff, exit 1 on drift
#
# Exit: 0 written or identical · 1 drift or a real failure · 2 could not run.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"

CHECK=0
HARNESS=""
for a in "$@"; do
  case "$a" in
  --check) CHECK=1 ;;
  -h | --help)
    echo "usage: export.sh [--check] <harness>   (harnesses: opencode, codex)"
    exit 0
    ;;
  -*)
    echo "export.sh: unknown arg '$a'" >&2
    exit 2
    ;;
  *) HARNESS="$a" ;;
  esac
done
[ -n "$HARNESS" ] || {
  echo "export.sh: no harness given (usage: export.sh [--check] <harness>)" >&2
  exit 2
}

# A harness is one sourced library of emitters. Unknown name is exit 2, the same
# code bin/devil uses for a tool it does not know, so a typo is never a pass.
case "$HARNESS" in
opencode)
  # shellcheck source=lib/export-opencode.sh
  . "$DIR/lib/export-opencode.sh"
  generate() {
    xoc_agents
    xoc_commands
    xoc_plugin
    xoc_config
    xoc_readme
  }
  ;;
codex)
  # shellcheck source=lib/export-codex.sh
  . "$DIR/lib/export-codex.sh"
  generate() {
    cx_manifest
    cx_hooks
    cx_agents_md
    cx_readme
  }
  ;;
*)
  echo "export.sh: unknown harness '$HARNESS' (known: opencode, codex)" >&2
  exit 2
  ;;
esac

DEST="$(claude_root)/dist/$HARNESS"

# --check compares against a temp tree rather than the committed one: a partial
# write must never be able to make a failing check look like a passing one.
if [ "$CHECK" = 1 ]; then
  TMP="$(mktemp -d)" || exit 2
  trap 'rm -rf "$TMP"' EXIT
  XOUT="$TMP/$HARNESS"
  mkdir -p "$XOUT" || exit 2
  generate || exit 2
  if diff -ru "$DEST" "$XOUT" >"$TMP/diff.txt" 2>&1; then
    echo "export --check: dist/$HARNESS is up to date"
    exit 0
  fi
  echo "export --check: dist/$HARNESS has drifted from its sources"
  echo "Run 'devil export $HARNESS' and commit the result."
  # Caveat: only the first 60 diff lines are shown, so a drift late in a long diff
  # is not printed. The exit code still reports it; run the diff yourself to see all.
  sed -n '1,60p' "$TMP/diff.txt"
  exit 1
fi

mkdir -p "$DEST" || exit 2
XOUT="$DEST"
generate || exit 2
n="$(find "$DEST" -type f | wc -l | tr -d ' ')"
echo "wrote dist/$HARNESS ($n files) from the kit's Claude-format sources"
