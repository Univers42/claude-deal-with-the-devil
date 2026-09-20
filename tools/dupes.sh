#!/usr/bin/env bash
# dupes.sh — repeated code blocks across the tree. These are the extraction
# candidates: pull each into the project library, test once, reuse everywhere
# (see rules/library-first.md). Caches to .claude/cache/dupes.md.
#
# Ponytail: sliding-window of WINDOW normalized lines, hashed and counted. It
# finds copy-paste, not semantic clones. Tune WINDOW for sensitivity.
#
# Usage: dupes.sh [--summary] [--refresh] [--window N]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"

MODE=full
WINDOW=6
while [ $# -gt 0 ]; do
  case "$1" in
  --summary) MODE=summary ;;
  --refresh) export REFRESH=1 ;;
  --window)
    WINDOW="${2:-6}"
    shift
    ;;
  *)
    echo "dupes.sh: unknown arg '$1'" >&2
    exit 2
    ;;
  esac
  shift
done

# Emits: count <TAB> first-location <TAB> sample, one per repeated block,
# busiest first. awk holds a per-file ring buffer; a window is keyed by its
# normalized text, locations are collected, blocks seen >1 are reported.
_blocks() {
  local root list
  root="$(repo_root)"
  # Files as awk ARGUMENTS (so FILENAME/FNR read contents), NUL-safe for spaces.
  list="$(list_files | while read -r rel; do
    if is_code "$rel" && ! is_test_file "$rel"; then printf '%s\n' "$root/$rel"; fi
  done)"
  [ -n "$list" ] || return 0
  printf '%s\n' "$list" | tr '\n' '\0' | xargs -0 awk -v W="$WINDOW" '
    FNR==1 { n=0; split("",ring); split("",rln) }      # reset ring at each file
    {
      line=$0
      gsub(/^[ \t]+|[ \t]+$/,"",line)                  # trim
      if (length(line) < 5) next                       # skip trivial lines
      if (line !~ /[A-Za-z0-9]/) next                  # skip pure braces/punct
      ring[n%W]=line; rln[n%W]=FNR; n++
      if (n>=W) {
        key=""; for(i=n-W;i<n;i++) key=key ring[i%W] SUBSEP
        cnt[key]++
        if (cnt[key]==1) { loc[key]=FILENAME ":" rln[(n-W)%W]; samp[key]=ring[(n-W)%W] }
      }
    }
    END { for (k in cnt) if (cnt[k]>1) printf "%d\t%s\t%s\n", cnt[k], loc[k], samp[k] }
  ' | sort -rn
}

build_full() {
  local blocks
  blocks="$(_blocks)"
  echo "# Duplication candidates (window=$WINDOW lines)"
  echo
  if [ -z "$blocks" ]; then
    echo "_No repeated $WINDOW-line blocks. Nothing obvious to extract._"
    return 0
  fi
  echo "Each row repeats — extract into the project library, then replace call sites:"
  echo
  echo "| count | first seen | starts with |"
  echo "|---:|---|---|"
  printf '%s\n' "$blocks" | awk -F'\t' '{printf "| %s | `%s` | %s |\n",$1,$2,substr($3,1,60)}'
}

build_summary() {
  local blocks n
  blocks="$(_blocks)"
  n="$(printf '%s\n' "$blocks" | grep -c . || true)"
  echo "## Duplication (window=$WINDOW)"
  if [ "$n" -eq 0 ]; then
    echo "- no repeated blocks found"
    return 0
  fi
  echo "- $n repeated block(s) — extraction candidates for the project library"
  printf '%s\n' "$blocks" | head -5 | awk -F'\t' '{printf "- ×%s `%s` — %s\n",$1,$2,substr($3,1,48)}'
  echo "- full list: \`.claude/tools/dupes.sh\`"
}

case "$MODE" in
summary) emit_cached dupes.summary.md build_summary ;;
full) emit_cached dupes.md build_full ;;
esac
