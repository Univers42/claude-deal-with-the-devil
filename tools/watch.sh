#!/usr/bin/env bash
# watch.sh — run a command under a watchdog so an agent never waits forever on a
# stuck process. Enforces BOTH a hard timeout and an idle timeout (no output for
# N seconds = likely stuck). Streams output live; reports why it stopped.
#
# Usage: watch.sh [--timeout S] [--idle S] -- <command> [args...]
#   --timeout S  hard cap on total runtime (default 300; 0 disables)
#   --idle S     kill if no output for S seconds — catches hangs (default 120; 0 disables)
#
# Exit: the command's own code on clean exit; 124 when the watchdog killed it.
# Ponytail: liveness is output-based — a genuinely silent long task needs a larger
# --idle (or --idle 0). Wrap builds/tests/installs/deploys; never an interactive REPL.
set -uo pipefail

HARD=300
IDLE=120
while [ $# -gt 0 ]; do
  case "$1" in
  --timeout)
    HARD="${2:-300}"
    shift 2
    ;;
  --idle)
    IDLE="${2:-120}"
    shift 2
    ;;
  --)
    shift
    break
    ;;
  -*)
    echo "watch.sh: unknown flag '$1'" >&2
    exit 2
    ;;
  *) break ;;
  esac
done
[ $# -ge 1 ] || {
  echo "usage: watch.sh [--timeout S] [--idle S] -- <command> [args...]" >&2
  exit 2
}

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
# New session so we can signal the whole process tree; exec so $! is the command.
setsid bash -c 'exec "$@"' _ "$@" >"$log" 2>&1 &
pid=$!
tail -n +1 -f --pid="$pid" "$log" 2>/dev/null & # live stream; GNU tail self-exits
tailpid=$!

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || date +%s; }
start=$(date +%s)
reason=""
while kill -0 "$pid" 2>/dev/null; do
  now=$(date +%s)
  if [ "$HARD" -gt 0 ] && [ $((now - start)) -ge "$HARD" ]; then
    reason="hard timeout ${HARD}s"
    break
  fi
  if [ "$IDLE" -gt 0 ] && [ $((now - $(mtime "$log"))) -ge "$IDLE" ]; then
    reason="idle ${IDLE}s — no output, likely stuck"
    break
  fi
  sleep 1
done

if [ -n "$reason" ]; then
  kill -TERM -- -"$pid" 2>/dev/null
  sleep 2
  kill -KILL -- -"$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  rc=124
else
  wait "$pid"
  rc=$?
fi
kill "$tailpid" 2>/dev/null
wait "$tailpid" 2>/dev/null

if [ -n "$reason" ]; then echo "watch.sh: KILLED — $reason" >&2; else echo "watch.sh: exit $rc" >&2; fi
exit "$rc"
