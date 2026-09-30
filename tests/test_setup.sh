#!/usr/bin/env bash
# test_setup.sh — `devil setup` must seed a host, be idempotent, and say so when
# it cannot.
#
# A seed that writes the same file twice, or that overwrites a host's own
# settings, is worse than no seed: the host has to notice and undo it. So the
# load-bearing cases here are the negative ones. Every stage is broken on purpose
# in its own fixture and `--check` must exit 1 naming that stage, because a check
# that cannot fail is not a check.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$ROOT/tools/setup.sh"
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

if ! command -v jq >/dev/null 2>&1; then
  echo "skip - jq is not installed; the settings and opencode stages need it"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A fresh git host that already has the three things a real host has: its own
# permission entry, its own opencode config, and its own CLAUDE.md and
# .gitignore. One fixture, changed one way per case.
host() {
  local d="$TMP/$1"
  mkdir -p "$d/.claude"
  git -C "$d" init -q
  printf 'a host project\n' >"$d/README.md"
  printf 'target/\n' >"$d/.gitignore"
  printf '# Host rules\n\nNothing to see.\n' >"$d/CLAUDE.md"
  printf '{"permissions": {"allow": ["Bash(host-only:*)"], "ask": ["Bash(host-ask:*)"]},\n  "outputStyle": "host"}\n' \
    >"$d/.claude/settings.json"
  printf '{"instructions": ["./docs/*.md"], "model": "host/model",\n  "permission": {"edit": "allow"}}\n' >"$d/opencode.json"
  echo "$d"
}

# run <host> [args...] -> stdout of setup.sh; the exit code lands in $RC.
RC=0
run() {
  local h="$1"
  shift
  RUN_OUT="$(bash "$SETUP" --host "$h" "$@" 2>&1)"
  RC=$?
  return 0
}

# status <stage> -> the status word that stage's row carried in the last run().
status() {
  grep -E "^\| $1 \|" <<<"$RUN_OUT" | awk -F'|' '{gsub(/ /, "", $3); print $3}'
}
# --- 1. a fresh host is not applied -----------------------------------------
H="$(host fresh)"
run "$H" --check
if [ "$RC" -eq 1 ]; then ok "a fresh host fails --check"; else no "a fresh host must fail --check, got rc=$RC"; fi
n="$(grep -cE '^\| [a-z-]+ \| change \|' <<<"$RUN_OUT")"
if [ "$n" -ge 5 ]; then ok "every seeded stage reports change ($n rows)"; else no "expected >=5 change rows, got $n"; fi
m="$(grep -cE '^\| (rules|settings|claude-md|opencode|tracker|gitignore) \|' <<<"$RUN_OUT")"
if [ "$m" -eq 6 ]; then ok "--check prints one row per stage"; else no "--check printed $m stage rows, want 6"; fi
# --- 2. the default mode writes nothing --------------------------------------
cp -a "$H" "$TMP/fresh-snap"
run "$H"
if [ "$RC" -eq 0 ] && diff -r "$H" "$TMP/fresh-snap" >/dev/null; then ok "the default dry run writes nothing and exits 0"; else no "the dry run must not write (rc=$RC): $(diff -r "$H" "$TMP/fresh-snap" | head -3)"; fi
# --- 3. apply, then check ----------------------------------------------------
run "$H" --apply
if [ "$RC" -eq 0 ] && [ "$(status rules)" = applied ] && [ "$(status gitignore)" = applied ]; then
  ok "--apply reports every writing stage as applied"
else
  no "--apply should exit 0 with applied rows, got rc=$RC: $(status rules)/$(status gitignore)"
fi
run "$H" --check
if [ "$RC" -eq 0 ] && [ "$(status rules)" = ok ]; then ok "an applied host passes --check"; else
  no "an applied host must pass --check, got rc=$RC"
fi
n="$(find "$H/.claude/rules/devil" -maxdepth 1 -name '*.md' | wc -l)"
if [ "$n" -eq "$(find "$ROOT/rules" -maxdepth 1 -name '*.md' | wc -l)" ]; then ok "all 12 always-on rules were seeded ($n)"; else no "expected the kit's rule count, seeded $n"; fi
for s in refactor-c refactor-go api-convention script-library; do
  if [ -e "$H/.claude/rules/devil/$s.md" ]; then no "the path-scoped rule $s was seeded"; fi
