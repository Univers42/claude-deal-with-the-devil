#!/usr/bin/env bash
# context.sh — what this .claude config costs you in context, every session.
#
# Why: config is not free. A rule in .claude/rules/ with no `paths:` frontmatter
# loads into EVERY session, forever, whether or not it is relevant. This repo
# shipped 11 such rules using Cursor's `globs:`/`alwaysApply:` fields — which
# Claude Code does not read — so all 22,018 bytes of them loaded on every
# session, including the Go and REST rules on a Python project. Nothing
# reported that, because nothing measured it.
#
# What loads when (the model this tool encodes):
#   ALWAYS  rules/*.md with no `paths:`         — full text, every session
#   ALWAYS  the description: of every skill,    — the listing Claude matches
#           command and workflow                  intent against
#   LAZY    rules/*.md with `paths:`            — only when a matching file is touched
#   LAZY    a skill/command/workflow body       — only when invoked
#   LAZY    an agent definition                 — only in that agent's own context
#
# So the lever is: keep always-on text short, put everything else behind
# `paths:` or an invocation. Pair with the bundled /skill-doctor, which reports
# which loaded skills actually went unused.
#
# Usage: context.sh [--summary] [--refresh]
# Exit: always 0 — this is a report, not a gate.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"

MODE=full
for a in "$@"; do
  case "$a" in
  --summary) MODE=summary ;;
  --refresh) export REFRESH=1 ;;
  *)
    echo "context.sh: unknown arg '$a'" >&2
    exit 2
    ;;
  esac
done

ROOT="$(claude_root)"
cd "$ROOT" || exit 1

# Ponytail: bytes/4 is the usual English-prose rule of thumb for tokens. It is
# an estimate, not a count — no tokenizer runs here. Trust the BYTES column;
# treat tokens as the order of magnitude. /skill-doctor reports real numbers.
_tok() { echo $(($1 / 4)); }

_bytes() { wc -c <"$1" 2>/dev/null | tr -d ' ' || echo 0; }

# The description: block of an invocable — the part that is always in context.
# Folded (`description: >`) blocks run until the next top-level key.
_desc_bytes() {
  fm_block "$1" | awk '
    /^description:/ {grab=1; print; next}
    grab && /^[a-zA-Z_-]+:/ {grab=0}
    grab {print}
  ' | wc -c | tr -d ' '
}

ALWAYS=0
LAZY=0
DESC=0
ROWS_ALWAYS=""
ROWS_LAZY=""

for f in rules/*.md; do
  [ -e "$f" ] || continue
  b=$(_bytes "$f")
  if fm_has_paths "$f"; then
    LAZY=$((LAZY + b))
    ROWS_LAZY+="rule	$f	$b	$(fm_block "$f" | grep -c '^  - ' || true) path globs"$'\n'
  else
    ALWAYS=$((ALWAYS + b))
    ROWS_ALWAYS+="rule	$f	$b	always-on: no paths: frontmatter"$'\n'
  fi
done

for kind in skills commands workflows; do
  case "$kind" in
  skills) files=(skills/*/SKILL.md) ;;
  *) files=("$kind"/*.md) ;;
  esac
  for f in "${files[@]}"; do
    [ -e "$f" ] || continue
    b=$(_bytes "$f")
    d=$(_desc_bytes "$f")
    DESC=$((DESC + d))
    LAZY=$((LAZY + b - d))
    ROWS_LAZY+="${kind%s}	$f	$b	$d B of description always in context"$'\n'
  done
done

AGENTS_B=0
for f in agents/*.md; do
  [ -e "$f" ] || continue
  b=$(_bytes "$f")
  AGENTS_B=$((AGENTS_B + b))
  ROWS_LAZY+="agent	$f	$b	loads only in its own subagent context"$'\n'
done

TOTAL_ALWAYS=$((ALWAYS + DESC))

echo "# Context budget"
echo
echo "| Bucket | Bytes | ~tokens | When it loads |"
echo "|---|---:|---:|---|"
echo "| Always-on rules | $ALWAYS | $(_tok $ALWAYS) | every session, no exceptions |"
echo "| Invocable descriptions | $DESC | $(_tok $DESC) | every session (the listing) |"
echo "| **Always-on total** | **$TOTAL_ALWAYS** | **$(_tok $TOTAL_ALWAYS)** | **the number to drive down** |"
echo "| Lazy rules + bodies | $LAZY | $(_tok $LAZY) | only on a matching file or an invocation |"
echo "| Agent definitions | $AGENTS_B | $(_tok $AGENTS_B) | only inside that agent |"
echo
echo "Without \`paths:\` every lazy rule would be always-on instead. Measured saving: \
**$(
  s=0
  for f in rules/*.md; do fm_has_paths "$f" && s=$((s + $(_bytes "$f"))); done
  echo "$s"
) bytes** per session."

if [ "$MODE" = full ]; then
  echo
  echo "## Always-on, heaviest first"
  echo
  echo "| Kind | File | Bytes | Note |"
  echo "|---|---|---:|---|"
  printf '%s' "$ROWS_ALWAYS" | sort -t'	' -k3 -rn | while IFS='	' read -r k f b n; do
    [ -n "${k:-}" ] && echo "| $k | \`$f\` | $b | $n |"
  done
  echo
  echo "## Lazy, heaviest first"
  echo
  echo "| Kind | File | Bytes | Note |"
  echo "|---|---|---:|---|"
  printf '%s' "$ROWS_LAZY" | sort -t'	' -k3 -rn | head -20 | while IFS='	' read -r k f b n; do
    [ -n "${k:-}" ] && echo "| $k | \`$f\` | $b | $n |"
  done
fi

echo
echo "**How to cut the always-on total:** give a rule \`paths:\` so it lazy-loads; \
move detail out of a long SKILL.md into a sibling \`reference.md\`; tighten a \
\`description:\` to one sentence; run \`/skill-doctor\` to find skills that load but \
never fire."
exit 0
