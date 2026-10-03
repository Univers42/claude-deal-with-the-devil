#!/usr/bin/env bash
# common.sh — shared helpers for the kit's tools/*.sh (run as `devil <tool>`).
# Source it; never execute it. This is the project library for the tools:
# every tool stays thin glue over these functions (see rules/library-first.md).

# A sourced library must not mutate the caller's shell options. This used to run
# `set -euo pipefail`, which silently re-enabled -e on the four tools that had
# deliberately turned it off — quality.sh even says "not -e: a failing gate is
# data, not a script error" and got -e back on the next line. The symptom was a
# gate script exiting silently at the first `grep -q` that found nothing, which
# is the SUCCESS case for a negative check. Every tool that wants -e declares it
# itself; the library now leaves that choice alone.

# --- capability probes ------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

# --- locations --------------------------------------------------------------

# Root of the repo being analyzed: CWD's git toplevel, else CWD.
repo_root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

# Directory holding the tools (.claude/tools), resolved from this file.
_tools_dir() { cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd; }

# Cache lives under the HOST repo at .claude/cache: the digest describes that
# tree, so it belongs to it, not to wherever the tools happen to be checked out.
# Outside git, repo_root() falls back to the CWD and so does the cache.
cache_dir() {
  local d
  d="$(repo_root)/.claude/cache"
  mkdir -p "$d"
  (cd "$d" && pwd)
}

# --- caching ----------------------------------------------------------------

_sum() { if have md5sum; then md5sum; else cksum; fi | cut -d' ' -f1; }

# Fingerprint of repo state: HEAD + dirty tree. Any change => caches are stale.
_repo_stamp() {
  {
    if git rev-parse HEAD >/dev/null 2>&1; then
      git rev-parse HEAD
      git status --porcelain 2>/dev/null
    else
      date +%Y%m%d%H # hourly bucket for non-git trees
    fi
  } | _sum
}

cache_fresh() {
  local cache="$1" stamp="$1.stamp"
  [ -s "$cache" ] && [ -f "$stamp" ] || return 1
  [ "$(_repo_stamp)" = "$(cat "$stamp")" ]
}

# emit_cached <cache-basename> <builder-fn> [args...]
# Prints the cache when fresh (unless REFRESH=1); otherwise rebuilds + caches.
emit_cached() {
  local name="$1"
  shift
  local builder="$1"
  shift
  local cache
  cache="$(cache_dir)/$name"
  if [ "${REFRESH:-0}" != "1" ] && cache_fresh "$cache"; then
    cat "$cache"
    return 0
  fi
  "$builder" "$@" >"$cache"
  _repo_stamp >"$cache.stamp"
  cat "$cache"
}

# --- source inventory -------------------------------------------------------

# Repo-relative paths of tracked files (respects .gitignore), else a pruned find.
list_files() {
  local root
  root="$(repo_root)"
  if git -C "$root" rev-parse >/dev/null 2>&1; then
    git -C "$root" ls-files
  else
    find "$root" -type f \
      -not -path '*/.git/*' -not -path '*/node_modules/*' \
      -not -path '*/target/*' -not -path '*/vendor/*' \
      -not -path '*/dist/*' -not -path '*/build/*' \
      -printf '%P\n'
  fi
}

# Does a file exist at the repo root?
manifest() { [ -f "$(repo_root)/$1" ]; }

# Does any tracked file carry one of these extensions? (regex alternation, no dots)
# Counts instead of `grep -q`: -q quits on the first match, the writer upstream
# takes SIGPIPE, and pipefail turned that into "no" on about one call in five.
has_ext() { [ "$(list_files | grep -ciE "\.($1)$")" -gt 0 ]; }

# Language of a path by extension; empty string for unknown.
lang_of() {
  case "$1" in
  *.c | *.h) echo c ;;
  *.go) echo go ;;
  *.rs) echo rust ;;
  *.ts | *.tsx) echo typescript ;;
  *.js | *.jsx | *.mjs | *.cjs) echo javascript ;;
  *.py) echo python ;;
  *.sh | *.bash) echo shell ;;
  *.sql) echo sql ;;
  *.proto) echo proto ;;
  *.md) echo markdown ;;
  *) echo "" ;;
  esac
}

