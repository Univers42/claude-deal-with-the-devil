#!/usr/bin/env bash
# setup.sh — seed into a HOST repo what a plugin cannot ship.
#
# A Claude Code plugin carries commands, skills, agents and hooks. It cannot
# carry `.claude/rules/*.md`, the permission list of a `settings.json`, or a
# `CLAUDE.md` fragment. Those are per-repo decisions, so they are written here,
# once, by whoever asked for it.
#
# Non-interactive on purpose: this is what `/devil:setup` runs, and an unscripted
# prompt is a prompt that hangs. What it cannot decide (the tracker kind) it
# detects; what it cannot do without a tool (the settings merge needs jq) it
# refuses to do quietly and says exit 2.
#
# Three modes over ONE code path: the default dry run prints what each stage
# would change, `--check` exits 1 unless every selected stage is already in its
# applied state, `--apply` writes. They share it on purpose: a check that
# recomputes differently from the write is a check that lies.
#
# Usage: setup.sh [--check | --apply] [--host <dir>] [--tracker github|gitlab|local]
#                 [--seed-mcp] [--skip <stage>]... [--only <stage>]
#   (no mode)  dry run, writes nothing, exit 0
#   --check    one row per stage, exit 1 if any stage is not applied
#   --apply    write
#   --skip / --only  stage names: rules settings claude-md opencode tracker mcp gitignore
#
# Exit: 0 clean · 1 (--check) a stage differs · 2 could not run: bad usage, no
# host to seed, or a stage whose tool is missing.
set -uo pipefail # not -e: a stage that fails is data, not a script error
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"
# shellcheck source=lib/seed.sh
. "$DIR/lib/seed.sh"
# shellcheck source=lib/seed-opencode.sh
. "$DIR/lib/seed-opencode.sh"
# shellcheck source=lib/seed-tracker.sh
. "$DIR/lib/seed-tracker.sh"

MODE=dry
HOST=""
TRACKER=""
SEED_MCP=0
SKIP=" "
ONLY=""
CHANGED=""
DRIFT=0
CANNOT=0
ROWS=""

say() { printf '%s\n' "$*"; }
warn() { printf 'setup.sh: %s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
usage: setup.sh [--check | --apply] [--host <dir>] [--tracker github|gitlab|local]
                [--seed-mcp] [--skip <stage>]... [--only <stage>]

Seeds the rules, settings, CLAUDE.md block, OpenCode wiring, tracker adapter and
gitignore lines a plugin cannot ship into a host repo.

  (no mode)  dry run: print what each stage would change
  --check    exit 1 unless every selected stage is already applied
  --apply    write
  --host     the repo to seed; default the git top-level of the cwd
  --tracker  override the detected ticket tracker: github, gitlab or local
  --seed-mcp also seed templates/mcp.json into the host's .mcp.json
  --skip     stage to leave out (repeatable)
  --only     the one stage to run

Exit 0 clean, 1 (--check) drift, 2 could not run.
USAGE
}

# --- arguments --------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
  --check) MODE=check ;;
  --apply) MODE=apply ;;
  --dry-run | --dry) MODE=dry ;;
  --seed-mcp) SEED_MCP=1 ;;
  --host)
    HOST="${2:-}"
    shift
    ;;
  --host=*) HOST="${1#--host=}" ;;
  --tracker)
    TRACKER="${2:-}"
    shift
    ;;
  --tracker=*) TRACKER="${1#--tracker=}" ;;
  --skip)
    SKIP="$SKIP $2 "
    shift
    ;;
  --skip=*) SKIP="$SKIP ${1#--skip=} " ;;
  --only)
    ONLY="${2:-}"
    shift
    ;;
  --only=*) ONLY="${1#--only=}" ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    warn "unknown arg '$1'"
    usage >&2
    exit 2
    ;;
  esac
  shift
done

case "$TRACKER" in
"" | github | gitlab | local) ;;
*) warn "--tracker takes github, gitlab or local, not '$TRACKER'" && exit 2 ;;
esac

# Two roots, never confused (tools/lib/seed.sh keeps the same rule): the kit is
# wherever this script really lives, the host is the repo being seeded.
KIT="$(claude_root)"
[ -n "$HOST" ] || HOST="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$HOST" ] || {
  warn "not inside a git repo; pass --host <dir>"
  exit 2
}
[ -d "$HOST" ] || {
  warn "--host '$HOST' is not a directory"
  exit 2
}
HOST="$(cd "$HOST" && pwd -P)"
KIT_VERSION="$(_plugin_version)"
[ -n "$KIT_VERSION" ] || {
  warn "cannot read a version from $KIT/.claude-plugin/plugin.json"
  exit 2
}
[ -d "$KIT/rules" ] && [ -f "$KIT/templates/settings.json" ] || {
  warn "'$KIT' does not look like the kit (no rules/ or templates/settings.json)"
  exit 2
}

