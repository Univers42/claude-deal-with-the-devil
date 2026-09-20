#!/usr/bin/env bash
# codemap.sh — a structured index of the codebase so the agent navigates
# instead of re-reading every file. Caches to .claude/cache/codemap.md.
#
# Usage: codemap.sh [--summary] [--refresh]
#   --summary  counts per language + the heaviest files (the briefing view)
#   --refresh  ignore the cache and rebuild
#
# Ponytail: symbols come from symbols_of() in lib/common.sh, which is a
# per-language regex, not a parser. It over-counts (a match inside a string or a
# block comment) and under-counts worse (a signature wrapped across lines, a
# macro-generated name, anything indented past column 0). Use it to find the
# file; read the file before editing it.
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
    echo "codemap.sh: unknown arg '$a'" >&2
    exit 2
    ;;
  esac
done

# Tab-separated rows: lang \t loc \t symbols \t has_test \t path
_rows() {
  local root tests rel f stem
  root="$(repo_root)"
  tests="$(list_files | while read -r rel; do is_test_file "$rel" && echo "$rel"; done)"
  list_files | while read -r rel; do
    is_code "$rel" || continue
    is_test_file "$rel" && continue
    f="$root/$rel"
    [ -f "$f" ] || continue
    stem="$(basename "$rel")"
    stem="${stem%.*}"
    if printf '%s\n' "$tests" | grep -qi -- "$stem"; then has=yes; else has=NO; fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$(lang_of "$rel")" "$(loc "$f")" "$(symbol_count "$f")" "$has" "$rel"
  done
}

build_full() {
  local rows
  rows="$(_rows)"
  echo "# Codemap"
  echo
  echo "Source files (tests excluded). \`symbols\` = regex-matched top-level defs; \`test?\` = a test file names this stem."
  echo
  echo "| lang | loc | symbols | test? | path |"
  echo "|---|---:|---:|:---:|---|"
  printf '%s\n' "$rows" | sort -t"$(printf '\t')" -k1,1 -k2,2nr | awk -F'\t' 'NF==5{printf "| %s | %s | %s | %s | `%s` |\n",$1,$2,$3,$4,$5}'
}

build_summary() {
  local rows
  rows="$(_rows)"
  echo "## Codemap (summary)"
  echo
  if [ -z "$rows" ]; then
    echo "_No source files detected._"
    return 0
  fi
  echo "| lang | files | loc | untested |"
  echo "|---|---:|---:|---:|"
  printf '%s\n' "$rows" | awk -F'\t' '
    {f[$1]++; l[$1]+=$2; if($4=="NO") u[$1]++}
    END{for(k in f) printf "| %s | %d | %d | %d |\n", k, f[k], l[k], u[k]+0}' | sort
  echo
  echo "Heaviest files:"
  printf '%s\n' "$rows" | sort -t"$(printf '\t')" -k2,2nr | head -5 |
    awk -F'\t' '{printf "- `%s` — %s loc (%s)\n",$5,$2,$1}'
  echo
  echo "_Drill in: \`.claude/tools/codemap.sh\` (full table) or \`rg <symbol> \$(.claude/tools/codemap.sh | …)\`._"
}

case "$MODE" in
summary) emit_cached codemap.summary.md build_summary ;;
full) emit_cached codemap.md build_full ;;
esac
