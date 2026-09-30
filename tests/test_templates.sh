#!/usr/bin/env bash
# test_templates.sh: the two copy-and-fill templates must lint, run headless
# from a here-string, and trace statically.
#
# The trace is the gate that matters. The agent never runs a wizard end to end
# (it opens browsers and writes secrets), so the only proof it can give is that
# every helper the stages call exists and every secret and variable they set is
# a literal name. A fixture that calls a misspelt helper must fail the trace,
# or the trace is not a gate.
#
# Usage: test_templates.sh                  run every case; exit 1 on a failure
#        test_templates.sh --trace <wizard>  trace one authored wizard; exit 1 on a gap
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HITL="skills/debug/scripts/hitl-loop.sh"
WIZ="templates/wizard.sh"
PASS=0
FAIL=0
SKIP=0

ok() {
  echo "ok   - $1"
  PASS=$((PASS + 1))
}
no() {
  echo "FAIL - $1"
  FAIL=$((FAIL + 1))
}
skip() {
  echo "skip - $1"
  SKIP=$((SKIP + 1))
}

library() { sed -n '1,/^# STAGES$/p' "$1"; }
stages() { sed '1,/^# STAGES$/d' "$1"; }

# Ponytail: a regex over shell source, not a parser. It drops quoted strings
# and comments, then takes the first word of every `;` `&&` `||` `|` `(` `{`
# segment below the marker as a command, after peeling the keywords and
# VAR=value prefixes that may precede one. It reads a heredoc body and a `case`
# pattern as commands and loses the rest of a line after a `"` inside a
# single-quoted string (noise, not a miss). It cannot see a helper called
# through a variable; the name check below reports that as untraceable.
called_words() {
  stages "$1" | sed -E 's/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g; s/#.*$//' | tr ';|&(){}`' '\n' | sed -E '
    s/^[[:space:]]+//
    :a
    s/^(!|if|then|else|elif|do|while|until|time)[[:space:]]+//
    s/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+//
    ta
    s/[[:space:]].*$//' | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' | sort -u
}

defined_functions() { grep -oE '^[A-Za-z_][A-Za-z0-9_]*\(\)' "$1" | tr -d '()' | sort -u; }

# set_secret / set_var names, one `kind NAME` per line; a non-literal is a gap.
set_names() { stages "$1" | sed 's/#.*$//' | grep -oE '\bset_(secret|var)[[:space:]]+[^[:space:]]+' | awk '{print $1, $2}'; }

# trace_wizard <file>: the report an agent gives instead of running it.
trace_wizard() {
  local f="$1" gaps=0 word kind name unresolved=()
  echo "trace: $f"
  while read -r kind name; do
    [ -n "$kind" ] || continue
    [ "$kind" = set_var ] && kind=variable || kind=secret
    if [[ $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo "  $kind: $name"
    else
      echo "  UNTRACEABLE: $kind $name (the name must be a literal)"
      gaps=$((gaps + 1))
    fi
  done < <(set_names "$f")
  while read -r word; do
    [ -n "$word" ] || continue
    defined_functions "$f" | grep -qx -- "$word" && continue
    # A fresh bash, so this test's own functions (ok, no, ...) do not resolve.
    bash -c 'type -t -- "$1" >/dev/null 2>&1' _ "$word" || unresolved+=("$word")
  done < <(called_words "$f")
  echo "  calls: $(called_words "$f" | tr '\n' ' ')"
  if [ "${#unresolved[@]}" -gt 0 ]; then
    echo "  UNRESOLVED: ${unresolved[*]} (no helper, builtin or command by that name)"
    gaps=$((gaps + 1))
  fi
  [ "$gaps" -eq 0 ]
}

cd "$ROOT" || exit 1
case "${1:-}" in
'') ;;
--trace)
  [ -f "${2:-}" ] || {
    echo "usage: test_templates.sh [--trace <wizard.sh>]" >&2
    exit 2
  }
  trace_wizard "$2"
  exit $?
  ;;
*)
  echo "usage: test_templates.sh [--trace <wizard.sh>]" >&2
  exit 2
  ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fixture() {
  local out="$1"
  shift
  library "$WIZ" >"$out"
  printf '%s\n' "$@" >>"$out"
}

# --- a. b. c. the linters -----------------------------------------------------
for f in "$HITL" "$WIZ"; do
  [ -x "$f" ] && head -1 "$f" | grep -q '^#!/usr/bin/env bash$' && ok "$f is executable with the shebang on line 1" ||
    no "$f must be executable with #!/usr/bin/env bash on line 1"
  bash -n "$f" && ok "bash -n $f" || no "bash -n $f"
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$f" && ok "shellcheck $f" || no "shellcheck $f"
  else skip "shellcheck not installed ($f)"; fi
  if command -v shfmt >/dev/null 2>&1; then
    shfmt -d -i 2 "$f" >/dev/null && ok "shfmt $f" || no "shfmt -d -i 2 $f"
  else skip "shfmt not installed ($f)"; fi
  bash "$f" --help >/dev/null && ok "$f --help exits 0" || no "$f --help must exit 0"
  bash "$f" --bogus >/dev/null 2>&1
  [ $? -eq 2 ] && ok "$f rejects an unknown flag with 2" || no "$f must exit 2 on an unknown flag"
