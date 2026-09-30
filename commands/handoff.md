---
description: Write a portable handoff document so a fresh session, or another harness, can continue the work. Usage: /devil:handoff
argument-hint: "[focus]"
disable-model-invocation: true
metadata:
  kind: command
  stage: beta
  since: "1.0.0"
---

# Handoff

Focus: $ARGUMENTS

Write the document the next session can act on without you. It is a list of pointers
and commands, never a copy of the work: a pasted excerpt is stale the moment the file
moves, and a stale pointer is worse than none because it looks trustworthy.

This command writes exactly one file and prints its path. It changes no other file.

## 1. Fix the target and the reader

- Repo: the git toplevel (`git rev-parse --show-toplevel`), branch (`git rev-parse
  --abbrev-ref HEAD`), HEAD (`git rev-parse --short HEAD`).
- Reader: a session that knows nothing about this work, or another harness. Anything
  you assume they have already read is a line you must write.
- $ARGUMENTS narrows the scope ("the migration", "the flaky test"); with none, cover
  everything in flight.

## 2. Collect pointers, not copies

- `file:line` for every place the work lives: the changed region, the test, the
  config, the decision it hangs on. Not the code, the address of the code.
- Last commits: `git log --oneline -10`, plus `git status --short` for the tree state.
- Commands to re-run: the project's own build and test commands from `devil facts`,
  the strict gate (`devil quality --no-audit`), and each command whose output you are
  about to quote.
- Repo facts: name `devil digest` as the way to get the toolchain, codemap and
  untested surface. Do not paste its output; it is cached and re-derivable, and a
  copy in the handoff is a copy that will be wrong.
- If a number matters (a measured latency, a test pass rate, a file count), it ships
  with the command that produced it, per `rules/prompt-contract.md`.

## 3. Record the decisions and the open questions

- Decisions: what was chosen, the one-line reason, and who chose it (a decision the
  user made is not a decision you may re-litigate next session).
- Open questions: what is still undecided or UNKNOWN, and what would settle it. Name
  them; a question hidden in prose is a question nobody answers.
- Verdict, if the devil gave one, and its conditions (`rules/risk.md`).

## 4. Redaction pass

- Names only, never values: the same rule `devil preflight` follows, which reports a
  variable as set or unset and prints no value.
- Strip: token and key material, `.env` and `env` output, connection strings, host
  and account identifiers, personal names, a credential pasted in a command, and any
  line of a log that carries one.
- Replace each with its name: `GITHUB_TOKEN (unset)`, not a truncated value. A
  truncated secret is still a leaked prefix.
- Caveat: this pass is a name-based read, not a scan. It misses a secret that does not
  look like one, a credential quoted in prose, and a value that was never named as a
  secret. It is a reason to read the draft once more, never a certificate, and the
  document leaves the machine on purpose.

## 5. Write it

- Fill `templates/handoff.md` from the kit root: `${CLAUDE_PLUGIN_ROOT}/templates/handoff.md`
  when the plugin is loaded, else the checkout holding `bin/devil` on `PATH`. If
  neither is reachable, write the same headings from the list in step 2.
- Path: `${TMPDIR:-/tmp}/devil-handoff-<repo>-<UTC timestamp>.md`, where `<repo>` is
  the toplevel's basename and the timestamp is `date -u +%Y%m%dT%H%M%SZ`. The
  timestamp is what keeps two handoffs in one day from overwriting each other.
- The document ends with the return block (`status`, `gates`, `changed`, `deviations`,
  `next`) and nothing after it: `devil orch oc-job` greps `status: done` out of the
  tail to decide whether a job landed.
- The `Suggested next` section names skills and tools only, never a command another
  person has to type for you: an asset with model invocation disabled is unreachable
  from a model, so naming one here is a dead step.

## Report

Print, in this order:

- The absolute path of the document, on its own line, so it can be copied.
- The return block, exactly as the document ends with it.
- The count of redactions made and anything you could not classify.

```text
status: <done | blocked>
gates: <command → exit code, one per line>
changed: <files, moves and deletions included>
deviations: <what differs from the plan, and why>
next: <what the next session needs>
```
