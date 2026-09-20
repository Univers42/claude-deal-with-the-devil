#!/usr/bin/env bash
# scripts.sh — reach a curated, version-pinned library of external scripts.
#
# The library is git@github.com:Univers42/scripts.git: real, useful tooling
# (valgrind wrappers, a comment stripper, C-norm helpers, header-cycle
# detection) that is NOT runnable the way an agent would naively run it. As
# measured at 2bb05b4 on 2026-09-20:
#
#   - 44 of 56 top-level scripts carry the 42 header block on line 1 INSTEAD of
#     a shebang, so ./script.sh executes under whatever shell happens to be
#     current. norminette.sh is Python despite the .sh.
#   - only 11 of 149 tracked files have the executable bit.
#   - README.md is 0 bytes, so there is nothing to read to find out what any of
#     it does or what arguments it takes.
#
# So this wrapper does three things no plain `git clone` does:
#   1. Pins a sha. An unpinned upstream is an unreviewed code path.
#   2. Invokes with an EXPLICIT interpreter from the registry, never by shebang
#      or executable bit — which is why the two defects above stop mattering.
#   3. Refuses any name not in scripts/REGISTRY.md. An unvetted script is not a
#      tool; the registry is the review record (`rules/script-library.md`).
#
# Everything runs under watch.sh, so nothing from upstream can hang a session.
#
# Usage:
#   scripts.sh list [--summary]        what is available, grouped by task
#   scripts.sh show <name>             one entry: what it does, args, exit codes
#   scripts.sh run <name> [-- args]    fetch if needed, then run it
#   scripts.sh sync [--pin <sha>]      clone/update the cache to the pinned sha
#   scripts.sh path                    print the cache directory
#
# Env: DEVIL_SCRIPTS_PIN overrides the pinned sha
#      DEVIL_SCRIPTS_URL overrides the upstream (for a fork or a local mirror)
#
# Exit: the script's own code for `run`; 2 on misuse; 3 when unavailable offline.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"

URL="${DEVIL_SCRIPTS_URL:-git@github.com:Univers42/scripts.git}"
PIN="${DEVIL_SCRIPTS_PIN:-2bb05b4f819c7f231ff00fb45cfe0d427af0f399}"
REGISTRY="$(claude_root)/scripts/REGISTRY.md"
CACHE="$(cache_dir)/scripts"

die() {
  echo "scripts.sh: $*" >&2
  exit 2
}

# --- registry ---------------------------------------------------------------
# REGISTRY.md holds a pipe table whose rows are the contract:
#   | name | runner | file | does | args | exit |
# Only rows whose `runner` is a bare interpreter are executable; that column is
# the whole defence against upstream's missing shebangs.
#
# Ponytail: this parses markdown with awk on `|`, not a markdown parser. A cell
# containing a literal pipe, or a row wrapped across lines, is silently mangled —
# and it under-reports, so a malformed row disappears from `list` rather than
# erroring. If a registered script is missing from `list`, suspect its row before
# suspecting the cache.
_rows() {
  [ -f "$REGISTRY" ] || die "no registry at $REGISTRY"
  awk -F'|' '
    /^\|/ && NF >= 7 {
      for (i = 2; i <= 7; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i); gsub(/`/, "", $i) }
      if ($2 == "name" || $2 ~ /^-+$/ || $2 == "") next
      print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7
    }' "$REGISTRY"
}

_row_for() { _rows | awk -F'\t' -v n="$1" '$1 == n {print; exit}'; }

# --- cache ------------------------------------------------------------------
_synced() { [ -d "$CACHE/.git" ] && [ "$(git -C "$CACHE" rev-parse HEAD 2>/dev/null)" = "$PIN" ]; }

_sync() {
  have git || die "git not found"
  if [ ! -d "$CACHE/.git" ]; then
    echo "scripts.sh: fetching $URL into $CACHE" >&2
    rm -rf "$CACHE"
    "$DIR/watch.sh" --timeout 300 --idle 60 -- git clone --quiet "$URL" "$CACHE" >&2 ||
      {
        echo "scripts.sh: clone failed (offline, or no SSH access to $URL)" >&2
        return 3
      }
  fi
  git -C "$CACHE" cat-file -e "$PIN^{commit}" 2>/dev/null ||
    "$DIR/watch.sh" --timeout 300 --idle 60 -- git -C "$CACHE" fetch --quiet origin >&2
  git -C "$CACHE" checkout --quiet --detach "$PIN" 2>/dev/null ||
    {
      echo "scripts.sh: pinned sha $PIN not found upstream" >&2
      return 3
    }
  echo "scripts.sh: at $PIN" >&2
}

# --- commands ---------------------------------------------------------------
cmd_list() {
  local summary="${1:-}"
  echo "# Script registry"
  echo
  echo "Pinned to \`${PIN:0:12}\` of \`$URL\`."
  _synced && echo "Cache: synced at \`$CACHE\`." || echo "Cache: **not fetched** — \`scripts.sh sync\` first."
  echo
  if [ "$summary" = "--summary" ]; then
    echo "| Script | Does |"
    echo "|---|---|"
    _rows | awk -F'\t' '{print "| `" $1 "` | " $4 " |"}'
  else
    echo "| Script | Runner | Does | Args | Exit |"
    echo "|---|---|---|---|---|"
    _rows | awk -F'\t' '{print "| `" $1 "` | " $2 " | " $4 " | `" $5 "` | " $6 " |"}'
  fi
  echo
  echo "\`scripts.sh run <name> -- <args>\`. Anything absent from this table is refused."
}

cmd_show() {
  local name="${1:-}" row
  [ -n "$name" ] || die "show needs a name"
  row="$(_row_for "$name")"
  [ -n "$row" ] || die "'$name' is not in the registry — see \`scripts.sh list\`"
  IFS=$'\t' read -r n runner file does args exits <<<"$row"
  echo "# $n"
  echo
  echo "- **Does:** $does"
  echo "- **Args:** \`$args\`"
  echo "- **Exit:** $exits"
  echo "- **Runs as:** \`$runner $file\` (explicit interpreter — upstream's shebang is not trusted)"
  echo "- **Source:** \`$file\` at \`${PIN:0:12}\`"
}

cmd_run() {
  local name="${1:-}" row
  [ -n "$name" ] || die "run needs a name"
  shift
  [ "${1:-}" = "--" ] && shift
  row="$(_row_for "$name")"
  [ -n "$row" ] || die "'$name' is not in the registry — refusing to run an unvetted script"
  IFS=$'\t' read -r _ runner file _ _ _ <<<"$row"
  case "$runner" in
  bash | sh | python3 | node) : ;;
  *) die "registry runner '$runner' for '$name' is not an allowed interpreter" ;;
  esac
  _synced || _sync || return 3
  [ -f "$CACHE/$file" ] || die "'$file' not present at $PIN — the registry is stale"
  # Never ./file: 44 of 56 upstream scripts have no shebang on line 1.
  exec "$DIR/watch.sh" --timeout 600 --idle 120 -- "$runner" "$CACHE/$file" "$@"
}

case "${1:-list}" in
list)
  shift || true
  cmd_list "${1:-}"
  ;;
show)
  shift
  cmd_show "$@"
  ;;
run)
  shift
  cmd_run "$@"
  ;;
sync)
  shift || true
  [ "${1:-}" = "--pin" ] && {
    PIN="${2:?--pin needs a sha}"
    shift 2
  }
  _sync
  ;;
path) echo "$CACHE" ;;
-h | --help | help) sed -n '2,32p' "$0" ;;
*) die "unknown command '${1}' — try list, show, run, sync, path" ;;
esac
