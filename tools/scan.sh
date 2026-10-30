#!/usr/bin/env bash
# scan.sh — white-hat web scan of OUR OWN app, refused for anything else.
#
# Runs ZAP's baseline scan (spider + passive rules: it reads responses, it sends
# no attack payloads) in a pinned, throwaway container, against a target that
# must match an exact `scheme://host:port` entry of the private overlay
# (~/.config/harness42/local.json, `.scan.active` or `.scan.passive`). Active
# scanning (`--full`) is refused: the devil's verdict of 2026-10-30 blocked it
# until the exact-allowlist test below is proven and re-submitted (doc/PROFILE.md).
#
# Usage: scan.sh <url> [--dry-run]
#   --dry-run  print the docker command instead of running it
# Exit: 0 scan ran (findings are in the report, not the exit code) · 2 refused
# (target not allowlisted, malformed URL or allowlist, a reserved port, --full).
#
# Caveat: the allowlist matches a URL's scheme, host and port as typed, not the
# address the host resolves to. A listed name that DNS points at someone else's
# machine is scanned anyway; list `127.0.0.1` / staging names you control. The
# container uses the host network so localhost targets are reachable, which also
# means it can reach anything this machine can: the allowlist is the boundary.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"

# ZAP `stable` as of 2026-10-30, pinned by digest so a scan is reproducible.
ZAP_IMAGE="${HARNESS42_ZAP_IMAGE:-ghcr.io/zaproxy/zaproxy@sha256:030d3df57735dacbb83464854758e674dd9ad01d79d12a129a8e58b1fd384238}"
# The kit's own local services and the Tor proxy: never a scan target, listed or not.
RESERVED_PORTS=" 5678 37777 6767 8282 9050 9052 "
LOCAL_FILE="${HARNESS42_LOCAL:-${XDG_CONFIG_HOME:-$HOME/.config}/harness42/local.json}"

refuse() {
  printf 'scan.sh: refused: %s\n' "$*" >&2
  exit 2
}

# origin_of <url>: `scheme://host:port`, lower-cased, the default port made
# explicit; empty for anything that is not a plain http(s) URL. A userinfo part
# (`http://ours@theirs`) or an IPv6 literal is rejected rather than parsed.
origin_of() {
  local u="$1" scheme rest auth host port
  [[ $u =~ ^([A-Za-z]+)://(.*)$ ]] || return 1
  scheme="${BASH_REMATCH[1],,}"
  rest="${BASH_REMATCH[2]}"
  auth="${rest%%[/?#]*}"
  case "$scheme" in http | https) ;; *) return 1 ;; esac
  case "$auth" in *@* | *\[* | *\]* | "") return 1 ;; esac
  host="${auth%%:*}"
  port="${auth#"$host"}"
  port="${port#:}"
  [[ $host =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  if [ -z "$port" ]; then
    [ "$scheme" = https ] && port=443 || port=80
  fi
  [[ $port =~ ^[0-9]+$ ]] || return 1
  printf '%s://%s:%s' "$scheme" "${host,,}" "$port"
}

TARGET=""
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
  --dry-run) DRY=1 ;;
  --full) refuse "active scanning is blocked by the devil's verdict (doc/PROFILE.md, ZAP item)" ;;
  -h | --help)
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  -*) refuse "unknown option $1" ;;
  *) TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || refuse "no target URL given"
have jq || refuse "jq is not installed; the allowlist cannot be read"
[ -f "$LOCAL_FILE" ] || refuse "no overlay at $LOCAL_FILE, so nothing is allowlisted"

origin="$(origin_of "$TARGET")" || refuse "'$TARGET' is not a plain http(s) URL with a host"
port="${origin##*:}"
case "$RESERVED_PORTS" in *" $port "*) refuse "port $port belongs to a local service of this kit" ;; esac

# Every allowlist entry must itself be an exact origin with an explicit port.
entries="$(jq -r '(.scan.active // []) + (.scan.passive // []) | .[]' "$LOCAL_FILE" 2>/dev/null)" ||
  refuse "the overlay's scan lists are not valid JSON"
match=0
while IFS= read -r e; do
  [ -n "$e" ] || continue
  [[ $e =~ ^https?://[A-Za-z0-9.-]+:[0-9]+$ ]] ||
    refuse "allowlist entry '$e' is not an exact scheme://host:port (no wildcards, no paths, port required)"
  [ "$(origin_of "$e")" = "$origin" ] && match=1
done <<<"$entries"
[ "$match" = 1 ] || refuse "$origin is not in the scan allowlist of $LOCAL_FILE"

out="${HARNESS42_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/harness42}/scans/$(printf '%s' "$origin" | tr ':/' '__')-$(date +%Y%m%dT%H%M%S)"
cmd=(docker run --rm --network host --memory 1536m
  -e HTTP_PROXY= -e HTTPS_PROXY= -e http_proxy= -e https_proxy= -e ALL_PROXY= -e all_proxy=
  -v "$out:/zap/wrk:rw" "$ZAP_IMAGE"
  zap-baseline.py -t "$TARGET" -J report.json -r report.html -w report.md -I)
if [ "$DRY" = 1 ]; then
  printf '%q ' "${cmd[@]}"
  printf '\n'
  exit 0
fi
have docker || refuse "docker is not installed"
mkdir -p "$out" && chmod 777 "$out" # the ZAP image writes as its own uid
"${cmd[@]}"
rc=$?
printf '\nreport: %s/report.html\n' "$out"
[ -f "$out/report.json" ] && jq -r '[.site[]?.alerts[]? | .riskdesc | split(" ")[0]] |
  group_by(.) | map("\(.[0]): \(length)") | join(" · ") | "findings: " + (if . == "" then "none" else . end)' \
  "$out/report.json"
# zap-baseline exits 1/2 for warnings/failures it found: those are findings, not a failed run.
[ "$rc" -le 2 ] && exit 0
exit "$rc"
