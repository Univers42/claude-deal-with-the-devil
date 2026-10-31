#!/usr/bin/env bash
# test_sovereign.sh — `devil sovereign` must name every way the user scope leaks
# off the machine, and stay quiet on a clean one. Stubs `ss` and `systemctl` on
# PATH and fakes /proc and the cgroup tree, so nothing real is inspected.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/tools/sovereign.sh"
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
command -v jq >/dev/null 2>&1 || {
  echo "skip - jq is not installed"
  exit 0
}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" STUB="$TMP/stub" SOVEREIGN_PROC="$TMP/proc" SOVEREIGN_CGROUP="$TMP/cgroup"
mkdir -p "$HOME/.claude" "$HOME/.ssh" "$STUB" "$TMP/bin"
echo key >"$HOME/.ssh/id_test"
export PATH="$TMP/bin:$PATH"

cat >"$TMP/bin/ss" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *-l*) cat "$STUB/listen" 2>/dev/null ;;
  *) cat "$STUB/established" 2>/dev/null ;;
esac
SH
cat >"$TMP/bin/systemctl" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *list-units*) cat "$STUB/units" 2>/dev/null ;;
  *ControlGroup*) echo "/user.slice/${*: -1}" ;;
esac
SH
chmod +x "$TMP/bin/ss" "$TMP/bin/systemctl"

# proc <pid> <comm> <sees-ssh:yes|no>: a fake process and its view of ~/.ssh.
proc() {
  mkdir -p "$SOVEREIGN_PROC/$1/root$HOME/.ssh"
  echo "$2" >"$SOVEREIGN_PROC/$1/comm"
  [ "$3" = yes ] && echo key >"$SOVEREIGN_PROC/$1/root$HOME/.ssh/id_test"
  return 0
}
# unit <name> <pid...>: a running harness42 unit and the processes in its cgroup.
unit() {
  local name="$1"
  shift
  echo "$name loaded active running x" >>"$STUB/units"
  mkdir -p "$SOVEREIGN_CGROUP/user.slice/$name"
  printf '%s\n' "$@" >"$SOVEREIGN_CGROUP/user.slice/$name/cgroup.procs"
}

SETTINGS_OK='{"env":{"ENABLE_CLAUDEAI_MCP_SERVERS":"false","DO_NOT_TRACK":"1","CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY":"1","DISABLE_FEEDBACK_COMMAND":"1","DISABLE_BUG_COMMAND":"1"},"syncClaudeAiPlugins":false,"autoUploadSessions":false,"remoteControlAtStartup":false,"agentPushNotifEnabled":false,"inputNeededNotifEnabled":false}'
# settings <jq filter>: the clean settings.json with one change applied.
settings() { jq -c "$1" <<<"$SETTINGS_OK" >"$HOME/.claude/settings.json"; }

