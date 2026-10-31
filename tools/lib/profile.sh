#!/usr/bin/env bash
# profile.sh (lib) — the state readers and the CLI-backed stages of tools/profile.sh.
# Source it; never execute it. Each stage reads the current user scope, compares
# it with the profile, and records every difference through act() or ensure()
# (tools/lib/stage.sh), so the three modes differ only in whether those run.
# The fetch-backed stages (tools, skills) live in lib/profile-fetch.sh.

PROFILE_MD_START='<!-- harness42:profile:start -->'
PROFILE_MD_END='<!-- harness42:profile:end -->'

# note <state> <what> <how>: the one line a stage reports (same shape as seed.sh).
# shellcheck disable=SC2034  # read by run_stage in lib/stage.sh
note() {
  ST_STATE="$1"
  ST_NOTE="$2 ($3)"
}

# profile_init <profile> <packs>: the paths and the overlay every stage reads.
# Caveat: with CLAUDE_CONFIG_DIR set, ~/.claude.json is assumed to move into that
# directory with everything else; a CLI that kept it in $HOME would make the mcp
# stage read an empty server list and re-add every server on each apply.
profile_init() {
  PROFILE_FILE="$1"
  CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  CLAUDE_JSON="$HOME/.claude.json"
  [ -n "${CLAUDE_CONFIG_DIR:-}" ] && CLAUDE_JSON="$CLAUDE_CONFIG_DIR/.claude.json"
  HARNESS42_BIN="${HARNESS42_BIN:-$HOME/.local/bin}"
  HARNESS42_CACHE="${HARNESS42_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/harness42}"
  LOCAL_FILE="${HARNESS42_LOCAL:-${XDG_CONFIG_HOME:-$HOME/.config}/harness42/local.json}"
  # shellcheck disable=SC2034  # read by stage_lock in lib/profile-audit.sh
  LOCK_FILE="${PROFILE_FILE%.json}.lock.json"
  TODAY="$(date +%F)"
  # shellcheck disable=SC2034  # read by act() in lib/stage.sh
  ACT_LOG="$HARNESS42_CACHE/act.log"
  PACKS_JSON=null
  [ -n "$2" ] && PACKS_JSON="$(jq -cR 'split(",")' <<<"$2")"
  VARS_JSON='{}'
  if [ -f "$LOCAL_FILE" ]; then
    VARS_JSON="$(jq -c '.vars // {}' "$LOCAL_FILE" 2>/dev/null)" || {
      printf 'profile.sh: overlay %s is not valid JSON\n' "$LOCAL_FILE" >&2
      return 1
    }
  fi
  mkdir -p "$HARNESS42_CACHE"
  export PATH="$HARNESS42_BIN:$PATH"
}

# pq <filter>: run a jq filter over the profile, one compact JSON value per line.
# `inpack` keeps an entry when no --pack was given or its pack was named.
pq() {
  jq -c --argjson packs "$PACKS_JSON" \
    'def inpack: ($packs == null) or (.pack as $p | $packs | index($p) != null); '"$1" \
    "$PROFILE_FILE"
}

# field <json> <name>: one string field of an entry, empty when absent.
field() { jq -r --arg k "$2" '.[$k] // empty' <<<"$1"; }

# user_plugins: the user-scope plugins as the CLI reports them, `[]` on failure.
user_plugins() {
  claude plugin list --json 2>/dev/null | jq -c '[.[] | select(.scope == "user")]' 2>/dev/null ||
    echo '[]'
}

# bin_ready <name>: the binary is on PATH, or (before --apply ran the tools stage)
# the profile itself will install it, so a dry run does not under-report.
bin_ready() {
  have "$1" && return 0
  [ "$MODE" != apply ] && jq -e --arg n "$1" 'any(.tools[]?; .name == $n)' "$PROFILE_FILE" >/dev/null
}

