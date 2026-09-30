#!/usr/bin/env bash
# seed-opencode.sh — the `opencode` stage of tools/setup.sh, in its own file.
#
# Sourced by setup.sh right after lib/seed.sh, which defines the RULES_GLOB this
# file needs and the note() every stage reports through; the write helpers
# (ensure, append_line) and HOST / MODE / KIT live in setup.sh. Never executed.
# It exists because seed.sh was at the 300-line limit and this stage is the one
# that grew a third job: merge the config, link the files, sweep what it left.
#
# What it wires is the contract in dist/opencode/README.md, section "What the
# setup stage writes", which `devil export opencode` regenerates from
# tools/lib/opencode-README.md. Two shapes changed since that table was written
# and both are visible in a host: the config key is `skills` as an array, not
# `skills.paths` (V2 reads the array), and the links are one per generated file,
# not one per directory, because a host may own `.opencode/agents` outright.
#
# What it never writes: the host's AGENTS.md (V2 reads it, but the bridge
# already injects the same rules as system text, so a file here would be a
# second copy the host pays for twice) and `.claude/skills` (Claude Code would
# load the kit's skills once through the plugin and once through that link).

# --- the config -------------------------------------------------------------

# One jq pass over the host's own file. `skills` becomes the array V2 reads,
# keeping whatever was already there; `instructions` loses exactly the glob an
# older version of this stage seeded and keeps every other entry, because V2
# resolves no file, glob or URL in it (doc/HARNESSES.md, [L16]: the bridge
# injects the rules instead). Every other key is not read, so it cannot change.
# Caveat: a V1 `skills` object is read through its `paths` key, so a key of that
# object other than `paths` would be dropped, and `unique` is deliberately not
# used: sorting a host's list reorders what the host wrote. `instructions` is
# only rewritten when it is already an array (or exactly the seeded glob as a
# string), because a host that wrote one string there keeps its string.
OC_CONFIG_MERGE='
  def arr: if type == "array" then . elif type == "string" then [.] else [] end;
  def uniq: reduce .[] as $x ([]; if index($x) then . else . + [$x] end);
  def base: if (.skills|type) == "object" then (.skills.paths | arr) else (.skills | arr) end;
  .skills = ((base + [$kit]) | uniq)
  | (if (.instructions|type) == "array" then
       ([.instructions[] | select(. != $rules)]) as $kept
       | if ($kept|length) == 0 then del(.instructions) else .instructions = $kept end
     elif (.instructions|type) == "string" and .instructions == $rules then del(.instructions)
     else . end)'

# The merged host config on stdout, empty when jq could not read the file.
_oc_config() {
  jq --indent 2 --arg kit "$KIT/skills" --arg rules "$RULES_GLOB" "$OC_CONFIG_MERGE" "$1" 2>/dev/null
}

# --- the links --------------------------------------------------------------

# The names `devil export opencode` generated for one kind, read from the kit so
# a command added upstream is linked by the next apply with no list here to keep
# in step. Caveat: a generated file that is not a plain <name>.md is not linked,
# and the glob is not a search: an agent called `a.md.md` would read as two.
_oc_generated() {
  local f
  for f in "$KIT/dist/opencode/$1"/*.md; do
    [ -f "$f" ] && printf '%s\n' "${f##*/}"
  done
  return 0
}

# _oc_link <path> <target> <label>: bring one symlink to its target.
#   0  it was missing or pointed elsewhere, and now (or under --apply would)
#      points at the target
#   1  already right
#   2  a regular file the host owns, left exactly as it is
# The third case is the reason this stage links file by file: a host agent of
# the same name has to survive the kit being installed into the same host.
# shellcheck disable=SC2034  # CHANGED is read by run_stage in setup.sh
_oc_link() {
  local link="$1" target="$2" label="$3"
  if [ -L "$link" ] && [ -e "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
    return 1
  fi
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    return 2
  fi
  CHANGED+="$label"$'\n'
  if [ "$MODE" = apply ]; then
    mkdir -p "$(dirname "$link")" && ln -sfn "$target" "$link"
  fi
  return 0
}

# Record a removal, and under --apply make it. Only ever called on a symlink
# pointing into the kit's own dist, so a host's own link is not a candidate.
# shellcheck disable=SC2034
_oc_drop() {
  CHANGED+="$2"$'\n'
  if [ "$MODE" = apply ]; then
    rm -f "$1"
  fi
  return 0
}

# Count one _oc_link result, and remember the name when the host kept the file.
_oc_tally() {
  case "$1" in
  0) OC_MISSING=$((OC_MISSING + 1)) ;;
  2) OC_KEPT="$OC_KEPT $2" ;;
  esac
  return 0
}

