#!/usr/bin/env bash
# index.sh — generate the asset tables the README shows, and the live router
# behind `/devil:guide`.
#
# A hand-kept table is a claim about the tree that nothing re-checks: it drifts
# the first time a skill is added, renamed or retired, and the reader cannot tell
# which side is right. This reads the frontmatter instead, so the README is a
# generated artefact and the router prints the same rows, from the same functions,
# at the moment it is asked. The blocks are fenced by
# <!-- devil:index:<kind>:start / end -->, so a human editing the prose around one
# never collides with a generator.
#
# Usage: index.sh [--check | --write | --router]   (no argument means --check)
#   --check   regenerate every marked README block and diff it; exit 1 on drift
#   --write   rewrite only the blocks between the markers, nothing else
#   --router  print every table to stdout, for the `/devil:guide` body
#
# Exit: 0 clean; 1 the blocks differ or a marker is missing; 2 could not run.
set -uo pipefail # not -e: a difference is data, not a script error
# Byte order, not locale order: the tables are committed, so `sort` must not
# reorder them when a host runs this under a different LC_COLLATE.
export LC_ALL=C
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"

MODE=check # one mode per run; a second flag replaces it
for a in "$@"; do
  case "$a" in
  --check) MODE=check ;;
  --write) MODE="write" ;; # quoted: shellcheck reads a bare `write` as a command
  --router) MODE=router ;;
  *)
    echo "index.sh: unknown arg '$a' (--check | --write | --router)" >&2
    exit 2
    ;;
  esac
done

ROOT="$(claude_root)"
cd "$ROOT" || exit 2
README=README.md
if [ ! -f "$README" ] || ! have mktemp || ! have diff; then
  echo "index.sh: need a readable $README in $ROOT plus mktemp and diff" >&2
  exit 2
fi

KINDS=(skills rules commands workflows retired)
HEADINGS=('Skills' 'Rule skills' 'Commands' 'Workflows' 'Retired')
TMPD=""
trap 'rm -rf "$TMPD"' EXIT

# --- cells ------------------------------------------------------------------

# A markdown table cell from free text: one line, no bare pipe, no run of spaces.
# A `|` inside a code span is escaped too, which renders a backslash inside the
# span; a description carrying a table in it needs a real escape.
_cell() {
  printf '%s' "$1" | tr '\n\t' '  ' | tr -s '[:space:]' ' ' |
    sed -e 's/|/\\|/g' -e 's/^ //' -e 's/ $//'
}

# The sentence a paragraph opens with, used when a description has no
# 'Use when' clause yet. Splits on the first ". ", so an abbreviation ("e.g. ")
# or a decimal point ends it early.
_first_sentence() {
  local d="$1"
  case "$d" in
  *". "*) d="${d%%. *}" ;; # the longest suffix starting ". " is the first one
  esac
  printf '%s' "$d"
}

# The A14 conditions: the text between 'Use when' and 'Auto-triggers on'. A beta
# description still on the old form has no such text, so its first sentence
# stands in and says so, rather than the row reading as a skill with no trigger.
# Caveat: a substring slice of a joined line, not YAML. A description mentioning
# 'Use when' inside a quoted trigger phrase, or a second 'Use when' later on,
# resolves to the first; 'Auto-triggers' absent leaves the tail in place (which
# is what a description with no trigger list wants).
_use_when() {
  local d="$1"
  case "$d" in
  *"Use when"*)
    d="${d#*Use when}"
    d="${d%%Auto-triggers*}"
    d="$(printf '%s' "$d" | sed -e 's/[[:space:]]*$//' -e 's/[[:space:]]*\.[[:space:]]*$//')"
    _cell "$d"
    ;;
  *) printf '%s (no Use when yet)' "$(_cell "$(_first_sentence "$d")")" ;;
  esac
}

