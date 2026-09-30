---
description: Split a spec into vertical-slice tickets with blocking edges and publish them to the tracker. Usage: /devil:to-tickets <spec file or issue>
argument-hint: "<spec file | issue number>"
disable-model-invocation: true
metadata:
  kind: command
  stage: beta
  since: "1.0.0"
---

# To tickets

Spec: $ARGUMENTS

A spec is not a plan. Cutting it means finding the thin paths that cross the
whole system, one per ticket, so that each one lands on something a test can
check and the set has an order. A layer list ("first the schema, then the API,
then the UI") is the same work with the risk left at the end.

**This command publishes.** Step 4 is a gate the person opens: nothing reaches
the tracker before they approve the list, and a tracker write is visible to
everyone on the repo.

## 1. Read the spec

- A file path: read it whole, and any file it points at.
- An issue number: fetch it through the tracker adapter you will publish with
  (github: `gh issue view <n> --comments`; local: no issues exist, so say so and
  stop).
- No argument: ask which spec and stop.

Ground the read in facts rather than prose: `devil facts` for the build and test
commands the done-when has to cite, `devil digest` for the layers the slices
actually have to cross.

**If the spec has no done-when a test can check, stop here.** Say that the
done-when is missing, name the command that produces the missing half, and stop.
`/devil:prompt` is what writes that section; splitting a spec with no gate gives
every ticket a done-when nobody can run, which is the same as no done-when.

Caveat: a spec is a snapshot of an intent, not of the code. The done-when it
names can already pass, or can name a command this repo no longer has. Both are
findings, and both are worth saying before any ticket is written.

## 2. Read the tracker adapter

Read `<host>/.claude/devil/tracker.md`, the file the setup command writes into
the host. It is where the abstract verbs become commands: `create-ticket`,
`list-ready`, `close-ticket`.

**If it is absent, stop.** Say: this repo has no ticket tracker configured, so
run devil setup --apply first. Do not guess a tracker, and do not write tickets
anywhere: a slice published to the wrong place is a slice nobody finds.

Caveat: that file is a copy in a host repo, so it can be older than the kit, and
a person can have edited it. Read it as what that repo does, and when it names a
command you cannot run, report the gap in the Report rather than substituting
your own.

## 3. Cut vertical tracer-bullet slices

For each slice, write three things and nothing else:

- **Objective**: the end-to-end behaviour it makes work, in the user's terms.
- **Done-when**: one command a test can run. If you cannot name the command, the
  slice is not a slice yet: either it is too thick or its gate is unknown, and
  both are worth splitting further.
- **Blocking edges**: the tickets that cannot start until this one lands. Every
  edge has to be one this slice really gates; an edge nobody would wait for is
  noise that serialises the work for nothing.

The shape of a good slice:

- It cuts a narrow but complete path through every layer the change touches
  (schema, service, interface, tests). Vertical, not one layer of them.
- It is demoable or verifiable on its own, with nothing else landed first.
- It fits in one fresh context window: one writer, one pass, no half-day of
  context to hold in mind.
- Fewer and thinner beats more and fatter. Five tickets that each land green beat
  two that land once at the end.

The exception, and it is a real one: a wide mechanical refactor (rename a column,
retype a shared symbol) has a blast radius that fans across the codebase, so no
vertical slice of it can land green on its own. Do not force it into a tracer
bullet: sequence it as expand, migrate, contract. Expand adds the new form beside
the old; migrate moves the call sites in batches by package, each batch its own
ticket blocked by the expand; contract deletes the old form in a ticket blocked by
every batch. Each batch stays green because the old form still exists. If even the
batches cannot be green alone, keep the order anyway and say so: green is then
promised only at the end.

Put any prefactoring first, on its own, when the slices would otherwise all be
fighting the same code. "Make the change easy, then make the easy change" is a
ticket here, not a step hidden inside the first slice.

Caveat: "fits in one context window" is an estimate with no measurement behind it
here, and no ticket size is checkable from the spec alone. Treat it as the thing
to argue about in step 4, not as a rule already satisfied.

## 4. Show the list and wait

Print the proposed breakdown as a numbered list, one row per ticket:

| # | Objective | Done when | Blocked by |
|---|---|---|---|
| 1 | <end-to-end behaviour> | `<command>` | none |

Then print the order: which tickets can start now (no open blocker), and which
one each other waits for. Say how many tickets there are in total.

**Stop and wait for approval.** Ask, plainly:

- is the granularity right, too coarse or too fine?
- are the blocking edges real, does each ticket only wait on tickets that
  genuinely gate it?
- should any two be merged, or any one split further?

Publish only after the person says yes. A revision to the list is free; a
published ticket is a commit somebody else will act on.

## 5. Publish through the adapter

Publish in dependency order, blockers first, so every ticket's `Blocks:` line can
name a real identifier rather than a promise.

Each ticket body is `templates/ticket.md`, filled in: Objective, Done when,
Blocks, Seams, Notes. The body shape lives there and only there; the adapter
decides how the body is delivered.

Use the adapter's `create-ticket` verb, and nothing else:

- github: `gh issue create --title "<title>" --body "<body>" --label ready-for-agent`.
- local: write `.scratch/tickets/NNN-slug.md`, NNN the next free number.

Keep file paths and code out of the body. A path is stale the moment the code
moves, and a body that reads as an implementation list pulls the next writer back
into horizontal slicing. The one exception is a snippet that encodes a decision
more precisely than prose can (a state machine, a schema, a type shape), and then
say in Notes that it came from a spike.

Then publish **one map ticket**, in the same way, titled for the whole change. It
lists every ticket in order with its blockers, so the order survives the session:
the dependency graph is the thing a reader needs first and the ticket bodies each
repeat only their own edge.

Never close or edit the spec issue you read in step 1. It is the source, and the
map ticket is the index over the slices cut from it.

Caveat: publishing is several independent writes with no transaction, so a
ticket that fails mid-run leaves a partial set on the tracker. If a write fails,
stop, list which tickets exist and which do not, and say the run is incomplete
rather than retrying blindly into duplicates.

## Report

Print, in this order:

- Every published ticket: its id or its path, in dependency order.
- The map ticket's id or path, with the order it states.
- What was left out of the slices and why: work with no test-checkable gate, work
  the person declined, seams the spec names that no slice touches.
- Any step that could not run (an issue the adapter cannot fetch, a tracker
  command missing, a partial publish), with the exact error and what a person has
  to do by hand.

Then the return block:

```text
status: <done | blocked>
gates: <command → exit code, one per line>
changed: <files, or the ticket ids and paths published>
deviations: <what differs from the spec, and why>
next: <the frontier: which ticket can start now>
```