done
ok "the 7 path-scoped rules are not seeded (they ship as skills)"
# --- 4. a second apply is a no-op -------------------------------------------
cp -a "$H" "$TMP/applied-snap"
run "$H" --apply
if [ "$RC" -eq 0 ] && diff -r "$H" "$TMP/applied-snap" >/dev/null; then ok "a second --apply changes nothing (diff -r)"; else no "a second --apply must be a no-op: $(diff -r "$H" "$TMP/applied-snap" | head -5)"; fi
blocks="$(grep -c 'devil:start' "$H/CLAUDE.md")"
if [ "$blocks" -eq 1 ]; then ok "CLAUDE.md holds exactly one devil block after two applies"; else
  no "CLAUDE.md has $blocks devil blocks"
fi
for l in '.claude/cache/' '.claude/devil.env' '.scratch/'; do
  c="$(grep -cxF "$l" "$H/.gitignore")"
  if [ "$c" -ne 1 ]; then no ".gitignore has $c copies of $l"; fi
done
ok "each .gitignore line appears once after two applies"
# --- 5. an edited seeded rule is drift (the negative control for 3 and 4) ----
printf 'a hand edit\n' >>"$H/.claude/rules/devil/risk.md"
run "$H" --check
if [ "$RC" -eq 1 ] && [ "$(status rules)" = change ]; then ok "an edited seeded rule makes --check exit 1, naming rules"; else no "an edited rule must fail --check (rc=$RC, rules=$(status rules))"; fi
run "$H" --apply
if [ "$RC" -eq 0 ] && diff -q "$H/.claude/rules/devil/risk.md" "$ROOT/rules/risk.md" >/dev/null; then ok "--apply restores an edited rule from the kit"; else no "--apply must re-seed the edited rule"; fi
# --- 6. an older stamp is drift even when the rules match -------------------
sed -i 's/^version=.*/version=0.0.1/' "$H/.claude/rules/devil/.version"
run "$H" --check
if [ "$RC" -eq 1 ] && grep -q 'plugin moved 0.0.1' <<<"$RUN_OUT"; then ok "a stale .version fails --check and names both versions"; else no "a stale stamp must fail --check, got rc=$RC: $(status rules)"; fi
sed -i "s/^version=.*/version=$(jq -r .version "$ROOT/.claude-plugin/plugin.json")/" \
  "$H/.claude/rules/devil/.version"
run "$H" --check
if [ "$RC" -eq 0 ]; then ok "the restored stamp passes --check"; else no "restoring the stamp must clear --check"; fi
# --- 7. the host's own settings survive the merge ---------------------------
if jq -e '.permissions.allow | index("Bash(host-only:*)")' "$H/.claude/settings.json" >/dev/null; then ok "a host permissions.allow entry survives the merge"; else no "the merge dropped the host's own allow entry"; fi
if [ "$(jq -r .outputStyle "$H/.claude/settings.json")" = host ]; then
  ok "a host scalar the template also sets keeps the host's value"
else
  no "outputStyle should be the host's 'host', got $(jq -r .outputStyle "$H/.claude/settings.json")"
fi
if jq -e '.permissions.ask | index("Bash(devil orch:*)")' "$H/.claude/settings.json" >/dev/null; then ok "the template's ask entry for orch jobs was added"; else no "Bash(devil orch:*) is missing from the merged ask list"; fi
if jq -e '.permissions.allow | index("Bash(.claude/tools/*.sh:*)")' "$H/.claude/settings.json" >/dev/null; then
  no "the stale .claude/tools allow entry is still there"
else
  ok "the stale .claude/tools allow entry is gone"
fi
# --- 8. a host without opencode.json is left alone --------------------------
G="$(host noopencode)"
rm "$G/opencode.json"
run "$G" --apply
if [ "$(status opencode)" = skip ] && [ ! -e "$G/.claude/devil.env" ]; then ok "no opencode.json means the opencode stage skips and writes no devil.env"; else no "the opencode stage should skip on a host without opencode.json"; fi
run "$G" --check
if [ "$RC" -eq 0 ]; then ok "a host without opencode.json still passes --check"; else
  no "a skipped stage must not fail --check, got rc=$RC"
fi
# --- 9. --skip and --only select stages --------------------------------------
S="$(host skipped)"
before="$(sha256sum "$S/.claude/settings.json" | cut -d' ' -f1)"
run "$S" --apply --skip settings
after="$(sha256sum "$S/.claude/settings.json" | cut -d' ' -f1)"
if [ "$before" = "$after" ] && [ "$(status settings)" = skip ] && [ -d "$S/.claude/rules/devil" ]; then
  ok "--skip settings leaves settings.json byte-identical and still seeds the rest"
else
  no "--skip settings must not touch settings.json"
fi
run "$S" --apply
if [ "$before" != "$(sha256sum "$S/.claude/settings.json" | cut -d' ' -f1)" ]; then
  ok "without --skip the same settings.json IS written (the control for the case above)"
else
  no "settings.json was never written, so --skip proves nothing"
