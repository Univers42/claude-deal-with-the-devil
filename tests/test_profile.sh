#!/usr/bin/env bash
# test_profile.sh — `devil profile` must bring a user scope to the profile, be
# idempotent, and refuse quietly half-applied states.
#
# Every run happens in a throwaway HOME with a stub `claude` on PATH
# (fixtures/profile/claude-stub.sh), so nothing here touches the real ~/.claude
# or the network: tools and skills are fetched from file:// and local git repos.
# The load-bearing cases are the negative ones: a drifted MCP server, a wrong
# checksum, a missing overlay var, a skill whose replacement is not installed.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_SH="$ROOT/tools/profile.sh"
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

for t in jq git curl tar sha256sum; do
  command -v "$t" >/dev/null 2>&1 || {
    echo "skip - $t is not installed; the profile engine needs it"
    exit 0
  }
done

TMP="$(mktemp -d)"
trap '[ -n "${KEEP_TMP:-}" ] || rm -rf "$TMP"' EXIT
export HOME="$TMP/home" STUB_STATE="$TMP/state" HARNESS42_LOCAL="$TMP/local.json"
export HARNESS42_BIN="$HOME/.local/bin" HARNESS42_CACHE="$TMP/cache"
mkdir -p "$HOME/.claude/skills" "$STUB_STATE" "$TMP/bin" "$HARNESS42_BIN"
cp "$ROOT/tests/fixtures/profile/claude-stub.sh" "$TMP/bin/claude"
chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$HARNESS42_BIN:$PATH"

# A tool shipped as a tarball, served from file://, pinned by its real sha256.
mkdir -p "$TMP/pkg/hello-1.0"
printf '#!/bin/sh\necho "hello 1.0"\n' >"$TMP/pkg/hello-1.0/hello"
chmod +x "$TMP/pkg/hello-1.0/hello"
tar -C "$TMP/pkg" -czf "$TMP/hello.tar.gz" hello-1.0
SHA="$(sha256sum "$TMP/hello.tar.gz" | cut -d' ' -f1)"

# A skill repo, pinned by commit.
git init -q "$TMP/skillrepo"
mkdir -p "$TMP/skillrepo/skills/tidy"
printf -- '---\nname: tidy\ndescription: test skill\n---\nbody\n' >"$TMP/skillrepo/skills/tidy/SKILL.md"
git -C "$TMP/skillrepo" add -A
git -C "$TMP/skillrepo" -c user.name=t -c user.email=t@t commit -qm skill
SKILL_SHA="$(git -C "$TMP/skillrepo" rev-parse HEAD)"

printf 'acme/market acme\n' >"$STUB_STATE/mkt-map"
cat >"$TMP/profile.json" <<JSON
{
  "version": 1,
  "budget": { "always_on_tokens": null },
  "settings": { "env": { "TEAMS_FLAG": "1" }, "syncClaudeAiPlugins": false },
  "tools": [
    { "name": "hello", "pack": "core", "kind": "tar", "version": "1.0",
      "url": "file://$TMP/hello.tar.gz", "sha256": "$SHA",
      "member": "hello-1.0/hello", "check": "hello --version" }
  ],
  "marketplaces": [ { "name": "acme", "source": "acme/market" } ],
  "plugins": [
    { "id": "alpha@acme", "pack": "core" },
    { "id": "lsp@acme", "pack": "core", "requires_bin": "no-such-binary-xyz" },
    { "id": "pretty@acme", "pack": "frontend" }
  ],
  "remove_plugins": ["cloudy@acme"],
  "mcp": [
    { "name": "browser", "pack": "frontend", "requires": ["BROWSER_PATH"],
      "config": { "type": "stdio", "command": "npx", "args": ["-y", "b@1.0.0", "--exe", "\${BROWSER_PATH}"] } },
    { "name": "db", "pack": "core", "requires": ["DB_DSN"],
      "config": { "type": "stdio", "command": "npx", "args": ["db@1.0.0", "\${DB_DSN}"] } }
  ],
  "skills": [
    { "name": "tidy", "pack": "core", "repo": "$TMP/skillrepo", "sha": "$SKILL_SHA", "path": "skills/tidy" }
  ],
  "retire_skills": [
    { "name": "dupe", "replaced_by": "pretty@acme" },
    { "name": "orphan", "replaced_by": "never@acme" }
  ],
  "json_files": [
    { "pack": "core", "path": "~/.memtool/settings.json", "merge": { "GATE": "false" } }
  ],
  "commands": [
    { "pack": "core", "name": "marker", "check": "test -f ~/.marker", "run": "touch ~/.marker" },
    { "pack": "core", "name": "kitpath", "check": "test -f ~/.kitpath", "run": "test -f \"\$HARNESS42_KIT/tools/profile.sh\" && touch ~/.kitpath" }
  ],
  "instructions": "$TMP/block.md"
}
JSON
printf '# Rules\n\nCite or say unverified.\n' >"$TMP/block.md"
printf '{"vars": {"BROWSER_PATH": "/usr/bin/chromium"}, "settings": {"autoMode": {"environment": ["private host"]}, "env": {"TEAMS_FLAG": "2"}}}\n' >"$HARNESS42_LOCAL"
printf '# mine\n\nKeep this line.\n' >"$HOME/.claude/CLAUDE.md"
mkdir -p "$HOME/.memtool" && printf '{"KEEP": 1}\n' >"$HOME/.memtool/settings.json"
printf '{"env": {"KEEP": "yes"}, "model": "opus"}\n' >"$HOME/.claude/settings.json"
printf '[{"id": "cloudy@acme", "scope": "user", "enabled": true, "version": "1"}]\n' >"$STUB_STATE/plugins.json"
mkdir -p "$HOME/.claude/skills/dupe" "$HOME/.claude/skills/orphan"

