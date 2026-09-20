# `.claude/tools/` — the parsing layer

Scripts that pre-digest the repo so agents read conclusions, not raw trees. Run one
command, get structured facts; the cache means you don't re-parse each time. This is
the "read-by-query" discipline (`AGENTS.md`) made executable.

## The tools

| Tool | Answers | Reads |
|---|---|---|
| `digest.sh` | "What am I working with?" — the start-of-task briefing | composes the summaries below |
| `facts.sh` | "How do I build/test/lint? Which gates and test frameworks exist?" | manifests, toolchain |
| `preflight.sh` | "Is the environment ready?" — `.env` / secrets / toolchain before building | manifests, `.env.example` |
| `codemap.sh` | "Where does X live? What's heavy? What's untested?" | every source file |
| `untested.sh` | "What needs a test before I touch it?" (the TDD worklist) | source vs tests |
| `dupes.sh` | "What should I extract into the library?" | repeated blocks |
| `quality.sh` | "Is it the highest quality — strictly?" (the gate) | every strict linter / SAST / audit |
| `watch.sh` | "Run this without ever hanging" — hard + idle timeouts around any command | wraps a command |
| `selfcheck.sh` | "Does this config tell the truth about itself?" (the drift gate) | every doc + every frontmatter block |
| `context.sh` | "What does this config cost me every session?" | `rules/`, `skills/`, `commands/`, `workflows/` |
| `ponytail.sh` | "Which approximations here don't admit they're approximations?" | every source file |
| `scripts.sh` | "Is there already a script for this?" | `scripts/REGISTRY.md` + a pinned external clone |

## Use

```sh
.claude/tools/digest.sh             # brief yourself first (cached)
.claude/tools/digest.sh --refresh   # rebuild after big changes
.claude/tools/codemap.sh            # full queryable index
.claude/tools/quality.sh            # the strict gate (exit 1 = a real failure)
.claude/tools/quality.sh --with-tests --no-audit
.claude/tools/preflight.sh          # verify .env / secrets / toolchain before building
.claude/tools/watch.sh --idle 60 -- make build   # run anything without hanging (exit 124 = killed)

.claude/tools/selfcheck.sh          # this config's own integrity (exit 1 = drift)
.claude/tools/context.sh            # always-on vs lazy bytes, per file
.claude/tools/ponytail.sh --strict  # approximations with no stated limitation
.claude/tools/scripts.sh list       # the vetted, sha-pinned external script library
```

## A sourced library sets nothing

`lib/common.sh` deliberately does **not** call `set -e`. It used to, which silently
re-enabled `errexit` on the four tools that had turned it off on purpose — `quality.sh`
says *"not -e: a failing gate is data, not a script error"* and got `-e` back on the next
line. The symptom was a gate exiting silently at the first `grep -q` that found nothing,
which is the *success* case for a negative check. Every tool declares its own options.

## How they're built

- **Pure `bash` + coreutils.** `rg` / `jq` used when present; degrade gracefully when not.
- **Library-first, dogfooded.** Shared logic lives in `lib/common.sh`; each tool is thin
  glue over it — the rule they enforce (`rules/library-first.md`).
- **Cached + fingerprinted.** Output caches to `.claude/cache/` (gitignored), keyed to
  `git HEAD` + dirty tree; a stale cache rebuilds itself.
- **Best-effort, honest.** Symbol / dup / coverage extraction is regex-heuristic (marked
  `ponytail`), not an AST. It points you at the file; you read the file.

## Extending

Add a tool? Put shared logic in `lib/common.sh`, support `--summary` (so `digest.sh` can
compose it) and `--refresh`, emit markdown, cache via `emit_cached`. One concern per tool.
Register it in the table above and the root `README.md`.
