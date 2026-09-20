#!/usr/bin/env bash
# test_hooks.sh — the enforcement hook must deny, ask, pass, and fail open.
#
# The fail-open cases are the important ones: a handler that throws on a
# malformed payload blocks every tool call in the session, which is worse than
# having no hook at all. Each case is proved, including the ones that must do
# nothing.
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

# fire <json> -> prints the handler's stdout; exit code in $?
fire() { printf '%s' "$1" | python3 "$HOOK" 2>/dev/null; }

# expect <label> <json> <deny|ask|silent>
expect() {
  local label="$1" payload="$2" want="$3" out rc
  out="$(fire "$payload")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    no "$label — handler exited $rc, must always exit 0"
    return
  fi
  case "$want" in
    silent)
      [ -z "$out" ] && ok "$label" || no "$label — expected no opinion, got: ${out:0:80}"
      ;;
    *)
      case "$out" in
        *"\"permissionDecision\": \"$want\""*) ok "$label" ;;
        *) no "$label — expected $want, got: ${out:0:120}" ;;
      esac
      ;;
  esac
}

bash_call() {
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"
}

# --- deny: no undo, no legitimate agent use case ----------------------------
expect "deny force-push to main" "$(bash_call 'git push --force origin main')" deny
expect "deny mkfs" "$(bash_call 'mkfs.ext4 /dev/sda1')" deny
expect "deny rm -rf /" "$(bash_call 'rm -rf /')" deny

# --- ask: legitimate but irreversible ---------------------------------------
expect "ask on git push" "$(bash_call 'git push origin feature')" ask
expect "ask on terraform apply" "$(bash_call 'terraform apply')" ask
expect "ask on npm publish" "$(bash_call 'npm publish')" ask
expect "ask on unqualified DELETE" "$(bash_call 'psql -c \"DELETE FROM users\"')" ask
expect "ask on git reset --hard" "$(bash_call 'git reset --hard HEAD~3')" ask
expect "ask writing a .env" \
  '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/x/.env"}}' ask
expect "ask writing an ssh key" \
  '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/x/id_ed25519"}}' ask

# --- silent: ordinary work must not be impeded ------------------------------
expect "ordinary ls" "$(bash_call 'ls -la')" silent
expect "a normal build" "$(bash_call 'make build')" silent
expect "a qualified DELETE" "$(bash_call 'psql -c \"DELETE FROM users WHERE id=1\"')" silent
expect "reading a file" \
  '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/x/a.go"}}' silent
expect "writing an ordinary file" \
  '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/x/main.go"}}' silent

# --- fail open: a broken hook must never block the session ------------------
for label in "malformed json" "empty stdin" "no event name" "null fields"; do
  case "$label" in
    "malformed json") payload='{not json' ;;
    "empty stdin") payload='' ;;
    "no event name") payload='{"tool_name":"Bash"}' ;;
    "null fields") payload='{"hook_event_name":"PreToolUse","tool_name":null,"tool_input":null}' ;;
  esac
  printf '%s' "$payload" | python3 "$HOOK" >/dev/null 2>&1
  if [ $? -eq 0 ]; then ok "fails open on $label"; else no "$label must still exit 0"; fi
done

# --- an unknown event is simply ignored -------------------------------------
expect "unknown event ignored" '{"hook_event_name":"SomeFutureEvent"}' silent

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
