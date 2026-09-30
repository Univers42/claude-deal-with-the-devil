#!/usr/bin/env bash
# test_setup_settings.sh — the settings stage honours a host's DEVIL_AUTONOMY=1.
#
# An `ask` rule prompts even in bypass mode, so a host that runs unattended
# sessions and set DEVIL_AUTONOMY=1 must not get the template's ask list back
# from `devil setup --apply`. The negative control is the same host without
# the knob: the template's ask entries must still be added there.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$ROOT/tools/setup.sh"
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

if ! command -v jq >/dev/null 2>&1; then
  echo "skip - jq is not installed; the settings stage needs it"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# host <name> <env json> -> a git host whose settings carry that env and one ask entry.
host() {
  local d="$TMP/$1"
  mkdir -p "$d/.claude"
  git -C "$d" init -q
  printf '{"env": %s, "permissions": {"ask": ["Bash(host-ask:*)"]}}\n' "$2" >"$d/.claude/settings.json"
  bash "$SETUP" --host "$d" --apply --only settings >/dev/null 2>&1
  echo "$d"
}
asks() { jq -c '.permissions.ask' "$1/.claude/settings.json"; }

A="$(host autonomous '{"DEVIL_AUTONOMY": "1"}')"
if [ "$(asks "$A")" = '["Bash(host-ask:*)"]' ]; then
  ok "DEVIL_AUTONOMY=1 keeps the host's own ask list"
else
  no "DEVIL_AUTONOMY=1 host got the template's ask list: $(asks "$A")"
fi
if bash "$SETUP" --host "$A" --check --only settings >/dev/null 2>&1; then
  ok "the autonomous host passes --check after one apply"
else
  no "the autonomous host must pass --check after --apply"
fi

for v in 0 true; do
  B="$(host "knob-$v" "{\"DEVIL_AUTONOMY\": \"$v\"}")"
  if jq -e '.permissions.ask | index("Bash(devil orch:*)")' "$B/.claude/settings.json" >/dev/null; then
    ok "DEVIL_AUTONOMY=$v still adds the template's ask entries"
  else
    no "DEVIL_AUTONOMY=$v must not suppress the template's ask list"
  fi
done

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