# The globs of a `paths:` key, one per line, whatever shape the list takes.
# Caveat: line-oriented. A glob containing a colon or a "- " of its own breaks it,
# and a nested map under paths: is skipped rather than read.
_paths() {
  fm_block "$1" | awk '
    /^paths:/ {
      v = $0; sub(/^paths:[[:space:]]*/, "", v)
      gsub(/[\[\]]/, "", v)
      n = split(v, a, ",")
      for (i = 1; i <= n; i++) { gsub(/^ *| *$/, "", a[i]); gsub(/"/, "", a[i]); if (a[i] != "") print a[i] }
      inside = 1; next
    }
    inside && /^[A-Za-z]/ { exit }
    inside && /^[[:space:]]*-/ { gsub(/^[[:space:]]*-[[:space:]]*/, ""); gsub(/"/, ""); if (NF) print }
  '
}

# --- tables -----------------------------------------------------------------

skills_table() {
  local f name stage
  printf '| Skill | Stage | Use when |\n| --- | --- | --- |\n'
  while read -r name; do
    [ -f "skills/$name/SKILL.md" ] || continue
    f="skills/$name/SKILL.md"
    stage="$(fm_meta "$f" stage)"
    case "$stage" in
    stable | beta) ;;
    *) continue ;; # a path-scoped rule and a tombstone are their own tables
    esac
    printf '| `%s` | %s | %s |\n' "$(_cell "$name")" "$stage" "$(_use_when "$(fm_desc "$f")")"
  done < <(asset_names skills)
}

# Each glob is a code span: a bare `**/x` pairs its asterisks into emphasis, which
# renders wrong and fails MD037. A glob that itself contains a backtick would break
# its span; none of the shipped ones does.
rules_table() {
  local f name globs
  printf '| Rule skill | Loads for |\n| --- | --- |\n'
  while read -r name; do
    [ -f "skills/$name/SKILL.md" ] || continue
    f="skills/$name/SKILL.md"
    [ "$(fm_meta "$f" stage)" = rule ] || continue
    globs="$(_paths "$f" | sed 's/.*/`&`/' | paste -sd, - | sed 's/`,`/`, `/g')"
    printf '| `%s` | %s |\n' "$(_cell "$name")" "$(_cell "$globs")"
  done < <(asset_names skills)
}

# A command or a workflow: the same four columns, filtered by metadata.kind.
# A user-only asset carries its marker in the Does cell, because the / menu
# offers it to a person and nothing else can reach it.
cmd_table() {
  local kind="$1" f name stage marker d does usage
  printf '| Command | Stage | Does | Usage |\n| --- | --- | --- | --- |\n'
  while read -r name; do
    [ -f "commands/$name.md" ] || continue
    f="commands/$name.md"
    [ "$(fm_meta "$f" kind)" = "$kind" ] || continue
    stage="$(fm_meta "$f" stage)"
    d="$(fm_desc "$f")"
    if fm_flag "$f" disable-model-invocation; then marker=' (you run it)'; else marker=''; fi
    IFS=$'\t' read -r does usage < <(_cols "$d")
    printf '| `%s` | %s | %s%s | %s |\n' "$(_cell "$name")" "$stage" "$does" "$marker" "$usage"
  done < <(asset_names commands)
}

# The two prose cells of a command row, tab-separated so one read splits them: the
# description before 'Usage:' and the text after it. Caveat: a substring slice, so
# a description carrying the word 'Usage:' outside the convention splits there.
_cols() {
  local d="$1"
  case "$d" in
  *"Usage:"*) printf '%s\t%s' "$(_cell "${d%%Usage:*}")" "$(_cell "${d#*Usage:}")" ;;
  *) printf '%s\t%s' "$(_cell "$d")" "-" ;; # skillcheck fails that asset anyway
  esac
}

# Rows for one directory; the caller sorts the two sets together, so a retired
# command and a retired skill interleave in one order.
_retired_rows() {
  local dir="$1" f name
  while read -r name; do
    if [ "$dir" = skills ]; then f="skills/$name/SKILL.md"; else f="commands/$name.md"; fi
    [ -f "$f" ] || continue
    [ "$(fm_meta "$f" stage)" = retired ] || continue
    printf '| `%s` | %s | `%s` |\n' "$(_cell "$name")" "$(_cell "$(fm_meta "$f" retired-in)")" \
      "$(_cell "$(fm_meta "$f" replaced-by)")"
  done < <(asset_names "$dir")
}

retired_table() {
  printf '| Retired | In | Use instead |\n| --- | --- | --- |\n'
  {
    _retired_rows skills
    _retired_rows commands
  } | sort
}

table_for() {
  case "$1" in
  skills) skills_table ;;
  rules) rules_table ;;
  commands) cmd_table command ;;
  workflows) cmd_table workflow ;;
  retired) retired_table ;;
  *) return 1 ;;
  esac
}

