#!/usr/bin/env bash
# test_n8n.sh — the committed n8n files must keep the devil's conditions
# (doc/PROFILE.md, "Conditions for n8n on the host"). Static: reads the unit,
# the lockfile and the workflows; starts nothing. The live half (socket, webhook,
# ~/.ssh read) is checked after an apply and recorded in doc/PROFILE.md.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
N8N="$ROOT/profiles/n8n"
# shellcheck disable=SC2034 # read inside the eval of check()
UNIT="$N8N/harness42-n8n.service"
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
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
command -v jq >/dev/null 2>&1 || {
  echo "skip - jq is not installed"
  exit 0
}

check "n8n is pinned to an exact version" 'jq -e ".dependencies.n8n | test(\"^[0-9]+\\\\.[0-9]+\\\\.[0-9]+$\")" "$N8N/package.json" >/dev/null'
check "the lockfile pins the same n8n" '[ "$(jq -r ".packages[\"node_modules/n8n\"].version" "$N8N/package-lock.json")" = "$(jq -r .dependencies.n8n "$N8N/package.json")" ]'
check "the analytics install script is denied" 'jq -e "any(.allowScripts | to_entries[]; (.key | startswith(\"@scarf/scarf@\")) and .value == false)" "$N8N/package.json" >/dev/null'
check "listens on loopback only" 'grep -qx "Environment=N8N_LISTEN_ADDRESS=127.0.0.1" "$UNIT"'
for node in webhook formTrigger localFileTrigger; do
  check "the $node trigger stays excluded" 'grep "^Environment=\"NODES_EXCLUDE=" "$UNIT" | grep -q "n8n-nodes-base.$node\\\\\""'
done
for path in .ssh .config/gh .gnupg; do
  check "\$HOME/$path is masked from n8n" 'grep -q -- "--tmpfs %h/$path\( \|$\)" "$UNIT"'
done
check "n8n starts under bwrap" 'grep -q "^ExecStart=/usr/bin/bwrap " "$UNIT"'
check "no InaccessiblePaths= to trust (skipped silently on Ubuntu)" '! grep -q "^InaccessiblePaths=" "$UNIT"'
check "memory is capped at 768M" 'grep -qx "MemoryMax=768M" "$UNIT"'
for flag in DIAGNOSTICS_ENABLED VERSION_NOTIFICATIONS_ENABLED TEMPLATES_ENABLED COMMUNITY_PACKAGES_ENABLED; do
  check "N8N_$flag is false" 'grep -qx "Environment=N8N_$flag=false" "$UNIT"'
done
check "no workflow bypasses claude permissions" '! grep -rqE -- "dangerously-skip-permissions|--permission-mode[= ]+bypassPermissions" "$N8N/workflows"'
check "every claude -p command names its allowed tools" '! jq -r ".nodes[] | select(.type == \"n8n-nodes-base.executeCommand\") | .parameters.command" "$N8N"/workflows/*.json | grep -- "claude -p" | grep -vq -- "--allowedTools"'
check "no workflow registers an MCP trigger" '! grep -rq "mcpTrigger" "$N8N/workflows"'
check "the nightly check is a systemd timer" 'grep -q "^OnCalendar=" "$N8N/harness42-profile-check.timer"'

echo "# pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