clean() {
  rm -rf "${STUB:?}"/* "$SOVEREIGN_PROC" "$SOVEREIGN_CGROUP" "$HOME/.claude-mem"
  settings .
  mkdir -p "$HOME/.claude-mem"
  printf '%s\n' '{"CLAUDE_MEM_PROVIDER":"claude","CLAUDE_MEM_EXCLUDED_PROJECTS":"**","CLAUDE_MEM_CLOUD_SYNC_TOKEN":""}' >"$HOME/.claude-mem/settings.json"
  printf '%s\n' '{"mcpServers":{"serena":{"type":"stdio","command":"serena"}}}' >"$HOME/.claude.json"
  cat >"$STUB/listen" <<'TXT'
LISTEN 0 511 127.0.0.1:5678 0.0.0.0:* users:(("n8n",pid=20,fd=22))
LISTEN 0 4096 *:5000 *:*
TXT
  printf '%s\n' 'ESTAB 0 0 127.0.0.1:40000 127.0.0.1:5678 users:(("n8n",pid=20,fd=30))' >"$STUB/established"
  proc 10 bwrap yes
  proc 20 node no
  unit harness42-n8n.service 10 20
}

run() {
  OUT="$(bash "$TOOL" 2>&1)"
  CODE=$?
}
expect() { # expect <label> <code> [<text in output>]
  if [ "$CODE" -eq "$2" ] && { [ -z "${3:-}" ] || grep -qF -- "$3" <<<"$OUT"; }; then
    ok "$1"
  else
    no "$1 (exit $CODE)"
    printf '%s\n' "$OUT" | sed 's/^/    /'
  fi
}

clean
run
expect "a clean machine passes" 0
expect "a listener whose owner is hidden is reported, not failed" 0 "*:5000"

clean
settings 'del(.env.ENABLE_CLAUDEAI_MCP_SERVERS)'
run
expect "claude.ai MCP servers left on is a finding" 1 "ENABLE_CLAUDEAI_MCP_SERVERS"

clean
settings 'del(.env.DO_NOT_TRACK)'
run
expect "telemetry not opted out is a finding" 1 "DO_NOT_TRACK"

clean
settings '.autoUploadSessions = true'
run
expect "sessions mirrored to claude.ai is a finding" 1 "autoUploadSessions=true"

clean
settings 'del(.remoteControlAtStartup)'
run
expect "Remote Control not explicitly off is a finding" 1 "remoteControlAtStartup=unset"

clean
settings '.agentPushNotifEnabled = true'
run
expect "mobile push through claude.ai is a finding" 1 "agentPushNotifEnabled=true"

clean
settings 'del(.env.CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY)'
run
expect "a feedback survey that can share the transcript is a finding" 1 "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY"

clean
printf '%s\n' '{"CLAUDE_MEM_PROVIDER":"claude"}' >"$HOME/.claude-mem/settings.json"
run
expect "claude-mem compressing sessions on a cloud model is a finding" 1 "CLAUDE_MEM_EXCLUDED_PROJECTS"

clean
printf '%s\n' '{"CLAUDE_MEM_EXCLUDED_PROJECTS":"**","CLAUDE_MEM_CLOUD_SYNC_TOKEN":"tok"}' >"$HOME/.claude-mem/settings.json"
run
expect "claude-mem cloud sync configured is a finding" 1 "CLAUDE_MEM_CLOUD_SYNC_TOKEN"

clean
rm -rf "$HOME/.claude-mem"
run
expect "no claude-mem installed is fine" 0

clean
printf '%s\n' '{"mcpServers":{"cloud":{"type":"http","url":"https://mcp.example.com"}},"projects":{"/p":{"mcpServers":{"sse1":{"type":"sse","url":"https://x.example"}}}}}' >"$HOME/.claude.json"
run
expect "a remote user MCP server is a finding" 1 "cloud"
expect "a remote project MCP server is a finding" 1 "sse1"

clean
echo 'LISTEN 0 511 0.0.0.0:8080 0.0.0.0:* users:(("node",pid=31,fd=3))' >>"$STUB/listen"
run
expect "one of our processes listening beyond loopback is a finding" 1 "0.0.0.0:8080"

clean
echo 'LISTEN 0 511 [::1]:9000 [::]:* users:(("node",pid=32,fd=3))' >>"$STUB/listen"
run
expect "an IPv6 loopback listener is fine" 0

clean
proc 30 node yes
unit harness42-leaky.service 30
run
expect "a kit service that can read ~/.ssh is a finding" 1 "harness42-leaky.service"

clean
echo 'ESTAB 0 0 10.0.0.2:41000 93.184.216.34:443 users:(("node",pid=20,fd=31))' >>"$STUB/established"
run
expect "a kit service talking to an outside host is a finding" 1 "93.184.216.34:443"

clean
echo 'ESTAB 0 0 10.0.0.2:41000 93.184.216.34:443 users:(("firefox",pid=99,fd=31))' >>"$STUB/established"
run
expect "outside traffic of a process that is not the kit's is not judged" 0

echo "test_sovereign: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
