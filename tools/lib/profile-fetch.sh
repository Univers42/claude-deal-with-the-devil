#!/usr/bin/env bash
# profile-fetch.sh — the two stages of tools/profile.sh that download: pinned tool
# binaries and vendored skills. Source it; never execute it. Every download is
# pinned (a sha256 for an archive, an exact version for a package manager, a
# commit for a skill) and verified before anything lands in ~/.local/bin or
# ~/.claude/skills.

# tool_ok <entry>: the tool answers its own check with the pinned version in it.
# Caveat: a substring match on the check's output: version "1.0" also matches a
# "11.0" build. `expect` overrides the string when a tool prints its version in
# another form (rust-analyzer prints a date that is not always the tag's).
tool_ok() {
  local check want out
  check="$(field "$1" check)"
  want="$(field "$1" expect)"
  [ -n "$want" ] || want="$(field "$1" version)"
  out="$(bash -c "$check" 2>/dev/null </dev/null)" || return 1
  [[ $out == *"$want"* ]]
}

# fetch_verified <url> <sha256>: the file, from the cache when it is already
# there, in FETCHED. A checksum mismatch deletes the download and fails.
fetch_verified() {
  local f="$HARNESS42_CACHE/dl/$2"
  mkdir -p "$HARNESS42_CACHE/dl"
  if [ ! -f "$f" ]; then
    curl -fsSL --retry 3 -o "$f.part" "$1" || {
      rm -f "$f.part"
      return 1
    }
    mv "$f.part" "$f"
  fi
  printf '%s  %s\n' "$2" "$f" | sha256sum -c --status || {
    printf 'profile.sh: checksum mismatch for %s, download deleted\n' "$1" >&2
    rm -f "$f"
    return 1
  }
  FETCHED="$f"
}

tool_install() {
  local e="$1" kind name member tmp rc=0 py
  kind="$(field "$e" kind)"
  name="$(field "$e" name)"
  mkdir -p "$HARNESS42_BIN"
  case "$kind" in
  tar | zip | gz)
    fetch_verified "$(field "$e" url)" "$(field "$e" sha256)" || return 1
    tmp="$(mktemp -d)"
    member="$(field "$e" member)"
    case "$kind" in
    tar) tar -xzf "$FETCHED" -C "$tmp" "$member" ;;
    zip) unzip -q -o "$FETCHED" "$member" -d "$tmp" ;;
    gz) member="$name" && gunzip -c "$FETCHED" >"$tmp/$name" ;;
    esac
    install -m 755 "$tmp/$member" "$HARNESS42_BIN/$name" || rc=1
    rm -rf "$tmp"
    return "$rc"
    ;;
  npm)
    # shellcheck disable=SC2046  # one argument per pinned package
    npm install -g --no-fund --no-audit --prefix "$(dirname "$HARNESS42_BIN")" \
      $(jq -r '.pkgs[]' <<<"$e")
    ;;
  go)
    local p
    for p in $(jq -r '.pkgs[]' <<<"$e"); do GOBIN="$HARNESS42_BIN" go install "$p" || return 1; done
    ;;
  uv)
    py="$(field "$e" python)"
    UV_TOOL_BIN_DIR="$HARNESS42_BIN" uv tool install --force ${py:+--python "$py"} \
      "$(jq -r '.pkgs[0]' <<<"$e")"
    ;;
  *)
    printf 'profile.sh: tool %s has unknown kind %s\n' "$name" "$kind" >&2
    return 1
    ;;
  esac
}

stage_tools() {
  local e name label n=0 ready=0
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    name="$(field "$e" name)"
    n=$((n + 1))
    if tool_ok "$e"; then
      ready=$((ready + 1))
      continue
    fi
    label="install $name $(field "$e" version) ($(field "$e" kind))"
    act "$label" tool_install "$e" || continue
    # An install that exits 0 but still fails its check is a failure too.
    if [ "$MODE" = apply ] && ! tool_ok "$e"; then FAILED+="$label"$'\n'; fi
  done < <(pq '.tools[]? | select(inpack)')
  note ok "$n tools, $ready already at their pinned version" "each tool's own check command"
}

# skill_source <repo>: an owner/name pair is GitHub, anything else is a git URL
# or a path git can clone as given.
skill_source() {
  if [[ $1 =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && [ ! -d "$1" ]; then
    printf 'https://github.com/%s.git' "$1"
  else
    printf '%s' "$1"
  fi
}

skill_vendor() {
  local e="$1" repo sha path dest cache tmp
  repo="$(field "$e" repo)"
  sha="$(field "$e" sha)"
  path="$(field "$e" path)"
  dest="$CLAUDE_HOME/skills/$(field "$e" name)"
  cache="$HARNESS42_CACHE/git/$(printf '%s' "$repo" | tr '/:' '__')"
  if [ ! -d "$cache" ]; then
    git clone -q --bare --filter=blob:none "$(skill_source "$repo")" "$cache" 2>/dev/null || return 1
  fi
  git -C "$cache" cat-file -e "$sha^{commit}" 2>/dev/null || git -C "$cache" fetch -q origin "$sha" || return 1
  tmp="$(mktemp -d)"
  if git -C "$cache" archive "$sha" "$path" | tar -x -C "$tmp" && [ -f "$tmp/$path/SKILL.md" ]; then
    printf '%s@%s:%s\n' "$repo" "$sha" "$path" >"$tmp/$path/.harness42"
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    mv "$tmp/$path" "$dest"
    rm -rf "$tmp"
    return 0
  fi
  rm -rf "$tmp"
  return 1
}

# A skill directory without our stamp is someone's own skill: it is never
# overwritten, the stage says so and exits 2 until a human renames one of them.
stage_skills() {
  local e name dest stamp n=0
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    name="$(field "$e" name)"
    dest="$CLAUDE_HOME/skills/$name"
    stamp="$(field "$e" repo)@$(field "$e" sha):$(field "$e" path)"
    n=$((n + 1))
    [ -f "$dest/.harness42" ] && [ "$(cat "$dest/.harness42")" = "$stamp" ] && continue
    if [ -d "$dest" ] && [ ! -f "$dest/.harness42" ]; then
      CHANGED+="skill $name: ~/.claude/skills/$name exists and is not vendored, left alone"$'\n'
      FAILED+="skill $name: ~/.claude/skills/$name exists and is not vendored, left alone"$'\n'
      continue
    fi
    act "vendor skill $name from $(field "$e" repo)@$(field "$e" sha | cut -c1-12)" skill_vendor "$e"
  done < <(pq '.skills[]? | select(inpack)')
  note ok "$n skills pinned by commit" "a .harness42 stamp in each"
}
