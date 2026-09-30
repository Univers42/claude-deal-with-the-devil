#!/usr/bin/env bash
# test_setup_opencode.sh — the `opencode` stage must wire an OpenCode 2.x host
# the way dist/opencode/README.md says, and nothing else.
#
# The stage writes into a host the kit does not own, so the load-bearing cases
# are the refusals: a host file of the same name, a host entry in the config, a
# config shape it did not seed. Each one is paired with the case that proves the
# assertion is not vacuous, because a check that cannot fail is not a check.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$ROOT/tools/setup.sh"
KIT_SKILLS="$ROOT/skills"
RULES_GLOB='./.claude/rules/devil/*.md'
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
  echo "skip - jq is not installed; this stage cannot merge a config without it"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A host with one opencode.json, its own settings file and nothing else of the
# kit's. The settings file is there so a `diff -r` of a whole fixture measures
# the opencode stage: the settings stage has its own idempotence cases in
# tests/test_setup.sh, and on a host with no settings.json it re-sorts its own
# output on the second apply, which would drown the diff this file is after.
host() {
  local d="$TMP/$1" cfg="$2"
  mkdir -p "$d/.claude"
  git -C "$d" init -q
  printf '{"outputStyle": "host"}\n' >"$d/.claude/settings.json"
  printf '%s\n' "$cfg" >"$d/opencode.json"
  echo "$d"
}

RC=0
run() {
  local h="$1"
  shift
  RUN_OUT="$(bash "$SETUP" --host "$h" "$@" 2>&1)"
  RC=$?
  return 0
}
status() { grep -E "^\| $1 \|" <<<"$RUN_OUT" | awk -F'|' '{gsub(/ /, "", $3); print $3}'; }

# Every generated agent and command, and the bridge, are one symlink each into
# the kit's dist, and nothing is written into the kit.
links_ok() {
  local h="$1" f kind bad=0
  for kind in agents commands; do
    for f in "$ROOT/dist/opencode/$kind"/*.md; do
      [ -e "$f" ] || continue
      local l="$h/.opencode/$kind/${f##*/}"
      if [ ! -L "$l" ] || [ "$(readlink "$l")" != "$f" ]; then
        bad=$((bad + 1))
        echo "    not a link into dist/opencode: $l"
      fi
    done
  done
  local p="$h/.opencode/plugins/devil.js"
  if [ ! -L "$p" ] || [ "$(readlink "$p")" != "$ROOT/dist/opencode/plugins/devil.js" ]; then
    bad=$((bad + 1))
    echo "    not a link into dist/opencode: $p"
  fi
  return "$bad"
}

# --- 1. no opencode.json: the stage skips and creates nothing -----------------
N="$(host noconf '')"
rm "$N/opencode.json"
run "$N" --apply
if [ "$(status opencode)" = skip ] && [ ! -e "$N/.opencode" ] && [ ! -e "$N/.claude/devil.env" ]; then
  ok "a host without opencode.json skips the stage and gets no .opencode/ and no devil.env"
else
  no "a host without opencode.json must skip (status=$(status opencode), .opencode=$([ -e "$N/.opencode" ] && echo yes || echo no))"
fi
run "$N" --check --only opencode
if [ "$RC" -eq 0 ] && [ "$(status opencode)" = skip ]; then
  ok "a skipped opencode stage does not fail --check"
else
  no "a skipped stage must not fail --check, got rc=$RC ($(status opencode))"
fi
# The control for the assertion above: the same host, with the config, is wired.
printf '{"model": "x"}\n' >"$N/opencode.json"
run "$N" --apply
if [ "$(status opencode)" = applied ] && [ -d "$N/.opencode/agents" ]; then
  ok "the same host with an opencode.json IS wired, so case 1 is not vacuous"
else
  no "adding opencode.json must wire the host, got $(status opencode)"
fi

# --- 2. a fresh host: skills is the array V2 reads, the links are per file ---
F="$(host fresh '{"model": "x"}')"
run "$F" --apply
if jq -e --arg k "$KIT_SKILLS" '.skills | index($k)' "$F/opencode.json" >/dev/null &&
  [ "$(jq -r '.skills | type' "$F/opencode.json")" = array ]; then
  ok "opencode.json gains skills as an array holding the kit's skills path"
else
  no "skills did not become an array holding $KIT_SKILLS: $(jq -c . "$F/opencode.json")"
fi
if [ "$(jq -r .model "$F/opencode.json")" = x ]; then ok "the host's own model key survives the merge"; else no "the merge lost the host's model"; fi
if [ -f "$F/opencode.json" ] && [ ! -e "$F/AGENTS.md" ] && [ ! -e "$F/.claude/skills" ]; then
  ok "the host's AGENTS.md and .claude/skills are not created"
else
  no "the stage created AGENTS.md or a .claude/skills link it must never write"
fi
if grep -q "^DEVIL_ROOT=$ROOT$" "$F/.claude/devil.env"; then ok ".claude/devil.env still carries DEVIL_ROOT"; else no ".claude/devil.env is missing DEVIL_ROOT"; fi
if out="$(links_ok "$F")"; then ok "every generated agent, command and devil.js is a link into dist/opencode"; else
  no "the links are wrong: $out"
