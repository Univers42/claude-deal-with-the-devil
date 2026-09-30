# shellcheck shell=bash
# release-bump.sh — the bump half of tools/release.sh, sourced by it. Split out to
# keep release.sh under the 300-line limit; it reads PLUGIN, LOG, GITROOT and DIR from it.

# The next x.y.z: major resets minor and patch, minor resets patch.
# Caveat: string surgery on the semver core, so `1.0.0-rc.1` carries its
# suffix into the result and `1.0` yields an empty patch. The caller refuses a
# current version that is not a bare x.y.z before this runs.
next_version() {
  local v="$1" level="$2" a b c
  IFS=. read -r a b c <<<"$v"
  case "$level" in
  major) echo "$((a + 1)).0.0" ;;
  minor) echo "$a.$((b + 1)).0" ;;
  patch) echo "$a.$b.$((c + 1))" ;;
  esac
}

# Insert the release heading under `## [Unreleased]`; the accumulated bullets
# below it then belong to the new version, which is where they were written for.
open_release() {
  local tmp
  tmp="$(mktemp)"
  awk -v rel="## [$1] - $2" '
    { print }
    /^## \[Unreleased\]$/ && !seen { print ""; print rel; seen = 1 }
  ' "$LOG" >"$tmp" && mv "$tmp" "$LOG"
}

# Write the version into plugin.json. jq rewrites the file; the sed fallback only
# rewrites the value of a `version` key already on one line.
# Caveat: the sed fallback leaves the file byte-identical when the key is
# missing or the value spans lines, and its first-match-wins is wrong for a
# nested `version`. The caller re-reads the field and refuses to commit unless
# it round-trips, so a silent no-op fails the bump instead of shipping.
set_version() {
  local tmp
  tmp="$(mktemp)"
  if have jq; then
    jq --arg v "$2" '.version = $v' "$1" >"$tmp" || return 1
  else
    sed -E "s/(\"version\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"/\1\"$2\"/" "$1" >"$tmp" || return 1
  fi
  mv "$tmp" "$1"
}

bump() {
  local cur next when
  case "$1" in
  major | minor | patch) ;;
  *)
    echo "release.sh: bump needs major|minor|patch (got \`$1\`)" >&2
    return 2
    ;;
  esac
  preflight || return 2
  # The release commit carries plugin.json, the changelog and the re-exported dists.
  if [ -n "$(git -C "$GITROOT" status --porcelain 2>/dev/null)" ]; then
    echo "release.sh: dirty tree; commit or stash before cutting a release" >&2
    return 2
  fi
  cur="$(json_str "$PLUGIN" version)"
  if ! semver "$cur"; then
    echo "release.sh: plugin.json version \`$cur\` is not x.y.z; fix it by hand" >&2
    return 2
  fi
  if ! grep -qE '^## \[Unreleased\]' "$LOG"; then
    echo "release.sh: $LOG has no '## [Unreleased]' heading to open" >&2
    return 2
  fi
  next="$(next_version "$cur" "$1")"
  when="${RELEASE_DATE:-$(date -u +%F)}"
  set_version "$PLUGIN" "$next" || return 2
  if [ "$(json_str "$PLUGIN" version)" != "$next" ]; then
    echo "release.sh: could not write $next into $PLUGIN" >&2
    return 2
  fi
  open_release "$next" "$when"
  git -C "$GITROOT" add "$PLUGIN" "$LOG" || return 2
  restamp_dists || return 2
  git -C "$GITROOT" commit -q -m "chore(release): v$next" || return 2
  git -C "$GITROOT" tag "v$next" || return 2
  echo "cut v$next ($when) and tagged it. Push the branch and the tag by hand."
}

# Every generated manifest copies plugin.json's version (tools/export.sh), so the
# release commit re-exports each dist/<harness>/ or its `--check` gate goes red.
restamp_dists() {
  local d
  for d in "$GITROOT"/dist/*/; do
    [ -d "$d" ] && [ -f "$DIR/export.sh" ] || continue
    bash "$DIR/export.sh" "$(basename "$d")" >/dev/null || return 1
    git -C "$GITROOT" add "$d" || return 1
  done
}
