#!/usr/bin/env bash
# seed.sh — one function per stage of tools/setup.sh, plus the helpers the stages
# share. Source it; never execute it (tools/lib/common.sh is the same contract,
# and the rule the kit enforces on itself: rules/library-first.md). A stage is
# `stage_<name>`, takes no argument, and reports one line through note(): a state
# and how it was reached. It records every file it touches through setup.sh's
# ensure()/append_line(), so the three modes differ only in whether those write.
# STAGES, in dependency order: the OpenCode stage (lib/seed-opencode.sh, sourced
# next) drops the rules glob this file's RULES_GLOB used to seed, the CLAUDE.md
# block names the tools the settings stage allowed.

CLAUDE_MD_START='<!-- devil:start -->'
CLAUDE_MD_END='<!-- devil:end -->'
# The layout the rules stage seeds, relative to the host root. OpenCode read the
# same glob through the `instructions` key until 2.x proved that key resolves
# nothing, so the value survives only as the exact string the opencode stage
# removes from a host that ran an older version of it.
# shellcheck disable=SC2034  # read by lib/seed-opencode.sh, sourced right after
RULES_GLOB='./.claude/rules/devil/*.md'

# The version of record (A12): .claude-plugin/plugin.json, read as release.sh
# reads it. Duplicated rather than sourced because release.sh is a script, not a
# library, and running it to read one field would run the gate.
# Caveat: the sed read matches the first `"version": "..."` on a line anywhere in
# the file, so a version inside a description string wins over the real one, and a
# value split across lines is not matched at all (it then reads as empty, and
# setup.sh exits 2 rather than seeding a stamp it cannot verify).
_plugin_version() {
  local f="$KIT/.claude-plugin/plugin.json"
  if have jq; then
    jq -r '.version // empty' "$f" 2>/dev/null
  else
    sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$f" | head -1
  fi
}

# sha256 of a file, or of stdin for `-`. Without one it says `unavailable`, so a
# stamp carrying it is visibly not a sha256.
_sha256() {
  if have sha256sum; then
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif have shasum; then
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else
    echo unavailable
  fi
}