fi
run "$F" --check --only opencode
if [ "$RC" -eq 0 ] && [ "$(status opencode)" = ok ]; then ok "a wired host passes --check"; else no "a wired host must pass --check, got rc=$RC ($(status opencode))"; fi

# --- 3. a second --apply is a no-op ------------------------------------------
cp -a "$F" "$TMP/fresh-applied"
run "$F" --apply
if [ "$RC" -eq 0 ] && diff -r "$F" "$TMP/fresh-applied" >/dev/null 2>&1; then
  ok "a second --apply changes nothing (diff -r)"
else
  no "a second --apply must be a no-op: $(diff -r "$F" "$TMP/fresh-applied" 2>&1 | head -5)"
fi

# --- 4. a V1 host: the object becomes the array, the old glob goes -----------
V="$(host v1 "{\"instructions\": [\"$RULES_GLOB\", \"host.md\"], \"skills\": {\"paths\": [\"/a\"]}}")"
run "$V" --apply
if [ "$(jq -c .instructions "$V/opencode.json")" = '["host.md"]' ]; then
  ok "instructions keeps the host's own entry and loses the seeded rules glob"
else
  no "instructions should be [\"host.md\"], got $(jq -c .instructions "$V/opencode.json")"
fi
if [ "$(jq -c .skills "$V/opencode.json")" = "[\"/a\",\"$KIT_SKILLS\"]" ]; then
  ok "a V1 skills.paths object becomes the array, host paths first"
else
  no "the V1 object form did not convert, got $(jq -c .skills "$V/opencode.json")"
fi
# The control: a glob this stage never seeded is a host entry, not kit debris.
V2H="$(host v1-other "{\"instructions\": [\"./.claude/rules/devil/**\", \"$RULES_GLOB\"]}")"
run "$V2H" --apply
if [ "$(jq -c .instructions "$V2H/opencode.json")" = '["./.claude/rules/devil/**"]' ]; then
  ok "an instruction glob this stage never seeded is left alone (only the exact one goes)"
else
  no "the stage removed a host entry it did not seed: $(jq -c .instructions "$V2H/opencode.json")"
fi
# The control for the key drop: the glob alone leaves the key empty, so it goes.
D="$(host drop "{\"instructions\": [\"$RULES_GLOB\"]}")"
run "$D" --apply
if [ "$(jq -r 'has("instructions")' "$D/opencode.json")" = false ]; then
  ok "instructions is dropped when removing the seeded glob empties it"
else
  no "an emptied instructions key should be dropped, got $(jq -c . "$D/opencode.json")"
fi

# --- 5. a host file of the same name wins, byte for byte ---------------------
H1="$(host ownfile '{"model": "x"}')"
mkdir -p "$H1/.opencode/agents"
printf 'the host owns this agent\n' >"$H1/.opencode/agents/reviewer.md"
before="$(sha256sum "$H1/.opencode/agents/reviewer.md" | cut -d' ' -f1)"
run "$H1" --apply
after="$(sha256sum "$H1/.opencode/agents/reviewer.md" | cut -d' ' -f1)"
if [ "$before" = "$after" ] && [ ! -L "$H1/.opencode/agents/reviewer.md" ] &&
  grep -q 'reviewer.md' <<<"$(status opencode) reviewer.md" && grep -q 'reviewer.md' <<<"$RUN_OUT"; then
  ok "a host's own .opencode/agents/reviewer.md is left byte-identical and named in the report"
else
  no "the stage overwrote or did not report the host's reviewer.md (status: $(status opencode))"
fi
out="$(links_ok "$H1")"
rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = "    not a link into dist/opencode: $H1/.opencode/agents/reviewer.md" ]; then
  ok "the host file is the only file that is not a link, and every other one still is"
else
  no "the host file changed the wiring of the other files (rc=$rc): $out"
fi

# --- 6. a retired link is reported, then removed -----------------------------
S="$(host retired '{"model": "x"}')"
run "$S" --apply
ln -s "$ROOT/dist/opencode/commands/gone.md" "$S/.opencode/commands/gone.md"
run "$S" --check
if [ "$RC" -eq 1 ] && [ "$(status opencode)" = change ] && [ -L "$S/.opencode/commands/gone.md" ]; then
  ok "--check fails on a link to a file the kit no longer generates, and removes nothing"
else
  no "a retired link must fail --check (rc=$RC, status=$(status opencode))"
fi
run "$S" --apply
if [ ! -e "$S/.opencode/commands/gone.md" ] && [ ! -L "$S/.opencode/commands/gone.md" ]; then
  ok "--apply removes the retired link"
else
  no "--apply left the retired link in place"
fi
# The control: a stale link the kit did not write is none of its business.
ln -s /nonexistent/host-owned.md "$S/.opencode/commands/host-gone.md"
run "$S" --apply
if [ -L "$S/.opencode/commands/host-gone.md" ]; then
  ok "a broken link that does not point into the kit is never removed"
