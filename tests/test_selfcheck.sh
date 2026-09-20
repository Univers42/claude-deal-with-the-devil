#!/usr/bin/env bash
# test_selfcheck.sh — selfcheck.sh must fail on the drift that actually shipped.
#
# The bugs this pins down, all of which were live in this repo:
#   - README named 4 agents, 5 rules, 1 skill and 2 workflows that did not exist
#   - rules used Cursor's globs:/alwaysApply:, which Claude Code ignores
#   - skills used `tools:`, which is not a skill frontmatter field
# A gate that only ever passes is not a gate, so every case below builds a
# deliberately broken tree and proves selfcheck catches it.
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

# A minimal but VALID payload, so each test changes exactly one thing.
fixture() {
  local d="$1"
  mkdir -p "$d"/{agents,rules,commands,workflows,skills/demo,tools/lib}
  cp "$ROOT/tools/selfcheck.sh" "$d/tools/"
  cp "$ROOT/tools/lib/common.sh" "$d/tools/lib/"
  chmod +x "$d/tools/selfcheck.sh"
  # shellcheck disable=SC2016  # the backticks are markdown links in the fixture
  printf -- '---\nname: demo-agent\ndescription: a demo\n---\n\nBody `rules/demo.md`\n' \
    >"$d/agents/demo-agent.md"
  # shellcheck disable=SC2016  # ditto
  printf -- '# Demo rule\n\nAlways on, no frontmatter. See `agents/demo-agent.md`.\n' \
    >"$d/rules/demo.md"
  printf -- '---\nname: demo\ndescription: a demo skill\n---\n\n# Demo\n' \
    >"$d/skills/demo/SKILL.md"
  printf -- '---\ndescription: a demo command. Usage: /demo\n---\n\nBody\n' \
    >"$d/commands/demo.md"
  printf -- '---\ndescription: a demo workflow. Usage: /workflow:demo\n---\n\nBody\n' \
    >"$d/workflows/demo.md"
  printf -- '# Index\n\n`agents/demo-agent.md` `rules/demo.md` `skills/demo/SKILL.md`\n`commands/demo.md` `workflows/demo.md`\n' \
    >"$d/README.md"
}

run() { bash "$1/tools/selfcheck.sh" --summary >/dev/null 2>&1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- 1. a clean payload passes ----------------------------------------------
fixture "$TMP/clean"
if run "$TMP/clean"; then ok "clean payload exits 0"; else
  no "clean payload should exit 0 (got $?)"
  bash "$TMP/clean/tools/selfcheck.sh" 2>&1 | head -12
fi

# --- 2. a documented-but-missing file fails ---------------------------------
fixture "$TMP/dangling"
echo 'See `agents/ghost.md` for details.' >>"$TMP/dangling/README.md"
if run "$TMP/dangling"; then no "dangling reference should fail"; else
  ok "dangling reference fails (the README bug)"
fi

# --- 3. Cursor frontmatter on a rule fails ----------------------------------
fixture "$TMP/cursor"
printf -- '---\nglobs: ["**/*.go"]\nalwaysApply: true\n---\n\n# Go\n' \
  >"$TMP/cursor/rules/demo.md"
if run "$TMP/cursor"; then no "globs:/alwaysApply: should fail"; else
  ok "Cursor frontmatter fails (Claude Code reads paths:)"
fi

# --- 4. `tools:` on a skill fails -------------------------------------------
fixture "$TMP/skilltools"
printf -- '---\nname: demo\ndescription: d\ntools: Read, Bash\n---\n\n# Demo\n' \
  >"$TMP/skilltools/skills/demo/SKILL.md"
if run "$TMP/skilltools"; then no "'tools:' on a skill should fail"; else
  ok "'tools:' on a skill fails (the field is allowed-tools:)"
fi

# --- 5. a skill whose name != its directory fails ---------------------------
fixture "$TMP/mismatch"
printf -- '---\nname: wrong-name\ndescription: d\n---\n\n# Demo\n' \
  >"$TMP/mismatch/skills/demo/SKILL.md"
if run "$TMP/mismatch"; then no "name/directory mismatch should fail"; else
  ok "skill name/directory mismatch fails"
fi

# --- 6. a command with no description fails ---------------------------------
fixture "$TMP/nodesc"
printf -- '---\nmodel: opus\n---\n\nBody\n' >"$TMP/nodesc/commands/demo.md"
if run "$TMP/nodesc"; then no "command with no description should fail"; else
  ok "command with no description fails (invisible in the / menu)"
fi

# --- 7. a relative link resolves from the doc's own directory ---------------
# hooks/HOOKS-README.md saying `scripts/hooks.py` is correct, not dangling.
fixture "$TMP/relative"
mkdir -p "$TMP/relative/doc/tools"
: >"$TMP/relative/doc/tools/thing.sh"
echo 'See `tools/thing.sh`.' >"$TMP/relative/doc/guide.md"
if run "$TMP/relative"; then ok "relative link resolves from its own directory"; else
  no "relative link wrongly reported dangling"
fi

# --- 8. the real payload is clean -------------------------------------------
if bash "$ROOT/tools/selfcheck.sh" --summary >/dev/null 2>&1; then
  ok "this repo's own payload is clean"
else
  no "this repo's own payload has drift"
  bash "$ROOT/tools/selfcheck.sh" --summary 2>&1 | head -15
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
