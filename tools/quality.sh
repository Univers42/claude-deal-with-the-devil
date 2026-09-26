#!/usr/bin/env bash
# quality.sh — run every strict quality gate available in this repo and
# aggregate PASS / FAIL / SKIP. One command instead of remembering N tools
# across N languages (see rules/quality-bar.md for the policy).
#
# Verify-only: it never writes or auto-fixes — a gate must not mutate the tree.
# The agent fixes findings, then re-runs. Each gate uses the STRICTEST flags.
#
# Canonical order (a failure early is cheaper to fix than one late):
#   format -> lint -> types -> sast -> audit
#
# Usage: quality.sh [--summary] [--no-audit] [--with-tests]
#   --summary     totals + only the FAIL/SKIP rows
#   --no-audit    skip network/registry audits (offline / fast loop)
#   --with-tests  also run the detected test command (see facts.sh)
#
# Exit: 0 if no gate FAILED (skips are not failures); 1 if any gate FAILED.
set -uo pipefail # not -e: a failing gate is data, not a script error
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"

SUMMARY=0
AUDIT=1
WITH_TESTS=0
for a in "$@"; do
  case "$a" in
  --summary) SUMMARY=1 ;;
  --no-audit) AUDIT=0 ;;
  --with-tests) WITH_TESTS=1 ;;
  *)
    echo "quality.sh: unknown arg '$a'" >&2
    exit 2
    ;;
  esac
done

ROOT="$(repo_root)"
cd "$ROOT" || exit 1
RESULTS=""
FAILED=0
RAN=0

# --- helpers ----------------------------------------------------------------

# Ponytail: 180s is a flat bound on the network gates, not a measurement. A
# genuinely slow audit on a large lockfile is killed and recorded FAIL, which
# reads as "vulnerable" when it means "did not finish" — re-run the named tool
# directly before acting on it. Without `timeout` installed there is no bound at
# all and a hung registry call will block the gate.
_t() { if have timeout; then timeout 180 "$@"; else "$@"; fi; } # bound network gates

# Resolve a CLI: prefer the repo-local node bin, then a global one. Empty = none.
resolve() {
  if [ -x "$ROOT/node_modules/.bin/$1" ]; then
    echo "$ROOT/node_modules/.bin/$1"
    return 0
  elif have "$1"; then
    command -v "$1"
    return 0
  fi
  return 1
}

record() { RESULTS+="$1	$2	$3	$4"$'\n'; } # status tool category note

# check <category> <label> <relevant 0|1> <bin|""> <gate-fn>
check() {
  local cat="$1" label="$2" rel="$3" bin="$4" fn="$5" rc
  [ "$rel" = 1 ] || return 0
  if [ -z "$bin" ]; then
    record SKIP "$label" "$cat" "not installed"
    return 0
  fi
  # The gate's own output is noise here: the board reports status, not logs.
  if "$fn" "$bin" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  RAN=$((RAN + 1))
  if [ "$rc" -eq 0 ]; then
    record PASS "$label" "$cat" ""
  else
    record FAIL "$label" "$cat" "exit $rc"
    FAILED=$((FAILED + 1))
  fi
}

# --- gate bodies (receive the resolved bin as $1, strictest flags) ----------

g_prettier() { "$1" --check .; }
g_eslint() { "$1" . --max-warnings 0; }
g_tsc() { "$1" --noEmit; }
g_gofmt() { [ -z "$("$1" -l .)" ]; } # -l lists unformatted
g_golangci() { "$1" run ./...; }
g_clippy() { "$1" clippy --all-targets --all-features -- -D warnings; }
g_rustfmt() { "$1" fmt --all --check; }
g_ruff_fmt() { "$1" format --check .; }
g_ruff_lint() { "$1" check .; }
g_shellcheck() { list_files | grep -iE '\.(sh|bash)$' | xargs -r "$1"; }
# `shfmt -d .` walked gitignored trees (a vendored clone, cache/) and used the
# default tab indent, so it disagreed with CI on a repo that is 2-space. Drive it
# from list_files like the shellcheck gate, at the width CI enforces.
g_shfmt() { list_files | grep -iE '\.(sh|bash)$' | xargs -r "$1" -d -i 2; }
g_clangfmt() { list_files | grep -iE '\.(c|h)$' | xargs -r "$1" --dry-run -Werror; }
g_cppcheck() { "$1" --error-exitcode=1 --enable=warning,style --quiet .; }
g_semgrep() { if manifest .semgrep.yml; then _t "$1" --error --config .semgrep.yml; else _t "$1" --error --config auto; fi; }
g_sonar() { _t "$1"; }
g_npm_audit() { _t "$1" audit --audit-level=high; }
g_cargo_audit() { _t "$1" audit; }
g_govuln() { _t "$1" ./...; }
g_pip_audit() { _t "$1"; }
g_osv() { _t "$1" --recursive .; }
g_trivy() { _t "$1" fs --quiet --exit-code 1 .; }
g_make_test() { _t "$1" test; }
g_go_test() { _t "$1" test -race ./...; }
g_cargo_test() { _t "$1" test; }
g_npm_test() { _t "$1" test; }
g_pytest() { _t "$1" -q; }

# --- relevance --------------------------------------------------------------