done

# --- d. the static trace ------------------------------------------------------
trace_wizard "$WIZ" >"$TMP/trace.out" && ok "the shipped wizard traces clean" ||
  {
    no "the shipped wizard must trace clean"
    cat "$TMP/trace.out"
  }
grep -q '^  secret: DASHBOARD_TOKEN$' "$TMP/trace.out" && grep -q '^  variable: DASHBOARD_PROJECT$' "$TMP/trace.out" &&
  ok "the trace names the secret and the variable the example sets" || no "the trace must list set_secret/set_var names"
fixture "$TMP/typo.sh" 'stage 1 1 "x"' 'ask_secret T "t"' 'set_sekret T "$T"' 'finish'
trace_wizard "$TMP/typo.sh" >/dev/null && no "a misspelt helper must fail the trace" || ok "a misspelt helper (set_sekret) fails the trace"
fixture "$TMP/dyn.sh" 'stage 1 1 "x"' 'N=T' 'set_secret "$N" "v"' 'finish'
trace_wizard "$TMP/dyn.sh" >/dev/null && no "a non-literal secret name must fail the trace" || ok "a secret set through a variable fails the trace"

# --- e. hitl-loop reads a here-string and prints the tail ---------------------
library "$HITL" >"$TMP/repro.sh"
printf '%s\n' 'step "one"' 'capture FIRST "q1"' 'tag "mid"' 'capture SECOND "q2"' 'tag' 'finish' >>"$TMP/repro.sh"
bash "$TMP/repro.sh" <<<$'\nalpha\nbeta' >"$TMP/repro.out" && ok "hitl-loop runs headless from a here-string" ||
  no "hitl-loop must exit 0 from a here-string"
grep -qx 'FIRST=alpha' "$TMP/repro.out" && grep -qx 'SECOND=beta' "$TMP/repro.out" &&
  ok "the captured KEY=VALUE lines are on stdout" || {
  no "KEY=VALUE tail missing"
  cat "$TMP/repro.out"
}
ids="$(grep -o '\[DEBUG-[^]]*\]' "$TMP/repro.out" | sort -u)"
[ "$(wc -l <<<"$ids")" -eq 1 ] && grep -cqE '^\[DEBUG-[0-9a-f]{4}\]$' <<<"$ids" &&
  [ "$(grep -c '\[DEBUG-' "$TMP/repro.out")" -eq 3 ] &&
  ok "one fixed 4-hex DEBUG tag on every tagged line ($ids)" || no "DEBUG tag must be one 4-hex id repeated (got: $ids)"
bash "$HITL" <<<$'\n\nx\ny' >"$TMP/ship.out" && [ "$(sed '1,/^== captured ==$/d' "$TMP/ship.out" | grep -c '^[A-Z_]*=')" -eq 2 ] &&
  ok "the shipped example prints its two captures" || no "the shipped hitl example must print two KEY=VALUE lines"

# --- f. write_env upserts and ask reads the default back ----------------------
mkdir "$TMP/env" && (
  # shellcheck source=templates/wizard.sh
  cd "$TMP/env" && . "$ROOT/$WIZ" && write_env TOKEN first && write_env TOKEN second && write_env OTHER x &&
    ask TOKEN "p" <<<"" && [ "$TOKEN" = second ]
) >"$TMP/env.out" 2>&1 && ok "sourcing loads only the library; ask defaults to the .env value" ||
  {
    no "source + write_env + ask failed"
    cat "$TMP/env.out"
  }
[ "$(grep -c '^TOKEN=' "$TMP/env/.env")" -eq 1 ] && grep -qx 'TOKEN=second' "$TMP/env/.env" && [ "$(wc -l <"$TMP/env/.env")" -eq 2 ] &&
  ok "write_env keeps one line per key, with the last value" || {
  no "write_env upsert wrong"
  cat "$TMP/env/.env"
}
grep -q 'Stage 1/2' "$TMP/env.out" && no "sourcing must not run the stages" || ok "sourcing does not run the stages"

# --- g. dry-run with gh absent: SKIPPED, no .env, no secret value -------------
mkdir "$TMP/dry" && (cd "$TMP/dry" && PATH=/nonexistent "$BASH" "$ROOT/$WIZ" --dry-run <<<$'s3cr3t-value-XYZ\nproj\ny') >"$TMP/dry.out" 2>&1 &&
  ok "wizard --dry-run exits 0 with an empty PATH" || no "wizard --dry-run must exit 0 with an empty PATH"
grep -q '^SKIPPED: set secret DASHBOARD_TOKEN' "$TMP/dry.out" && ok "gh absent prints SKIPPED for set_secret" || no "SKIPPED line missing"
[ ! -e "$TMP/dry/.env" ] && ok "dry-run writes nothing to .env" || no "dry-run wrote a .env"
grep -q 's3cr3t-value-XYZ' "$TMP/dry.out" && no "the secret value was printed" || ok "the secret value never appears in the output"

echo
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ] || exit 1