# --- the README blocks ------------------------------------------------------

_marker() { printf '<!-- devil:index:%s:%s -->' "$1" "$2"; }

_has_markers() { grep -qxF "$(_marker "$1" start)" "$README" && grep -qxF "$(_marker "$1" end)" "$README"; }

# Copy <in> to <out> with the <kind> block replaced by the table in <tbl>. Outside
# the two marker lines every byte is copied as it is, so a prose edit next to a
# block is never at risk. A blank line sits on each side of the table for MD058.
_replace_block() {
  local in="$1" out="$2" kind="$3" tbl="$4" line start end inside=0
  start="$(_marker "$kind" start)"
  end="$(_marker "$kind" end)"
  : >"$out"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
    "$start")
      printf '%s\n\n' "$line" >>"$out"
      cat "$tbl" >>"$out"
      inside=1
      ;;
    "$end")
      inside=0
      printf '\n%s\n' "$line" >>"$out"
      ;;
    *)
      [ "$inside" = 1 ] || printf '%s\n' "$line" >>"$out"
      ;;
    esac
  done <"$in"
  return 0
}

# --- modes ------------------------------------------------------------------

# Replace every block, in turn, in a scratch copy of the README. Neither mode
# writes anything: --check diffs what comes out, --write copies it over.
# Two scratch files, never the same one twice: _replace_block reads its input to
# the end, so writing it to itself would truncate the file it is reading.
assemble() {
  local kind
  TMPD="$(mktemp -d)" || return 2
  cp "$README" "$TMPD/current.md"
  for kind in "${KINDS[@]}"; do
    table_for "$kind" >"$TMPD/$kind.md" || return 2
    _has_markers "$kind" || {
      printf 'index.sh: %s has no marked block for %s (expected %s)\n' \
        "$README" "$kind" "$(_marker "$kind" start)" >&2
      return 1
    }
    _replace_block "$TMPD/current.md" "$TMPD/next.md" "$kind" "$TMPD/$kind.md"
    mv "$TMPD/next.md" "$TMPD/current.md"
  done
}

check_it() {
  local n="${#KINDS[@]}"
  if diff -u "$README" "$TMPD/current.md" >"$TMPD/diff"; then
    printf '**%s blocks match the frontmatter.** %s\n' "$n" "$README"
    return 0
  fi
  diff -u --label "$README" --label "$README (generated)" "$README" "$TMPD/current.md"
  printf '\nindex.sh: the tables above drifted from the frontmatter. Regenerate: bash tools/index.sh --write\n'
  return 1
}

write_it() {
  local n="${#KINDS[@]}"
  if cmp -s "$README" "$TMPD/current.md"; then
    printf '**%s blocks, all current.** nothing written\n' "$n"
    return 0
  fi
  cat "$TMPD/current.md" >"$README"
  printf '**%s blocks rewritten.** %s\n' "$n" "$README"
}

# The router's payload: one line on how to invoke things, then every table. They
# are the report, so `/devil:guide` has nothing to add to them.
router() {
  printf '%s\n\n' 'Type `/devil:<name>` to run a command; skills load by themselves when their conditions match.'
  local i
  for i in "${!KINDS[@]}"; do
    printf '\n## %s\n\n' "${HEADINGS[$i]}"
    table_for "${KINDS[$i]}" || return 2
  done
}

case "$MODE" in
router) router || exit 2 ;;
check)
  assemble || exit $?
  check_it || exit 1
  ;;
write)
  assemble || exit $?
  write_it
  ;;
esac
exit 0
