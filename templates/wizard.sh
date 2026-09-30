#!/usr/bin/env bash
# wizard.sh: the template for a one-off provisioning procedure a person must
# perform (a dashboard, credentials, CI secrets, a cutover). Copy it, keep the
# library above `# STAGES` byte-identical, and author the stages below it.
#
# The agent never runs a wizard end to end: it opens browsers, reads secrets
# and writes to a live repo. The agent checks it statically instead:
# `bash tests/test_templates.sh` traces the shipped template, and
# `bash tests/test_templates.sh --trace <file>` traces a wizard you authored
# (every helper it calls exists, every secret and variable it sets is named).
# Bash on purpose, like the kit's own tools: arrays and `printf -v` are the
# point, so rules/refactor-shell.md (POSIX) does not apply here.
#
# Usage: wizard.sh [--dry-run] [--help]
#   --dry-run  print each write (.env, gh secret, gh variable) instead of doing it
#   Reads GH_REPO like gh does; prompts read the terminal when stdin is one,
#   else stdin, so a here-string drives it in a test.
# Exit: 0 after `finish` (the summary lists what is still to do by hand);
#   2 on misuse. Not -e: one failed write must not skip the summary.
#
# Never prints a secret value: only names, and `set -x` is never turned on.
#
# Caveat: open_url detects WSL from /proc/version and otherwise trusts
# `xdg-open`/`open` to exist only where a browser does. An SSH session without
# display forwarding, a container that ships xdg-open, or a headless CI runner
# all look like a desktop to it: the URL is printed in every case, so the
# fallback is to copy it. The gh login check is a one-shot at start, bounded
# to 15 s: a `gh auth login` mid-run is only seen on the next run.
set -uo pipefail

DRY_RUN="${DRY_RUN:-0}"
GH_OK="${GH_OK:-0}"
ENV_FILE="${ENV_FILE:-.env}"
WRITTEN=()
BY_HAND=()

have() { command -v "$1" >/dev/null 2>&1; }

_read() {
  if [ -t 0 ]; then
    IFS= read -r "$@" </dev/tty
  else
    IFS= read -r "$@"
    echo
  fi
}

_ident() {
  [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && return 0
  echo "wizard: '$1' is not a variable name" >&2
  return 2
}

# Pure bash on purpose: a missing grep once truncated the file mid-upsert.
_env_get() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    [[ $line == "$1="* ]] || continue
    printf '%s' "${line#*=}"
    return 0
  done <"${2:-$ENV_FILE}" 2>/dev/null
  return 1
}