run() { bash "$PROFILE_SH" --profile "$TMP/profile.json" "$@" >"$TMP/out" 2>&1; }
mutations() { grep -cE '^(plugin (install|enable)|plugin marketplace add|mcp (add-json|remove))' "$STUB_STATE/calls.log" 2>/dev/null || true; }

# --- malformed profile: exit 2, nothing done
printf '{ not json' >"$TMP/bad.json"
bash "$PROFILE_SH" --profile "$TMP/bad.json" --check >"$TMP/out" 2>&1
check "malformed profile exits 2" '[ $? -eq 2 ]'

# --- dry run and check on a fresh scope: report, write nothing
run
check "dry run exits 0" '[ $? -eq 0 ]'
run --check
check "--check on a fresh scope exits 1" '[ $? -eq 1 ]'
check "--check names the plugins stage" 'grep -q "| plugins | change" "$TMP/out"'
check "dry run and --check mutate nothing" '[ "$(mutations)" -eq 0 ]'
check "dry run and --check install no tool" '[ ! -e "$HARNESS42_BIN/hello" ]'

# --- apply
run --apply
rc=$?
check "apply exits 0" "[ $rc -eq 0 ]"
check "tool installed from its pinned tarball" '"$HARNESS42_BIN/hello" | grep -q "hello 1.0"'
check "marketplace added" 'jq -e "any(.[]; .name == \"acme\")" "$STUB_STATE/marketplaces.json" >/dev/null'
check "plugin installed at user scope" 'jq -e "any(.[]; .id == \"alpha@acme\" and .scope == \"user\")" "$STUB_STATE/plugins.json" >/dev/null'
check "plugin with a missing binary is skipped" '! jq -e "any(.[]; .id == \"lsp@acme\")" "$STUB_STATE/plugins.json" >/dev/null'
check "MCP placeholder filled from the overlay" 'jq -e ".mcpServers.browser.args[3] == \"/usr/bin/chromium\"" "$HOME/.claude.json" >/dev/null'
check "MCP server with a missing var is not added" 'jq -e ".mcpServers.db == null" "$HOME/.claude.json" >/dev/null'
check "skill vendored at its pinned commit" 'grep -q "name: tidy" "$HOME/.claude/skills/tidy/SKILL.md"'
check "duplicate skill retired to backups" '[ ! -d "$HOME/.claude/skills/dupe" ] && ls -d "$HOME"/.claude/backups/skills-*/dupe >/dev/null 2>&1'
check "skill whose replacement is absent is kept" '[ -d "$HOME/.claude/skills/orphan" ]'
check "CLAUDE.md block written" 'grep -q "Cite or say unverified." "$HOME/.claude/CLAUDE.md"'
check "CLAUDE.md own text kept" 'grep -q "Keep this line." "$HOME/.claude/CLAUDE.md"'
check "overlay settings merge last and win" 'jq -e ".autoMode.environment == [\"private host\"] and .env.TEAMS_FLAG == \"2\"" "$HOME/.claude/settings.json" >/dev/null'
check "settings merged deep, own keys kept" 'jq -e ".env.TEAMS_FLAG == \"2\" and .env.KEEP == \"yes\" and .model == \"opus\" and .syncClaudeAiPlugins == false" "$HOME/.claude/settings.json" >/dev/null'
check "a plugin listed in remove_plugins is uninstalled" '! jq -e "any(.[]; .id == \"cloudy@acme\")" "$STUB_STATE/plugins.json" >/dev/null'
check "json_files merged into a file under HOME" 'jq -e ".GATE == \"false\" and .KEEP == 1" "$HOME/.memtool/settings.json" >/dev/null'
check "a command runs when its check fails" '[ -f "$HOME/.marker" ]'
check "a command sees the kit as HARNESS42_KIT" '[ -f "$HOME/.kitpath" ]'
check "lock records the plugin version" 'jq -e ".plugins[\"alpha@acme\"].version == \"1.0.0\"" "$TMP/profile.lock.json" >/dev/null'

