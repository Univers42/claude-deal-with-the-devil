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

# A minimal but VALID payload, so each test changes exactly one thing. The
# workflow is a command tagged kind: workflow and is cited only as /devil:<n>.
fixture() {
  local d="$1"
  mkdir -p "$d"/{agents,rules,commands,skills/demo,tools/lib,tools/orch,bin}
  cp "$ROOT/tools/selfcheck.sh" "$d/tools/"
  cp "$ROOT/tools/lib/common.sh" "$d/tools/lib/"
  printf '#!/usr/bin/env bash\n' >"$d/tools/orch/timed"
  printf '#!/usr/bin/env bash\n' >"$d/bin/devil"
  chmod +x "$d/tools/selfcheck.sh" "$d/tools/orch/timed" "$d/bin/devil"
  # shellcheck disable=SC2016  # the backticks are markdown links in the fixture
  printf -- '---\nname: demo-agent\ndescription: a demo\n---\n\nBody `rules/demo.md`\n' \
    >"$d/agents/demo-agent.md"
  # shellcheck disable=SC2016  # ditto
  printf -- '# Demo rule\n\nAlways on, no frontmatter. See `agents/demo-agent.md`.\n' \
    >"$d/rules/demo.md"
  printf -- '---\nname: demo\ndescription: a demo skill\n---\n\n# Demo\n' \
    >"$d/skills/demo/SKILL.md"
  printf -- '---\ndescription: a demo command. Usage: /devil:demo\nmetadata:\n  kind: command\n---\n\nBody\n' \
    >"$d/commands/demo.md"
  printf -- '---\ndescription: a demo workflow. Usage: /devil:demo-flow\nmetadata:\n  kind: workflow\n---\n\nBody\n' \
    >"$d/commands/demo-flow.md"
  printf -- '# Index\n\n`agents/demo-agent.md` `rules/demo.md` `skills/demo/SKILL.md`\n`commands/demo.md` /devil:demo-flow `bin/devil`\nRun `devil selfcheck --strict`, `devil orch timed`, `devil <tool>`; `#!/usr/bin/env bash`.\n' \
    >"$d/README.md"
}

# run <dir> [selfcheck args] -> exit code of selfcheck --summary on the fixture
run() {
  local d="$1"
  shift
  bash "$d/tools/selfcheck.sh" --summary "$@" >/dev/null 2>&1
}

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

# --- 8. generated output under .claude/cache is not a doc -------------------
# In a standalone checkout cache_dir() is ./.claude/cache; a codemap cached
# there names paths in its own words and must never count as drift.
fixture "$TMP/cached"
mkdir -p "$TMP/cached/.claude/cache"
echo 'Symbols: `scripts/hooks.py` `agents/ghost.md`' >"$TMP/cached/.claude/cache/codemap.md"
if run "$TMP/cached"; then ok "a cached codemap under .claude/ is not scanned"; else
  no "generated output under .claude/cache was scanned as a doc"
fi

# --- 9. a workflow is one asset: counted as a workflow, never an orphan command
out="$(bash "$TMP/clean/tools/selfcheck.sh" --strict 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && grep -q 'commands 1 · workflows 1 ·' <<<"$out"; then
  ok "a kind: workflow command counts once, as a workflow (strict clean)"
else no "workflow counting: rc=$rc, $(tail -1 <<<"$out")"; fi
fixture "$TMP/orphanflow"
sed -i 's| /devil:demo-flow||' "$TMP/orphanflow/README.md"
out="$(bash "$TMP/orphanflow/tools/selfcheck.sh" --strict --summary 2>&1)"
rows="$(grep -c 'orphan.*demo-flow' <<<"$out")"
if [ "$rows" = 1 ] && grep -q '`commands/demo-flow`' <<<"$out"; then
  ok "an uncited workflow is one orphan row, named by its commands/ path"
else no "uncited workflow gave $rows orphan rows: $(grep orphan <<<"$out")"; fi

# --- 10. the real payload is clean -------------------------------------------
if bash "$ROOT/tools/selfcheck.sh" --strict --summary >/dev/null 2>&1; then
  ok "this repo's own payload is clean (--strict)"
else
  no "this repo's own payload has drift"
  bash "$ROOT/tools/selfcheck.sh" --strict --summary 2>&1 | head -15
fi

# --- 11. the two layout greps of the plan's section D are empty --------------
hits="$(cd "$ROOT" && grep -rn '\.claude/tools/' --include='*.md' --exclude-dir=.git . | grep -v CHANGELOG.md)"
if [ -z "$hits" ]; then ok "no doc cites .claude/tools/"; else no "docs cite .claude/tools/: $hits"; fi
hits="$(cd "$ROOT" && grep -rn '/workflow:' --include='*.md' --exclude-dir=.git .)"
if [ -z "$hits" ]; then ok "no doc cites /workflow:"; else no "docs cite /workflow:: $hits"; fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
