#!/usr/bin/env bash
# seed-tracker.sh: the tracker stage of tools/setup.sh, split out of
# lib/seed.sh. It moved rather than grew because seed.sh was already at the
# 300-line ceiling and a third adapter kind is not a reason to cross it.
# Source it after lib/seed.sh, never execute it: it uses that file's note() and
# setup.sh's ensure(), the same contract every stage has.

# --- tracker: which tracker the three abstract verbs map onto. `gh` installed
# with a github.com remote is a real signal; `glab` installed with a gitlab.com
# remote is the same signal for GitLab; anything else is local, which always
# works and never needs a network call.
# Caveat: the remote test greps `git remote -v` for the literal host, so a
# self-hosted GitLab, a GitHub Enterprise host, an SSH alias for either, or a
# repo whose remote is unreachable all read as local. Pass --tracker to say so.
# github is tested first, so a repo carrying both a github.com and a gitlab.com
# remote gets github. That ordering is a choice, not a detection result, and
# --tracker overrides it.

# _host_remotes <dir>: `git remote -v` for that repo, empty when it is not one.
# Empty is the direction every test below reads as "no signal", so a path that is
# not a git repo degrades to local rather than to an error.
_host_remotes() { git -C "$1" remote -v 2>/dev/null; }

# TRACKER_KIND / TRACKER_WHY: what detect_tracker decided and how it decided it.
# Globals, not a return value plus a global, because a single `echo` on stdout
# cannot carry both back through a command substitution without a subshell.
TRACKER_KIND=local
TRACKER_WHY=""

# detect_tracker: fill TRACKER_KIND and TRACKER_WHY from the CLI and the remote.
# Called in the caller's shell, never inside $( ): a subshell would set both and
# throw them away, which is the exact trap ensure() documents one file over.
# Caveat: `have` is `command -v`, so a `glab` on PATH that cannot authenticate, is
# a wrapper script, or belongs to a different account still counts as installed.
# Detection never runs the CLI: a tool that would fail only when it is actually
# used is not a signal worth failing a setup over.
detect_tracker() {
  local remotes
  remotes="$(_host_remotes "$HOST")"
  TRACKER_WHY="no gh with a github.com remote, no glab with a gitlab.com remote"
  if have gh && grep -q 'github\.com' <<<"$remotes"; then
    TRACKER_KIND=github
    TRACKER_WHY="gh installed, github.com remote"
  elif have glab && grep -q 'gitlab\.com' <<<"$remotes"; then
    TRACKER_KIND=gitlab
    TRACKER_WHY="glab installed, gitlab.com remote"
  else
    TRACKER_KIND=local
  fi
}

# stage_tracker: seed .claude/devil/tracker.md from the adapter that was chosen,
# whether --tracker named it or the CLI plus the remote decided.
# Caveat: the template is read once and written whole, so a host that edited its
# own tracker.md loses the edit on the next apply; the file is a copy of the
# kit's adapter, and the kit is where an adapter is edited.
stage_tracker() {
  local kind="$TRACKER" why
  if [ -z "$kind" ]; then
    detect_tracker
    kind="$TRACKER_KIND"
    why="$TRACKER_WHY"
  else
    why="--tracker $kind"
  fi
  # Reached for a --tracker value no template matches, and for a kit whose
  # templates/tracker/ lost a file: `cannot` is exit 2, not a silent fallback to
  # local, because seeding the wrong adapter writes a plausible wrong answer.
  if [ ! -f "$KIT/templates/tracker/$kind.md" ]; then
    note cannot "templates/tracker/$kind.md is missing" "no adapter for '$kind' in the kit"
    return 0
  fi
  ensure "$HOST/.claude/devil/tracker.md" "write .claude/devil/tracker.md" \
    <"$KIT/templates/tracker/$kind.md"
  note ok "ticket tracker: $kind" "$why"
  return 0
}
