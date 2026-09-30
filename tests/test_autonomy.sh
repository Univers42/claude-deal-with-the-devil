#!/usr/bin/env bash
# test_autonomy.sh — DEVIL_AUTONOMY=1 turns the ask into silence, and nothing else.
#
# The knob exists for sessions the user runs unattended: an ask is a prompt, and a
# prompt stops a session even in bypass mode. Every case here is paired with its
# control, because a switch with one direction is indistinguishable from a broken
# matcher: the ask must still appear with the knob off, the deny must survive the knob
# on, and only the exact value "1" may silence anything.
#
# Command strings are assembled from parts, so this file holds no literal
# irreversible command: editing it must not be stopped by the hook it tests.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/scripts/hooks.py"
PASS=0
FAIL=0

ok() {
  echo "ok   - $1"
  PASS=$((PASS + 1))
}
no() {
  echo "FAIL - $1"
  FAIL=$((FAIL + 1))
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "skip - python3 not installed"
  exit 0
fi

# expect <label> <want> <payload> [VAR=value ...]
# DEVIL_AUTONOMY is cleared first: this suite runs inside unattended sessions too, so
# a case about the default must not inherit the environment of whoever ran it.
expect() {
  local label="$1" want="$2" payload="$3" out rc
  shift 3
  out="$(printf '%s' "$payload" | env -u DEVIL_AUTONOMY "$@" python3 "$HOOK" 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    no "$label — handler exited $rc, must always exit 0"
    return
  fi
  case "$want" in
  silent)
    if [ -z "$out" ]; then
      ok "$label"
    else
      no "$label — expected no opinion, got: ${out:0:80}"
    fi
    ;;
  *)
    case "$out" in
    *"\"permissionDecision\": \"$want\""*) ok "$label" ;;
    *) no "$label — expected $want, got: ${out:0:120}" ;;
    esac
    ;;
  esac
}

verb=push
push_to() { printf 'git %s origin %s' "$verb" "$1"; }
force_to() { printf 'git %s --force origin %s' "$verb" "$1"; }
bash_call() {
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"
}
secret_name() { printf '.%s' "$1"; }
write_call() {
  printf '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1"
}

PUSH="$(bash_call "$(push_to develop)")"
FORCED="$(bash_call "$(force_to main)")"
SECRET="$(write_call "/x/$(secret_name env)")"

# --- the ask defers to the session's permission mode ---------------------------
expect "a push asks with the knob unset" ask "$PUSH"
expect "the knob defers a push to the permission mode" silent "$PUSH" DEVIL_AUTONOMY=1
expect "the knob does not ask about a secret path" silent "$SECRET" DEVIL_AUTONOMY=1

# The controls. A switch that guesses is a switch that lies: every value except the
# exact "1" keeps the prompt, including the ones a person would reach for.
expect "DEVIL_AUTONOMY=true is not the knob" ask "$PUSH" DEVIL_AUTONOMY=true
expect "DEVIL_AUTONOMY=yes is not the knob" ask "$PUSH" DEVIL_AUTONOMY=yes
expect "DEVIL_AUTONOMY=0 is not the knob" ask "$PUSH" DEVIL_AUTONOMY=0
expect "DEVIL_AUTONOMY= 1 is not the knob" ask "$PUSH" "DEVIL_AUTONOMY= 1"
expect "a secret path asks with the knob unset" ask "$SECRET"

# --- the deny is not part of the deal ------------------------------------------
expect "the knob does not unlock a force-push to main" deny "$FORCED" DEVIL_AUTONOMY=1
# The control for that one: the same command denied with the knob off, so the case
# above cannot pass because the matcher stopped seeing the command.
expect "a force-push to main is denied with the knob unset" deny "$FORCED"

# The knob is about prompts, so an ordinary command stays ordinary either way.
ORDINARY="$(bash_call 'ls -la')"
expect "ordinary work is untouched with the knob unset" silent "$ORDINARY"
expect "ordinary work is untouched with the knob on" silent "$ORDINARY" DEVIL_AUTONOMY=1

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
