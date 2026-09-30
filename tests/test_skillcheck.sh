#!/usr/bin/env bash
# test_skillcheck.sh — one fixture FAIL case per check skillcheck.sh makes.
#
# A gate that only ever passes is not a gate, so every case below builds a
# deliberately broken payload and proves skillcheck catches that one thing and
# not something else. `fails_on` greps the exact row, so a case cannot pass on
# some other failure the fixture happens to contain.
#
# The clean fixture is checked under --strict too: it carries no WARN either, so
# "the real tree passes" is a claim about a clean report, not a quiet one.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok() {
  echo "ok   - $1"
  PASS=$((PASS + 1))
}
no() {
  echo "FAIL - $1"
  FAIL=$((FAIL + 1))
}

SKILL_DESC='Generate tests for existing code. Use when a fix has no test or coverage is thin. Auto-triggers on: "write tests for", "add test coverage"'

# A minimal but VALID payload, so each case changes exactly one thing.
fixture() {
  local d="$1"
  mkdir -p "$d"/{agents,rules,commands,skills/demo,tools/lib,tests/scenarios}
  cp "$ROOT/tools/skillcheck.sh" "$d/tools/"
  cp "$ROOT/tools/lib/common.sh" "$d/tools/lib/"
  printf -- '---\nname: demo-agent\ndescription: a demo agent\n---\n\nBody\n' \
    >"$d/agents/demo-agent.md"
  printf -- '# Demo rule\n\nAlways on. See `agents/demo-agent.md`.\n' >"$d/rules/demo.md"
  # shellcheck disable=SC2016  # the auto-trigger phrases are markdown quotes
  printf -- '---\nname: demo\ndescription: %s\nmetadata:\n  stage: beta\n  since: "1.0.0"\n---\n\n# Demo\n\n## Report\n\nok\n' \
    "$SKILL_DESC" >"$d/skills/demo/SKILL.md"
  printf -- '---\ndescription: Generate the tests a module is missing. Usage: /devil:demo\nmetadata:\n  kind: command\n  stage: beta\n  since: "1.0.0"\n---\n\nBody\n' \
    >"$d/commands/demo.md"
  printf -- '---\ndescription: Drive the demo arc. Usage: /devil:demo-flow\nmetadata:\n  kind: workflow\n  stage: beta\n  since: "1.0.0"\n---\n\nBody\n\n## Report\n\nok\n' \
    >"$d/commands/demo-flow.md"
  # shellcheck disable=SC2016  # a markdown link, not a command substitution
  printf -- '# Index\n\n`skills/demo/SKILL.md` `commands/demo.md` /devil:demo-flow\n' \
    >"$d/README.md"
}

# run <dir> [args] -> exit code of skillcheck on the fixture
run() {
  local d="$1"
  shift
  bash "$d/tools/skillcheck.sh" --summary "$@" >/dev/null 2>&1
}

