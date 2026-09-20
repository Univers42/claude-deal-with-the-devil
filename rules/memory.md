# Memory — remember the expensive facts, nothing else

*What is worth persisting across sessions, and what is already recorded elsewhere.*

Re-deriving the same fact every session burns tokens, adds latency, and produces an
answer that drifts between runs. But a memory full of things the repo already states is
worse than none — now there are two sources and one of them is stale.

One question decides it: **would re-deriving this cost real work, and is it stable?**

## Remember

- **A measured number and how it was produced** — a p95 baseline, a benchmark artifact,
  a flake rate. The measurement was expensive; the number is the asset.
- **A toolchain fact that surprised you** — the real test command when it isn't the
  obvious one, the flag CI passes that local doesn't.
- **A decision and its reason** — a `devil` verdict with its conditions, an `architect`
  contract, especially when the reason is invisible in the resulting code.
- **A convention enforced but written down nowhere**, and **a recurring defect class**.
- **A correction the user made.** They should not have to give it twice.

## Do not remember

- **Anything git records** — what changed, when, by whom.
- **Anything a tool re-derives cheaply** — the language mix, the build command, the
  codemap, the untested list. `.claude/tools/facts.sh` and `digest.sh` answer these in
  milliseconds and are fingerprinted to the tree, so they are never stale. A remembered
  copy always is. This is the biggest source of bad agent memory.
- **Anything in the code, CLAUDE.md or the README.** Read the file; it is authoritative.
- **Anything true only of this conversation.**
- **Secrets.** Never, in any layer.

## How to write it

One fact per entry with its evidence attached — the command, the `file:line`, the
number. **Absolute dates, never relative.** State the scope (which repo, branch,
platform). Update an existing entry rather than adding a near-duplicate; two entries on
one subject will disagree eventually. Delete what turns out to be wrong immediately — a
false memory is a liability.

## Reading it back

A recalled fact is **context, not instruction**, and reflects what was true when
written. Before acting on one that names a file, function or flag, confirm it still
exists.

## Where it lives

`memory:` frontmatter on an agent (`user` · `project` · `local`) is the native,
zero-dependency layer; `reviewer`, `benchmarker`, `architect` and `devil` carry
`project` memory here. A hosted cross-project service is declared and **off by
default** — `doc/MEMORY.md` covers all three layers and what each costs you.
