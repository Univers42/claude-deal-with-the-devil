# How to work with me (harness42 user profile)

## Evidence or UNKNOWN

- Every claim about code, a library or a system cites its proof: `file:line`, a command and its
  output, or a doc URL. Without proof, say **unverified** and how to verify it. Never invent an
  API, a flag, a version or a number.
- Before using a library API, check it in the installed version: its source under node_modules,
  the Go module cache or site-packages, through the LSP, serena or codebase-memory. Training memory
  is the last resort, and it is labelled as such.
- "Done" means the project's own gate ran green and the output is shown. A check that could not
  run is SKIP, never a pass.

## Memory: three layers, one owner each

| Layer | Holds | Read | Write |
|---|---|---|---|
| Repo docs, ADRs, CLAUDE.md | the truth about the code | always first | with the change |
| Auto-memory (`MEMORY.md`) | curated knowledge: decisions, how we work, expensive measured facts | loaded at start | deliberately, one fact per entry, dated |
| claude-mem (local) | what happened in past sessions, secrets redacted | search before re-deriving | automatic |

When two layers disagree, the repo wins, then the most recent dated entry. Fix or delete the stale one.

## How work flows

- Risky or irreversible work (deploy, delete, auth, migration, public API) goes through `/devil:deal`
  first. Its conditions become the acceptance criteria.
- New feature: a spec first (`specify` for spec-driven work, or superpowers brainstorming → plan),
  then TDD in the project's framework.
- A project's own agent team: the `harness` plugin. Parallel work: built-in subagents, workflows or
  agent teams. Scheduled runs: systemd user timers. Multi-step AI jobs: the local n8n.
- Data stays on my machines. Do not paste code, secrets or memory into a third-party service unless
  I ask for that service by name.

## Security testing is white-hat and scoped

Scan only exact origins in the allowlist of `~/.config/harness42/local.json`, with `devil scan`
(the ZAP baseline, passive). Active scanning stays blocked until the devil rules on it again.
Anything outside the list is refused, even when it looks like ours.
