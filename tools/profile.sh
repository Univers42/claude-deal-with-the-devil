#!/usr/bin/env bash
# profile.sh — bring the USER scope (~/.claude, ~/.claude.json, ~/.local/bin) to
# a declared profile: the user-scope twin of setup.sh, which seeds a host repo.
#
# The profile (profiles/user.json) pins every marketplace, plugin, MCP server,
# tool binary and vendored skill. Machine-specific values come from a private
# overlay (~/.config/harness42/local.json) because this kit is public. The run
# writes a lock next to the profile (<profile>.lock.json) recording what was
# actually installed, so a second machine can be compared, not guessed.
#
# Same contract as setup.sh, over the same runner (tools/lib/stage.sh): the
# default dry run prints what would change, `--check` exits 1 unless every stage
# is already applied, `--apply` changes things. Changes are made by the `claude`
# CLI (marketplaces, plugins, MCP servers) or ensure() (files), never by editing
# ~/.claude.json directly.
#
# Usage: profile.sh [--check | --apply] [--profile <file>] [--pack a,b]
#                   [--skip <stage>]... [--only <stage>]
# Exit: 0 clean · 1 (--check) drift · 2 could not run (bad usage, malformed
# profile, missing tool, a failed install or a checksum mismatch).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"
# shellcheck source=lib/stage.sh
. "$DIR/lib/stage.sh"
# shellcheck source=lib/profile.sh
. "$DIR/lib/profile.sh"
# shellcheck source=lib/profile-fetch.sh
. "$DIR/lib/profile-fetch.sh"

MODE=dry
PROFILE=""
PACKS=""
SKIP=" "
ONLY=""
# shellcheck disable=SC2034  # the runner state, read and written by lib/stage.sh
CHANGED="" FAILED="" DRIFT=0 CANNOT=0 ROWS=""

warn() { printf 'profile.sh: %s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
usage: profile.sh [--check | --apply] [--profile <file>] [--pack a,b]
                  [--skip <stage>]... [--only <stage>]

Brings ~/.claude to the pinned profile (default: the kit's profiles/user.json).
  (no mode)  dry run: print what each stage would change
  --check    exit 1 unless every selected stage is already applied
  --apply    change things
  --pack     only entries of these packs (core,knowledge,frontend,backend,business,...)
  --skip     stage to leave out (repeatable)
  --only     the one stage to run
Stages: tools marketplaces plugins localonly mcp skills retire settings instructions budget lock

Exit 0 clean, 1 (--check) drift, 2 could not run.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
  --check) MODE=check ;;
  --apply) MODE=apply ;;
  --dry-run | --dry) MODE=dry ;;
  --profile)
    PROFILE="${2:-}"
    shift
    ;;
  --profile=*) PROFILE="${1#--profile=}" ;;
  --pack)
    PACKS="${2:-}"
    shift
    ;;
  --pack=*) PACKS="${1#--pack=}" ;;
  --skip)
    SKIP="$SKIP ${2:-} "
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

for t in jq claude; do
  have "$t" || {
    warn "$t is not installed; the profile cannot be read or applied without it"
    exit 2
  }
done
KIT="$(claude_root)"
[ -n "$PROFILE" ] || PROFILE="$KIT/profiles/user.json"
[ -f "$PROFILE" ] || {
  warn "no profile at '$PROFILE'"
  exit 2
}
jq -e 'type == "object" and .version == 1' "$PROFILE" >/dev/null 2>&1 || {
  warn "'$PROFILE' is not a version-1 profile (malformed JSON or wrong version)"
  exit 2
}
profile_init "$PROFILE" "$PACKS" || exit 2

STAGES="tools marketplaces plugins localonly mcp skills retire settings instructions budget lock"
# shellcheck disable=SC2317,SC2329  # called by run_stage in lib/stage.sh
selected() {
  [ -n "$ONLY" ] && [ "$1" != "$ONLY" ] && return 1
  case "$SKIP" in *" $1 "*) return 1 ;; esac
  return 0
}

case "$MODE" in
dry) verb="dry run, nothing changed" ;;
check) verb="check, nothing changed" ;;
apply) verb="apply" ;;
esac
printf 'profile: %s%s\n' "$PROFILE" "${PACKS:+ (packs: $PACKS)}"
printf 'scope:   %s (%s)\n\n' "$CLAUDE_HOME" "$verb"
for s in $STAGES; do run_stage "$s"; done
stage_report
exit $?
