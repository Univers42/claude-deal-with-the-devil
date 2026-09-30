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
  if printf '%s' "$payload" | python3 "$HOOK" >/dev/null 2>&1; then
    ok "fails open on $label"
  else
    no "$label must still exit 0"
  fi
done

# --- an unknown event is simply ignored -------------------------------------
expect "unknown event ignored" '{"hook_event_name":"SomeFutureEvent"}' silent

# --- the entry point finds its sibling modules itself -------------------------
# Python skips putting the script's directory on sys.path under -P or
# PYTHONSAFEPATH (3.11+), so hooks.py must add it before importing its modules.
out="$(cd / && printf '%s' "$(bash_call 'rm -rf /')" | PYTHONSAFEPATH=1 python3 "$HOOK" 2>/dev/null)"
case "$out" in
*'"permissionDecision": "deny"'*) ok "deny fires from / under PYTHONSAFEPATH=1" ;;
*) no "PYTHONSAFEPATH=1 from / must still deny, got: ${out:0:120}" ;;
esac

# --- plugin root vs host root ------------------------------------------------
# The handler finds its own kit (tools/, hooks/config) from its file location
# and the host project from CLAUDE_PROJECT_DIR, else the cwd. A fixture plugin
# root copied from the real tools proves each half separately.
fixture_plugin() {
  local d="$1"
  mkdir -p "$d"/{agents,rules,commands,skills/demo,tools/lib,hooks/scripts,hooks/config,doc}
  cp "$ROOT"/tools/*.sh "$d/tools/"
  cp "$ROOT/tools/lib/common.sh" "$d/tools/lib/"
  chmod +x "$d"/tools/*.sh
  cp "$ROOT"/hooks/scripts/*.py "$d/hooks/scripts/"
  cp "$ROOT/hooks/config/hooks-config.json" "$d/hooks/config/"
  printf -- '---\nname: demo-agent\ndescription: a demo\n---\n\nBody\n' >"$d/agents/demo-agent.md"
  # shellcheck disable=SC2016  # the backticks are markdown links in the fixture
  printf -- '# Demo rule\n\nSee `agents/demo-agent.md`.\n' >"$d/rules/demo.md"
  printf -- '---\nname: demo\ndescription: A demo skill. Use when testing the hook. Auto-triggers on: "test the hook"\nmetadata:\n  stage: beta\n  since: "1.0.0"\n---\n\n# Demo\n\n## Report\n\nok\n' \
    >"$d/skills/demo/SKILL.md"
  printf -- '---\ndescription: a demo command. Usage: /devil:demo\nmetadata:\n  kind: command\n  stage: beta\n  since: "1.0.0"\n---\n\nBody\n' >"$d/commands/demo.md"
  printf -- '---\ndescription: a demo workflow. Usage: /devil:demo-flow\nmetadata:\n  kind: workflow\n  stage: beta\n  since: "1.0.0"\n---\n\nBody\n\n## Report\n\nok\n' >"$d/commands/demo-flow.md"
  # shellcheck disable=SC2016  # ditto
  printf -- '# Index\n\n`agents/demo-agent.md` `rules/demo.md` `skills/demo/SKILL.md`\n`commands/demo.md` `commands/demo-flow.md`\n' \
    >"$d/README.md"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/plugin"
HOST="$TMP/host"
OUTSIDE="$TMP/outside"
fixture_plugin "$FIX"
FHOOK="$FIX/hooks/scripts/hooks.py"
mkdir -p "$HOST" "$OUTSIDE"
git -C "$HOST" init -q && : >"$HOST/main.go" && git -C "$HOST" add . &&
  git -C "$HOST" -c user.name=t -c user.email=t@t.invalid commit -qm init
HOST_P="$(cd "$HOST" && pwd -P)"

# A drift row below must come from the edit, not from the fixture itself.
if bash "$FIX/tools/selfcheck.sh" --summary >/dev/null 2>&1; then
  ok "fixture plugin root starts clean"
else
  no "fixture plugin root must start clean"
  bash "$FIX/tools/selfcheck.sh" --summary 2>&1 | head -8
fi
if bash "$FIX/tools/skillcheck.sh" --summary >/dev/null 2>&1; then
  ok "fixture plugin root starts managed"
else
  no "fixture plugin root must start managed"
  bash "$FIX/tools/skillcheck.sh" --summary 2>&1 | head -8
fi

# quiet <label> <payload> [env args...]: the fixture handler exits 0 and says nothing
quiet() {
  local label="$1" payload="$2" out
  shift 2
  if out="$(printf '%s' "$payload" | env "$@" python3 "$FHOOK" 2>/dev/null)" && [ -z "$out" ]; then
    ok "$label"
  else
    no "$label: expected exit 0 and silence, got: ${out:0:120}"
  fi
}

benign='{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/x/a.go"}}'
quiet "exit 0 with CLAUDE_PLUGIN_ROOT set" "$benign" CLAUDE_PLUGIN_ROOT="$FIX"
quiet "exit 0 with CLAUDE_PLUGIN_ROOT unset (fail open)" "$benign" -u CLAUDE_PLUGIN_ROOT

# A doc inside the plugin root that names a missing file re-runs selfcheck.
md_write() {
  printf '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1"
}
# shellcheck disable=SC2016  # a markdown link, not a command substitution
printf 'See `agents/ghost.md`.\n' >"$FIX/doc/notes.md"
out="$(printf '%s' "$(md_write "$FIX/doc/notes.md")" | python3 "$FHOOK" 2>/dev/null)"
case "$out" in
*selfcheck.sh*"now fails"*agents/ghost.md*) ok "a dangling reference inside the plugin root reports drift" ;;
*) no "expected the selfcheck drift message, got: ${out:0:160}" ;;
esac

# The same edit, breaking a lifecycle contract instead, reports skillcheck. A
# skill that loses metadata.stage is a command of unproven shape in the / menu.
# shellcheck disable=SC2016  # ditto
printf -- '---\nname: demo\ndescription: A demo skill. Use when testing the hook. Auto-triggers on: "test the hook"\nmetadata:\n  since: "1.0.0"\n---\n\n# Demo\n\n## Report\n\nok\n' \
  >"$FIX/skills/demo/SKILL.md"
out="$(printf '%s' "$(md_write "$FIX/skills/demo/SKILL.md")" | python3 "$FHOOK" 2>/dev/null)"
case "$out" in
*skillcheck.sh*"now fails"*"no metadata.stage"*) ok "an untagged skill inside the plugin root reports skillcheck" ;;
*) no "expected the skillcheck lifecycle message, got: ${out:0:160}" ;;
esac

# The same edit outside the plugin root is the host's business, not selfcheck's.
# shellcheck disable=SC2016  # ditto
printf 'See `agents/ghost.md`.\n' >"$OUTSIDE/notes.md"
quiet "a .md outside the plugin root does not trigger selfcheck" "$(md_write "$OUTSIDE/notes.md")"

# A sibling module that fails to import fails open like any other error: exit 0,
# nothing on stdout or stderr, even for a payload that would be denied.
BROKEN="$TMP/broken/hooks/scripts"
mkdir -p "$BROKEN" && cp "$FIX"/hooks/scripts/*.py "$BROKEN/"
siblings=0
for f in "$BROKEN"/*.py; do
  [ "$(basename "$f")" = hooks.py ] && continue
  echo 'raise RuntimeError("broken sibling")' >"$f"
  siblings=$((siblings + 1))
done
out="$(printf '%s' "$(bash_call 'rm -rf /')" | python3 "$BROKEN/hooks.py" 2>&1)"
rc=$?
if [ "$siblings" -gt 0 ] && [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "a broken sibling module fails open"
else
  no "broken sibling modules ($siblings) must exit 0 silently, got rc=$rc: ${out:0:120}"
fi

# SessionStart briefs the host named by CLAUDE_PROJECT_DIR, not the hook's cwd.
out="$(cd "$OUTSIDE" && printf '%s' '{"hook_event_name":"SessionStart","source":"startup"}' |
  CLAUDE_PROJECT_DIR="$HOST" python3 "$FHOOK" 2>/dev/null)"
case "$out" in
*"Build briefing"*"$HOST_P"*) ok "SessionStart digests CLAUDE_PROJECT_DIR" ;;
*) no "SessionStart should brief $HOST_P, got: ${out:0:160}" ;;
esac

# --- PreCompact names the handoff that outlives the session --------------------
# What compaction drops is exactly what a fresh session has to re-derive, so the
# hook has to name the one thing that carries it. The control runs the same match
# over a payload that returns no context: if it matched there, the case below
# would pass for the wrong reason.
out="$(fire '{"hook_event_name":"PreCompact","trigger":"auto"}')"
case "$out" in
*/devil:handoff*) ok "PreCompact suggests /devil:handoff" ;;
*) no "PreCompact must suggest /devil:handoff, got: ${out:0:160}" ;;
esac
out="$(fire "$(bash_call 'ls -la')")"
case "$out" in
*/devil:handoff*) no "the control payload must not name /devil:handoff" ;;
*) ok "the control payload carries no handoff hint, so the case above can fail" ;;
esac

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