else
  no "the stage deleted a link it did not create"
fi

# --- 7. a missing link and a link pointing elsewhere are both drift ----------
M="$(host drift '{"model": "x"}')"
run "$M" --apply
rm "$M/.opencode/agents/reviewer.md"
run "$M" --check
if [ "$RC" -eq 1 ] && [ "$(status opencode)" = change ]; then
  ok "--check fails when an expected link is missing"
else
  no "a missing link must fail --check (rc=$RC, status=$(status opencode))"
fi
rm -f "$M/.opencode/commands/quality.md"
ln -s /etc/hostname "$M/.opencode/commands/quality.md"
run "$M" --check
if [ "$RC" -eq 1 ] && grep -q '2 missing or pointing elsewhere' <<<"$RUN_OUT"; then
  ok "--check names both the missing link and the one pointing elsewhere"
else
  no "--check should count 2 wrong links, got: $(grep -E '^\| opencode \|' <<<"$RUN_OUT")"
fi
run "$M" --apply
if out="$(links_ok "$M")"; then ok "--apply restores both links into dist/opencode"; else no "the links were not restored: $out"; fi
run "$M" --check
if [ "$RC" -eq 0 ]; then ok "the restored host passes --check again"; else no "restoring the links must clear --check, got rc=$RC"; fi

# --- 7b. a whole-directory link is reported, never written into --------------
# A host wired by the install README's three symlinks has a directory link, and
# linking a file "inside" one would create it in the kit's own tree.
W="$(host whole '{"model": "x"}')"
mkdir -p "$W/.opencode"
ln -s "$ROOT/dist/opencode/agents" "$W/.opencode/agents"
run "$W" --apply
if [ -L "$W/.opencode/agents" ] && [ "$(readlink "$W/.opencode/agents")" = "$ROOT/dist/opencode/agents" ]; then
  ok "a whole-directory link is left as it is, never replaced by per-file links"
else
  no "the stage replaced a whole-directory link with per-file links"
fi
if grep -q 'one-link-to-the-directory' <<<"$RUN_OUT" && grep -qE '^\| opencode \| (applied|ok) \|' <<<"$RUN_OUT"; then
  ok "the report names the one link instead of counting 11 agents"
else
  no "the report should name the directory link, got: $(grep -E '^\| opencode \|' <<<"$RUN_OUT")"
fi
# The control: the per-file links for the OTHER kind still appear, and the
# kit's dist is unchanged, so the case above is not "the stage did nothing".
if [ -L "$W/.opencode/commands/reviewer.md" ] || [ -L "$W/.opencode/commands/quality.md" ]; then
  ok "the other kind is still linked per file alongside a directory link"
else
  no "commands were not linked on a host with an agents directory link"
fi
if bash "$ROOT/tools/export.sh" --check opencode >/dev/null 2>&1; then
  ok "the kit's own dist/opencode is byte-identical afterwards (nothing was written into it)"
else
  no "the stage wrote into the kit's dist/opencode"
fi

# The control for the case above: a directory link whose target is gone IS
# retired, and the per-file links then appear, because there is no directory.
D2="$(host dead-dir '{"model": "x"}')"
mkdir -p "$D2/.opencode"
ln -s "$ROOT/dist/opencode/agents-gone" "$D2/.opencode/agents"
run "$D2" --apply
if [ -L "$D2/.opencode/agents/reviewer.md" ] && [ ! -L "$D2/.opencode/agents" ]; then
  ok "a dead directory link is dropped and the agents are linked one by one instead"
else
  no "a dead directory link should be dropped and the agents linked one by one"
fi
run "$D2" --check --only opencode
if [ "$RC" -eq 0 ]; then ok "the repaired host passes --check"; else no "the repaired host must pass --check, got rc=$RC: $(status opencode)"; fi

# --- 8. opencode.jsonc is reported, never silently skipped -------------------
C="$TMP/jsonc"
mkdir -p "$C"
rm -f "$C/opencode.json"
printf '{"skills": []}\n' >"$C/opencode.jsonc"
run "$C" --apply
if [ "$RC" -eq 2 ] && [ "$(status opencode)" = cannot ] && grep -q 'JSONC' <<<"$RUN_OUT"; then
  ok "opencode.jsonc is exit 2 and says why, not a silent skip"
else
  no "an opencode.jsonc host must be reported as cannot (rc=$RC, status=$(status opencode))"
fi
if [ -z "$(find "$C/.opencode" -mindepth 1 2>/dev/null)" ]; then
  ok "nothing is linked when the config is JSONC"
else
  no "the stage linked files into a host whose config it could not merge"
fi

# --- 9. a malformed opencode.json is exit 2, not an overwrite ---------------
B="$(host malformed 'not json')"
run "$B" --apply
if [ "$RC" -eq 2 ] && [ "$(status opencode)" = cannot ] && [ "$(cat "$B/opencode.json")" = "not json" ]; then
  ok "a malformed opencode.json is exit 2 and the host's bytes are untouched"
else
  no "a malformed opencode.json must be exit 2 with the file intact (rc=$RC)"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