# One kind (agents, commands): link every generated file into the host.
# A whole-directory link is the shape the install README used to show. It
# already delivers every generated file, so nothing is linked inside it, because
# creating a file there writes into the kit's own tree; when its target is gone
# the link is dropped first and the files are linked one by one, because there
# is then no directory to link into. Caveat: a whole-directory link into a kit
# that is still there is reported as done and nothing under it is verified, so a
# file deleted from that directory by hand stays deleted until the link is
# replaced by the per-file layout.
_oc_link_kind() {
  local kind="$1" dir="$HOST/.opencode/$1" name
  if [ -L "$dir" ]; then
    if [ -e "$dir" ]; then
      OC_WANT=$((OC_WANT + 1))
      # One token, like every other entry here, so the note can cap the list by
      # counting words instead of guessing where a name ends.
      OC_KEPT="$OC_KEPT $kind/(one-link-to-the-directory)"
      return 0
    fi
    _oc_drop "$dir" "remove .opencode/$kind (a link to a directory that is gone)"
    OC_STALE=$((OC_STALE + 1))
  fi
  while IFS= read -r name; do
    OC_WANT=$((OC_WANT + 1))
    _oc_link "$dir/$name" "$KIT/dist/opencode/$kind/$name" "link .opencode/$kind/$name"
    _oc_tally "$?" "$kind/$name"
  done < <(_oc_generated "$kind")
  return 0
}

# The hook bridge: the one file the kit needs, and the only plugin route that
# works in 2.0.18 (a `plugins: [path]` config key parses and never loads).
_oc_plugin() {
  OC_WANT=$((OC_WANT + 1))
  _oc_link "$HOST/.opencode/plugins/devil.js" "$KIT/dist/opencode/plugins/devil.js" \
    "link .opencode/plugins/devil.js"
  _oc_tally "$?" "plugins/devil.js"
}

# A link into dist/opencode/ whose target is gone: a retired command, or a
# directory link whose kit moved. OpenCode would offer a command it cannot
# read, so --check reports it and --apply removes it. Nothing else under
# .opencode/ is a candidate; a host's own links are the host's business.
# Caveat: the match is on the readlink text, so a link made through a
# symlinked kit path, or a relative one, is neither reported nor removed.
_oc_sweep() {
  local link
  while IFS= read -r link; do
    case "$(readlink "$link")" in
    "$KIT"/dist/opencode/*) ;;
    *) continue ;;
    esac
    [ -e "$link" ] && continue
    _oc_drop "$link" "remove ${link#"$HOST"/} (a link to a file the kit no longer generates)"
    OC_STALE=$((OC_STALE + 1))
  done < <(find "$HOST/.opencode" -type l 2>/dev/null)
  return 0
}

# --- the stage --------------------------------------------------------------

# .claude/devil.env: what a headless worker sources to get `devil` on its PATH.
# Caveat: the PATH line is a fixed system default, not the PATH this ran under,
# so a host whose toolchain lives in a venv has to append it, and the line is
# rewritten on every apply, so an edit there is lost.
_oc_env() {
  echo "# written by devil setup; the next apply rewrites this file"
  echo "DEVIL_ROOT=$KIT"
  echo "PATH=$KIT/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
}

# The one line the stage reports. A missing link, a link pointing elsewhere or a
# retired one is drift, which is what --check fails on; a file the host owns is
# not drift, because the kit has nothing to say about it.
_oc_note() {
  local kept="" n
  n="$(wc -w <<<"$OC_KEPT")"
  if [ "${n:-0}" -gt 4 ]; then
    kept="left as they were: $(cut -d' ' -f1-4 <<<"$OC_KEPT"), and $((n - 4)) more"
  elif [ "${n:-0}" -gt 0 ]; then
    kept="left as they were:${OC_KEPT}"
  fi
  [ "$OC_STALE" -gt 0 ] && kept="retired links to drop: $OC_STALE${kept:+; $kept}"
  if [ "$OC_MISSING" -gt 0 ]; then
    note change "$OC_WANT files under .opencode/" "$OC_MISSING missing or pointing elsewhere${kept:+; $kept}"
  else
    note ok "$OC_WANT files under .opencode/" "linked into dist/opencode${kept:+; $kept}"
  fi
}

# --- 4 of seven stages in tools/setup.sh: only a host that already runs
# OpenCode. The stage adds to a config that exists; it does not create one for a
# host that does not use the harness.
stage_opencode() {
  local file="$HOST/opencode.json" merged
  if [ ! -f "$file" ]; then
    if [ -f "$HOST/opencode.jsonc" ]; then
      note cannot "opencode.jsonc, not opencode.json" \
        "jq reads JSON, not JSONC: rename it, or wire .opencode/ by hand (dist/opencode/README.md)"
      return 0
    fi
    note skip "no opencode.json in this host" "nothing to wire"
    return 0
  fi
  if ! have jq; then
    note cannot "jq is not installed" "cannot wire opencode.json without losing its keys"
    return 0
  fi
  merged="$(_oc_config "$file")"
  if [ -z "$merged" ]; then
    note cannot "jq could not read opencode.json" "malformed host file?"
    return 0
  fi
  OC_WANT=0 OC_MISSING=0 OC_STALE=0 OC_KEPT=""
  ensure "$file" "write opencode.json (skills points at the kit, the seeded rules glob is dropped)" \
    < <(printf '%s\n' "$merged")
  _oc_link_kind agents
  _oc_link_kind commands
  _oc_plugin
  _oc_sweep
  ensure "$HOST/.claude/devil.env" "write .claude/devil.env (DEVIL_ROOT, PATH)" < <(_oc_env)
  _oc_note
  return 0
}
