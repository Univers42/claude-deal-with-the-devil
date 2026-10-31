#!/usr/bin/env bash
# stage.sh — the stage runner tools/setup.sh and tools/profile.sh share: one
# code path for the dry run, `--check` and `--apply`, so a check never recomputes
# differently from the write. Source it; never execute it. The caller owns MODE
# (dry|check|apply), defines `selected <stage>` and one `stage_<name>` per stage,
# and starts with CHANGED="" DRIFT=0 CANNOT=0 ROWS="".
#
# A stage reports with note() (tools/lib/seed.sh, or its own) by setting
# ST_STATE / ST_NOTE, records every change it would make in CHANGED (via
# ensure(), append_line() or act()), and every change it could not make in FAILED.

# --- write helpers ----------------------------------------------------------

# ensure <path> <label>: the content arrives on stdin. 0 when the file did not
# match, 1 when it did. Writing is the only difference between the three modes,
# so it is the only thing this function branches on. Called from lib/seed.sh,
# which shellcheck does not read from here.
#
# Callers must REDIRECT (`< <(...)`), never pipe. In a pipeline this function
# runs in a subshell, the CHANGED it records is lost with it, and a stage that
# wrote nothing then reports ok. That is how a merge stage can look clean on a
# host it never touched.
# shellcheck disable=SC2317
# shellcheck disable=SC2329  # called from tools/lib/seed*.sh, which this file sources
ensure() {
  local path="$1" label="$2" tmp
  tmp="$(mktemp)" || return 1
  cat >"$tmp"
  chmod 644 "$tmp"
  if cmp -s "$tmp" "$path" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  CHANGED+="$label"$'\n'
  if [ "$MODE" = apply ]; then
    mkdir -p "$(dirname "$path")" && mv "$tmp" "$path"
  else
    rm -f "$tmp"
  fi
  return 0
}

# append_line <file> <line> <label>: 0 when the line was missing, 1 when it was
# already there, 2 when no temporary file could be made. It appends at the end,
# contiguously and with no separator: a .gitignore is a set of patterns, and the
# property that matters is that a line is added at most once, so a second apply
# finds all three and writes nothing. A file whose last line has no newline gets
# one, because `cat` alone would glue the new line onto it. It builds the new
# content and hands it to ensure(), so the three modes still have exactly one
# place that writes.
# shellcheck disable=SC2317
# shellcheck disable=SC2329  # called from tools/lib/seed*.sh, which this file sources
append_line() {
  local file="$1" line="$2" label="$3" tmp rc l
  if [ -f "$file" ] && grep -qxF -- "$line" "$file"; then return 1; fi
  tmp="$(mktemp)" || return 2
  {
    if [ -f "$file" ]; then
      while IFS= read -r l || [ -n "$l" ]; do printf '%s\n' "$l"; done <"$file"
    fi
    printf '%s\n' "$line"
  } >"$tmp"
  chmod 644 "$tmp"
  ensure "$file" "$label" <"$tmp"
  rc=$?
  rm -f "$tmp"
  return "$rc"
}

# act <label> <cmd> [args...]: the command-shaped twin of ensure(), for a change
# made by another tool (the `claude` CLI) rather than by writing a file. The
# label lands in CHANGED in every mode; only --apply runs the command, and a
# command that fails lands in FAILED, which makes the stage `cannot` (exit 2):
# a failed install is never reported as applied.
# shellcheck disable=SC2317,SC2329  # called from the stage libraries
act() {
  local label="$1"
  shift
  CHANGED+="$label"$'\n'
  [ "$MODE" = apply ] || return 0
  # One line per action as it starts: a long install is visibly alive (and
  # devil watch's idle timer sees output) instead of silent until its stage ends.
  printf '  ... %s\n' "$label"
  "$@" >>"${ACT_LOG:-/dev/null}" 2>&1 && return 0
  FAILED+="$label"$'\n'
  return 1
}

row() { ROWS+="$1	$2	$3"$'\n'; }

run_stage() {
  local name="$1" state
  CHANGED=""
  FAILED=""
  if ! selected "$name"; then
    row skip "$name" "not selected"
    return 0
  fi
  ST_NOTE=""
  ST_STATE=""
  "stage_$name"
  state="${ST_STATE:-ok}"
  # A stage that recorded a change is the definition of drift under --check and
  # the dry run, whatever its own read-back said before the write; under --apply
  # the same recording means it was applied. A stage that could not run keeps its
  # own verdict: exit 2, not "not applied".
  if [ -n "$FAILED" ]; then
    state=cannot
  elif [ -n "$CHANGED" ]; then
    if [ "$MODE" = apply ]; then
      state=applied
    elif [ "$state" != cannot ]; then
      state=change
    fi
  fi
  [ "$state" = change ] && DRIFT=$((DRIFT + 1))
  [ "$state" = cannot ] && CANNOT=$((CANNOT + 1))
  row "$state" "$name" "${ST_NOTE:-said nothing about what it did}"
  [ -z "$CHANGED" ] && return 0
  printf '%s' "$CHANGED" | while IFS= read -r label; do
    [ -z "$label" ] && continue
    if printf '%s' "$FAILED" | grep -qxF -- "$label"; then
      printf '                 - FAILED: %s\n' "$label"
    else
      printf '                 - %s\n' "$label"
    fi
  done
  return 0
}

# stage_report: the table every run ends with, then the exit code all three
# modes share: 2 when a stage could not run, 1 when --check found drift, else 0.
stage_report() {
  printf '\n| stage | status | note |\n|---|---|---|\n'
  printf '%s' "$ROWS" | while IFS='	' read -r st name note; do
    [ -n "${st:-}" ] || continue
    printf '| %s | %s | %s |\n' "$name" "$st" "${note//|/\\|}"
  done
  printf '\n**%s to change · %s could not run**\n\n' "$DRIFT" "$CANNOT"
  [ "$CANNOT" -gt 0 ] && return 2
  [ "$MODE" = check ] && [ "$DRIFT" -gt 0 ] && return 1
  return 0
}

# render_block <file> <block-file> <start> <end>: <file> with the text between
# the two marker lines replaced by <block-file>, or the marked block appended
# when the markers are absent. Everything outside the markers is kept verbatim,
# so a user's own CLAUDE.md survives any number of applies.
render_block() {
  awk -v s="$3" -v e="$4" -v blk="$2" '
    BEGIN { while ((getline line < blk) > 0) body = body line "\n"; close(blk) }
    !done && index($0, s) { printf "%s\n%s%s\n", s, body, e; done = 1; skip = 1; next }
    skip && index($0, e) { skip = 0; next }
    skip { next }
    { print }
    END { if (!done) { if (NR > 0) print ""; printf "%s\n%s%s\n", s, body, e } }
  ' "$1"
}
