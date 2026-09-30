#!/usr/bin/env bash
# test_export.sh — the OpenCode export must be reproducible, complete, and honest.
#
# A generator is only worth having if drift is loud, so the negative controls are
# the point: a hand-edited generated file must FAIL --check, and a read-only agent
# must come out denying edit and shell. A test that only proves the happy path
# would pass just as well with a broken generator.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- 1. the committed tree is what the sources generate ------------------------
if out="$(cd "$ROOT" && bash tools/export.sh --check opencode 2>&1)"; then
  ok "committed dist/opencode matches its sources"
else
  no "committed dist/opencode is stale: $out"
fi

# A hand edit to a generated file is drift. Proved by making one.
DRIFT="$ROOT/dist/opencode/agents/reviewer.md"
cp "$DRIFT" "$TMP/reviewer.keep"
printf '\nhand edit\n' >>"$DRIFT"
if (cd "$ROOT" && bash tools/export.sh --check opencode >/dev/null 2>&1); then
  no "a hand-edited generated file must fail --check"
else
  ok "a hand-edited generated file fails --check"
fi
cp "$TMP/reviewer.keep" "$DRIFT"
if (cd "$ROOT" && bash tools/export.sh --check opencode >/dev/null 2>&1); then
  ok "restoring the file clears the drift"
else
  no "restore must put the tree back in sync"
fi

# A file the sources no longer produce is drift, and a write must delete it:
# a removed skill once outlived its source in dist/.
STALE="$ROOT/dist/opencode/stale-by-test.md"
echo stale >"$STALE"
if (cd "$ROOT" && bash tools/export.sh --check opencode >/dev/null 2>&1); then
  no "a file with no source must fail --check"
else
  ok "a file with no source fails --check"
fi
(cd "$ROOT" && bash tools/export.sh opencode >/dev/null 2>&1)
if [ ! -e "$STALE" ]; then
  ok "a write removes a file with no source"
else
  rm -f "$STALE"
  no "a write must remove a file with no source"
fi

# An unknown harness is exit 2, never a silent pass.
(cd "$ROOT" && bash tools/export.sh --check nosuch >/dev/null 2>&1)
[ $? -eq 2 ] && ok "unknown harness exits 2" || no "unknown harness must exit 2"

# --- 2. a fixture kit: new assets appear, and the mapping is right ------------
# A fixture, not the real tree, so the test can add an agent the kit does not have
# and assert a read-only permission list without touching generated output.
FIX="$TMP/kit"
mkdir -p "$FIX"/{agents,commands,skills/sample,tools/lib,rules,hooks/scripts,hooks/config}
cp "$ROOT/tools/export.sh" "$FIX/tools/"
cp "$ROOT/tools/lib/common.sh" "$ROOT/tools/lib/export-opencode.sh" "$FIX/tools/lib/"
cp "$ROOT/tools/lib/opencode-plugin.js" "$ROOT/tools/lib/opencode-README.md" "$FIX/tools/lib/"
chmod +x "$FIX/tools/export.sh"
printf -- '---\nname: rules-x\n---\n\nA rule.\n' >"$FIX/rules/rules-x.md"
printf -- '---\nname: sample\ndescription: a sample skill\n---\n\nBody\n' >"$FIX/skills/sample/SKILL.md"
printf -- '---\ndescription: A read-only look. Usage: /devil:look <target>\n---\n\nRead $ARGUMENTS closely.\n' \
  >"$FIX/commands/look.md"
printf -- '---\nname: looker\ndescription: Reads and reports, never edits.\ntools: Read, Grep, Glob\n---\n\nLook only.\n' \
  >"$FIX/agents/looker.md"
# One Claude tool name with no V2 action at all, to prove the deny-all base holds.
printf -- '---\nname: oddity\ndescription: Holds a tool V2 has no action for.\ntools: Read, TodoWrite\n---\n\nBody\n' \
  >"$FIX/agents/oddity.md"

if (cd "$FIX" && bash tools/export.sh opencode >/dev/null 2>&1); then
  ok "a fixture kit exports"
else
  no "the fixture kit must export"
fi
[ -f "$FIX/dist/opencode/agents/looker.md" ] && ok "a new agent appears in the output" ||
  no "agents/looker.md missing from the fixture output"
[ -f "$FIX/dist/opencode/commands/look.md" ] && ok "a new command appears in the output" ||
  no "commands/look.md missing from the fixture output"

# Read-only agent: edit and shell must be denied, read/grep/glob allowed.
r="$FIX/dist/opencode/agents/looker.md"
if grep -q 'action: "\*"' "$r" && grep -q 'effect: deny' "$r" &&
  grep -q 'action: read' "$r" && ! grep -q 'action: edit' "$r" && ! grep -q 'action: shell' "$r"; then
  ok "a read-only agent denies edit and shell, allows read"
