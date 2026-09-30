#!/usr/bin/env bash
# test_templates.sh: the two copy-and-fill shell templates must lint, run headless
# from a here-string, and trace statically; the three decision templates
# (adr, out-of-scope, agent-brief) must keep their required headings, and the
# kit's own .out-of-scope records must follow the template.
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

# Caveat: a regex over shell source, not a parser. It drops quoted strings
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

# --- h. the decision templates: headings, size, and the negative control -----
# A template is a contract with whatever fills it, so its headings are a shape and
# the shape is worth a check. The negative control is the point: every case below
# also builds a copy with ONE heading deleted and requires the same assertion to
# reject it. An assertion that has never been seen to fail is not a gate.
#
# Caveat: a fixed-string shape check. It proves the headings are present, not that
# the prose under them is any good, and a template that needs a new heading has to
# be added here in the same change. That is the intended cost: the shape is part of
# the contract, so changing it is a deliberate act.

# shape <name>: the patterns a template of that name must satisfy, one per line.
shape() {
  case "$1" in
  adr)
    printf '%s\n' '^- Status:' '^## Context$' '^## Decision$' \
      '^## Alternatives considered$' '^## Consequences$' \
      'irreversible' 'public surface' 'PROCEED'
    ;;
  out-of-scope)
    printf '%s\n' '^- Decided: ' '^## The concept$' \
      '^## Why not$' '^## Prior requests$' '^## Reopen when$'
    ;;
  agent-brief)
    printf '%s\n' '^## Objective$' '^## Contract$' '^## Constraints$' '^## Facts$' \
      '^## Return block$' '^status:' '^gates:' '^changed:' '^deviations:' '^next:'
    ;;
  ticket)
    printf '%s\n' '^## Objective$' '^## Done when$' '^## Blocks$' '^## Seams$' '^## Notes$'
    ;;
  *) return 1 ;;
  esac
}

# has_shape <file> <name>: every pattern of that shape is present.
has_shape() {
  local pat
  while read -r pat; do
    [ -n "$pat" ] || continue
    grep -qE -- "$pat" "$1" || return 1
  done < <(shape "$2")
}

# drop <name>: the one heading the negative control deletes.
drop() {
  case "$1" in
  adr) printf '^## Consequences$\n' ;;
  out-of-scope) printf '^## Why not$\n' ;;
  *) printf '^## Facts$\n' ;;
  esac
}

DECISIONS="adr out-of-scope agent-brief"
for t in $DECISIONS; do
  f="templates/$t.md"
  if [ ! -f "$f" ]; then
    no "$f is missing"
    continue
  fi
  has_shape "$f" "$t" && ok "$t.md has every required heading" ||
    no "$t.md is missing a required heading: $(shape "$t" | tr '\n' ' ')"
  [ "$(wc -l <"$f")" -le 40 ] && ok "$t.md is at most 40 lines" || no "$t.md exceeds 40 lines"
  # Negative control: the same assertion, one heading short.
  grep -vE -- "$(drop "$t")" "$f" >"$TMP/short-$t.md"
  has_shape "$TMP/short-$t.md" "$t" && no "$t.md assertion must fail on a copy missing $(drop "$t")" ||
    ok "$t.md assertion fails on a copy with $(drop "$t") deleted"
done

# The kit's own records follow the out-of-scope template, and a fifth one has to
# be named here or it lands unnoticed.
RECORDS="openai-sidecars changesets wizard-interactive skills-array-as-stable-set"
for r in $RECORDS; do
  f=".out-of-scope/$r.md"
  if [ ! -f "$f" ]; then
    no "$f is missing"
    continue
  fi
  has_shape "$f" out-of-scope && ok "$r.md follows the out-of-scope template" ||
    no "$r.md is missing a required heading"
  # A record with no real decision date is a note, not a record.
  grep -qE '^- Decided: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" ||
    no "$r.md has no ISO decision date"
done
found="$(find .out-of-scope -name '*.md' -printf '%f\n' | sed 's/\.md$//' | sort | tr '\n' ' ' | sed 's/ $//')"
# One line per name, sorted, so the comparison is a set equality and not an order.
expected="$(printf '%s\n' "$RECORDS" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
[ "$found" = "$expected" ] &&
  ok "no .out-of-scope record outside the four named ones" ||
  no ".out-of-scope holds '$found', expected only '$expected'"
grep -vE '^## Why not$' "$ROOT/.out-of-scope/changesets.md" >"$TMP/short-record.md"
has_shape "$TMP/short-record.md" out-of-scope &&
  no "a record missing '## Why not' must fail the assertion" ||
  ok "a record missing '## Why not' fails the same assertion"

# --- i. ticket.md: the five sections a ticket body needs ---------------------
# A body that loses `Blocks` has no dependency edge and reads as ready when it is
# blocked, so the negative controls drop that heading and `Seams`.
has_shape "$ROOT/templates/ticket.md" ticket && ok "templates/ticket.md carries its five headings" ||
  no "templates/ticket.md is missing one of: $(shape ticket | tr '\n' ' ')"
for h in Blocks Seams; do
  grep -vx "## $h" "$ROOT/templates/ticket.md" >"$TMP/ticket-no$h.md"
  has_shape "$TMP/ticket-no$h.md" ticket && no "a ticket body without '## $h' must fail the check" ||
    ok "a ticket body with '## $h' removed fails the check"
done
# both tracker adapters point at the one body shape
for t in github local; do
  grep -q 'templates/ticket.md' "$ROOT/templates/tracker/$t.md" &&
    ok "templates/tracker/$t.md references templates/ticket.md" ||
    no "templates/tracker/$t.md must reference templates/ticket.md"
done

echo
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ] || exit 1