# --- idempotence
run --check
check "--check after apply exits 0" '[ $? -eq 0 ]'
before="$(mutations)"
run --apply
check "second apply exits 0" '[ $? -eq 0 ]'
check "second apply mutates nothing" "[ \"\$(mutations)\" -eq $before ]"
check "second apply reports 0 to change" 'grep -q "\*\*0 to change" "$TMP/out"'
check "CLAUDE.md block not duplicated" '[ "$(grep -c "harness42:profile:start" "$HOME/.claude/CLAUDE.md")" -eq 1 ]'

# --- drift: an MCP server edited by hand is caught and restored
jq '.mcpServers.browser.args[1] = "b@0.9.0"' "$HOME/.claude.json" >"$TMP/cj" && mv "$TMP/cj" "$HOME/.claude.json"
run --check
check "drifted MCP server: --check exits 1" '[ $? -eq 1 ]'
check "drifted MCP server: names the mcp stage" 'grep -q "| mcp | change" "$TMP/out"'
run --apply
check "drifted MCP server restored" 'jq -e ".mcpServers.browser.args[1] == \"b@1.0.0\"" "$HOME/.claude.json" >/dev/null'

# --- a disabled plugin is re-enabled
jq 'map(if .id == "alpha@acme" then .enabled = false else . end)' "$STUB_STATE/plugins.json" >"$TMP/p" && mv "$TMP/p" "$STUB_STATE/plugins.json"
run --apply
check "disabled plugin re-enabled" 'jq -e "any(.[]; .id == \"alpha@acme\" and .enabled)" "$STUB_STATE/plugins.json" >/dev/null'

# --- a failing install is "cannot" (exit 2), never a silent pass
jq 'map(select(.id != "pretty@acme"))' "$STUB_STATE/plugins.json" >"$TMP/p" && mv "$TMP/p" "$STUB_STATE/plugins.json"
echo "pretty@acme" >"$STUB_STATE/fail-install"
run --apply
check "failed install exits 2" '[ $? -eq 2 ]'
rm -f "$STUB_STATE/fail-install"

# --- a wrong checksum refuses the tool
rm -f "$HARNESS42_BIN/hello"
sed -i "s/$SHA/$(printf '0%.0s' {1..64})/" "$TMP/profile.json"
run --apply --only tools
check "wrong checksum exits 2" '[ $? -eq 2 ]'
check "wrong checksum installs nothing" '[ ! -e "$HARNESS42_BIN/hello" ]'

# --- local-only: a plugin that bundles a remote MCP server fails --check
mkdir -p "$TMP/plug/.claude-plugin"
printf '{"mcpServers": {"saas": {"type": "http", "url": "https://mcp.example.com/mcp"}}}\n' >"$TMP/plug/.mcp.json"
jq --arg p "$TMP/plug" 'map(if .id == "alpha@acme" then .installPath = $p else . end)' "$STUB_STATE/plugins.json" >"$TMP/p" && mv "$TMP/p" "$STUB_STATE/plugins.json"
run --check --only localonly
check "a plugin with a remote MCP server fails --check" '[ $? -eq 1 ] && grep -q "alpha@acme" "$TMP/out"'
printf '{"mcpServers": {"local": {"command": "npx", "args": ["x@1.0.0"]}}}\n' >"$TMP/plug/.mcp.json"
run --check --only localonly
check "a plugin with only stdio servers passes" '[ $? -eq 0 ]'

# --- --pack limits the run to one pack
run --check --pack frontend --only plugins
check "--pack frontend sees only frontend plugins" '! grep -q "alpha@acme" "$TMP/out"'

echo
echo "test_profile: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