stage_marketplaces() {
  local known e name src n=0 add=0
  known="$(claude plugin marketplace list --json 2>/dev/null)" || known='[]'
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    name="$(field "$e" name)"
    src="$(field "$e" source)"
    n=$((n + 1))
    jq -e --arg n "$name" 'any(.[]; .name == $n)' <<<"$known" >/dev/null 2>&1 && continue
    add=$((add + 1))
    act "add marketplace $name from $src" claude plugin marketplace add "$src"
  done < <(pq '.marketplaces[]?')
  note ok "$n marketplaces, $add missing" "claude plugin marketplace list, matched by name"
}

stage_plugins() {
  local installed e id bin state n=0 skipped=""
  installed="$(user_plugins)"
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    id="$(field "$e" id)"
    bin="$(field "$e" requires_bin)"
    if [ -n "$bin" ] && ! bin_ready "$bin"; then
      skipped+=" $id"
      continue
    fi
    n=$((n + 1))
    state="$(jq -r --arg id "$id" 'map(select(.id == $id)) |
      if length == 0 then "missing" elif .[0].enabled then "ok" else "disabled" end' <<<"$installed")"
    case "$state" in
    missing) act "install $id" claude plugin install "$id" --scope user ;;
    disabled) act "enable $id" claude plugin enable "$id" --scope user ;;
    esac
  done < <(pq '.plugins[]? | select(inpack)')
  # remove_plugins names each plugin the profile takes out (cloud connectors, a
  # replaced tool): uninstalled only when listed, never because it is unknown.
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    jq -e --arg id "$id" 'any(.[]; .id == $id)' <<<"$installed" >/dev/null &&
      act "uninstall $id (remove_plugins)" claude plugin uninstall "$id" --scope user
  done < <(jq -r '.remove_plugins[]?' "$PROFILE_FILE")
  note ok "$n plugins${skipped:+; skipped, binary missing:$skipped}" "claude plugin list --json"
}

