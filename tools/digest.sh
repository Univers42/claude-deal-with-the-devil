#!/usr/bin/env bash
# digest.sh — one command, full situational awareness. Run this at the start
# of a build task instead of hand-reading the tree. Composes the other tools'
# --summary views into a single briefing.
#
# Usage: digest.sh [--refresh]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"

REFRESH_FLAG=""
for a in "$@"; do
  case "$a" in
  --refresh) REFRESH_FLAG="--refresh" ;;
  *)
    echo "digest.sh: unknown arg '$a'" >&2
    exit 2
    ;;
  esac
done

echo "# Build briefing — $(repo_root)"
echo
echo "_Facts before action. Read this, then read-by-query (rg/jq), then build. Never hand-parse what a tool already digested._"
echo
_section() {
  bash "$1" --summary $REFRESH_FLAG || echo "_($(basename "$1") failed — run it directly to see why)_"
  echo
}
_section "$DIR/facts.sh"
bash "$DIR/preflight.sh" --summary || true
echo # non-zero = findings, not failure
_section "$DIR/codemap.sh"
_section "$DIR/untested.sh"
_section "$DIR/dupes.sh"
echo "---"
echo "Next: turn the request into a contract (\`/prompt\`), then build TDD + library-first (\`agents/builder.md\`)."
