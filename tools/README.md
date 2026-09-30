# `tools/`: the parsing layer, run as `devil <tool>`

Scripts that pre-digest the repo so agents read conclusions, not raw trees. Run one
command, get structured facts; the cache means you don't re-parse each time. This is
the "read-by-query" discipline (`AGENTS.md`) made executable.

Every tool is run by name through `bin/devil`, from the directory it should describe:
`devil <tool> [args]` executes `tools/<tool>.sh`, `devil orch <sub> [args]` executes
`tools/orch/<sub>.sh` (or `tools/orch/<sub>` when that is the file, as for `timed`),
and a bare `devil` lists both. The dispatcher finds the kit from its own location,
through symlinks, never from the current directory. It returns the tool's exit code,
and 2 for a name it does not know. An enabled plugin has its `bin/` on the Bash tool's
`PATH`; elsewhere, call `bin/devil` by path.

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
| `setup.sh` | "What is this host still missing from the kit?" — seeds rules, permissions, CLAUDE.md, OpenCode wiring, tracker, gitignore | the host's `.claude/`, `opencode.json`, `.gitignore` |
| `release.sh` | "Is the version source honest, and can I cut a release?" (the version gate) | `.claude-plugin/*.json` + `CHANGELOG.md` |
| `skillcheck.sh` | "Is this config MANAGED?" (lifecycle, description form, resolving references) | `skills/`, `commands/`, agents, rules, every doc |
| `index.sh` | "Do the README tables and the router still match the frontmatter?" (the generated index) | the marked blocks of `README.md`, every skill and command |
| `export.sh` | "Has a harness's generated copy drifted from the Claude sources?" (exit 1 = drift) | `agents/`, `commands/`, `rules/`, `tools/lib/` vs `dist/<harness>/` |
| `context.sh` | "What does this config cost me every session?" | `rules/`, `skills/`, `commands/` (the `paths:` skills count as lazy) |
| `caveat.sh` | "Which approximations here don't admit they're approximations?" | every source file |
| `scripts.sh` | "Is there already a script for this?" | `scripts/REGISTRY.md` + a pinned external clone |
| `orch/` | "Delegate bulk work to headless OpenCode builders and check it" — launch, watch (`devil orch oc-status`), gate before merge | job journals under `<worktree>/target/wf/` — see `orch/README.md` |

## Use

```sh
devil digest                         # brief yourself first (cached)
devil digest --refresh               # rebuild after big changes
devil codemap                        # full queryable index
devil quality                        # the strict gate (exit 1 = a real failure)
devil quality --with-tests --no-audit
devil preflight                      # verify .env / secrets / toolchain before building
devil watch --idle 60 -- make build  # run anything without hanging (exit 124 = killed)

devil selfcheck                      # this config's own integrity (exit 1 = drift)
devil setup --check                  # is this host fully seeded? (exit 1 = a stage differs)
devil setup --apply                  # seed it: rules, permissions, CLAUDE.md, OpenCode, tracker
devil release --check                # one version source: plugin.json == changelog heading
devil release bump patch             # cut a release: edit, commit, tag, never push
devil skillcheck                     # skill and command management (exit 1 = a finding)
devil index --check                  # the README tables match the frontmatter (exit 1 = drift)
devil index --write                  # regenerate those tables from the frontmatter
devil index --router                 # the same tables, for /devil:guide
devil export opencode                # regenerate dist/opencode from the Claude sources
devil export --check opencode        # exit 1 if dist/opencode drifted (CI runs this)
devil export codex                   # regenerate dist/codex from the Claude sources
devil export --check codex           # exit 1 if dist/codex drifted (CI runs this)
devil context                        # always-on vs lazy bytes, per file
devil caveat --strict              # approximations with no stated limitation
devil scripts list                   # the vetted, sha-pinned external script library
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
  glue over it — the rule they enforce (`rules/library-first.md`). `setup.sh` keeps the
  same shape: argument parsing and the write helpers above, one `stage_<name>` function
  per stage in `lib/seed.sh`, and one code path so `--check` cannot disagree with
  `--apply`.
- **Cached + fingerprinted.** Output caches to the host's `.claude/cache/` (gitignored), keyed to
  `git HEAD` + dirty tree; a stale cache rebuilds itself.
- **Best-effort, honest.** Symbol / dup / coverage extraction is regex-heuristic (marked
  `caveat`), not an AST. It points you at the file; you read the file.
- **Setup never deletes.** `setup.sh` seeds what the plugin cannot ship into a host repo. It
  overwrites only the files it wrote (inside the markers of a CLAUDE.md block, and by content
  match elsewhere), and a `.gitignore` line is added at most once. A file you wrote is
  reported, never removed.

## Extending

Add a tool? Put shared logic in `lib/common.sh`, support `--summary` (so `digest.sh` can
compose it) and `--refresh`, emit markdown, cache via `emit_cached`. One concern per tool.
Register it in the table above and the root `README.md`; `devil <name>` finds it with no
further wiring.

Add a harness? Put its emitters in `lib/export-<harness>.sh` and one `case` arm in
`export.sh`. The Claude-format files stay canonical: the generator is the only place that
knows another dialect, and `--check` is what keeps the two from drifting. `opencode` is the
worked example; its install contract and its measured limits are in
`dist/opencode/README.md`.
