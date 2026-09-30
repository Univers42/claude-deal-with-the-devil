#!/usr/bin/env bash
# test_devil.sh - bin/devil must dispatch by name, never by the caller's cwd.
#
# Hosts cite `devil digest`, not a path, so the dispatcher is the one place a
# wrong root or a swallowed exit code would break every doc at once. Each case
# runs a fixture kit whose tools say where they ran and exit with a known code.
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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A kit with one tool per behaviour under test, plus the real dispatcher.
KIT="$TMP/kit"
mkdir -p "$KIT/bin" "$KIT/tools/orch" "$TMP/elsewhere" "$TMP/links"
cp "$ROOT/bin/devil" "$KIT/bin/devil"
printf '#!/usr/bin/env bash\nexit 7\n' >"$KIT/tools/fail.sh"
printf '#!/usr/bin/env bash\necho "cwd=$PWD args=$*"\n' >"$KIT/tools/where.sh"
printf '#!/usr/bin/env bash\nexit 5\n' >"$KIT/tools/orch/sub.sh"
printf '#!/usr/bin/env bash\necho "timed $*"\n' >"$KIT/tools/orch/bare"
printf '# not a subcommand\n' >"$KIT/tools/orch/README.md"
chmod +x "$KIT/bin/devil" "$KIT"/tools/*.sh "$KIT/tools/orch/sub.sh" "$KIT/tools/orch/bare"
DEVIL="$KIT/bin/devil"

# --- unknown names exit 2 with the reason on stderr -------------------------
for args in "nosuch" "orch nosuch" "../tools/fail" "orch ../sub"; do
  # shellcheck disable=SC2086  # word-splitting the case into argv is the point
  out="$("$DEVIL" $args 2>"$TMP/err")"
  rc=$?
  if [ "$rc" -eq 2 ] && [ -z "$out" ] && [ -s "$TMP/err" ]; then
    ok "devil $args exits 2, message on stderr"
  else no "devil $args: rc=$rc stdout='$out' stderr='$(cat "$TMP/err")'"; fi
done

# --- the tool's exit code and arguments reach the caller --------------------
"$DEVIL" fail >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 7 ]; then ok "a tool's exit 7 propagates"; else no "tool exit 7 came back as $rc"; fi
"$DEVIL" orch sub >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 5 ]; then ok "an orch tool's exit 5 propagates"; else no "orch exit 5 came back as $rc"; fi
got="$("$DEVIL" orch bare a b 2>&1)"
if [ "$got" = "timed a b" ]; then ok "devil orch <sub> runs an extensionless executable"; else
  no "devil orch bare printed '$got'"
fi

# --- a symlink from another directory still finds the kit -------------------
# The link sits in one directory and is called from another, the way a PATH
# entry is: the tool must run from the caller's cwd, found via the real file.
ln -s "$DEVIL" "$TMP/links/devil"
ln -s devil "$TMP/links/devil2"
want="cwd=$(cd "$TMP/elsewhere" && pwd) args=x y"
got="$(cd "$TMP/elsewhere" && ../links/devil2 where x y 2>&1)"
if [ "$got" = "$want" ]; then ok "a chained relative symlink resolves the kit; the tool keeps the caller's cwd"; else
  no "via symlink: want '$want', got '$got'"
fi

# --- bare devil lists every tool and orch subcommand of the real kit -------
listing="$(cd "$TMP/elsewhere" && "$ROOT/bin/devil")"
rc=$?
missing=""
for f in "$ROOT"/tools/*.sh; do
  name="$(basename "$f" .sh)"
  grep -qx "  $name" <<<"$listing" || missing+=" $name"
done
for f in "$ROOT"/tools/orch/*; do
  [ -f "$f" ] && [ -x "$f" ] || continue
  name="$(basename "$f" .sh)"
  grep -qx "  orch $name" <<<"$listing" || missing+=" orch:$name"
done
if [ "$rc" -eq 0 ] && [ -z "$missing" ]; then ok "bare devil lists every tools/*.sh and orch subcommand"; else
  no "bare devil (rc=$rc) is missing:$missing"
fi
if grep -q 'README' <<<"$listing"; then no "bare devil lists a non-executable README"; else
  ok "bare devil skips files that are not executables"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
