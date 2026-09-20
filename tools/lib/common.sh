#!/usr/bin/env bash
# common.sh — shared helpers for .claude/tools/*.
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

# Cache lives at .claude/cache — next to the tools, so it survives any CWD.
cache_dir() {
  local d
  d="$(_tools_dir)/../cache"
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
has_ext() { list_files | grep -qiE "\.($1)$"; }

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

# Value of a top-level frontmatter key, trimmed. Empty when absent.
# Ponytail: line-oriented, so it reads a scalar (`model: opus`) but not a
# multi-line block or a nested map — which is all any field here uses.
fm_field() {
  fm_block "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 |
    sed 's/^["'"'"']//; s/["'"'"']$//; s/[[:space:]]*$//'
}

# True when the frontmatter declares a `paths:` key (scalar or YAML list),
# i.e. the rule/skill lazy-loads instead of costing context every session.
fm_has_paths() { fm_block "$1" | grep -q '^paths:'; }

# Names of this config's assets, one per line, sorted.
#   agents|rules|commands|workflows -> <dir>/<name>.md  ->  name
#   skills                          -> skills/<name>/SKILL.md -> name
#   tools                           -> tools/<name>.sh  ->  name
asset_names() {
  local root
  root="$(claude_root)"
  case "$1" in
  skills) find "$root/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort ;;
  tools) find "$root/tools" -maxdepth 1 -name '*.sh' -printf '%f\n' 2>/dev/null | sed 's/\.sh$//' | sort ;;
  *) find "$root/$1" -maxdepth 1 -name '*.md' -printf '%f\n' 2>/dev/null | sed 's/\.md$//' | sort ;;
  esac
}

# Best-effort top-level symbol matches (regex, not AST — ponytail: good enough
# to navigate; the agent reads the real file before editing).
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
