#!/usr/bin/env bash
# claude-stub.sh — a fake `claude` for tests/test_profile*.sh. It implements only the
# subcommands tools/profile.sh calls, against JSON files under $STUB_STATE, and logs
# every call to $STUB_STATE/calls.log so a test can prove the dry run and a second
# apply mutate nothing.
# Caveat: it models the CLI's state, not its behaviour. A real `claude plugin install`
# can fail on network, auth or a command-source prompt; the stub always succeeds unless
# the id is listed in $STUB_STATE/fail-install, which is how the failure path is tested.
set -uo pipefail
S="${STUB_STATE:?STUB_STATE is not set}"
CJ="$HOME/.claude.json"
echo "$*" >>"$S/calls.log"
[ -f "$S/plugins.json" ] || echo '[]' >"$S/plugins.json"
[ -f "$S/marketplaces.json" ] || echo '[]' >"$S/marketplaces.json"
[ -f "$CJ" ] || echo '{}' >"$CJ"

put() {
  local f="$1" t
  t="$(mktemp)"
  cat >"$t" && mv "$t" "$f"
}

case "$1 $2" in
"plugin list") cat "$S/plugins.json" ;;
"plugin install")
  id="$3"
  if grep -qxF "$id" "$S/fail-install" 2>/dev/null; then
    echo "failed to install $id" >&2
    exit 1
  fi
  jq --arg id "$id" 'map(select(.id != $id or .scope != "user"))
    + [{id: $id, scope: "user", enabled: true, version: "1.0.0"}]' "$S/plugins.json" |
    put "$S/plugins.json"
  ;;
"plugin enable")
  jq --arg id "$3" 'map(if .id == $id and .scope == "user" then .enabled = true else . end)' \
    "$S/plugins.json" | put "$S/plugins.json"
  ;;
"plugin details") printf '%s\n' "$3" "  Always-on:   ~100 tok   added to every session" ;;
"plugin marketplace")
  case "$3" in
  list) cat "$S/marketplaces.json" ;;
  add)
    name="$(awk -v s="$4" '$1 == s { print $2 }' "$S/mkt-map")"
    [ -n "$name" ] || {
      echo "unknown source $4" >&2
      exit 1
    }
    jq --arg n "$name" --arg r "$4" '. + [{name: $n, source: "github", repo: $r}]' \
      "$S/marketplaces.json" | put "$S/marketplaces.json"
    ;;
  esac
  ;;
"mcp add-json")
  # claude mcp add-json -s user <name> <json>
  jq --arg n "$5" --argjson c "$6" '.mcpServers[$n] = $c' "$CJ" | put "$CJ"
  ;;
"mcp remove")
  jq --arg n "$3" 'del(.mcpServers[$n])' "$CJ" | put "$CJ"
  ;;
*)
  echo "claude-stub: unhandled: $*" >&2
  exit 3
  ;;
esac