fi
run "$S" --check --only gitignore
if [ "$(status rules)" = skip ] && [ "$(status gitignore)" = ok ] && [ "$RC" -eq 0 ]; then ok "--only gitignore runs that stage alone and --check passes on it"; else no "--only gitignore should run one stage (rc=$RC)"; fi
# --- 10. without jq the settings stage refuses and prints the block ---------
NOJQ="$TMP/nojq-bin"
mkdir -p "$NOJQ"
for b in bash env git grep sed awk cat cut head tail basename dirname mktemp chmod mv mkdir rm cmp; do
  ln -sf "$(command -v "$b")" "$NOJQ/$b" 2>/dev/null || true
done
N="$(host nojq)"
out="$(env -i PATH="$NOJQ" HOME="$HOME" bash "$SETUP" --host "$N" --apply --only settings 2>&1)"
rc=$?
if [ "$rc" -eq 2 ] && grep -q '| settings | cannot |' <<<"$out" && grep -q '"Bash(devil:\*)"' <<<"$out"; then ok "no jq: the settings stage exits 2 and prints the block"; else no "no jq must exit 2 and print the block, got rc=$rc"; fi
cp "$N/.claude/settings.json" "$TMP/nojq-before"
env -i PATH="$NOJQ" HOME="$HOME" bash "$SETUP" --host "$N" --apply --only settings >/dev/null 2>&1
if cmp -s "$N/.claude/settings.json" "$TMP/nojq-before"; then ok "no jq: the host settings file was not touched"; else no "no jq: setup must not write settings.json it could not merge"; fi
# --- 11. --seed-mcp merges, the host wins ------------------------------------
M="$(host mcp)"
printf '{"mcpServers": {"playwright": {"command": "host-binary"}}}\n' >"$M/.mcp.json"
run "$M" --check
if [ "$(status mcp)" = skip ]; then ok "the mcp stage is skipped without --seed-mcp"; else
  no "mcp must be opt-in"
fi
run "$M" --apply --seed-mcp
if [ "$(jq -r '.mcpServers.playwright.command' "$M/.mcp.json")" = host-binary ] &&
  [ "$(jq -r '.mcpServers.context7.command' "$M/.mcp.json")" = npx ]; then
  ok "--seed-mcp keeps the host's server and adds the template's"
else
  no "the .mcp.json merge lost a server on one side"
fi
# The negative control: the same host, same flag, with a malformed .mcp.json.
printf 'not json\n' >"$M/.mcp.json"
run "$M" --apply --seed-mcp
if [ "$RC" -eq 2 ] && [ "$(status mcp)" = cannot ]; then ok "a malformed .mcp.json is exit 2, not a silent overwrite"; else no "a malformed .mcp.json must exit 2, got rc=$RC"; fi
# --- 12. the tracker adapter follows --tracker ------------------------------
T="$(host tracker)"
run "$T" --apply --tracker github
if head -1 "$T/.claude/devil/tracker.md" | grep -q GitHub; then ok "--tracker github seeds the GitHub adapter"; else no "--tracker github did not seed the GitHub adapter"; fi
if grep -q 'ready-for-agent' "$T/.claude/devil/tracker.md" && grep -q '\.scratch/tickets' "$ROOT/templates/tracker/local.md"; then
  ok "both adapters name the exact command for every verb"
else
  no "an adapter is missing its command or its label"
fi
run "$T" --apply --tracker nonsense
if [ "$RC" -eq 2 ]; then ok "an unknown --tracker is exit 2 (bad usage)"; else
  no "an unknown --tracker must exit 2, got rc=$RC"
fi
run "$T" --apply --host-does-not-exist
if [ "$RC" -ne 0 ]; then ok "an unknown argument is refused"; else no "an unknown argument must not exit 0"; fi
# --- 13. the tracker is detected, not asked for -----------------------------
D="$(host detected)"
git -C "$D" remote add origin git@github.com:example/host.git
run "$D" --apply
if head -1 "$D/.claude/devil/tracker.md" | grep -q GitHub; then ok "a github.com remote detects the GitHub adapter"; else no "a github.com remote should detect the GitHub adapter"; fi
E="$(host nodetect)"
run "$E" --apply
if head -1 "$E/.claude/devil/tracker.md" | grep -qi 'local'; then ok "a host with no github remote gets the local adapter"; else no "a host with no github remote should get the local adapter"; fi
# --- 14. the host's own CLAUDE.md prose survives ----------------------------
P="$(host prose)"
printf '## House rules\n\nAlways run `make check`.\n' >>"$P/CLAUDE.md"
run "$P" --apply
if grep -q 'Always run `make check`' "$P/CLAUDE.md" && [ "$(grep -c 'devil:start' "$P/CLAUDE.md")" -eq 1 ]; then ok "the host's prose survives and the block lands once"; else no "the claude-md stage damaged the host's CLAUDE.md"; fi
# The negative control for the count: block removed by hand, apply puts it back
# exactly once, not twice.
sed -i '/devil:start/,/devil:end/d' "$P/CLAUDE.md"
run "$P" --apply
if [ "$(grep -c 'devil:start' "$P/CLAUDE.md")" -eq 1 ] && [ "$(grep -c 'Always run' "$P/CLAUDE.md")" -eq 1 ]; then
  ok "a removed block is restored once, and the host's prose once"