# --- write helpers ----------------------------------------------------------

# ensure <path> <label>: the content arrives on stdin. 0 when the file did not
# match, 1 when it did. Writing is the only difference between the three modes,
# so it is the only thing this function branches on. Called from lib/seed.sh,
# which shellcheck does not read from here.
#
# Callers must REDIRECT (`< <(...)`), never pipe. In a pipeline this function
# runs in a subshell, the CHANGED it records is lost with it, and a stage that
# wrote nothing then reports ok. That is how a merge stage can look clean on a
# host it never touched.
# shellcheck disable=SC2317
# shellcheck disable=SC2329  # called from tools/lib/seed*.sh, which this file sources
ensure() {
  local path="$1" label="$2" tmp
  tmp="$(mktemp)" || return 1
  cat >"$tmp"
  chmod 644 "$tmp"
  if cmp -s "$tmp" "$path" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  CHANGED+="$label"$'\n'
  if [ "$MODE" = apply ]; then
    mkdir -p "$(dirname "$path")" && mv "$tmp" "$path"
  else
    rm -f "$tmp"
  fi
  return 0
}

# append_line <file> <line> <label>: 0 when the line was missing, 1 when it was
# already there, 2 when no temporary file could be made. It appends at the end,
# contiguously and with no separator: a .gitignore is a set of patterns, and the
# property that matters is that a line is added at most once, so a second apply
# finds all three and writes nothing. A file whose last line has no newline gets
# one, because `cat` alone would glue the new line onto it. It builds the new
# content and hands it to ensure(), so the three modes still have exactly one
# place that writes.
# shellcheck disable=SC2317
# shellcheck disable=SC2329  # called from tools/lib/seed*.sh, which this file sources
append_line() {
  local file="$1" line="$2" label="$3" tmp rc l
  if [ -f "$file" ] && grep -qxF -- "$line" "$file"; then return 1; fi
  tmp="$(mktemp)" || return 2
  {
    if [ -f "$file" ]; then
      while IFS= read -r l || [ -n "$l" ]; do printf '%s\n' "$l"; done <"$file"
    fi
    printf '%s\n' "$line"
  } >"$tmp"
  chmod 644 "$tmp"
  ensure "$file" "$label" <"$tmp"
  rc=$?
  rm -f "$tmp"
  return "$rc"
}

# --- stages -----------------------------------------------------------------
# STAGES is the order they must run in: rules before the OpenCode glob that
# points at them, settings before the CLAUDE.md block that names the tools.
STAGES="rules settings claude-md opencode tracker mcp gitignore"

selected() {
  [ "$1" = mcp ] && [ "$SEED_MCP" != 1 ] && return 1
  [ -n "$ONLY" ] && [ "$1" != "$ONLY" ] && return 1
  case "$SKIP" in *" $1 "*) return 1 ;; esac
  return 0
}

row() { ROWS+="$1	$2	$3"$'\n'; }

run_stage() {
  local name="$1" state
  CHANGED=""
  if ! selected "$name"; then
    row skip "$name" "not selected"
    return 0
  fi
  ST_NOTE=""
  ST_STATE=""
  "stage_$name"
  state="${ST_STATE:-ok}"
  # A stage that recorded a change is the definition of drift under --check and
  # the dry run, whatever its own read-back said before the write; under --apply
  # the same recording means it was applied. A stage that could not run keeps its
  # own verdict: exit 2, not "not applied".
  if [ -n "$CHANGED" ]; then
    if [ "$MODE" = apply ]; then
      state=applied
    elif [ "$state" != cannot ]; then
      state=change
    fi
  fi
  [ "$state" = change ] && DRIFT=$((DRIFT + 1))
  [ "$state" = cannot ] && CANNOT=$((CANNOT + 1))
  row "$state" "$name" "${ST_NOTE:-said nothing about what it did}"
  [ -z "$CHANGED" ] && return 0
  printf '%s' "$CHANGED" | while IFS= read -r label; do
    [ -n "$label" ] && printf '                 - %s\n' "$label"
  done
  return 0
}

# --- run --------------------------------------------------------------------
case "$MODE" in
dry) verb="dry run, nothing written" ;;
check) verb="check, nothing written" ;;
apply) verb="apply" ;;
esac
say "setup: $HOST"
say "kit:   $KIT_VERSION at $KIT ($verb)"
say
for s in $STAGES; do run_stage "$s"; done

say
say "| stage | status | note |"
say "|---|---|---|"
printf '%s' "$ROWS" | while IFS='	' read -r st name note; do
  [ -n "${st:-}" ] || continue
  say "| $name | $st | ${note//|/\\|} |"
done
say
say "**$DRIFT to change · $CANNOT could not run**"
say

[ "$CANNOT" -gt 0 ] && exit 2
[ "$MODE" = check ] && [ "$DRIFT" -gt 0 ] && exit 1
exit 0
