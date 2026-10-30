#!/usr/bin/env bash
# test_scan.sh — `devil scan` must refuse every target that is not an exact,
# allowlisted origin of ours. These are the devil's Z1 conditions (doc/PROFILE.md):
# the live tailnet host, a portless localhost, the kit's own service ports, a
# wildcard in the allowlist, a userinfo trick and active scanning are all refused.
# Only --dry-run runs here: no container, no network.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$ROOT/tools/scan.sh"
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
command -v jq >/dev/null 2>&1 || {
  echo "skip - jq is not installed"
  exit 0
}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HARNESS42_LOCAL="$TMP/local.json" HARNESS42_CACHE="$TMP/cache"
cat >"$HARNESS42_LOCAL" <<'JSON'
{ "scan": {
    "active": ["http://localhost:3001", "http://127.0.0.1:5678"],
    "passive": ["https://app.example.com:443"] } }
JSON

expect() { # expect <rc> <label> <args...>
  local want="$1" label="$2"
  shift 2
  bash "$SCAN" "$@" --dry-run >"$TMP/out" 2>&1
  local rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$label"; else no "$label (rc=$rc: $(head -1 "$TMP/out"))"; fi
}

expect 0 "an exact allowlisted origin is scanned" http://localhost:3001/
expect 0 "a path under an allowlisted origin is scanned" "http://LOCALHOST:3001/login?x=1"
expect 0 "a passive-list origin gets the baseline scan" https://app.example.com/
expect 2 "the live tailnet host is refused" https://baas.tail10f2ea.ts.net/
expect 2 "a portless localhost is refused (port 80 is not listed)" http://localhost/
expect 2 "a listed origin on a kit service port is refused" http://127.0.0.1:5678/
expect 2 "the Tor proxy port is refused" http://127.0.0.1:9052/
expect 2 "a userinfo trick is refused" http://localhost:3001@evil.example.com/
expect 2 "a non-http scheme is refused" file:///etc/passwd
expect 2 "an IPv6 literal is refused" "http://[::1]:3001/"
expect 2 "active scanning is refused" http://localhost:3001/ --full

bash "$SCAN" http://localhost:3001/ --dry-run >"$TMP/out" 2>&1
if grep -q 'zap-baseline.py' "$TMP/out" && grep -q 'HTTPS_PROXY=' "$TMP/out" && grep -q 'memory 1536m' "$TMP/out"; then
  ok "the container runs the baseline, with proxies cleared and a memory cap"
else
  no "the dry-run command lacks baseline / proxy reset / memory cap: $(cat "$TMP/out")"
fi

printf '{ "scan": { "active": ["https://*.tail10f2ea.ts.net:443"] } }\n' >"$HARNESS42_LOCAL"
expect 2 "a wildcard allowlist entry is refused" http://localhost:3001/
printf '{ "scan": { "active": ["http://localhost"] } }\n' >"$HARNESS42_LOCAL"
expect 2 "a portless allowlist entry is refused" http://localhost:80/
rm -f "$HARNESS42_LOCAL"
expect 2 "no overlay means nothing is allowlisted" http://localhost:3001/

echo
echo "test_scan: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