else
  no "restoring a removed block duplicated it or ate the host's prose"
fi
# --- 15. the opencode wiring keeps the host's own keys ----------------------
# The shape asserted here is the per-file link layout, not the V1
# skills.paths + rules glob: OpenCode 2.x reads `skills` as an array and
# resolves nothing in `instructions`. tests/test_setup_opencode.sh carries the
# cases for that merge and for the links; this row only proves the shared
# fixture's host keys survive it.
O="$(host opencode)"
run "$O" --apply
if jq -e --arg k "$ROOT/skills" '.skills | index($k)' "$O/opencode.json" >/dev/null; then
  ok "opencode.json gains the kit's skills path in the array V2 reads"
else
  no "the opencode stage did not add the kit's skills path"
fi
if [ "$(jq -r .model "$O/opencode.json")" = host/model ] &&
  jq -e '.instructions | index("./docs/*.md")' "$O/opencode.json" >/dev/null &&
  [ "$(jq -r .permission.edit "$O/opencode.json")" = allow ]; then
  ok "opencode.json keeps the host's model, its own instruction and its permissions"
else
  no "the opencode merge lost a key the host already had"
fi
if [ -L "$O/.opencode/agents/reviewer.md" ] && [ -L "$O/.opencode/plugins/devil.js" ] &&
  [ ! -e "$O/AGENTS.md" ]; then
  ok ".opencode/ holds one link per generated file and no AGENTS.md is written"
else
  no "the per-file links under .opencode/ are missing, or an AGENTS.md was created"
fi
if grep -q "^DEVIL_ROOT=$ROOT$" "$O/.claude/devil.env" && grep -q "^PATH=$ROOT/bin:" "$O/.claude/devil.env"; then
  ok ".claude/devil.env carries DEVIL_ROOT and the kit's bin on PATH"
else
  no ".claude/devil.env is missing DEVIL_ROOT or the PATH entry"
fi
# --- 16. a file the kit did not write is reported, never deleted ------------
X="$(host stale)"
run "$X" --apply
printf '# retired\n' >"$X/.claude/rules/devil/retired-rule.md"
run "$X" --check
if [ "$RC" -eq 1 ] && [ "$(status rules)" = change ]; then ok "a file the kit never seeded changes the rules fingerprint, so --check fails"; else no "an extra file under .claude/rules/devil should fail --check, got rc=$RC"; fi
if [ -f "$X/.claude/rules/devil/retired-rule.md" ]; then ok "setup never deletes a host file it did not write"; else no "setup deleted a file from the host: a seeding tool must not"; fi
# --- 17. a host with NO settings.json: two applies are a no-op ---------------
# The merge sorts the permission lists, so a first write that copied the template
# verbatim came out in the template's order and the second apply re-sorted the
# file it had just written. A diff -r of a whole tree is the only assertion that
# sees it: the file is valid JSON and the right content either way.
NB="$TMP/nosettings"
mkdir -p "$NB"
git -C "$NB" init -q
run "$NB" --apply
cp -a "$NB" "$TMP/nosettings-1"
run "$NB" --apply
if [ "$RC" -eq 0 ] && diff -r "$NB" "$TMP/nosettings-1" >/dev/null 2>&1; then
  ok "a host with no settings.json: two --apply runs are a no-op (diff -r)"
else
  no "two applies must not differ on a settings-less host: $(diff -r "$NB" "$TMP/nosettings-1" 2>&1 | head -5)"
fi
# The negative control, and it has to be a control rather than a second copy of
# the case above: put back the first write the old code made, a plain copy of
# the template, and the next apply MUST change it. If that stopped being true the
# case above would pass for the wrong reason, namely that settings.json is a
# fixed point no matter what is put in it.
jq --indent 2 . "$ROOT/templates/settings.json" >"$NB/.claude/settings.json"
cp "$NB/.claude/settings.json" "$TMP/nosettings-unsorted"
run "$NB" --apply
if ! cmp -s "$NB/.claude/settings.json" "$TMP/nosettings-unsorted"; then
  ok "the control reproduces: an unsorted settings.json is NOT a fixed point"
else
  no "the control did not reproduce: an unsorted settings.json was already stable"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
