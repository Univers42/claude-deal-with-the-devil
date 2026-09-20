#!/usr/bin/env bash
# facts.sh — the project's toolchain facts so the agent stops re-discovering
# how to build/test/lint every session. Caches to .claude/cache/facts.md.
#
# Usage: facts.sh [--summary] [--refresh]
#
# Ponytail: detection is manifest-presence plus target names, so it reports what
# a project *offers*, not what actually works — a listed make target can still be
# broken, and a monorepo with several manifests reports all of them without
# saying which one is yours. It fails silent rather than loud: a project whose
# build lives somewhere unconventional reports "no build manifest found", and
# that means "ask the user", not "there is no build".
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"

MODE=full
for a in "$@"; do
  case "$a" in
    --summary) MODE=summary ;;
    --refresh) export REFRESH=1 ;;
    *) echo "facts.sh: unknown arg '$a'" >&2; exit 2 ;;
  esac
done

_languages() {
  list_files | while read -r f; do is_code "$f" && lang_of "$f"; done | sort | uniq -c | sort -rn \
    | awk '{printf "%s(%s) ", $2, $1}'
}

_commands() {
  local root; root="$(repo_root)"
  if manifest Makefile || manifest makefile; then
    echo "- make targets: $(grep -hE '^[a-zA-Z0-9_.-]+:' "$root"/[Mm]akefile 2>/dev/null | cut -d: -f1 | sort -u | tr '\n' ' ')"
  fi
  if manifest package.json; then
    if have jq; then
      echo "- npm scripts: $(jq -r '.scripts // {} | keys | join(" ")' "$root/package.json" 2>/dev/null)"
    else
      echo "- npm scripts: (install jq to list; see package.json)"
    fi
  fi
  manifest go.mod      && echo "- go: go build ./... | go test ./... | go vet ./..."
  manifest Cargo.toml  && echo "- rust: cargo build | cargo test | cargo clippy"
  manifest Makefile || manifest go.mod || manifest Cargo.toml || manifest package.json \
    || echo "- (no build manifest found — ask the user how to build/test)"
}

_docker() {
  if manifest Dockerfile || manifest docker-compose.yml || manifest compose.yaml; then
    echo "- Docker present — prefer container lifecycle over host toolchains."
  fi
}

_entrypoints() {
  list_files | grep -iE '(^|/)(main\.(c|go|rs|py)|index\.(ts|js)|cmd/.*/main\.go)$' | head -10 \
    | sed 's/^/- /' || true
}

# Which strict gates exist here. Presence only — quality.sh runs them.
_quality_tools() {
  local present="" absent="" t
  for t in prettier eslint tsc gofmt golangci-lint cargo ruff shellcheck shfmt clang-format \
           cppcheck semgrep sonar-scanner npm govulncheck cargo-audit pip-audit osv-scanner trivy; do
    if have "$t"; then present="$present $t"; else absent="$absent $t"; fi
  done
  echo "- present:${present:- none}"
  echo "- absent (install to close gaps):${absent:- none}"
}

# Detected test framework(s), so the agent writes tests in the right one
# (see rules/test-frameworks.md). Subshell with errexit off — many probes miss.
_test_frameworks() (
  set +e
  local root out="" deps c f; root="$(repo_root)"
  seen() { grep -qiE "$2" "$1" 2>/dev/null && out="$out $3"; }
  if manifest go.mod; then
    seen "$root/go.mod" 'stretchr/testify' testify
    seen "$root/go.mod" 'onsi/ginkgo' ginkgo
    seen "$root/go.mod" 'go\.uber\.org/mock|golang/mock' gomock
    list_files | grep -q '_test\.go$' && out="$out go-test"
  fi
  if manifest Cargo.toml; then
    out="$out cargo-test"
    for c in proptest quickcheck criterion rstest insta mockall; do seen "$root/Cargo.toml" "(^|[^[:alnum:]])$c" "$c"; done
  fi
  if manifest package.json; then
    if have jq; then
      deps="$(jq -r '((.devDependencies//{})+(.dependencies//{}))|keys|join(" ")' "$root/package.json" 2>/dev/null)"
      for c in vitest jest mocha ava cypress fast-check; do case " $deps " in *" $c "*) out="$out $c";; esac; done
      case " $deps " in *" @playwright/test "*) out="$out playwright";; esac
    else
      seen "$root/package.json" '"vitest"' vitest; seen "$root/package.json" '"jest"' jest
      seen "$root/package.json" '@playwright/test' playwright; seen "$root/package.json" '"cypress"' cypress
    fi
  fi
  for f in pyproject.toml requirements.txt; do
    [ -f "$root/$f" ] && { seen "$root/$f" '\bpytest\b' pytest; seen "$root/$f" '\bhypothesis\b' hypothesis; seen "$root/$f" '\bnox\b' nox; }
  done
  [ -f "$root/conftest.py" ] && out="$out pytest"
  list_files | grep -q '\.bats$' && out="$out bats"
  if has_ext 'c|h|cc|cpp|hpp|cxx'; then
    local m; m="$(list_files | grep -iE '\.(c|h|cc|cpp|hpp|cxx)$' | sed "s#^#$root/#" | tr '\n' '\0' \
      | xargs -0 grep -hoiE 'gtest|catch2|catch\.hpp|doctest|criterion/criterion|unity\.h|cmocka' 2>/dev/null | tr 'A-Z' 'a-z' | sort -u)"
    case "$m" in *gtest*) out="$out gtest";; esac
    case "$m" in *catch*) out="$out catch2";; esac
    case "$m" in *doctest*) out="$out doctest";; esac
    case "$m" in *criterion*) out="$out criterion";; esac
    case "$m" in *unity*) out="$out unity";; esac
    case "$m" in *cmocka*) out="$out cmocka";; esac
  fi
  out="$(printf '%s' "$out" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')"
  [ -n "$out" ] && echo "${out% }" || echo "(none — pick the canonical default, see rules/test-frameworks.md)"
)

build_full() {
  echo "# Project facts"
  echo
  echo "Root: \`$(repo_root)\`"
  echo
  echo "## Languages"
  echo "$(_languages)"
  echo
  echo "## Build / test / lint"
  _commands
  _docker
  echo
  echo "## Entry points"
  local e; e="$(_entrypoints)"; [ -n "$e" ] && echo "$e" || echo "- (none matched the usual names)"
  echo
  echo "## Quality gates (run them: \`.claude/tools/quality.sh\`)"
  _quality_tools
  echo
  echo "## Test framework (detected — write tests in this one)"
  echo "- $(_test_frameworks)"
  echo
  echo "_Generated by \`.claude/tools/facts.sh\`. Re-run with \`--refresh\` after toolchain changes._"
}

build_summary() {
  echo "## Facts"
  echo "- langs: $(_languages)"
  _commands | sed 's/^- /- /'
  _docker
  echo "- tests: $(_test_frameworks)"
}

case "$MODE" in
  summary) emit_cached facts.summary.md build_summary ;;
  full)    emit_cached facts.md build_full ;;
esac
