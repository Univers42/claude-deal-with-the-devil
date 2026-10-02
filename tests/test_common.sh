#!/usr/bin/env bash
# test_common.sh - the frontmatter and location helpers in tools/lib/common.sh.
#
# Every case proves both directions: the value a helper must read and the
# near-miss it must refuse (a top-level key that looks like a metadata one, a
# `True` that is not `true`, a command whose kind is not workflow). A helper
# that only ever returns something is not a parser, it is a guess.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/tools/lib/common.sh"
# shellcheck source=../tools/lib/common.sh
. "$LIB"
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
# is <case> <expected> <actual>
is() {
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (expected '$2', got '$3')"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# fm <name> <frontmatter body> -> path of a file carrying exactly that frontmatter
fm() {
  printf -- '---\n%s\n---\n\nBody\n' "$2" >"$TMP/$1.md"
  echo "$TMP/$1.md"
}

# in_kit <kit-root> <helper> [args] -> run a helper with claude_root() resolved
# to a copy of the library under <kit-root>, so asset_names sees the fixture.
in_kit() {
  local kit="$1"
  shift
  # shellcheck source=../tools/lib/common.sh
  (. "$kit/tools/lib/common.sh" && "$@")
}

# --- fm_meta ----------------------------------------------------------------
f="$(fm meta-map $'name: x\nmetadata:\n  stage: stable\n  since: "1.0.0"\n  extra:\n    stage: nested\nkind: command')"
is "fm_meta reads a key of the metadata map" stable "$(fm_meta "$f" stage)"
is "fm_meta strips matching quotes" 1.0.0 "$(fm_meta "$f" since)"
is "fm_meta ignores a top-level key after the map" "" "$(fm_meta "$f" kind)"
is "fm_meta is empty for a missing key" "" "$(fm_meta "$f" nope)"
f="$(fm meta-toplevel $'stage: stable\nname: x')"
is "fm_meta refuses a top-level key when there is no metadata map" "" "$(fm_meta "$f" stage)"
f="$(fm meta-scalar $'metadata: not-a-map\nstage: stable')"
is "fm_meta is empty when metadata: is a scalar" "" "$(fm_meta "$f" stage)"
f="$(fm meta-before $'stage: draft\nmetadata:\n  since: 1.0.0')"
is "fm_meta does not fall back to a top-level key before the map" "" "$(fm_meta "$f" stage)"

# --- fm_desc ----------------------------------------------------------------
want='a demo command. Usage: /demo'
scalar="$(fm desc-scalar "description: $want")"
folded="$(fm desc-folded $'description: >\n  a demo command.\n  Usage: /demo\nmodel: opus')"
is "fm_desc reads a scalar" "$want" "$(fm_desc "$scalar")"
is "fm_desc joins a folded > block with single spaces and stops at the next key" "$want" "$(fm_desc "$folded")"
if cmp -s <(fm_desc "$scalar") <(fm_desc "$folded"); then
  ok "fm_desc: folded and scalar are byte-identical"
else no "fm_desc: folded and scalar differ"; fi
f="$(fm desc-strip $'description: >-\n  a demo command.\n  Usage: /demo')"
is "fm_desc reads a >- block" "$want" "$(fm_desc "$f")"
f="$(fm desc-literal $'description: |\n  a demo command.\n  Usage: /demo\nmodel: opus')"
is "fm_desc puts a literal | block on one line" "$want" "$(fm_desc "$f")"
f="$(fm desc-quoted "description: \"$want\"")"
is "fm_desc strips the quotes of a quoted scalar" "$want" "$(fm_desc "$f")"
f="$(fm desc-none $'name: x\nmodel: opus')"
is "fm_desc prints nothing without a description" "" "$(fm_desc "$f")"
is "fm_desc emits zero bytes without a description" 0 "$(fm_desc "$f" | wc -c | tr -d ' ')"