WEB=$(manifest package.json && echo 1 || (has_ext 'ts|tsx|js|jsx' && echo 1 || echo 0))
GO=$(manifest go.mod && echo 1 || (has_ext 'go' && echo 1 || echo 0))
RUST=$(manifest Cargo.toml && echo 1 || (has_ext 'rs' && echo 1 || echo 0))
PY=$({ manifest pyproject.toml || manifest requirements.txt || has_ext 'py'; } && echo 1 || echo 0)
SH=$(has_ext 'sh|bash' && echo 1 || echo 0)
C=$(has_ext 'c|h' && echo 1 || echo 0)
TS=$({ manifest tsconfig.json; } && echo 1 || echo 0)

# --- run gates, in canonical order -----------------------------------------

# format
# A .claude payload's own integrity is a gate like any other: this repo once
# documented 4 agents, 5 rules and a settings.json that did not exist, and
# nothing caught it. Only relevant when the tree IS such a payload.
g_selfcheck() { "$1" "$DIR/selfcheck.sh" --summary >/dev/null 2>&1; }
check config selfcheck \
  "$([ -f "$DIR/selfcheck.sh" ] && [ -d "$ROOT/rules" ] && [ -d "$ROOT/agents" ] && echo 1 || echo 0)" \
  "$(resolve bash)" g_selfcheck

check format prettier "$WEB" "$(resolve prettier)" g_prettier
check format gofmt "$GO" "$(resolve gofumpt || resolve gofmt)" g_gofmt
check format rustfmt "$RUST" "$(resolve cargo)" g_rustfmt
check format "ruff format" "$PY" "$(resolve ruff)" g_ruff_fmt
check format shfmt "$SH" "$(resolve shfmt)" g_shfmt
check format clang-format "$C" "$(resolve clang-format)" g_clangfmt

# lint
check lint eslint "$WEB" "$(resolve eslint)" g_eslint
check lint golangci-lint "$GO" "$(resolve golangci-lint)" g_golangci
check lint clippy "$RUST" "$(resolve cargo)" g_clippy
check lint "ruff check" "$PY" "$(resolve ruff)" g_ruff_lint
check lint shellcheck "$SH" "$(resolve shellcheck)" g_shellcheck
check lint cppcheck "$C" "$(resolve cppcheck)" g_cppcheck

# types
check types tsc "$TS" "$(resolve tsc)" g_tsc

# sast (cross-cutting static analysis)
ANYCODE=$({ [ "$WEB" = 1 ] || [ "$GO" = 1 ] || [ "$RUST" = 1 ] || [ "$PY" = 1 ] || [ "$C" = 1 ]; } && echo 1 || echo 0)
check sast semgrep "$ANYCODE" "$(resolve semgrep)" g_semgrep
check sast sonarcloud "$(manifest sonar-project.properties && echo 1 || echo 0)" "$(resolve sonar-scanner)" g_sonar

# audit (supply-chain / vulns — network; skipped with --no-audit)
if [ "$AUDIT" = 1 ]; then
  check audit npm-audit "$WEB" "$(resolve npm)" g_npm_audit
  check audit cargo-audit "$RUST" "$(resolve cargo-audit >/dev/null && echo cargo)" g_cargo_audit
  check audit govulncheck "$GO" "$(resolve govulncheck)" g_govuln
  check audit pip-audit "$PY" "$(resolve pip-audit)" g_pip_audit
  check audit osv-scanner "$ANYCODE" "$(resolve osv-scanner)" g_osv
  check audit trivy "$ANYCODE" "$(resolve trivy)" g_trivy
fi

# tests (the TDD gate; opt-in here because a full suite is slower than statics)
if [ "$WITH_TESTS" = 1 ]; then
  if manifest Makefile && grep -qE '^test:' "$ROOT/Makefile"; then
    check tests "make test" 1 "$(resolve make)" g_make_test
  elif [ "$GO" = 1 ]; then
    check tests "go test" 1 "$(resolve go)" g_go_test
  elif [ "$RUST" = 1 ]; then
    check tests "cargo test" 1 "$(resolve cargo)" g_cargo_test
  elif [ "$WEB" = 1 ]; then
    check tests "npm test" 1 "$(resolve npm)" g_npm_test
  elif [ "$PY" = 1 ]; then
    check tests pytest 1 "$(resolve pytest)" g_pytest
  fi
fi

# --- report -----------------------------------------------------------------

icon() { case "$1" in PASS) echo "✅" ;; FAIL) echo "❌" ;; SKIP) echo "⚪" ;; esac }

emit_table() {
  echo "| gate | category | status | note |"
  echo "|---|---|:---:|---|"
  printf '%s' "$RESULTS" | while IFS=$'\t' read -r st tool cat note; do
    [ -n "$st" ] || continue
    if [ "$SUMMARY" = 1 ] && [ "$st" = PASS ]; then continue; fi
    printf '| %s | %s | %s | %s |\n' "$tool" "$cat" "$(icon "$st") $st" "$note"
  done
}

SKIPPED=$(printf '%s' "$RESULTS" | grep -c '^SKIP' || true)
PASSED=$(printf '%s' "$RESULTS" | grep -c '^PASS' || true)

echo "# Quality gates"
echo
echo "$PASSED passed · $FAILED failed · $SKIPPED skipped (strictest flags; verify-only)"
echo
emit_table
echo
if [ "$RAN" -eq 0 ]; then
  echo "⚠️ No gates ran — install tooling so quality is verifiable, not assumed (see rules/quality-bar.md)."
fi
if [ "$SKIPPED" -gt 0 ]; then
  echo "_Skips are uncovered surface. Install the skipped tools (semgrep, sonar-scanner, the \`*-audit\` family) to close them._"
fi

[ "$FAILED" -eq 0 ]
