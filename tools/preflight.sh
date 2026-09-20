#!/usr/bin/env bash
# preflight.sh — verify the environment BEFORE building/compiling/running. Missing
# .env, secrets, or credentials fail HERE — fast and clear — not ten minutes into a
# build. Never prints secret values; only names and set/unset.
#
# Usage: preflight.sh [--summary]
# Exit: 0 if ready to build; 1 if required config is missing.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"
set +e # a checker manages its own exit codes; don't abort on a missing var

SUMMARY=0
for a in "$@"; do case "$a" in
  --summary) SUMMARY=1 ;;
  *)
    echo "preflight.sh: unknown arg '$a'" >&2
    exit 2
    ;;
  esac done

ROOT="$(repo_root)"
cd "$ROOT" || exit 1
MISS=0
CREDS=0

_env_keys() { grep -hE '^[A-Za-z_][A-Za-z0-9_]*=' "$1" 2>/dev/null | sed 's/=.*//' | sort -u; }
is_set() { [ -n "${!1:-}" ]; }                                      # exported and non-empty
in_env() { [ -f "$ROOT/.env" ] && grep -qE "^$1=.+" "$ROOT/.env"; } # present with a value
is_cred() { printf '%s' "$1" | grep -qiE 'KEY|SECRET|TOKEN|PASSWORD|PASSWD|CREDENTIAL|PRIVATE'; }

# Ponytail: required config is inferred from whichever of these files exists
# first, so a project that declares its config anywhere else (a schema, a chart,
# a README table) reports as having none — which reads as "nothing required"
# when it means "nothing found". Absence of an example file is reported ⚪, not
# green, for exactly that reason.
example="$(ls .env.example .env.sample .env.template .env.dist 2>/dev/null | head -1)"

report_env() {
  if [ -z "$example" ]; then
    echo "- ⚪ no .env.example — declare required config there so it can be verified"
    return
  fi
  if [ ! -f .env ]; then
    echo "- ❌ \`$example\` exists but \`.env\` is missing — \`cp $example .env\` and fill it"
    MISS=$((MISS + 1))
  fi
  local k
  for k in $(_env_keys "$example"); do
    if is_set "$k" || in_env "$k"; then
      [ "$SUMMARY" = 1 ] || echo "- ✅ $k"
    elif is_cred "$k"; then
      echo "- ❌ $k — unset (credential)"
      MISS=$((MISS + 1))
      CREDS=$((CREDS + 1))
    else
      echo "- ❌ $k — unset"
      MISS=$((MISS + 1))
    fi
  done
}

report_tools() {
  local m=""
  manifest go.mod && ! have go && m="$m go"
  manifest Cargo.toml && ! have cargo && m="$m cargo"
  manifest package.json && ! have node && m="$m node"
  { manifest Makefile || manifest makefile; } && ! have make && m="$m make"
  if [ -n "$m" ]; then
    echo "- ❌ build tools absent:$m"
    MISS=$((MISS + 1))
  else echo "- ✅ build toolchain present"; fi
}

[ "$SUMMARY" = 1 ] && echo "## Preflight" || echo "# Preflight — $ROOT"
echo
report_env
report_tools
echo
if [ "$MISS" -eq 0 ]; then
  echo "✅ ready to build"
  exit 0
fi
printf '❌ %d config problem(s)' "$MISS"
[ "$CREDS" -gt 0 ] && printf ' (%d credential(s))' "$CREDS"
echo " — fix before building (never compile with config unset)"
exit 1
