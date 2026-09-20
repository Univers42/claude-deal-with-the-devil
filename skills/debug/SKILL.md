---
name: debug
description: >
  Find the actual cause of a failure instead of guessing at fixes. Reproduce, bisect to
  the smallest failing case, prove the mechanism, then fix once. Auto-triggers on:
  "why is this failing", "debug this", "this test is flaky", "it works locally",
  "fix this bug", "this crashes"
allowed-tools: Read, Grep, Glob, Bash
---

# Debug

The expensive failure mode is changing code until the symptom disappears. That does not
remove the bug; it moves it. You are done when you can **explain the mechanism** and
**turn the failure on and off on demand**.

## 1. Reproduce — a bug you cannot trigger, you cannot fix

- Get the exact command, input, and environment. Run it yourself under
  `.claude/tools/watch.sh` so a hang is killed with a reason (exit 124), not waited on.
- Record the real, complete error: the message, the stack, the exit code. Not a summary.
- **Cannot reproduce?** That is the finding. Say so and collect what is missing —
  version, platform, data, timing, concurrency. Do not "fix" an unreproduced bug.
- Flaky? Run it 20 times and report the rate (`3/20`). A rate is a fact; "sometimes" is
  not, and the rate is how you will know you fixed it.

## 2. Narrow — halve the search space, don't tour it

Pick the cheapest axis available and bisect it:

- **In time** — `git bisect run <cmd>` when it used to work. This is the single
  highest-value debugging tool and it is consistently the one skipped.
- **In input** — delete half the input; still fails? delete half again. Land on the
  smallest failing case and keep it, it becomes the test.
- **In code** — stub, short-circuit or comment out half the path. Which half keeps it?
- **In environment** — clean checkout, empty cache, the other machine, the CI container.

State what you eliminated at each step. Narrowing without recording the eliminations
means re-walking the same ground later.

## 3. Prove the mechanism

Form one hypothesis, phrased so it can be **wrong**: "X is null here because Y returns
early when the cache is cold." Then instrument to confirm or kill it.

- Print or log the actual values at the boundary — the input, the return, the state.
  Assumed values are where bugs hide; `rg` for the assignment rather than guessing.
- Reach for the real instrument when the cheap one stalls: a debugger and a watchpoint,
  `strace`/`dtruss`, `-fsanitize=address,undefined`, `valgrind`,
  `go test -race`, `RUST_BACKTRACE=1`, the browser console via the `browser-testing`
  skill for anything rendered.
- **A hypothesis you did not confirm is not the cause.** UNKNOWN = FAIL
  (`rules/prompt-contract.md`). If the evidence kills your hypothesis, say so and form
  the next one — do not fix the thing you happened to be looking at.

### The usual suspects, when you are stuck

Uninitialized or stale state · an off-by-one or an inverted condition · a silently
swallowed error · a race or an ordering assumption · an encoding, timezone or locale
difference · a cache serving something stale · a version skew between local and CI ·
a shared fixture mutated by another test · a resource never released.

## 4. Write the failing test first

Before the fix, turn the smallest failing case from step 2 into a test in the project's
framework (`.claude/tools/facts.sh` detects it; `rules/test-frameworks.md`). Run it and
**watch it fail for the right reason** — a test that passes before the fix is testing
something else.

This is the RED step of `agents/builder.md`; the fix is GREEN.

## 5. Fix the cause, once

- Fix the mechanism you proved, not the symptom you saw. If the cause is a class of
  bug, fix the class — one helper that escapes correctly beats twelve call sites
  (`rules/library-first.md`).
- Minimum change that makes the test pass (`rules/minimalism-ladder.md`). Do not
  refactor in the same commit.
- Touches anything irreversible, security-sensitive, schema-level or concurrent? Route
  the fix through the `devil` first (`rules/risk.md`).
- Then re-run the whole suite plus `.claude/tools/quality.sh` — a fix that breaks
  something else is not a fix.

## 6. Report

- **Symptom** — the exact error and the command that produced it.
- **Cause** — the mechanism, at `file:line`, in one sentence.
- **Evidence** — what proved it, and what you eliminated on the way.
- **Fix** — what changed and why that is the cause, not the symptom.
- **Proof** — the new test failing before and passing after, pasted. For a flake, the
  rate before and after (`3/20` → `0/20`).
- **Still unknown** — anything you could not explain, named rather than skipped.
