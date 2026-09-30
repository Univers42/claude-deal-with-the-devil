#!/usr/bin/env bash
# test_setup_tracker.sh: the tracker stage of `devil setup` must seed the
# adapter it was told to seed, and detect one only when a CLI and the remote
# agree.
#
# Split out of tests/test_setup.sh, which was at the line ceiling. Detection is
# where the interesting failures live: a missing tool, a missing remote and a
# wrong host each read as "no signal", so a detector that always answered github
# would pass a test that only ever looked at github. Every case here therefore
# carries a negative control: the same fixture with the one thing changed that
# should flip the answer, or the assertion that proves the check can fail.
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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- PATH fixtures -----------------------------------------------------------
# A PATH holding the tools setup.sh needs and nothing else, so the only gh and the
# only glab are the stubs this file writes. Two of them: one with both, one
# without glab, so "no glab" is a property of the fixture and not of the machine
# the test happens to run on.
BIN_BOTH="$TMP/bin-both"
BIN_NOGLAB="$TMP/bin-noglab"
mkbin() {
  local d="$1" b p
  mkdir -p "$d"
  for b in bash env git grep sed awk cat cut head tail basename dirname \
    mktemp chmod mv mkdir rm cmp sha256sum shasum jq date printf; do
    p="$(command -v "$b" 2>/dev/null)" && ln -sf "$p" "$d/$b"
  done
}
# A stub that fails loudly if it ever runs: detection probes PATH and never
# executes the CLI, so a passing run proves it.
stub() {
  printf '#!/bin/sh\necho "%s stub must never be executed" >&2\nexit 1\n' "$1" >"$2/$1"
  chmod +x "$2/$1"
}
mkbin "$BIN_BOTH"
stub gh "$BIN_BOTH"
stub glab "$BIN_BOTH"
mkbin "$BIN_NOGLAB"
stub gh "$BIN_NOGLAB"

# --- host fixtures -----------------------------------------------------------
# host <remote>: a git repo with one origin remote, or none when <remote> is
# empty. Nothing else in it: `--only tracker` is what runs, so no other stage can
# make these fixtures pass or fail. mktemp, not a counter: the call happens in a
# command substitution, and a counter incremented inside one hands every fixture
# the same directory.
host() {
  local d
  d="$(mktemp -d "$TMP/host.XXXXXX")"
  git -C "$d" init -q
  [ -n "$1" ] && git -C "$d" remote add origin "$1"
  echo "$d"
}

RC=0
RUN_OUT=""
# run <bin> <host> [args...]: setup.sh under that PATH, tracker stage only. env -i
# so a real gh or glab cannot leak into the answer; HOME is kept because git
# wants it.
run() {
  local bin="$1" h="$2"
  shift 2
  RUN_OUT="$(env -i PATH="$bin" HOME="$HOME" bash "$SETUP" --host "$h" --only tracker "$@" 2>&1)"
  RC=$?
}
# kind <host>: the first line of the adapter setup.sh seeded there.
kind() { head -1 "$1/.claude/devil/tracker.md" 2>/dev/null; }
# status <stage>: that stage's status word in the last run.
status() {
  grep -E "^\| $1 \|" <<<"$RUN_OUT" | awk -F'|' '{gsub(/ /, "", $3); print $3}'
}

# --- 1. --tracker gitlab seeds the gitlab adapter -----------------------------
G="$(host '')"
run "$BIN_NOGLAB" "$G" --apply --tracker gitlab
if [ "$RC" -eq 0 ] && grep -qi gitlab <<<"$(kind "$G")"; then
  ok "--tracker gitlab seeds the GitLab adapter"
else
  no "--tracker gitlab must exit 0 and seed the GitLab adapter, got rc=$RC, '$(kind "$G")'"
fi
if grep -q 'glab issue create' "$G/.claude/devil/tracker.md" &&
  grep -q -- '--label ready-for-agent' "$G/.claude/devil/tracker.md" &&
  grep -q 'templates/ticket.md' "$G/.claude/devil/tracker.md"; then
  ok "the GitLab adapter names its create command, the label and the body template"
else
  no "the GitLab adapter is missing its command, its label or templates/ticket.md"
fi
run "$BIN_NOGLAB" "$G" --check --tracker gitlab
if [ "$RC" -eq 0 ] && [ "$(status tracker)" = ok ]; then ok "a host seeded with --tracker gitlab passes --check with the same flag"; else
  no "the gitlab adapter must satisfy --check, got rc=$RC ($(status tracker))"
fi
# The control for the three lines above: another adapter on the same host is a
# different file, so those assertions were reading gitlab.md and not a leftover.
run "$BIN_NOGLAB" "$G" --apply --tracker github
if ! cmp -s "$G/.claude/devil/tracker.md" "$ROOT/templates/tracker/gitlab.md"; then
  ok "--tracker github rewrites the file, so --tracker gitlab wrote one of its own"
else
  no "the tracker file still holds gitlab.md after --tracker github"
fi

# --- 2. a missing adapter is exit 2, not a silent fallback --------------------
# The negative control for case 1: a kit whose templates/tracker/ lost gitlab.md.
# Only the files setup.sh reads are copied, so the fixture stays honest about what
# it takes to make the stage run at all.
FAKEKIT="$TMP/kit"
mkdir -p "$FAKEKIT/tools/lib" "$FAKEKIT/.claude-plugin" "$FAKEKIT/rules" "$FAKEKIT/templates/tracker"
cp "$ROOT/tools/setup.sh" "$FAKEKIT/tools/"
cp "$ROOT/tools/lib/common.sh" "$ROOT/tools/lib/seed.sh" "$ROOT/tools/lib/seed-tracker.sh" \
  "$FAKEKIT/tools/lib/"
