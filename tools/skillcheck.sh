#!/usr/bin/env bash
# skillcheck.sh — enforce skill and command management with a gate, not prose.
#
# selfcheck.sh asks "does this config tell the truth about itself?". This asks
# the harder one: "is this config MANAGED?". A description naming no trigger, a
# skill promoted with no recorded run, a retired name cited by a live one: each
# is a decision nobody made. A lifecycle is only real if a tool enforces it.
#
# Usage: skillcheck.sh [--summary] [--strict]  (--summary: failing rows only;
# --strict: a WARN is a failure. Default reports warnings and exits 0.)
# Exit: 0 clean; 1 on a FAIL; 2 when it could not run.
set -uo pipefail # not -e: a failing check is data, not a script error
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
    echo "skillcheck.sh: unknown arg '$a'" >&2
    exit 2
    ;;
  esac
done

ROOT="$(claude_root)"
cd "$ROOT" || exit 2
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

STAGES="stable beta retired rule"
KINDS="command workflow"
DESC_HARD_MAX=1024
DESC_SOFT_MAX=400
SCENARIO_HEADINGS=('## Scenario' '## Baseline' '## With skill' '## Verdict')

# A name a doc may cite before the slice that writes it lands (`/devil:setup` is
# documented by README; slice M5 writes the command). Caveat: a promise the gate
# cannot check, so delete the entry the day the file exists.
PENDING="setup"

_has() { [[ " $1 " == *" $2 "* ]]; }

# Only a skill or a command owns lifecycle metadata; the rest are listed for A15.
_managed() { [[ "$1" == skill || "$1" == command ]]; }

# The raw value, quotes intact: fm_meta strips them and would read 1.0.0 as a float.
_fm_raw() { fm_block "$1" | sed -n "s/^  $2:[[:space:]]*//p" | head -1; }

_docs() { find . -name '*.md' -not -path './cache/*' -not -path './.claude/*' -not -path './target/*' -not -path './.git/*' | sort; }