# True for source code; false for docs/unknown.
is_code() {
  case "$(lang_of "$1")" in
  "" | markdown) return 1 ;;
  *) return 0 ;;
  esac
}

# Paths arrive repo-relative from list_files ("tests/x.sh", not "./tests/x.sh"),
# so the `*/tests/*` globs alone missed a top-level tests/ directory entirely —
# every file in it counted as untested source. Match both anchored and nested.
is_test_file() {
  case "$1" in
  *_test.go | *_test.rs | *_test.py | test_*.py | test_*.sh | *.bats) return 0 ;;
  *.test.ts | *.test.tsx | *.test.js | *.spec.ts | *.spec.js) return 0 ;;
  */tests/* | */test/* | */__tests__/* | */spec/*) return 0 ;;
  tests/* | test/* | __tests__/* | spec/*) return 0 ;;
  esac
  return 1
}

loc() { wc -l <"$1" 2>/dev/null | tr -d ' ' || echo 0; }

# --- this config's own assets -----------------------------------------------
# selfcheck.sh and context.sh analyse the .claude payload itself, not the host
# repo. Everything below addresses THIS directory tree, never repo_root().

# Root of the .claude payload (the directory holding tools/, rules/, agents/).
claude_root() { cd "$(_tools_dir)/.." && pwd; }

# Print a file's YAML frontmatter body (between the opening --- and the next ---).
# Prints nothing when line 1 is not exactly '---' — which is the Claude Code
# signal for "always load this rule", so absence is meaningful, not an error.
fm_block() {
  [ -f "$1" ] || return 0
  [ "$(head -1 "$1")" = "---" ] || return 0
  awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {exit} inside' "$1"
}

# Everything after the closing frontmatter fence: the body, fences excluded.
# The two exporter libraries both need it and neither should own it.
fm_body() {
  awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { body = 1; next } body' "$1"
}

# A Claude `tools:` value, one name per line: a comma list, or a YAML block
# list. Read by both exporters, since both dialects grant per tool.
# Caveat: line-oriented. A flow list (`tools: [Read, Bash]`) is not parsed and
# yields no grants, and a name no target action exists for is dropped there, so
# the caller decides whether that means read-only or over-privileged.
claude_tools() {
  fm_block "$1" | awk '
    /^tools:[[:space:]]*\[/ { gsub(/^\[|\].*$/, ""); print; exit }
    /^tools:[[:space:]]*[^[:space:]]/ {
      sub(/^tools:[[:space:]]*/, "")
      gsub(/[\[\]]/, "")
      print
      exit
    }
    /^tools:[[:space:]]*$/ { inside = 1; next }
    inside && /^[[:space:]]*-[[:space:]]+/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); print; next }
    inside { exit }
  ' | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'
}

# Trim surrounding whitespace, then one pair of matching quotes.
_fm_unquote() { sed -E "s/^[[:space:]]+//; s/[[:space:]]+\$//; s/^([\"'])(.*)\1\$/\2/"; }

# Value of a top-level frontmatter key, trimmed. Empty when absent.
# Caveat: line-oriented, so it reads a scalar (`model: opus`) but not a
# multi-line block (use fm_desc) or a nested map (use fm_meta).
fm_field() {
  fm_block "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 | _fm_unquote
}

# True when the frontmatter declares a `paths:` key (scalar or YAML list),
# i.e. the rule/skill lazy-loads instead of costing context every session.
fm_has_paths() { fm_block "$1" | grep -q '^paths:'; }

# True when a top-level key is exactly `true`; case-sensitive, the way Claude
# Code reads `disable-model-invocation:`.
fm_flag() { [ "$(fm_field "$1" "$2")" = true ]; }

