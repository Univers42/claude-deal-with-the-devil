#!/usr/bin/env bash
# untested.sh — source files with no test naming their stem. Drives TDD:
# this is the worklist of red bars to write before code. Caches to cache/.
#
# Existence-coverage only (ponytail: a test file *names* the stem). For real
# line coverage, run the suite's coverage target — see facts.sh.
#
# Usage: untested.sh [--summary] [--refresh]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"

MODE=full
for a in "$@"; do
  case "$a" in
  --summary) MODE=summary ;;
  --refresh) export REFRESH=1 ;;
  *)
    echo "untested.sh: unknown arg '$a'" >&2
    exit 2
    ;;
  esac
done

# Emits: untested-path lines.
_gaps() {
  local tests rel stem
  tests="$(list_files | while read -r rel; do is_test_file "$rel" && echo "$rel"; done)"
  list_files | while read -r rel; do
    is_code "$rel" || continue
    is_test_file "$rel" && continue
    stem="$(basename "$rel")"
    stem="${stem%.*}"
    printf '%s\n' "$tests" | grep -qi -- "$stem" || echo "$rel"
  done
}

_total_code() { list_files | while read -r f; do is_code "$f" && ! is_test_file "$f" && echo x; done | grep -c x || true; }

build_full() {
  local gaps total n
  gaps="$(_gaps)"
  total="$(_total_code)"
  n="$(printf '%s\n' "$gaps" | grep -c . || true)"
  echo "# Untested source ($n of $total files)"
  echo
  if [ "$n" -eq 0 ]; then
    echo "_Every source file is named by a test. Run the coverage target for line-level gaps._"
    return 0
  fi
  echo "Write the failing test FIRST, then the code (see agents/builder.md):"
  echo
  printf '%s\n' "$gaps" | sed 's/^/- `/; s/$/`/'
}

build_summary() {
  local gaps total n
  gaps="$(_gaps)"
  total="$(_total_code)"
  n="$(printf '%s\n' "$gaps" | grep -c . || true)"
  echo "## Untested"
  if [ "$total" -eq 0 ]; then
    echo "- no source files detected"
    return 0
  fi
  echo "- $n of $total source files have no test naming their stem"
  [ "$n" -gt 0 ] && printf '%s\n' "$gaps" | sed 's#/[^/]*$##' | sort | uniq -c | sort -rn | head -5 |
    awk '{printf "- %s untested under `%s/`\n",$1,$2}'
  echo "- full list: \`.claude/tools/untested.sh\`"
}

case "$MODE" in
summary) emit_cached untested.summary.md build_summary ;;
full) emit_cached untested.md build_full ;;
esac