# fails_on <dir> <check> <subject> -> exits non-zero AND reports that exact row
fails_on() {
  local out
  out="$(bash "$1/tools/skillcheck.sh" --summary 2>&1)" && return 1
  grep -qF "| FAIL | $2 | \`$3\` |" <<<"$out"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- 0. a clean payload passes, strictly ------------------------------------
fixture "$TMP/clean"
if run "$TMP/clean" --strict; then ok "clean payload exits 0 (--strict: no warning either)"; else
  no "clean payload should exit 0"
  bash "$TMP/clean/tools/skillcheck.sh" 2>&1 | head -10
fi

# --- 1. stage, since, kind --------------------------------------------------
fixture "$TMP/nostage"
sed -i '/^  stage:/d' "$TMP/nostage/skills/demo/SKILL.md"
if fails_on "$TMP/nostage" stage skill/demo; then ok "an untagged skill fails (stage)"; else
  no "an untagged skill should fail with a stage row"
fi
fixture "$TMP/badstage"
sed -i 's/stage: beta/stage: prod/' "$TMP/badstage/skills/demo/SKILL.md"
if fails_on "$TMP/badstage" stage skill/demo; then ok "a stage outside the enum fails"; else
  no "stage 'prod' should fail with a stage row"
fi
fixture "$TMP/since"
sed -i 's/since: "1.0.0"/since: 1.0.0/' "$TMP/since/skills/demo/SKILL.md"
if fails_on "$TMP/since" since skill/demo; then ok "an unquoted since fails (YAML reads it as a float)"; else
  no "an unquoted since should fail with a since row"
fi
fixture "$TMP/nokind"
sed -i '/^  kind:/d' "$TMP/nokind/commands/demo.md"
if fails_on "$TMP/nokind" kind command/demo; then ok "a command with no metadata.kind fails"; else
  no "a command with no kind should fail with a kind row"
fi
fixture "$TMP/cmdrule"
sed -i 's/stage: beta/stage: rule/' "$TMP/cmdrule/commands/demo.md"
if fails_on "$TMP/cmdrule" stage command/demo; then ok "stage rule on a command fails (skills only)"; else
  no "stage rule on a command should fail with a stage row"
fi

# --- 2. description: budget, A14 form, and the / menu line ------------------
fixture "$TMP/longdesc"
sed -i "s/^description: Generate tests for existing code\./description: Generate tests for existing code $(printf 'x%.0s' {1..1100})/" \
  "$TMP/longdesc/skills/demo/SKILL.md"
if fails_on "$TMP/longdesc" description skill/demo; then ok "a description over 1024 bytes fails"; else
  no "an over-long description should fail with a description row"
fi
fixture "$TMP/soft"
sed -i "s/^description: Generate tests for existing code\./description: Generate tests for existing code $(printf 'y%.0s' {1..420})/" \
  "$TMP/soft/skills/demo/SKILL.md"
if run "$TMP/soft" && ! run "$TMP/soft" --strict; then
  ok "a description over 400 bytes warns, and --strict fails it"
else no "a 400+ byte description should warn and fail under --strict"; fi
fixture "$TMP/nousewhen"
sed -i 's/ Use when a fix has no test or coverage is thin\.//' "$TMP/nousewhen/skills/demo/SKILL.md"
sed -i 's/stage: beta/stage: stable/' "$TMP/nousewhen/skills/demo/SKILL.md"
if fails_on "$TMP/nousewhen" a14 skill/demo; then ok "a stable skill with no 'Use when' fails (A14)"; else
  no "a stable skill with no 'Use when' should fail with an a14 row"
fi
fixture "$TMP/notriggers"
sed -i 's/ Auto-triggers on: .*$//' "$TMP/notriggers/skills/demo/SKILL.md"
sed -i 's/stage: beta/stage: stable/' "$TMP/notriggers/skills/demo/SKILL.md"
if fails_on "$TMP/notriggers" a14 skill/demo; then ok "a stable skill with no trigger list fails (A14)"; else
  no "a stable skill with no Auto-triggers list should fail with an a14 row"
fi
fixture "$TMP/betadesc"
sed -i 's/ Use when a fix has no test or coverage is thin\.//' "$TMP/betadesc/skills/demo/SKILL.md"
if run "$TMP/betadesc" && ! run "$TMP/betadesc" --strict; then
  ok "a beta skill off the A14 form warns only"
else no "a beta skill off the A14 form should warn, not fail"; fi
fixture "$TMP/nousage"
sed -i 's| Usage: /devil:demo||' "$TMP/nousage/commands/demo.md"
if fails_on "$TMP/nousage" usage command/demo; then ok "a command with no Usage line fails"; else
  no "a command with no Usage line should fail with a usage row"
fi

# --- 3. the report heading --------------------------------------------------
fixture "$TMP/noreport"
sed -i '/^## Report/d' "$TMP/noreport/skills/demo/SKILL.md"
if fails_on "$TMP/noreport" report skill/demo; then ok "a skill with no report heading fails"; else
  no "a skill with no report heading should fail with a report row"
fi
fixture "$TMP/noreportflow"
sed -i '/^## Report/d' "$TMP/noreportflow/commands/demo-flow.md"
if fails_on "$TMP/noreportflow" report command/demo-flow; then
  ok "a workflow with no report heading fails"
else no "a workflow with no report heading should fail with a report row"; fi

# --- 4. slash references ----------------------------------------------------
fixture "$TMP/ghost"
printf '\nThen run /devil:ghost.\n' >>"$TMP/ghost/agents/demo-agent.md"
if fails_on "$TMP/ghost" slash agents/demo-agent.md; then
  ok "a /devil: reference reaching nothing fails"
else no "a /devil:ghost reference should fail with a slash row"; fi

# --- 5. the scenario record a stable stage is earned by ---------------------
fixture "$TMP/noscenario"
sed -i 's/stage: beta/stage: stable/' "$TMP/noscenario/skills/demo/SKILL.md"
if fails_on "$TMP/noscenario" scenario demo; then ok "a stable skill with no scenario record fails"; else
  no "a stable skill with no record should fail with a scenario row"
fi
printf '## Scenario\n## Baseline\n## With skill\n' >"$TMP/noscenario/tests/scenarios/demo.md"
if fails_on "$TMP/noscenario" scenario demo; then ok "a scenario record missing ## Verdict fails"; else
  no "an incomplete scenario record should fail with a scenario row"
fi
printf '## Verdict\n' >>"$TMP/noscenario/tests/scenarios/demo.md"
if run "$TMP/noscenario" --strict; then ok "a complete scenario record passes"; else
  no "a complete scenario record should pass"
fi

# --- 6. the retired tombstone -----------------------------------------------
# The skill is renamed `old` here so its name cannot collide with the fixture's
# `demo` command, which would otherwise make the A15 pass read every citation
# of /devil:demo as a reference to the tombstone.
# <dir> <replaced-by> <1 to add disable-model-invocation, 0 to leave it off>
tombstone() {
  fixture "$1"
  mkdir -p "$1/skills/replacement" "$1/skills/old"
  printf -- '---\nname: replacement\ndescription: What old became. Use when old is gone. Auto-triggers on: "the new thing"\nmetadata:\n  stage: beta\n  since: "1.0.0"\n---\n\n## Report\n\nok\n' \
    >"$1/skills/replacement/SKILL.md"
  {
    printf -- '---\nname: old\ndescription: Retired in 1.0.0; use `replacement`.\n'
    [ "$3" = 1 ] && printf -- 'disable-model-invocation: true\n'
    printf -- 'metadata:\n  stage: retired\n  since: "0.9.0"\n  replaced-by: %s\n---\n\nRetired.\n' "$2"
  } >"$1/skills/old/SKILL.md"
  rm -rf "$1/skills/demo"
}
tombstone "$TMP/retired" replacement 1
if run "$TMP/retired"; then ok "a tombstone with a live replacement passes"; else
  no "a valid tombstone should pass"
  bash "$TMP/retired/tools/skillcheck.sh" 2>&1 | head -8
fi
tombstone "$TMP/retired-ghost" ghost 1
if fails_on "$TMP/retired-ghost" retired skill/old; then
  ok "a tombstone pointing at a missing asset fails"
else no "a tombstone pointing at nothing should fail with a retired row"; fi
tombstone "$TMP/retired-invokable" replacement 0
if fails_on "$TMP/retired-invokable" retired skill/old; then
  ok "a tombstone that is still model-invocable fails"
else no "an invokable tombstone should fail with a retired row"; fi

# --- 7. the path-scoped rule skill ------------------------------------------
ruleskill() { # <dir> <frontmatter lines between name: and metadata:>
  fixture "$1"
  {
    printf -- '---\nname: demo\ndescription: Refactor Go. Use when editing Go. Auto-triggers on: "refactor c"\n'
    printf '%b' "$2"
    printf -- 'metadata:\n  stage: rule\n  since: "1.0.0"\n---\n\n## Report\n\nok\n'
  } >"$1/skills/demo/SKILL.md"
}
ruleskill "$TMP/rule" 'paths: ["**/*.go"]\nuser-invocable: false\n'
if run "$TMP/rule"; then ok "a rule skill with paths: and user-invocable: false passes"; else
  no "a valid rule skill should pass"
  bash "$TMP/rule/tools/skillcheck.sh" 2>&1 | head -8
fi
ruleskill "$TMP/rule-nopaths" 'user-invocable: false\n'
if fails_on "$TMP/rule-nopaths" rule demo; then ok "a rule skill with no paths: fails"; else
  no "a rule skill with no paths should fail with a rule row"
fi
ruleskill "$TMP/rule-invocable" 'paths: ["**/*.go"]\n'
if fails_on "$TMP/rule-invocable" rule demo; then ok "a rule skill that is user-invocable fails"; else
  no "an invocable rule skill should fail with a rule row"
fi

# --- 8. the user-only invariant (A15) ---------------------------------------
# <dir> <the line the skill body ends with>
useronly() {
  fixture "$1"
  printf -- '---\ndescription: Ship it. Usage: /devil:demo\ndisable-model-invocation: true\nargument-hint: "<level>"\nmetadata:\n  kind: command\n  stage: beta\n  since: "1.0.0"\n---\n\nBody\n' \
    >"$1/commands/demo.md"
  printf '\n%s\n' "$2" >>"$1/skills/demo/SKILL.md"
}
useronly "$TMP/useronly" 'Then run /devil:demo to finish.'
if fails_on "$TMP/useronly" user-only skills/demo/SKILL.md; then
  ok "a model-invocable asset pointing at a user-only one fails (A15)"
else no "a /devil:demo reference to a user-only command should fail"; fi
useronly "$TMP/telluser" 'ask the user to run /devil:demo to finish.'
if run "$TMP/telluser" --strict; then
  ok "the 'ask the user to run it' exception passes (A15)"
else no "a line that tells the user to run it should be exempt from A15"; fi

# --- 9. the real tree passes ------------------------------------------------
if bash "$ROOT/tools/skillcheck.sh" --summary >/dev/null 2>&1; then
  ok "this repo's own skills and commands are managed"
else
  no "this repo's own skills and commands have findings"
  bash "$ROOT/tools/skillcheck.sh" --summary 2>&1 | head -15
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
