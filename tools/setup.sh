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
# shellcheck source=lib/stage.sh
. "$DIR/lib/stage.sh"
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
# shellcheck disable=SC2034  # the runner state, read and written by lib/stage.sh
CHANGED="" DRIFT=0 CANNOT=0 ROWS=""

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

# --- stages -----------------------------------------------------------------
# STAGES is the order they must run in: rules before the OpenCode glob that
# points at them, settings before the CLAUDE.md block that names the tools.
STAGES="rules settings claude-md opencode tracker mcp gitignore"

# shellcheck disable=SC2317,SC2329  # called by run_stage in lib/stage.sh
selected() {
  [ "$1" = mcp ] && [ "$SEED_MCP" != 1 ] && return 1
  [ -n "$ONLY" ] && [ "$1" != "$ONLY" ] && return 1
  case "$SKIP" in *" $1 "*) return 1 ;; esac
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

stage_report
exit $?
