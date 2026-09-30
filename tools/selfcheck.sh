#!/usr/bin/env bash
# selfcheck.sh — verify this .claude config tells the truth about itself.
#
# Why this exists: the README once documented 4 agents, 5 rules, 1 skill, 2
# workflows and a settings.json that did not exist on disk. Nothing caught it,
# because nothing was checking. For a config whose thesis is "evidence, not
# adjectives", that is the worst possible defect — so it is now a gate.
#
# Three classes of drift, each one a real bug that shipped here:
#   1. DANGLING   a doc names agents/x.md, rules/x.md, tools/x.sh ... that is absent.
#      This is the one that bit us: /devil:refactor <tech> reads
#      rules/refactor-<tech>.md by exact filename, so a documented-but-missing
#      rule fails at use time.
#   2. FRONTMATTER  a field Claude Code does not read. Skills took `tools:`
#      (the field is `allowed-tools:`); rules took Cursor's `globs:`/`alwaysApply:`
#      (the field is `paths:`, and its absence means "load every session").
#      Both parse fine and both silently do nothing.
#   3. ORPHAN     an asset on disk that no doc mentions — invisible, so unused.
#
# Usage: selfcheck.sh [--summary] [--strict]
#   --summary  only the failing rows plus the totals
#   --strict   orphans (class 3) fail too; default is to report them as warnings
#
# Exit: 0 when no drift; 1 when any check FAILED. Verify-only — never writes.
set -uo pipefail # not -e: a failed check is data, not a script error
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"

SUMMARY=0
STRICT=0
for a in "$@"; do
  case "$a" in
  --summary) SUMMARY=1 ;;
  --strict) STRICT=1 ;;
  *)
    echo "selfcheck.sh: unknown arg '$a'" >&2
    exit 2
    ;;
  esac
done

ROOT="$(claude_root)"
cd "$ROOT" || exit 1
FAILED=0
WARNED=0
ROWS=""

# row <status> <check> <subject> <detail>
row() {
  ROWS+="$1	$2	$3	$4"$'\n'
  [ "$1" = FAIL ] && FAILED=$((FAILED + 1))
  [ "$1" = WARN ] && WARNED=$((WARNED + 1))
  return 0
}

# Every markdown file in the config, excluding vendored/reference trees and
# generated output. cache_dir() puts the cache under the host's .claude/, which
# in a standalone checkout of this kit is ./.claude/cache: its codemap named
# `scripts/hooks.py` and read as a dangling reference.
_docs() {
  find . -name '*.md' \
    -not -path './cache/*' \
    -not -path './.claude/*' \
    -not -path './claude-code-best-practice/*' \
    -not -path './.git/*' | sort
}

# --- 1. dangling references -------------------------------------------------
# Pull every self-referential path out of the prose and prove it resolves.
# Matches `agents/devil.md`, `skills/debug/SKILL.md` inside backticks or
# plain. A path char before the prefix means someone else's path
# (`.github/workflows/ci.yml`, `hooks/scripts/hooks.py` read from `scripts/`),
# so it is not read as ours. Ponytail: prefix-anchored, so a path split across
# a line break is missed. It finds the real class of drift; it is not a link
# checker.
check_dangling() {
  local doc ref target seen=""
  while read -r doc; do
    [ -n "$doc" ] || continue
    grep -oE '(^|[^A-Za-z0-9_./-])(\.claude/)?(agents|rules|commands|workflows|skills|tools|doc|scripts)/[A-Za-z0-9_./-]+' "$doc" 2>/dev/null |
      sed -E 's|^[^A-Za-z0-9_.]||; s|^\.claude/||' | sort -u | while read -r ref; do
      case "$ref" in
      */) continue ;;
      *.md | *.sh | *.py | *.json) target="$ref" ;;
      *) continue ;; # a bare directory is not a claim about a file
      esac
      # A markdown link is relative to its own file, so resolve both ways:
      # hooks/HOOKS-README.md saying `scripts/hooks.py` means hooks/scripts/hooks.py.
      [ -e "$ROOT/$target" ] && continue
      [ -e "$(dirname "$doc")/$target" ] && continue
      echo "$doc|$target"
    done
  done < <(_docs) | sort -u | while IFS='|' read -r doc target; do
    echo "FAIL	dangling	$target	named by ${doc#./}, not on disk"
  done
  : "$seen"
}

