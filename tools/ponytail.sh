#!/usr/bin/env bash
# ponytail.sh — find approximations that don't admit they are approximations.
#
# `rules/ponytail.md`: every heuristic, regex parser, sampler, estimate, cache
# or timeout ships one line saying what it gets wrong and when. The failure mode
# it prevents is specific — an approximation read as a fact, trusted, and wrong
# in a way nobody wrote down. This tool finds the code that owes that line.
#
# It looks for two things in every source file:
#   SIGNAL  a construct or comment that reads as best-effort — a hedge word, a
#           regex over source, a sample, a bounded read, a timeout, a cache.
#   MARKER  a `Ponytail:` comment anywhere in the file.
# Signal without marker is the finding.
#
# Ponytail: this tool is itself a heuristic, and it fails in both directions.
# It over-reports — a hedge word in ordinary prose ("assume the caller holds the
# lock") reads as a signal. It under-reports worse: an approximation written
# without any of these tells is invisible to it, and file-scope marker matching
# means one marker silences an unrelated heuristic further down the same file.
# It is a prompt to look, never a certificate. Confirm by reading the file.
#
# Usage: ponytail.sh [--summary] [--strict] [--refresh] [<path>]
#   --strict  exit 1 on findings (use as a gate); default reports and exits 0
#
# Exit: 0 unless --strict and something was found. Verify-only — never writes.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"

MODE=full
STRICT=0
TARGET=""
for a in "$@"; do
  case "$a" in
  --summary) MODE=summary ;;
  --strict) STRICT=1 ;;
  --refresh) export REFRESH=1 ;;
  -*)
    echo "ponytail.sh: unknown arg '$a'" >&2
    exit 2
    ;;
  *) TARGET="$a" ;;
  esac
done

ROOT="$(repo_root)"
cd "$ROOT" || exit 1

# A comment that hedges. These are the words people reach for instead of writing
# the caveat properly — which is exactly where the caveat is owed.
HEDGE='best[ -]effort|approximat|heuristic|good enough|rough(ly)?|estimate|naive|
|for now|not exact|imprecise|may miss|might miss|should be|probably|in practice|
|assume[sd]?|fallback|hack|simplif'

# Constructs that ARE an approximation whether or not anyone said so.
CONSTRUCT='re\.(compile|match|search|findall)|grep -[EoP]|sed -n|awk .*\/.*\/|
|\| *head -|\| *tail -|LIMIT [0-9]|sample|random\.|shuf |
|timeout |setTimeout|SIGKILL|--idle|
|cache|memo|ttl|TTL'

_clean() { tr -d '\n' <<<"$1" | sed 's/||*/|/g; s/^|//; s/|$//'; }
HEDGE="$(_clean "$HEDGE")"
CONSTRUCT="$(_clean "$CONSTRUCT")"

_targets() {
  if [ -n "$TARGET" ]; then
    if [ -d "$TARGET" ]; then
      find "$TARGET" -type f -not -path '*/.git/*' -printf '%P\n' | sed "s|^|$TARGET/|"
    else echo "$TARGET"; fi
  else
    list_files
  fi
}

FOUND=0
MARKED=0
ROWS=""

while read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  is_code "$f" || continue
  case "$f" in
  */cache/* | */node_modules/* | */claude-code-best-practice/*) continue ;;
  esac
  # Tests are deliberately full of bounded reads, samples and fixtures that read
  # as signals but are the point of the test. Scanning them produced only false
  # positives, and a gate that cries wolf gets switched off.
  is_test_file "$f" && continue

  if grep -qi 'ponytail:' "$f" 2>/dev/null; then
    MARKED=$((MARKED + 1))
    continue
  fi

  # Hedge words only count inside a comment; a construct counts anywhere.
  hits="$(grep -nEi "^[[:space:]]*(#|//|\*|--)[^\"']*($HEDGE)" "$f" 2>/dev/null | head -3)"
  if [ -z "$hits" ]; then
    hits="$(grep -nEi "($CONSTRUCT)" "$f" 2>/dev/null | head -3)"
    [ -n "$hits" ] || continue
    kind=construct
  else
    kind=hedge
  fi

  n="$(grep -cEi "($HEDGE|$CONSTRUCT)" "$f" 2>/dev/null || echo 0)"
  line="$(head -1 <<<"$hits" | cut -d: -f1)"
  excerpt="$(head -1 <<<"$hits" | cut -d: -f2- | sed 's/^[[:space:]]*//' | cut -c1-70)"
  ROWS+="$n	$f	$line	$kind	$excerpt"$'\n'
  FOUND=$((FOUND + 1))
done < <(_targets)

echo "# Unmarked approximations"
echo
if [ "$FOUND" -eq 0 ]; then
  echo "None. $MARKED file(s) carry a \`Ponytail:\` marker."
else
  echo "| Signals | File | Line | Kind | What tripped it |"
  echo "|---:|---|---:|---|---|"
  limit=40
  [ "$MODE" = summary ] && limit=10
  printf '%s' "$ROWS" | sort -rn | head -"$limit" | while IFS='	' read -r n f l k e; do
    [ -n "${n:-}" ] && echo "| $n | \`$f:$l\` | $l | $k | \`$(sed 's/|/\\|/g' <<<"$e")\` |"
  done
fi
echo
echo "**$FOUND file(s) with an unmarked signal · $MARKED already marked.**"
echo
echo "A row is a prompt to look, not a verdict (see this tool's own header). If the code \
really is approximate, add one line saying what it gets wrong and when \
(\`rules/ponytail.md\`). If it is exact, leave it — a marker on exact code trains \
readers to skip markers."

[ "$STRICT" = 1 ] && [ "$FOUND" -gt 0 ] && exit 1
exit 0