banner() {
  local rule
  printf -v rule '%*s' $((${#1} + 4)) ''
  printf '%s\n= %s =\n%s\n' "${rule// /=}" "$1" "${rule// /=}"
}

# stage <i> <n> <title>: one screen per stage when there is a screen.
stage() {
  [ -t 1 ] && printf '\033[2J\033[H'
  printf '\nStage %s/%s: %s\n\n' "$1" "$2" "$3"
}

say() { printf '%s\n' "$*"; }
note() { printf '  note: %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

# The URL is always printed: when the opener is absent, when it silently does
# nothing (see the header), and when a dry run must not touch a browser.
open_url() {
  say "open: $1"
  [ "$DRY_RUN" = 1 ] && return 0
  if [ -r /proc/version ] && [[ $(</proc/version) == *icrosoft* ]]; then return 0; fi
  if have xdg-open; then
    xdg-open "$1" >/dev/null 2>&1 &
  elif have open; then
    open "$1" >/dev/null 2>&1 &
  fi
  return 0
}

# ask VAR "<prompt>" [default]: an existing .env value beats the given default.
ask() {
  local current answer=""
  _ident "$1" || return 2
  current="$(_env_get "$1")" || current="${3:-}"
  printf '%s%s: ' "$2" "${current:+ [$current]}"
  _read answer
  printf -v "$1" '%s' "${answer:-$current}"
}

# ask_secret VAR "<prompt>": no echo; Enter keeps the existing .env value.
ask_secret() {
  local current answer=""
  _ident "$1" || return 2
  current="$(_env_get "$1")" || current=""
  printf '%s%s: ' "$2" "${current:+ [Enter keeps the existing value]}"
  _read -s answer
  printf -v "$1" '%s' "${answer:-$current}"
}

# write_env KEY VALUE [file]: upsert, one line per key, value never printed.
# The key moves to the end on an update; a .env is not ordered.
write_env() {
  local key="$1" value="$2" file="${3:-$ENV_FILE}" line kept=()
  _ident "$key" || return 2
  if [ "$DRY_RUN" = 1 ]; then
    say "dry-run: would set $key in $file"
    return 0
  fi
  if [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [[ $line == "$key="* ]] || kept+=("$line")
    done <"$file"
  else
    # Owner-only on creation; a .env holds secrets. Rewriting in place keeps
    # the mode and inode of a file that already exists.
    (umask 077 && : >"$file")
  fi
  printf '%s\n' "${kept[@]}" "$key=$value" >"$file"
  WRITTEN+=("$file:$key")
  say "set $key in $file"
}

# _gh_set <secret|variable> NAME VALUE: the value goes over stdin, never argv.
_gh_set() {
  local kind="$1" name="$2"
  _ident "$name" || return 2
  if [ "$GH_OK" != 1 ]; then
    BY_HAND+=("set $kind $name")
    say "SKIPPED: set $kind $name by hand (gh is absent or not logged in)"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    say "dry-run: would set $kind $name via gh"
    return 0
  fi
  if printf '%s' "$3" | gh "$kind" set "$name" >/dev/null; then
    WRITTEN+=("gh $kind $name")
    say "set $kind $name via gh"
  else
    BY_HAND+=("set $kind $name (gh failed)")
    say "SKIPPED: set $kind $name by hand (gh failed)"
  fi
}

set_secret() { _gh_set secret "$@"; }
set_var() { _gh_set variable "$@"; }

pause() {
  local _enter
  printf '(Enter to continue) '
  _read _enter
}

# confirm "<question>": 0 on y/yes, 1 on anything else including EOF.
confirm() {
  local answer=""
  printf '%s [y/N] ' "$1"
  _read answer
  [[ ${answer,,} == y || ${answer,,} == yes ]]
}

finish() {
  echo
  banner "Done"
  [ "${#WRITTEN[@]}" -eq 0 ] || say "written: ${WRITTEN[*]}"
  if [ "${#BY_HAND[@]}" -eq 0 ]; then
    say "nothing left to do by hand"
  else
    warn "still to do by hand:"
    printf '  %s\n' "${BY_HAND[@]}" >&2
  fi
}

usage() {
  cat <<'USAGE'
usage: wizard.sh [--dry-run] [--help]
  A copy-and-fill provisioning procedure for a person at the keyboard. Edit
  only below the `# STAGES` marker. --dry-run prints each write (.env, gh
  secret, gh variable) instead of doing it. Exit 0 after `finish`; 2 on misuse.
USAGE
}

# One-shot: gh present and logged in. Bounded, it is a network call.
_gh_ready() {
  have gh && have timeout && timeout 15s gh auth status >/dev/null 2>&1 && GH_OK=1
  return 0
}

[[ ${BASH_SOURCE[0]} != "$0" ]] && return 0
case "${1:-}" in
'') ;;
--dry-run) DRY_RUN=1 ;;
--help | -h)
  usage
  exit 0
  ;;
*)
  usage >&2
  exit 2
  ;;
esac
_gh_ready

# STAGES
# Replace everything below with the procedure. Keep the helpers above.
banner "Example: connect CI to the demo dashboard"

stage 1 2 "Create the dashboard API token"
say "Create a token with read scope and paste it here. It is stored in $ENV_FILE and in the repo's secrets."
open_url "https://dashboard.example.com/settings/tokens"
ask_secret DASHBOARD_TOKEN "Dashboard token"
write_env DASHBOARD_TOKEN "$DASHBOARD_TOKEN"
set_secret DASHBOARD_TOKEN "$DASHBOARD_TOKEN"

stage 2 2 "Point CI at the right project"
ask DASHBOARD_PROJECT "Project id" "demo"
write_env DASHBOARD_PROJECT "$DASHBOARD_PROJECT"
set_var DASHBOARD_PROJECT "$DASHBOARD_PROJECT"
confirm "Did the pipeline go green with these values?" || note "re-run this wizard after fixing the pipeline; Enter keeps every value"
finish
