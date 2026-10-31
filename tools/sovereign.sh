#!/usr/bin/env bash
# sovereign.sh — does this machine's AI stack keep its data here? Measured, not trusted.
#
# Settings say what should happen; this checks what does. It exists because three
# promises broke on the profile's own machine (doc/PROFILE.md): a claude-mem default
# that phoned home, a systemd `InaccessiblePaths=` skipped without an error, and a
# claude.ai connector loading despite its off-switch. Six checks:
#   claude.ai  settings turn the account's MCP servers and plugin sync off
#   telemetry  settings carry DO_NOT_TRACK=1
#   mcp        no user or project MCP server is a remote URL (~/.claude.json)
#   listen     none of our processes listens beyond loopback (ss -ltnp)
#   secrets    no process of a running harness42-* unit can read ~/.ssh, ~/.gnupg
#              or ~/.config/gh (each process's own mount namespace, via /proc)
#   outbound   no process of a harness42-* unit holds a connection off the machine
#
# Usage: sovereign.sh     Exit: 0 clean · 1 a finding · 2 could not run.
#
# Caveat: `listen` and `outbound` are one snapshot. A service that calls home once
# an hour passes between calls; the nightly timer runs it again, which narrows the
# gap without closing it. `ss` shows owners only for this user's processes, so a
# listener owned by root or another user is reported as `info`, never judged.
# `secrets` reads the processes of harness42-* units only: an MCP server or a
# plugin hook launched by Claude runs as you and can read ~/.ssh by design.
set -uo pipefail

PROC="${SOVEREIGN_PROC:-/proc}"
CGROUP="${SOVEREIGN_CGROUP:-/sys/fs/cgroup}"
SETTINGS="$HOME/.claude/settings.json"
CLAUDE_JSON="$HOME/.claude.json"
FINDINGS=0
ROWS=""

row() { # row <check> <ok|finding|info> <evidence>
  [ "$2" = finding ] && FINDINGS=$((FINDINGS + 1))
  ROWS+="| $1 | $2 | $3 |"$'\n'
}

command -v jq >/dev/null 2>&1 || {
  echo "sovereign.sh: jq is required" >&2
  exit 2
}

setting() { jq -r "$1 // \"unset\"" "$SETTINGS" 2>/dev/null || echo unreadable; }

check_claude_ai() {
  local mcp sync
  mcp="$(setting '.env.ENABLE_CLAUDEAI_MCP_SERVERS')"
  sync="$(setting '.syncClaudeAiPlugins | tostring')"
  if [ "$mcp" = false ] && [ "$sync" = false ]; then
    row claude.ai ok "ENABLE_CLAUDEAI_MCP_SERVERS=false, syncClaudeAiPlugins=false"
  else
    row claude.ai finding "ENABLE_CLAUDEAI_MCP_SERVERS=$mcp, syncClaudeAiPlugins=$sync (both must be false)"
  fi
}

check_telemetry() {
  local dnt
  dnt="$(setting '.env.DO_NOT_TRACK')"
  if [ "$dnt" = 1 ]; then row telemetry ok "DO_NOT_TRACK=1"; else row telemetry finding "DO_NOT_TRACK=$dnt (want 1)"; fi
}

check_mcp() {
  local remote
  [ -f "$CLAUDE_JSON" ] || {
    row mcp ok "no $CLAUDE_JSON"
    return
  }
  remote="$(jq -r '[(.mcpServers // {}), (.projects // {} | .[] | .mcpServers // {})]
    | map(to_entries[]) | .[]
    | select(.value.url or ((.value.type // "stdio") | test("^(http|sse|ws)")))
    | "\(.key) (\(.value.url // .value.type))"' "$CLAUDE_JSON" 2>/dev/null | sort -u | paste -sd, -)"
  if [ -z "$remote" ]; then row mcp ok "every MCP server in $CLAUDE_JSON is local stdio"; else row mcp finding "remote: $remote"; fi
}

# is_loopback <addr:port>: 127/8, ::1, or a 127.x stub resolver bound to an interface.
is_loopback() { [[ "$1" =~ ^(127\.[0-9.]+(%[a-z0-9]+)?|\[::1\]|::1|\[::ffff:127\.[0-9.]+\]):[0-9]+$ ]]; }

check_listen() {
  local line addr ours="" hidden=""
  while read -r line; do
    addr="$(awk '{print $4}' <<<"$line")"
    [ -n "$addr" ] && ! is_loopback "$addr" || continue
    if [[ "$line" == *users:* ]]; then ours+=" $addr($(grep -o '(("[^"]*"' <<<"$line" | tr -d '("'))"; else hidden+=" $addr"; fi
  done < <(ss -ltnpH 2>/dev/null)
  if [ -n "$ours" ]; then row listen finding "ours beyond loopback:$ours"; else row listen ok "our listeners are all loopback"; fi
  [ -z "$hidden" ] || row listen info "not ours (owner hidden by ss):$hidden"
}

# unit_pids: "<unit> <pid>" for every process of every running harness42-* user unit.
unit_pids() {
  local unit cg
  while read -r unit _; do
    [ -n "$unit" ] || continue
    cg="$(systemctl --user show -p ControlGroup --value "$unit" 2>/dev/null)"
    [ -f "$CGROUP$cg/cgroup.procs" ] || continue
    sed "s/^/$unit /" "$CGROUP$cg/cgroup.procs"
  done < <(systemctl --user list-units 'harness42-*.service' --state=running --no-legend --plain 2>/dev/null)
}

check_secrets() {
  local unit pid dir leaks="" n=0
  while read -r unit pid; do
    # bwrap is the launcher: it stays in the host namespace by design; its child is masked.
    [ "$(cat "$PROC/$pid/comm" 2>/dev/null)" = bwrap ] && continue
    n=$((n + 1))
    for dir in .ssh .gnupg .config/gh; do
      [ -n "$(ls -A "$HOME/$dir" 2>/dev/null)" ] || continue
      [ -n "$(ls -A "$PROC/$pid/root$HOME/$dir" 2>/dev/null)" ] && leaks+=" $unit:~/$dir"
    done
  done < <(unit_pids)
  if [ -n "$leaks" ]; then row secrets finding "readable by:$(tr ' ' '\n' <<<"$leaks" | sort -u | paste -sd' ' -)"; else row secrets ok "$n kit processes inspected; none sees a secret dir"; fi
}

check_outbound() {
  local pids line peer pid out=""
  pids=" $(unit_pids | awk '{print $2}' | paste -sd' ' -) "
  while read -r line; do
    peer="$(awk '{print $5}' <<<"$line")"
    pid="$(grep -o 'pid=[0-9]*' <<<"$line" | head -1 | cut -d= -f2)"
    [ -n "$pid" ] && [[ "$pids" == *" $pid "* ]] && ! is_loopback "$peer" && out+=" $peer(pid $pid)"
  done < <(ss -tnpH 2>/dev/null)
  if [ -n "$out" ]; then row outbound finding "kit services talking off-machine:$out"; else row outbound ok "no kit service holds an off-machine connection"; fi
}

check_claude_ai
check_telemetry
check_mcp
check_listen
check_secrets
check_outbound

printf '| check | status | evidence |\n|---|---|---|\n%s\n' "$ROWS"
if [ "$FINDINGS" -gt 0 ]; then
  printf '**%d finding(s)**: something on this machine sends or exposes data the profile says it keeps.\n' "$FINDINGS"
  exit 1
fi
printf '**clean**: nothing measured leaves the machine (one snapshot; see the Caveat in this file).\n'