# The fingerprint of a directory of seeded rules: one `name sha` line per *.md,
# hashed again. Naming the file makes a rename a change, not a swap that hashes
# the same. Caveat: it covers content and file names and nothing else, and it is
# deliberately not the kit's git tree hash, so two kits seeding byte-identical
# rules hash the same; that is why the version is stamped beside it, not in it.
_rules_sha() {
  local f
  for f in "$1"/*.md; do
    [ -f "$f" ] || continue
    printf '%s %s\n' "$(basename "$f")" "$(_sha256 "$f")"
  done | _sha256 -
}

# One `key=value` line of a stamp file, empty when the key or the file is absent.
_stamp_field() {
  [ -f "$1" ] || return 0
  sed -nE "s/^$2=(.*)\$/\1/p" "$1" | head -1
}

# note <state> <what> <how>: the one line a stage reports. Three arguments because
# every stage has the same shape: a decision, and how it was reached.
# shellcheck disable=SC2034  # both are read by run_stage in setup.sh
note() {
  ST_STATE="$1"
  ST_NOTE="$2 ($3)"
}

# --- 1. rules: copies the always-on rules into the host, because a plugin has no
# rules component. The 7 path-scoped ones are not here: they ship as `paths:`
# skills inside the plugin, and Claude Code loads a skill by exactly the same lazy
# mechanism a path-scoped rule used.
# Caveat: the subdirectory layout was measured, not assumed. In a scratch repo,
# `.claude/rules/devil/probe.md` holding "The codeword is PERIWINKLE-42." and
# `timeout 180 claude -p "What is the codeword? Reply with the codeword only."`
# answered PERIWINKLE-42; with that file moved away the same prompt answered that
# it had no codeword, so the rule really was loaded out of the subdirectory. The
# flat `.claude/rules/devil-probe.md` layout answered the same, so a Claude Code
# that stopped recursing would need three things changed together, not one: the
# `dest` below, `RULES_GLOB`, and the path in `templates/claude-md-block.md`. One
# CLI version (2.1.285); it says nothing about older builds.
stage_rules() {
  local dest="$HOST/.claude/rules/devil" f n=0 want stamped old
  if ! have sha256sum && ! have shasum; then
    note cannot "no sha256sum and no shasum" "cannot stamp the seeded rules"
    return 0
  fi
  want="$(_rules_sha "$KIT/rules")"
  for f in "$KIT"/rules/*.md; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    # shellcheck disable=SC2094  # ensure() writes a temp file, never $f
    ensure "$dest/$(basename "$f")" "write .claude/rules/devil/$(basename "$f")" <"$f"
  done
  # ensure() is redirected, never piped: see its definition in setup.sh.
  ensure "$dest/.version" "write .claude/rules/devil/.version" \
    < <(printf 'version=%s\nsha256=%s\nrules=%s\n' "$KIT_VERSION" "$want" "$n")
  stamped="$(_stamp_field "$dest/.version" sha256)"
  old="$(_stamp_field "$dest/.version" version)"
  # Three comparisons, each catching a different lie: what the host holds, what
  # the stamp claims, and what the plugin is. Reading the host back rather than
  # trusting the stamp is what catches a file someone added or deleted by hand.
  if [ "$(_rules_sha "$dest")" != "$want" ]; then
    note change "$n rules under .claude/rules/devil/" "the seeded rules are not the kit's: edited, added or removed"
  elif [ "$stamped" != "$want" ]; then
    note change "$n rules under .claude/rules/devil/" ".version is missing or its fingerprint is not the kit's"
  elif [ "$old" != "$KIT_VERSION" ]; then
    note change "$n rules under .claude/rules/devil/" "rules are current but the plugin moved $old -> $KIT_VERSION"
  else
    note ok "$n rules under .claude/rules/devil/" "stamp $KIT_VERSION"
  fi
  return 0
}

# --- 2. settings: merges the template into the host. Every key the host already
# has wins, and the permission lists are unioned rather than replaced, so a host
# that already allows something the template does not still has it.
# Caveat: `unique` also sorts the three lists, so a host that hand-ordered `allow`
# to read top-down gets it back alphabetised (order means nothing to Claude Code).
# Every other key is merged with jq's `*`, a deep merge: where both sides set the
# same nested key the host wins and the template's siblings stay.
# A host with no settings.json is merged against an empty object rather than
# copied, because `unique` sorts: a plain copy would keep the template's own
# order, so the next apply re-sorted the file it had just written and two applies
# were not a no-op. Same merge, one code path, nothing host-specific to get
# wrong.
MERGE_PERMS='
def u($a; $b): [(($a // [])[]), (($b // [])[])] | unique;
.[0] as $t | .[1] as $h | $t * $h
| (if .permissions? then .permissions.allow = u($t.permissions.allow; $h.permissions.allow) else . end)
| (if .permissions? then .permissions.ask = u($t.permissions.ask; $h.permissions.ask) else . end)
| (if .permissions? then .permissions.deny = u($t.permissions.deny; $h.permissions.deny) else . end)'

stage_settings() {
  local file="$HOST/.claude/settings.json" merged
  if ! have jq; then
    say "  jq is not installed. Paste this into $file yourself:"
    cat "$KIT/templates/settings.json"
    note cannot "jq is not installed" "printed templates/settings.json; nothing was written"
    return 0
  fi
  # The same merge either way. With no host file, `{}` is the host side: an empty
  # object is the identity of `*` and of the union, so the template comes out
  # already sorted and the second apply finds nothing to change.
  if [ -f "$file" ]; then
    merged="$(jq -s "$MERGE_PERMS" "$KIT/templates/settings.json" "$file" 2>/dev/null)" || merged=""
  else
    merged="$(jq -s "$MERGE_PERMS" "$KIT/templates/settings.json" - 2>/dev/null <<<'{}')" || merged=""
  fi
  [ -n "$merged" ] || {
    note cannot "jq could not merge templates/settings.json" "malformed host file?"
    return 0
  }
  ensure "$file" "write .claude/settings.json (host keys win)" < <(printf '%s\n' "$merged")
  note ok "templates/settings.json merged into .claude/settings.json" "host keys win, lists unioned"
  return 0
}

# --- 3. claude-md: one block between two markers, replaced in place when it is
# already there and appended when it is not. Everything the host wrote outside the
# markers is left alone: this is the host's CLAUDE.md and not the kit's.
# Caveat: the match is line-anchored, so a CLAUDE.md carrying an end marker with
# no start marker has it rewritten as ordinary prose rather than repaired, and a
# block a person edited by hand is overwritten on the next apply. The block is a
# pointer, not a source of truth: it points at `/devil:guide` and the seeded rules.
stage_claude-md() {
  local file="$HOST/CLAUDE.md"
  if [ -f "$file" ]; then
    ensure "$file" "write the devil block in CLAUDE.md" < <(_claude_md_render "$file")
  else
    ensure "$file" "write CLAUDE.md with the devil block" < <(
      printf '%s\n' "$CLAUDE_MD_START"
      cat "$KIT/templates/claude-md-block.md"
      printf '%s\n' "$CLAUDE_MD_END"
    )
  fi
  note ok "one block between <!-- devil:start --> and <!-- devil:end -->" "from templates/claude-md-block.md"
  return 0
}

# The host CLAUDE.md on argv, the same file with the block written on stdout. awk,
# not sed: the replacement is multi-line and the file may be empty.
_claude_md_render() {
  awk -v s="$CLAUDE_MD_START" -v e="$CLAUDE_MD_END" -v blk="$KIT/templates/claude-md-block.md" '
    BEGIN { while ((getline line < blk) > 0) body = body line "\n"; close(blk) }
    !done && index($0, s) { printf "%s\n%s%s\n", s, body, e; done = 1; skip = 1; next }
    skip && index($0, e) { skip = 0; next }
    skip { next }
    { print }
    END { if (!done) { if (NR > 0) print ""; printf "%s\n%s%s\n", s, body, e } }
  ' "$1"
}

# --- 4. opencode lives in lib/seed-opencode.sh, which this file is sourced
# before: it grew past what a stage-shaped function can hold (the config merge,
# one link per generated file, and the sweep of a retired one).

# --- 5. tracker: which tracker the three abstract verbs map onto. `gh` installed
# and a github.com remote is a real signal; anything else is local, which works.
# Caveat: the remote test greps `git remote -v` for the literal `github.com`, so a
# GitHub Enterprise host, an SSH alias for github, or a worktree whose remote is
# unreachable all read as local. Pass --tracker to say so.
stage_tracker() {
  local kind="$TRACKER" why
  if [ ! -f "$KIT/templates/tracker/github.md" ] || [ ! -f "$KIT/templates/tracker/local.md" ]; then
    note cannot "templates/tracker/{github,local}.md are missing" "from the kit"
    return 0
  fi
  if [ -z "$kind" ]; then
    if have gh && git -C "$HOST" remote -v 2>/dev/null | grep -q 'github\.com'; then
      kind=github
      why="gh installed, github.com remote"
    else
      kind=local
      why="no gh or no github.com remote"
    fi
  else
    why="--tracker $kind"
  fi
  ensure "$HOST/.claude/devil/tracker.md" "write .claude/devil/tracker.md" \
    <"$KIT/templates/tracker/$kind.md"
  note ok "ticket tracker: $kind" "$why"
  return 0
}

# --- 6. mcp: opt-in, because a server is a network call and a supply-chain
# surface. Seeding it unasked would start four processes in every host that
# installed the plugin.
# Caveat: the merge is jq's `*` with the host winning, so a host that already
# turned a server off by naming it is turned off again. Nothing here decides
# whether a server should be on; `supermemory` stays out on purpose (doc/MEMORY.md).
stage_mcp() {
  local file="$HOST/.mcp.json" merged
  if ! have jq; then
    note cannot "jq is not installed" "cannot merge .mcp.json"
    return 0
  fi
  if [ -f "$file" ]; then
    merged="$(jq -s '.[0] * .[1]' "$KIT/templates/mcp.json" "$file" 2>/dev/null)" || merged=""
  else
    merged="$(jq --indent 2 . "$KIT/templates/mcp.json" 2>/dev/null)" || merged=""
  fi
  [ -n "$merged" ] || {
    note cannot "jq could not merge .mcp.json" "malformed host file?"
    return 0
  }
  ensure "$file" "write .mcp.json (host servers win)" < <(printf '%s\n' "$merged")
  note ok "templates/mcp.json merged into .mcp.json" "--seed-mcp, host servers win"
  return 0
}

# --- 7. gitignore: three lines the kit writes into the host and does not want
# committed, its cache, its env file for workers, and the local ticket store.
stage_gitignore() {
  local file="$HOST/.gitignore" n=0 line rc
  for line in '.claude/cache/' '.claude/devil.env' '.scratch/'; do
    append_line "$file" "$line" "add $line to .gitignore"
    rc=$?
    [ "$rc" = 1 ] && continue
    if [ "$rc" = 2 ]; then
      note cannot "cannot create a temporary file" "next to $file"
      return 0
    fi
    n=$((n + 1))
  done
  if [ "$n" -eq 0 ]; then
    note ok "3 lines already present" "each at most once"
  else
    note change "3 lines in .gitignore" "$n to add"
  fi
  return 0
}
