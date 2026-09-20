---
paths:
  - "**/*.sh"
  - "**/*.bash"
  - "**/*.py"
  - "**/Makefile"
  - "**/makefile"
---

# Script library — check the registry before you write a script

`library-first` applied to tooling. Before writing a shell or Python utility, find out
whether it already exists. Most "quick scripts" are the fourth copy of something.

## The order to look

1. **The project's own scripts.** `.claude/tools/facts.sh` reports the make targets,
   npm scripts and task-runner entries that already exist. A repo almost always has a
   command for the thing you are about to script by hand.
2. **`.claude/tools/*.sh`.** The parsing and gate layer: `digest`, `facts`, `preflight`,
   `codemap`, `untested`, `dupes`, `quality`, `watch`, `selfcheck`, `context`,
   `ponytail`. Do not reimplement one of these badly.
3. **The registry.** `.claude/tools/scripts.sh list` — a vetted, version-pinned subset
   of an external library (valgrind wrappers, a comment stripper, C-norm helpers,
   header-cycle detection, markdown-to-PDF). `show <name>` gives the real arguments and
   exit codes.
4. **A one-liner.** `rg`, `jq`, `awk`, `find`. If a pipeline does it, write the
   pipeline, not a script (`rules/minimalism-ladder.md` rung 5).
5. **Only then write one** — and if it is a recurring check rather than a one-off, it
   belongs in `.claude/tools/` as a real tool, built by the `forger`.

## Using the registry

```sh
.claude/tools/scripts.sh list             # what is vetted
.claude/tools/scripts.sh show valgrind-check
.claude/tools/scripts.sh run valgrind-check -- src/ ./a.out
```

- **Only registry names run.** An unvetted script is refused, by design: nothing from
  upstream executes without a human having read it and recorded what it does.
- **The registry names the interpreter**, and `scripts.sh` uses it rather than the
  file's shebang. Upstream's shebangs are frequently absent or wrong; that is a
  property of the library, not a bug you need to work around.
- **Everything runs under `watch.sh`**, so nothing upstream can hang the session.
- **It is pinned to a sha.** A different sha is different code and the registry's
  claims no longer hold — re-verify after `sync --pin`.
- **Read the verification column.** Entries marked unverified were registered from
  reading the source, not from running it. Check their output before acting on it.

## If you write one anyway

- Shebang on **line 1**, before any header block. This is the single most common defect
  in the upstream library, and it means the script runs under the wrong shell.
- `set -euo pipefail` for a task script; `-uo pipefail` for a gate, where a non-zero
  result is data rather than an error. A sourced library sets nothing — it must not
  mutate the caller's shell options.
- `--help` that states the arguments and the exit codes, and misuse exits non-zero.
- Quote every expansion. Bound every loop and every network call.
- A destructive action is dry-run by default and `--apply` is opt-in — the way
  `strip-comments` does it.
- Then run `shellcheck` and `shfmt -d`.
