# Handoff: <repo> · <UTC timestamp>

Pointers, not copies: every line is a place to look or a command to re-run, because
a pasted excerpt goes stale the moment the file moves.

## Where the work is

- Repo: `<repo root>` · branch `<branch>` · HEAD `<short sha>` · tree `<git status>`

```text
<git log --oneline -10>
```

## What changed

- `<file:line>`: <what is there now, and why>

## Re-run these

- `devil quality --no-audit`: the gate; `<the project's own test command>`
- <measured number>: <the command that produced it>, or do not carry it at all
- Repo facts: `devil digest` re-derives toolchain, codemap and untested surface

## Decisions and open questions

- <decision>: <the reason in one line, and who decided it>
- <question>: <what would settle it>

## Suggested next

- <skill or tool name>: <why this one next>

## Return block

status: <done | blocked>
gates: <command → exit code, one per line>
changed: <files, moves and deletions included>
deviations: <what differs from the plan, and why>
next: <what the next session needs>