# Value of `metadata.<key>`, the map that carries an asset's own labels (kind,
# stage, since). A top-level <key>: is a different field and is never read.
# Caveat: line-oriented YAML with a two-space indent. A map indented by four,
# a flow map (`metadata: {kind: workflow}`) or a CRLF file (fm_block never sees
# the `---` fence) all read as absent, and a nested map under metadata is
# skipped, not flattened. Absent is the failure direction: a tagged command is
# treated as untagged, never the reverse.
fm_meta() {
  fm_block "$1" | awk -v key="$2" '
    /^metadata:[[:space:]]*$/ { inside = 1; next }
    inside && /^[A-Za-z]/ { exit }
    inside && index($0, "  " key ":") == 1 {
      sub(/^  [^:]*:[[:space:]]*/, "")
      print
      exit
    }
  ' | _fm_unquote
}

# The full `description:` on one line, however it was written: a scalar, a
# folded block (> or >-) or a literal block (|). Block lines are joined with
# single spaces because the / listing shows every description on one line.
# Caveat: line-oriented YAML. It takes the first `description:` at column 0
# and stops at the next unindented line, so a duplicate key hides the later
# one, a nested map under description: is flattened into the text, a value
# carrying a literal `description:` at column 0 (invalid YAML) ends the block
# early, and a CRLF file yields nothing because fm_block never sees the fence.
fm_desc() {
  fm_block "$1" | awk -v sq="'" '
    /^description:/ && !seen {
      seen = 1
      s = $0
      sub(/^description:[[:space:]]*/, "", s)
      sub(/[[:space:]]+$/, "", s)
      if (s == "" || s ~ /^[>|]-?$/) { grab = 1; next }
      if (s ~ /^".*"$/ || s ~ ("^" sq ".*" sq "$")) s = substr(s, 2, length(s) - 2)
      print s
      exit
    }
    grab && /^[^[:space:]]/ { exit }
    grab && NF {
      sub(/^[[:space:]]+/, "")
      sub(/[[:space:]]+$/, "")
      out = out (out == "" ? "" : " ") $0
    }
    END { if (out != "") print out }
  '
}

_md_names() { find "$1" -maxdepth 1 -name '*.md' -printf '%f\n' 2>/dev/null | sed 's/\.md$//' | sort; }

# Commands tagged `metadata.kind: workflow`, by name.
_workflow_commands() {
  local f
  for f in "$1"/commands/*.md; do
    [ -e "$f" ] || continue
    if [ "$(fm_meta "$f" kind)" = workflow ]; then basename "$f" .md; fi
  done
}

# Names of this config's assets, one per line, sorted.
#   agents|rules|commands -> <dir>/<name>.md  ->  name
#   workflows             -> commands/<name>.md tagged `metadata.kind: workflow`,
#                            plus a legacy workflows/<name>.md (selfcheck fails one)
#   skills                -> skills/<name>/SKILL.md -> name
#   tools                 -> tools/<name>.sh  ->  name
#   bin|templates         -> every file under <dir>/, as its path inside it
asset_names() {
  local root
  root="$(claude_root)"
  case "$1" in
  skills) find "$root/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort ;;
  tools) find "$root/tools" -maxdepth 1 -name '*.sh' -printf '%f\n' 2>/dev/null | sed 's/\.sh$//' | sort ;;
  bin | templates) find "$root/$1" -type f -printf '%P\n' 2>/dev/null | sort ;;
  workflows) {
    _workflow_commands "$root"
    _md_names "$root/workflows"
  } | sort -u ;;
  *) _md_names "$root/$1" ;;
  esac
}

# Caveat: regex over source, not an AST, so it misses a method declared inside
# an impl block and picks up a bare `foo()` call in a body. Good enough to
# navigate; the agent reads the real file before editing.
symbols_of() {
  local f="$1" pat
  case "$(lang_of "$f")" in
  go) pat='^func (\([^)]*\) )?[A-Za-z]|^type [A-Za-z]' ;;
  rust) pat='^[[:space:]]*pub (fn|struct|enum|trait|mod) ' ;;
  c) pat='^[A-Za-z_].*[A-Za-z_*)][[:space:]]*\(' ;;
  typescript | javascript) pat='^export (default )?(async )?(function|class|const|interface|type|enum) ' ;;
  python) pat='^(def|class) ' ;;
  shell) pat='^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)' ;;
  *) return 0 ;;
  esac
  grep -E "$pat" "$f" 2>/dev/null || true
}

symbol_count() { symbols_of "$1" | grep -c . || true; }