else
  no "read-only agent mapping is wrong:"
  sed -n '/^permissions:/,/^[a-z]/p' "$r"
fi

# A Claude tool with no V2 action grants nothing, so the deny-all base still holds.
o="$FIX/dist/opencode/agents/oddity.md"
if grep -q 'action: read' "$o" && ! grep -qE 'action: (edit|shell|write)' "$o"; then
  ok "an unmapped Claude tool grants no V2 action"
else
  no "an unmapped Claude tool must not become a grant"
fi

# The command namespace is rewritten to what V2 actually registers.
if grep -q 'Usage: /look <target>' "$FIX/dist/opencode/commands/look.md"; then
  ok "command description is rewritten from /devil:look to /look"
else
  no "command description still names the Claude namespace"
fi
grep -q '\$ARGUMENTS' "$FIX/dist/opencode/commands/look.md" &&
  ok "\$ARGUMENTS survives the export" || no "\$ARGUMENTS was lost"

# --- 3. every generated file declares itself generated -------------------------
# A frontmatter file cannot start with its notice (line 1 must be the `---` fence
# or the block is body text), so agents and commands carry it on line 2 as a YAML
# comment. JSON has no comment form, so opencode.json carries it in `_comment` on
# line 3, after `$schema`. Three lines is the window all three forms fit in.
missing=""
while read -r f; do
  head -3 "$f" | grep -q 'GENERATED by' || missing="$missing $f"
done < <(find "$ROOT/dist/opencode" -type f)
[ -z "$missing" ] && ok "all $(find "$ROOT/dist/opencode" -type f | wc -l | tr -d ' ') generated files carry the header" ||
  no "no generated header on:$missing"

# And the notice must not cost the frontmatter: line 1 is still the fence, which
# is the one thing V2 needs to read the file as an agent at all.
for f in "$ROOT/dist/opencode/agents/reviewer.md" "$ROOT/dist/opencode/commands/prompt.md"; do
  if [ "$(head -1 "$f")" = "---" ] && sed -n '2p' "$f" | grep -q '^# GENERATED'; then
    ok "$(basename "$(dirname "$f")")/$(basename "$f") keeps the fence on line 1"
  else
    no "$(basename "$f"): line 1 must stay the --- fence, with the notice on line 2"
  fi
done

# The frontmatter must be a real YAML mapping that closes. An unterminated block
# parses as "no frontmatter at all": the host drops `mode: subagent` and every
# agent comes back a primary agent no subagent tool can launch, with no error
# anywhere. That is the failure this check exists for.
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  badfm="$(
    python3 - "$ROOT/dist/opencode" <<'PY'
import glob, sys, yaml
root = sys.argv[1]
bad = []
for f in sorted(glob.glob(root + "/agents/*.md")) + sorted(glob.glob(root + "/commands/*.md")):
    parts = open(f).read().split("---\n")
    if len(parts) < 3:
        bad.append(f + " (frontmatter never closes)")
        continue
    try:
        d = yaml.safe_load(parts[1])
    except Exception as exc:
        bad.append(f + " (" + str(exc).splitlines()[0] + ")")
        continue
    if not isinstance(d, dict) or "description" not in d:
        bad.append(f + " (no description)")
    if "/agents/" in f and d.get("mode") != "subagent":
        bad.append(f + " (mode is not subagent)")
print("\n".join(bad))
PY
  )"
  [ -z "$badfm" ] && ok "every generated frontmatter is a closed YAML mapping with mode: subagent" ||
    no "frontmatter not usable by the host:"$'\n'"$badfm"
else
  skip "python3 with PyYAML unavailable: frontmatter not parsed as YAML"
fi

# --- 4. the bridge, if node can be run ----------------------------------------
# node is not on this host, so the bridge is checked in a container and the paths
# it is given are the container's, not the host's. Both the syntax and the mapping
# are asserted; a skip is reported, never counted as a pass.
if command -v node >/dev/null 2>&1; then
  NODE=(node)
  IN="$ROOT"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  NODE=(docker run --rm -v "$ROOT:/k:ro" -w /k node:22-slim node)
  IN=/k
else
  NODE=()
  IN=""
fi

if [ -z "$IN" ]; then
  skip "node and docker unavailable: devil.js syntax and payload mapping not run"
else
  if "${NODE[@]}" --check "$IN/dist/opencode/plugins/devil.js" 2>/dev/null; then
    ok "devil.js parses"
  else
    no "devil.js does not parse"
  fi
  if "${NODE[@]}" "$IN/tests/opencode-plugin-probe.mjs" 2>&1; then
    ok "devil.js maps bash to Bash and denies on a deny decision"
  else
    no "devil.js payload mapping probe failed"
  fi
fi

echo
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ] || exit 1