# <path> TAB <kind> TAB <name>, for every asset a body can point at.
_assets() {
  local f kind n
  for f in skills/*/SKILL.md commands/*.md agents/*.md rules/*.md; do
    [ -e "$f" ] || continue
    case "$f" in
    skills/*) kind=skill n="$(basename "$(dirname "$f")")" ;;
    commands/*) kind=command n="$(basename "$f" .md)" ;;
    agents/*) kind=agent n="$(basename "$f" .md)" ;;
    *) kind=rule n="$(basename "$f" .md)" ;;
    esac
    printf '%s\t%s\t%s\n' "$f" "$kind" "$n"
  done
}

# --- 1. stage, since, kind --------------------------------------------------
# Absent metadata is the failure direction on purpose, not the reverse of a misread tag.
check_stage() {
  local f="$1" dir="$2" name="$3" stage since
  _managed "$dir" || return 0
  stage="$(fm_meta "$f" stage)"
  if [ -z "$stage" ]; then
    row FAIL stage "$dir/$name" "no metadata.stage (one of: $STAGES)"
    return 0
  fi
  _has "$STAGES" "$stage" || row FAIL stage "$dir/$name" "metadata.stage '$stage' is not one of: $STAGES"
  [ -z "$(fm_field "$f" stage)" ] || row FAIL stage "$dir/$name" "a top-level 'stage:' is not metadata.stage; no host reads it"
  if [ "$dir" = command ]; then
    _has "$KINDS" "$(fm_meta "$f" kind)" || row FAIL kind "$dir/$name" "metadata.kind must be one of: $KINDS"
    [ "$stage" != rule ] || row FAIL stage "$dir/$name" "stage 'rule' is valid only on a skill"
  fi
  since="$(_fm_raw "$f" since)"
  [[ "$since" == \"*\" ]] || row FAIL since "$dir/$name" "metadata.since must be a quoted string, got '$since'"
  return 0
}

# --- 2. description ---------------------------------------------------------
# Caveat: "ends with the quoted phrase list" is a string test on the joined
# description, so a list trailing a closing sentence reads as absent. It catches
# the real drift (the list dropped, or rewritten as prose); it is not a parser.
_ends_with_triggers() { [[ "$1" == *'Auto-triggers on: '* && "$1" == *'"' ]]; }

check_description() {
  local f="$1" dir="$2" name="$3" desc bytes sev
  _managed "$dir" || return 0
  desc="$(fm_desc "$f")"
  if [ -z "$desc" ]; then
    row FAIL description "$dir/$name" "no description: it will not appear in the / menu"
    return 0
  fi
  bytes="$(printf '%s' "$desc" | wc -c | tr -d ' ')"
  [ "$bytes" -le "$DESC_HARD_MAX" ] || row FAIL description "$dir/$name" "$bytes bytes, over the $DESC_HARD_MAX a listing can hold"
  [ "$bytes" -le "$DESC_SOFT_MAX" ] || row WARN description "$dir/$name" "$bytes bytes, over the $DESC_SOFT_MAX that stays cheap"
  if [ "$dir" = command ]; then
    [[ "$desc" == *"Usage: /devil:$name"* ]] || row FAIL usage "$dir/$name" "description has no 'Usage: /devil:$name'"
    return 0
  fi
  case "$(fm_meta "$f" stage)" in
  stable) sev=FAIL ;;
  beta) sev=WARN ;;
  *) return 0 ;; # a tombstone and a path-scoped rule describe themselves
  esac
  [[ "$desc" == *"Use when"* ]] || row "$sev" a14 "$dir/$name" "description has no 'Use when <conditions>'"
  _ends_with_triggers "$desc" || row "$sev" a14 "$dir/$name" 'description does not end with Auto-triggers on: "..."'
  return 0
}

# --- 3. the report heading --------------------------------------------------
# `## Report`, `## 5. Report`, `### Phase 3 — Report`: the forms taken so far.
# Caveat: a regex, so bold text or a fenced report is not seen. Read the body.
_has_report() { grep -qE '^#{2,3} .*Report[[:space:]]*$' "$1"; }

check_report() {
  local f="$1" dir="$2" name="$3"
  _managed "$dir" || return 0
  if [ "$dir" = command ] && [ "$(fm_meta "$f" kind)" != workflow ]; then return 0; fi
  case "$dir:$(fm_meta "$f" stage)" in
  skill:retired | skill:rule) return 0 ;;
  esac
  _has_report "$f" || row FAIL report "$dir/$name" "no '## Report' heading: a body with nothing to paste is not finished"
  return 0
}

# --- 4. slash references ----------------------------------------------------
# A `/devil:<name>` reaching nothing is a dead step in a procedure. Bare built-ins
# (`/compact`, `/plugin`) carry no namespace and are left alone.
check_slash_refs() {
  local doc name
  while read -r doc; do
    while read -r name; do
      [ -n "$name" ] || continue
      _has "$PENDING" "$name" && continue
      { [ -f "commands/$name.md" ] || [ -f "skills/$name/SKILL.md" ]; } && continue
      row FAIL slash "${doc#./}" "/devil:$name has no commands/$name.md or skills/$name/SKILL.md"
    done < <(grep -ohE '/devil:[A-Za-z0-9_-]+' "$doc" 2>/dev/null | sed 's|^/devil:||' | sort -u)
  done < <(_docs)
}

# --- 5. the scenario record -------------------------------------------------
# Presence and shape only: the verdict is a human judgement no regex reads.
# Caveat: headings by name, so a placeholder record passes here, fails review.
check_scenario() {
  local f="$1" dir="$2" name="$3" rec h
  [ "$dir" = skill ] || return 0
  [ "$(fm_meta "$f" stage)" = stable ] || return 0
  rec="tests/scenarios/$name.md"
  if [ ! -f "$rec" ]; then
    row FAIL scenario "$name" "stage stable with no $rec: run the scenario before promoting"
    return 0
  fi
  for h in "${SCENARIO_HEADINGS[@]}"; do
    grep -qE "^$h" "$rec" || row FAIL scenario "$name" "$rec has no '$h' heading"
  done
  return 0
}

# --- 6. the retired tombstone -----------------------------------------------
# A tombstone pointing nowhere is worse than none: the name stays in every index.
_replaced_by_exists() {
  local t
  for t in "commands/$1.md" "skills/$1/SKILL.md"; do
    [ -f "$t" ] && [ "$(fm_meta "$t" stage)" != retired ] && return 0
  done
  return 1
}

check_retired() {
  local f="$1" dir="$2" name="$3" by
  _managed "$dir" || return 0
  [ "$(fm_meta "$f" stage)" = retired ] || return 0
  fm_flag "$f" disable-model-invocation || row FAIL retired "$dir/$name" "no 'disable-model-invocation: true', so a tombstone is invokable"
  by="$(fm_meta "$f" replaced-by)"
  if [ -z "$by" ]; then
    row FAIL retired "$dir/$name" "no metadata.replaced-by"
  elif ! _replaced_by_exists "$by"; then
    row FAIL retired "$dir/$name" "replaced-by '$by' is missing, or is itself retired"
  fi
  return 0
}

# --- 7. the path-scoped rule skill ------------------------------------------
# A rule skill loads on its paths alone; without those keys it costs context daily.
check_rule() {
  local f="$1" dir="$2" name="$3"
  [ "$dir" = skill ] || return 0
  [ "$(fm_meta "$f" stage)" = rule ] || return 0
  fm_has_paths "$f" || row FAIL rule "$name" "stage rule with no paths:, so it loads every session instead of on its globs"
  [ "$(fm_field "$f" user-invocable)" = false ] || row FAIL rule "$name" "stage rule needs 'user-invocable: false': it is guidance, not a command"
  return 0
}

# --- 8. the user-only invariant (A15) ---------------------------------------
# The Skill tool cannot reach an asset the model may not invoke, so a reference to
# one dead-ends mid-procedure. Exception: a line handing it to the reader, which
# carries "the user". Caveat: that substring silences the whole line, so a body
# naming the user beside an unreachable reference passes here.
_user_only_names() {
  local f
  for f in commands/*.md skills/*/SKILL.md; do
    fm_flag "$f" disable-model-invocation || continue
    case "$f" in
    skills/*) f="$(dirname "$f")" ;;
    esac
    basename "$f" .md
  done
  return 0
}

check_user_only() {
  local src dir name uname hit
  while IFS=$'\t' read -r src dir name; do
    fm_flag "$src" disable-model-invocation && continue
    while read -r uname; do
      [ -n "$uname" ] || continue
      while IFS= read -r hit; do
        [[ "${hit#*:}" == *"the user"* ]] && continue
        row FAIL user-only "${src#./}" "line ${hit%%:*} sends the model to /devil:$uname, which it may not invoke"
      done < <(grep -nE "/devil:$uname([^A-Za-z0-9_-]|$)" "$src" || true)
    done < <(_user_only_names)
  done < <(_assets)
}

# --- run --------------------------------------------------------------------
# One pass over the inventory, so every per-asset check sees the same rows.
while IFS=$'\t' read -r f dir name; do
  check_stage "$f" "$dir" "$name"
  check_description "$f" "$dir" "$name"
  check_report "$f" "$dir" "$name"
  check_scenario "$f" "$dir" "$name"
  check_retired "$f" "$dir" "$name"
  check_rule "$f" "$dir" "$name"
done < <(_assets)
check_slash_refs
check_user_only

# --- report -----------------------------------------------------------------
echo "# Skill check"
echo
if [ -z "$ROWS" ]; then
  echo "Managed: metadata, description form, report heading, and every reference resolving."
else
  echo "| Status | Check | Subject | Detail |"
  echo "|---|---|---|---|"
  printf '%s' "$ROWS" | while IFS='	' read -r s c sub d; do
    [ -n "${s:-}" ] || continue
    [ "$SUMMARY" = 1 ] && [ "$s" != FAIL ] && continue
    echo "| $s | $c | \`$sub\` | $d |"
  done
fi
printf '\n**%s failed, %s warned.**  skills %s · commands %s · workflows %s\n' "$FAILED" "$WARNED" \
  "$(asset_names skills | grep -c .)" "$(comm -23 <(asset_names commands) <(asset_names workflows) | grep -c .)" \
  "$(asset_names workflows | grep -c .)"

[ "$FAILED" -eq 0 ] || exit 1
[ "$STRICT" = 1 ] && [ "$WARNED" -gt 0 ] && exit 1
exit 0