cp "$ROOT/.claude-plugin/plugin.json" "$FAKEKIT/.claude-plugin/"
cp "$ROOT/templates/settings.json" "$FAKEKIT/templates/"
cp "$ROOT/templates/tracker/github.md" "$ROOT/templates/tracker/local.md" \
  "$FAKEKIT/templates/tracker/"
K="$(host '')"
run_fake() {
  RUN_OUT="$(env -i PATH="$BIN_NOGLAB" HOME="$HOME" bash "$FAKEKIT/tools/setup.sh" --host "$K" "$@" 2>&1)"
  RC=$?
}
run_fake --apply --tracker gitlab
if [ "$RC" -eq 2 ] && [ "$(status tracker)" = cannot ] && [ ! -e "$K/.claude/devil/tracker.md" ]; then
  ok "a kit with no templates/tracker/gitlab.md is exit 2 and seeds nothing"
else
  no "a missing adapter must be exit 2 with no file written, got rc=$RC: $(status tracker)"
fi
run_fake --apply --tracker github
if [ "$RC" -eq 0 ] && grep -qi github <<<"$(kind "$K")"; then
  ok "the same fixture seeds github, so the failure above was the missing file"
else
  no "the fixture without gitlab.md should still seed github, got rc=$RC"
fi

# --- 3. glab plus a gitlab.com remote detects gitlab --------------------------
L="$(host 'git@gitlab.com:example/host.git')"
run "$BIN_BOTH" "$L" --apply
if grep -qi gitlab <<<"$(kind "$L")"; then ok "a glab and a gitlab.com remote detect the GitLab adapter"; else
  no "a glab and a gitlab.com remote must detect GitLab, got '$(kind "$L")'"
fi
if grep -q 'glab installed, gitlab.com remote' <<<"$RUN_OUT"; then
  ok "the detection row says which signal it saw"
else
  no "the tracker row must report why gitlab was chosen: $(status tracker)"
fi
# The control: same PATH, same stage, no remote at all.
N0="$(host '')"
run "$BIN_BOTH" "$N0" --apply
if grep -qi local <<<"$(kind "$N0")"; then ok "the same glab on PATH with no remote gives local"; else
  no "no remote must give local, got '$(kind "$N0")'"
fi

# --- 4. the remote without glab is local (the control for case 3) ------------
NOG="$(host 'git@gitlab.com:example/host.git')"
run "$BIN_NOGLAB" "$NOG" --apply
if grep -qi local <<<"$(kind "$NOG")"; then ok "a gitlab.com remote with no glab gives local"; else
  no "a gitlab.com remote with no glab must give local, got '$(kind "$NOG")'"
fi
if cmp -s "$NOG/.claude/devil/tracker.md" "$ROOT/templates/tracker/local.md"; then
  ok "the no-glab host holds templates/tracker/local.md byte for byte"
else
  no "the no-glab host must hold the local adapter, byte for byte"
fi
SELF="$(host 'git@gitlab.example.org:example/host.git')"
run "$BIN_BOTH" "$SELF" --apply
if grep -qi local <<<"$(kind "$SELF")"; then
  ok "a self-hosted GitLab remote reads as local, which is what the Caveat says"
else
  no "a self-hosted GitLab remote must read as local, got '$(kind "$SELF")'"
fi

# --- 5. github still wins, and wins for a reason -----------------------------
BOTH="$(host 'git@github.com:example/host.git')"
git -C "$BOTH" remote add mirror 'https://gitlab.com/example/host.git'
run "$BIN_BOTH" "$BOTH" --apply
if grep -qi github <<<"$(kind "$BOTH")"; then
  ok "a github.com remote with both stubs present still selects github"
else
  no "both remotes must select github, got '$(kind "$BOTH")'"
fi
if git -C "$BOTH" remote -v | grep -q 'gitlab\.com' &&
  grep -q 'gh installed, github.com remote' <<<"$RUN_OUT"; then
  ok "the gitlab remote really was there, so github won on the rule and not on luck"
else
  no "the github row must report the gh + github.com signal with both remotes present"
fi
# The control: drop the github remote from that same fixture and the answer flips,
# so the case above came from the remote and not from gh merely existing.
git -C "$BOTH" remote remove origin
run "$BIN_BOTH" "$BOTH" --apply
if grep -qi gitlab <<<"$(kind "$BOTH")"; then ok "the same fixture without the github remote selects gitlab"; else
  no "removing the github remote must select gitlab, got '$(kind "$BOTH")'"
fi

# --- 6. an unknown tracker is bad usage --------------------------------------
U="$(host '')"
run "$BIN_BOTH" "$U" --apply --tracker bogus
if [ "$RC" -eq 2 ] && grep -q -- '--tracker takes github, gitlab or local' <<<"$RUN_OUT"; then
  ok "--tracker bogus is exit 2 and names the three kinds"
else
  no "--tracker bogus must be exit 2 naming the valid kinds, got rc=$RC"
fi
# The control: the exit 2 above is about the value, not about the run failing.
run "$BIN_BOTH" "$U" --apply --tracker=gitlab
if [ "$RC" -eq 0 ]; then ok "--tracker=gitlab (the = form) is accepted"; else
  no "--tracker=gitlab must be accepted, got rc=$RC"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
