<!-- Copy into the HOST repo as docs/adr/NNNN-<slug>.md, numbered in the order taken. -->

# NNNN. <the decision, one imperative line>

- Status: <proposed | accepted | superseded by NNNN>
- Date: <YYYY-MM-DD>
- Deciders: <who ruled, and who has to live with it>

## Context

Facts only, each with a place to verify it. A claim without a location is a
hypothesis, and six months later the reader cannot tell the two apart.

- <fact> (`<file>:<line>`)
- <measured number>: <the command that produced it>
- Unknown when this was written: <what nobody had verified, or "none">

## Decision

<What is now true, in the present tense: "X is the thing we do". The decision, not
the process that produced it.>

## Alternatives considered

Each option loses for a reason a reader can check, not one that sounded good.

- **<option>**: <why it lost, with the file or the number behind it>
- **<option>**: <same>

## Consequences

- <what becomes true, and who is now on the hook for it>
- <what this makes harder, and the day you would reverse it>
- <the follow-up it creates, and where that is tracked>

<!-- Three-gate rule. Write an ADR only when at least one gate fires:
       1. the decision is irreversible (a deploy, a delete, a migration, a publish);
       2. it changes a public surface (a shipped API, a contract, a shared library);
       3. the `devil` returned a verdict other than PROCEED.
     Below all three the record is a commit message and a line in the handoff. -->