# The fields an MCP server is compared on; the CLI may add keys of its own.
MCP_NORM='{type: (.type // "stdio"), command, args: (.args // []), env: (.env // {}),
  url, headers: (.headers // {})} | with_entries(select(.value != null))'

mcp_replace() { claude mcp remove "$1" -s user >/dev/null && claude mcp add-json -s user "$1" "$2"; }

stage_mcp() {
  local e name bin missing want cur n=0 skipped=""
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    name="$(field "$e" name)"
    bin="$(field "$e" requires_bin)"
    missing="$(jq -r --argjson v "$VARS_JSON" '[.requires[]? | select($v[.] == null)] | join(",")' <<<"$e")"
    if [ -n "$missing" ] || { [ -n "$bin" ] && ! bin_ready "$bin"; }; then
      skipped+=" $name(${missing:-$bin})"
      continue
    fi
    n=$((n + 1))
    want="$(jq -c --argjson v "$VARS_JSON" '.config | walk(if type == "string"
      then gsub("\\$\\{(?<k>[A-Za-z0-9_]+)\\}"; ($v[.k] // "")) else . end)' <<<"$e")"
    cur="$(jq -c --arg n "$name" '.mcpServers[$n] // null' "$CLAUDE_JSON" 2>/dev/null)" || cur=null
    if [ "$cur" = null ] || [ -z "$cur" ]; then
      act "add MCP server $name" claude mcp add-json -s user "$name" "$want"
    elif [ "$(jq -cS "$MCP_NORM" <<<"$cur")" != "$(jq -cS "$MCP_NORM" <<<"$want")" ]; then
      act "replace drifted MCP server $name" mcp_replace "$name" "$want"
    fi
  done < <(pq '.mcp[]? | select(inpack)')
  note ok "$n servers${skipped:+; skipped, overlay var or binary missing:$skipped}" "$CLAUDE_JSON mcpServers"
}

retire_move() {
  local d="$CLAUDE_HOME/backups/skills-$TODAY"
  [ -e "$d/$1" ] && d="$d-$$"
  mkdir -p "$d" && mv "$CLAUDE_HOME/skills/$1" "$d/$1"
}

# A loose skill is retired only when the plugin that ships the same skill is
# installed and enabled: the move is reversible (backups/), the duplicate is not
# free (its description is paid twice in every session).
stage_retire() {
  local installed e name by moved=0 kept=""
  installed="$(user_plugins)"
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    name="$(field "$e" name)"
    by="$(field "$e" replaced_by)"
    [ -d "$CLAUDE_HOME/skills/$name" ] || continue
    [ -f "$CLAUDE_HOME/skills/$name/.harness42" ] && continue
    if jq -e --arg id "$by" 'any(.[]; .id == $id and .enabled)' <<<"$installed" >/dev/null; then
      moved=$((moved + 1))
      act "retire loose skill $name (shipped by $by) to backups/skills-$TODAY" retire_move "$name"
    else
      kept+=" $name"
    fi
  done < <(pq '.retire_skills[]?')
  note ok "$moved to retire${kept:+; kept, replacement not installed:$kept}" "plugin list"
}

# merge_json <file> <json> <label>: <file> deep-merged with <json> (the profile wins
# on its own keys, every other key is kept), written through ensure(). Returns 1
# when <file> exists and is not JSON.
merge_json() {
  local merged
  if [ -f "$1" ]; then
    merged="$(jq --argjson w "$2" '. * $w' "$1" 2>/dev/null)" || return 1
  else
    merged="$(jq -n --argjson w "$2" '$w')"
  fi
  ensure "$1" "$3" < <(printf '%s\n' "$merged")
  return 0
}

json_keys() { jq -r '[paths(type != "object" and type != "array") | join(".")] | join(",")' <<<"$1"; }

stage_settings() {
  local f="$CLAUDE_HOME/settings.json" want
  want="$(jq -c '.settings // {}' "$PROFILE_FILE")"
  if [ "$want" = '{}' ]; then
    note ok "no settings to merge" "profile"
    return 0
  fi
  merge_json "$f" "$want" "merge $(json_keys "$want") into settings.json" || {
    note cannot "settings.json is not valid JSON" "$f"
    return 0
  }
  note ok "$(json_keys "$want")" "deep merge: the profile wins on its keys, every other key kept"
}

# json_files: the same merge for another tool's config (claude-mem's settings).
# A leading ~/ is the user's HOME; any other path is taken as written.
stage_json_files() {
  local e path want n=0
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    path="$(field "$e" path)"
    path="${path/#\~\//$HOME/}"
    want="$(jq -c '.merge' <<<"$e")"
    n=$((n + 1))
    merge_json "$path" "$want" "merge $(json_keys "$want") into $path" || {
      CHANGED+="$path is not valid JSON"$'\n'
      FAILED+="$path is not valid JSON"$'\n'
    }
  done < <(pq '.json_files[]? | select(inpack)')
  note ok "$n files" "deep merge, the profile wins on its keys"
}

# commands: a one-shot setup step another tool owns (rtk init). `check` exits 0
# when the step is already in place; only then is `run` skipped. Both are
# trusted strings from this public, reviewed profile, run with bash -c.
stage_commands() {
  local e name n=0
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    name="$(field "$e" name)"
    n=$((n + 1))
    bash -c "$(field "$e" check)" </dev/null >/dev/null 2>&1 && continue
    act "run setup step $name" bash -c "$(field "$e" run)" </dev/null
    if [ "$MODE" = apply ] && ! bash -c "$(field "$e" check)" </dev/null >/dev/null 2>&1; then
      FAILED+="run setup step $name"$'\n'
    fi
  done < <(pq '.commands[]? | select(inpack)')
  note ok "$n setup steps" "each step's own check command"
}

stage_instructions() {
  local f="$CLAUDE_HOME/CLAUDE.md" blk
  blk="$(jq -r '.instructions // empty' "$PROFILE_FILE")"
  [ -n "$blk" ] || {
    note ok "no instructions block" "profile"
    return 0
  }
  case "$blk" in /*) ;; *) blk="$KIT/$blk" ;; esac
  [ -f "$blk" ] || {
    note cannot "instructions file missing" "$blk"
    return 0
  }
  local src=/dev/null
  [ -f "$f" ] && src="$f"
  ensure "$f" "write the profile block into ~/.claude/CLAUDE.md" \
    < <(render_block "$src" "$blk" "$PROFILE_MD_START" "$PROFILE_MD_END")
  note ok "block between $PROFILE_MD_START markers" "text outside the markers kept"
}
