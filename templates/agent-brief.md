<!-- The brief a subagent gets instead of your memory. Durable over precise: name
     contracts, not paths. A pasted copy goes stale; a `file:line` still resolves. -->

# Agent brief: <the one-line job>

## Objective

<One sentence, the outcome in the caller's terms. The list is what the agent does; this is what is true when it is done.>

## Contract

- **Inputs**: <what the agent may rely on existing, by contract>
- **Outputs**: <what it must produce, and where the caller will look for it>
- **Done when**: <the verifiable condition and the command that checks it>
- **Out of scope**: <what it must not touch, and the blast it does not own>

## Constraints

- The binding rules: <rules>, plus the house limits (<file and function size, line
  width, what is forbidden here).
- No git history operation and no co-authorship line unless this brief says so.
- A check you could not run is reported as SKIP, never as a pass.

## Facts

Pointers, not copies: a place to look, or a command to re-run.

- <fact>: `<file>:<line>` · re-check with <command>
- <measured number>: <the command that produced it, or do not carry it>
- Toolchain, codemap, untested surface: `devil digest` re-derives them

## Return block

Every job ends with this, verbatim, so a caller can grep it without reading a log.

status: <done | blocked>
gates: <command → exit code, one per line>
changed: <files, moves and deletions included>
deviations: <what differs from the brief, and why>
next: <what the next session needs>