# --- fm_flag ----------------------------------------------------------------
f="$(fm flag-true 'disable-model-invocation: true')"
if fm_flag "$f" disable-model-invocation; then ok "fm_flag: true is set"; else no "fm_flag: true should be set"; fi
f="$(fm flag-false 'disable-model-invocation: false')"
if fm_flag "$f" disable-model-invocation; then no "fm_flag: false should not be set"; else ok "fm_flag: false is not set"; fi
f="$(fm flag-absent 'name: x')"
if fm_flag "$f" disable-model-invocation; then no "fm_flag: absent should not be set"; else ok "fm_flag: absent is not set"; fi
f="$(fm flag-case 'disable-model-invocation: True')"
if fm_flag "$f" disable-model-invocation; then no "fm_flag: True should not be set (case-sensitive)"; else ok "fm_flag: True is not true"; fi
f="$(fm flag-nested $'metadata:\n  disable-model-invocation: true')"
if fm_flag "$f" disable-model-invocation; then no "fm_flag: a nested key is not the top-level flag"; else ok "fm_flag: a nested key is not the top-level flag"; fi

# --- fm_field keeps stripping quotes (it now shares the unquote step) --------
f="$(fm field-quotes $'model: "opus"\nname: \'demo\'  ')"
is "fm_field strips double quotes" opus "$(fm_field "$f" model)"
is "fm_field strips single quotes and trailing space" demo "$(fm_field "$f" name)"

# --- cache_dir --------------------------------------------------------------
# The kit copy lives OUTSIDE the host so the old and new locations differ.
KIT="$TMP/kit"
mkdir -p "$KIT/tools/lib" "$TMP/host/src" "$TMP/nogit"
cp "$LIB" "$KIT/tools/lib/common.sh"
git -C "$TMP/host" init -q
got="$(cd "$TMP/host/src" && in_kit "$KIT" cache_dir)"
is "cache_dir lives under the host repo's .claude" "$(cd "$TMP/host" && pwd -P)/.claude/cache" "$got"
if [ -d "$got" ]; then ok "cache_dir creates the directory"; else no "cache_dir did not create $got"; fi
if [ -e "$KIT/cache" ]; then no "cache_dir still lands next to the tools"; else ok "cache_dir no longer lands next to the tools"; fi
ceiling="$(cd "$TMP" && pwd -P)"
if got="$(cd "$TMP/nogit" && export GIT_CEILING_DIRECTORIES="$ceiling" && in_kit "$KIT" cache_dir)" && [ -d "$got" ]; then
  ok "cache_dir works outside git ($got)"
else no "cache_dir failed outside git"; fi

# --- asset_names ------------------------------------------------------------
mkdir -p "$KIT/bin" "$KIT/templates/skill" "$KIT/commands" "$KIT/workflows"
: >"$KIT/bin/cdwd"
: >"$KIT/bin/other"
: >"$KIT/templates/agent.md"
: >"$KIT/templates/skill/SKILL.md"
printf -- '---\ndescription: d\nmetadata:\n  kind: workflow\n---\n' >"$KIT/commands/harden.md"
printf -- '---\ndescription: d\nmetadata:\n  kind: command\n---\n' >"$KIT/commands/quality.md"
printf -- '---\ndescription: d\nkind: workflow\n---\n' >"$KIT/commands/toplevel.md"
printf -- '---\ndescription: d\n---\n' >"$KIT/workflows/legacy.md"
names() { in_kit "$KIT" asset_names "$1" | tr '\n' ' '; }
is "asset_names bin lists the files under bin/" "cdwd other " "$(names bin)"
is "asset_names templates lists files under templates/, nested too" "agent.md skill/SKILL.md " "$(names templates)"
is "asset_names workflows = commands tagged metadata.kind: workflow + legacy workflows/" "harden legacy " "$(names workflows)"
is "asset_names commands is unchanged by the tag" "harden quality toplevel " "$(names commands)"

# --- has_ext ----------------------------------------------------------------
# The bug was a flake, not a wrong answer: `grep -q` quits at the first match,
# `git ls-files` takes SIGPIPE, and under pipefail the pipeline reported "no such
# file" about one call in five. One call proves nothing, so ask 100 times.
misses=0
for _ in $(seq 1 100); do has_ext 'md' || misses=$((misses + 1)); done
is "has_ext finds a tracked .md on every one of 100 calls under pipefail" 0 "$misses"
is "has_ext refuses an extension nothing here carries" no "$(has_ext 'zzzz' && echo yes || echo no)"

# --- the real payload -------------------------------------------------------
bad=""
for f in "$ROOT"/commands/*.md "$ROOT"/skills/*/SKILL.md; do
  [ "$(fm_desc "$f" | wc -l | tr -d ' ')" = 1 ] || bad+=" ${f#"$ROOT"/}"
done
is "every invocable in this repo has a one-line readable description" "" "$bad"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