# --- 2. frontmatter ---------------------------------------------------------
check_agents() {
  local f name desc
  for f in agents/*.md; do
    [ -e "$f" ] || continue
    name="$(fm_field "$f" name)"
    desc="$(fm_field "$f" description)"
    if [ -z "$(fm_block "$f")" ]; then
      row FAIL agent "$f" "no frontmatter; agents need name + description"
      continue
    fi
    [ "$name" = "$(basename "$f" .md)" ] ||
      row FAIL agent "$f" "name '$name' != filename '$(basename "$f" .md)'"
    # description may be a folded block (>), in which case the scalar read is
    # empty but the key is present — check the key, not the value.
    fm_block "$f" | grep -q '^description:' || row FAIL agent "$f" "no description:"
    : "$desc"
  done
}

check_skills() {
  local d name
  for d in skills/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if [ ! -f "$d/SKILL.md" ]; then
      row FAIL skill "$name" "no SKILL.md"
      continue
    fi
    [ "$(fm_field "$d/SKILL.md" name)" = "$name" ] ||
      row FAIL skill "$name" "frontmatter name != directory name"
    fm_block "$d/SKILL.md" | grep -q '^description:' ||
      row FAIL skill "$name" "no description:"
    if fm_block "$d/SKILL.md" | grep -q '^tools:'; then
      row FAIL skill "$name" "uses 'tools:' — not a skill field; use 'allowed-tools:'"
    fi
  done
}

check_rules() {
  local f
  for f in rules/*.md; do
    [ -e "$f" ] || continue
    if fm_block "$f" | grep -qE '^(globs|alwaysApply):'; then
      row FAIL rule "$f" "Cursor field (globs/alwaysApply); Claude Code reads 'paths:'"
    elif [ -n "$(fm_block "$f")" ] && ! fm_has_paths "$f"; then
      row FAIL rule "$f" "has frontmatter but no 'paths:' — it will load every session anyway"
    fi
  done
}

check_invocables() {
  local f kind
  for f in commands/*.md; do
    [ -e "$f" ] || continue
    kind="$(fm_meta "$f" kind)"
    fm_block "$f" | grep -q '^description:' ||
      row FAIL "${kind:-command}" "$f" "no description: — it will not appear in the / menu"
  done
}

check_tools() {
  local f
  for f in tools/*.sh; do
    [ -e "$f" ] || continue
    [ -x "$f" ] || row FAIL tool "$f" "not executable (chmod +x)"
    head -1 "$f" | grep -q '^#!' || row FAIL tool "$f" "no shebang on line 1"
  done
}

# --- 3. orphans -------------------------------------------------------------
# An asset no document names is one nobody will find. Docs here cite an asset in
# whichever form a reader would type it, not by path: an agent or rule as
# `reviewer`, a command or workflow as /devil:harden. Matching only
# "<kind>/<name>" reported 21 false orphans on a tree where every one of them
# was in fact documented — so accept every citation form.
# A workflow is a command file tagged kind: workflow; asset_names lists it
# under both kinds, so the commands pass drops it and each file counts once.
_commands_only() { comm -23 <(asset_names commands) <(asset_names workflows); }

_names_of() {
  if [ "$1" = commands ]; then _commands_only; else asset_names "$1"; fi
}

check_orphans() {
  local kind name pat dir hits sev
  sev=WARN
  [ "$STRICT" = 1 ] && sev=FAIL
  for kind in agents rules skills workflows commands; do
    while read -r name; do
      [ -n "$name" ] || continue
      dir="$kind"
      [ "$kind" = workflows ] && [ -f "commands/$name.md" ] && dir=commands
      case "$kind" in
      commands | workflows) pat="$dir/$name|/devil:$name\b|\`$name\`" ;;
      skills) pat="skills/$name/|\`$name\`" ;;
      *) pat="$kind/$name|\`$name\`" ;;
      esac
      hits="$(grep -rlE "$pat" --include='*.md' . 2>/dev/null |
        grep -v "^\./$dir/$name" | grep -v claude-code-best-practice | head -1)"
      [ -n "$hits" ] || row "$sev" orphan "$dir/$name" "no other doc references it"
    done < <(_names_of "$kind")
  done
}

# --- run --------------------------------------------------------------------
while IFS='	' read -r s c sub d; do
  [ -n "${s:-}" ] || continue
  row "$s" "$c" "$sub" "$d"
done < <(check_dangling)
check_agents
check_skills
check_rules
check_invocables
check_tools
check_orphans

# --- report -----------------------------------------------------------------
echo "# Self-check"
echo
if [ -z "$ROWS" ]; then
  echo "No drift. Every documented name resolves; every frontmatter field is one Claude Code reads."
else
  echo "| Status | Check | Subject | Detail |"
  echo "|---|---|---|---|"
  printf '%s' "$ROWS" | while IFS='	' read -r s c sub d; do
    [ -n "${s:-}" ] || continue
    [ "$SUMMARY" = 1 ] && [ "$s" != FAIL ] && continue
    echo "| $s | $c | \`$sub\` | $d |"
  done
fi
echo
echo "**$FAILED failed, $WARNED warned.**  \
agents $(asset_names agents | grep -c .) · rules $(asset_names rules | grep -c .) · \
skills $(asset_names skills | grep -c .) · commands $(_commands_only | grep -c .) · \
workflows $(asset_names workflows | grep -c .) · tools $(asset_names tools | grep -c .)"

[ "$FAILED" -eq 0 ] || exit 1
[ "$STRICT" = 1 ] && [ "$WARNED" -gt 0 ] && exit 1
exit 0
