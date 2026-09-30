#!/usr/bin/env bash
# hitl-loop.sh: a human-in-the-loop reproduction harness. Copy it when a bug
# needs a person at the keyboard (sign in, click, observe), fill in the stages,
# hand it to that person, and parse the KEY=VALUE tail it prints.
#
# The marker rule: everything above `# STAGES` is the library and is never
# edited; everything below it is the reproduction and is replaced per bug.
# Bash on purpose, like the kit's own tools: `printf -v` and arrays are the
# point, so rules/refactor-shell.md (POSIX) does not apply here.
#
# Usage: hitl-loop.sh [--help]
#   Prompts read the terminal when stdin is one, else stdin itself, so a
#   here-string drives the same script in tests/test_templates.sh.
# Exit: 0 after `finish`; 2 on misuse. Not -e: a failed command in a stage
#   must not skip the tail, so the agent still gets what was captured.
#
# Caveat: INTERACTIVE. Never run it under tools/watch.sh: the idle timeout
# kills it while the person is still reading. Captured values are free text
# typed by a person; they are testimony, not facts, and the agent verifies
# them before acting on them.
set -uo pipefail

RUN_ID="$(printf '%02x%02x' $((RANDOM % 256)) $((RANDOM % 256)))"
STEP=0
CAPTURED=()

# Reads one line into the named variable: from the terminal when stdin is one
# (so `./repro.sh | tee log` still prompts), else from stdin.
_read() {
  if [ -t 0 ]; then
    IFS= read -r "$1" </dev/tty
  else
    IFS= read -r "$1"
    echo # keep the transcript line-oriented when nothing echoes the input
  fi
}

_ident() {
  [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && return 0
  echo "hitl-loop: '$1' is not a variable name" >&2
  return 2
}

# step "<instruction>": print it, wait for Enter.
step() {
  local _enter
  STEP=$((STEP + 1))
  printf '\n[%d] %s\n    (Enter when done) ' "$STEP" "$1"
  _read _enter
}

# capture VAR "<question>": ask, store the answer, remember VAR for `finish`.
capture() {
  local answer=""
  _ident "$1" || return 2
  printf '\n? %s\n> ' "$2"
  _read answer
  printf -v "$1" '%s' "$answer"
  CAPTURED+=("$1")
}

# tag [text]: prefix debug output with the run's id, so one grep for
# DEBUG-<id> finds every line this run produced.
tag() { printf '[DEBUG-%s]%s\n' "$RUN_ID" "${1:+ $*}"; }

# The tail the agent parses: one KEY=VALUE per captured variable, after the
# `== captured ==` line.
finish() {
  local key
  printf '\n== captured ==\n'
  for key in "${CAPTURED[@]}"; do printf '%s=%s\n' "$key" "${!key}"; done
}

usage() {
  cat <<'USAGE'
usage: hitl-loop.sh [--help]
  A copy-and-fill reproduction harness for a person at the keyboard. Edit only
  below the `# STAGES` marker. Prompts read the terminal when stdin is one,
  else stdin. Prints one KEY=VALUE per captured value after `== captured ==`.
  Exit 0 after `finish`; 2 on misuse. Never run it under tools/watch.sh.
USAGE
}

[[ ${BASH_SOURCE[0]} != "$0" ]] && return 0
case "${1:-}" in
'') ;;
--help | -h)
  usage
  exit 0
  ;;
*)
  usage >&2
  exit 2
  ;;
esac
tag "run started"

# STAGES
# Replace everything below with the reproduction. Keep the helpers above.
step "Sign in to the staging dashboard as the affected user."
step "Open the Orders page and click Export."
capture RESULT "What did the page show: a download, a spinner or an error? Paste the exact text."
capture PAGE_URL "Paste the address bar URL at that moment."
tag "reproduction finished"
finish
