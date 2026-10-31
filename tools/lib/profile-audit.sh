#!/usr/bin/env bash
# profile-audit.sh — the stages of tools/profile.sh that only read: the token
# budget, the lock and the local-only rule. Source it; never execute it.

# plugin_tokens <id>: the always-on tokens `claude plugin details` reports, 0 when
# it reports none.
# Caveat: parsed from the human output ("Always-on:   ~848 tok", "~1.2k tok"); a
# CLI that rewords that line makes every plugin read as 0 and the budget pass
# vacuously, so the note prints how many plugins actually reported a number.
plugin_tokens() {
  claude plugin details "$1" 2>/dev/null |
    awk '/Always-on:/ { for (i = 1; i <= NF; i++) if ($i ~ /^~?[0-9.]+k?$/) {
      v = $i; sub(/^~/, "", v); m = (v ~ /k$/) ? 1000 : 1; sub(/k$/, "", v); print int(v * m); exit } }'
}

stage_budget() {
  local installed id tok total=0 n=0 measured=0 ceil
  installed="$(user_plugins)"
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    jq -e --arg id "$id" 'any(.[]; .id == $id and .enabled)' <<<"$installed" >/dev/null || continue
    n=$((n + 1))
    tok="$(plugin_tokens "$id")"
    [ -n "$tok" ] || continue
    measured=$((measured + 1))
    total=$((total + tok))
  done < <(pq '.plugins[]? | select(inpack) | .id' | jq -r .)
  ceil="$(jq -r '.budget.always_on_tokens // empty' "$PROFILE_FILE")"
  if [ -n "$ceil" ] && [ "$total" -gt "$ceil" ]; then
    note change "~$total always-on tokens, over the $ceil ceiling" "$measured/$n plugins measured"
  else
    note ok "~$total always-on tokens${ceil:+ (ceiling $ceil)}" "$measured/$n plugins measured by claude plugin details"
  fi
}

# The lock: what is installed for each profile entry, written on --apply and
# compared (never enforced) otherwise, because the official marketplace updates
# itself and the pins that matter are already in the profile.
# Caveat: gitCommitSha is read from ~/.claude/plugins/installed_plugins.json, an
# internal file the CLI does not document; when it moves the lock records null.
lock_render() {
  local installed meta="$CLAUDE_HOME/plugins/installed_plugins.json" stamps='{}' d
  installed="$(user_plugins)"
  [ -f "$meta" ] || meta=/dev/null
  for d in "$CLAUDE_HOME"/skills/*/.harness42; do
    [ -f "$d" ] || continue
    stamps="$(jq -c --arg k "$(basename "$(dirname "$d")")" --arg v "$(cat "$d")" '. + {($k): $v}' <<<"$stamps")"
  done
  jq -n -S --argjson inst "$installed" --argjson stamps "$stamps" --slurpfile meta <(cat "$meta" 2>/dev/null || echo '{}') --slurpfile prof "$PROFILE_FILE" '
    ($meta[0].plugins // {}) as $m |
    { plugins: ([$prof[0].plugins[]?.id as $id | $inst[] | select(.id == $id) |
        {key: $id, value: {version, sha: ([$m[$id][]? | select(.scope == "user") | .gitCommitSha][0])}}]
        | from_entries),
      tools: ([$prof[0].tools[]? | {key: .name, value: .version}] | from_entries),
      skills: ([$prof[0].skills[]?.name as $n | select($stamps[$n] != null) | {key: $n, value: $stamps[$n]}]
        | from_entries) }'
}

stage_lock() {
  if [ "$MODE" = apply ]; then
    ensure "$LOCK_FILE" "record $(basename "$LOCK_FILE")" < <(lock_render)
    note ok "$(basename "$LOCK_FILE") records what is installed" "commit it with the profile"
  elif cmp -s <(lock_render) "$LOCK_FILE" 2>/dev/null; then
    note ok "installed set matches $(basename "$LOCK_FILE")" "lock_render"
  else
    note ok "installed set differs from $(basename "$LOCK_FILE") (info; --apply re-records it)" "lock_render"
  fi
}

# The local-only rule (doc/PROFILE.md): no enabled user plugin may bundle a remote
# MCP server (a `url`, or type http/sse/ws). Read from each plugin's own files, so
# a plugin that grows a connector in an update is caught on the next --check.
# Caveat: reads `.mcp.json` and the `mcpServers` object of `.claude-plugin/plugin.json`
# only; servers declared in a separate file that plugin.json points to by path, or
# packed in an .mcpb bundle, are not inspected and pass unseen.
stage_localonly() {
  local installed id path bad="" n=0
  installed="$(claude plugin list --json 2>/dev/null | jq -c '[.[] | select(.scope == "user" and .enabled)]')" ||
    installed='[]'
  while IFS=$'\t' read -r id path; do
    [ -n "$id" ] && [ -d "$path" ] || continue
    n=$((n + 1))
    local files=() f
    for f in "$path/.mcp.json" "$path/.claude-plugin/plugin.json"; do [ -f "$f" ] && files+=("$f"); done
    [ "${#files[@]}" -gt 0 ] || continue
    if jq -se '[.[] | (.mcpServers // {}) | select(type == "object") | .[] |
      select(.url != null or ((.type // "") | test("^(http|sse|ws)")))] | length > 0' \
      "${files[@]}" >/dev/null 2>&1; then
      bad+=" $id"
    fi
  done < <(jq -r '.[] | [.id, (.installPath // "")] | @tsv' <<<"$installed")
  if [ -n "$bad" ]; then
    note change "remote MCP servers bundled by:$bad (add them to remove_plugins)" "$n plugins inspected"
  else
    note ok "no enabled plugin bundles a remote MCP server" "$n plugins inspected"
  fi
}
