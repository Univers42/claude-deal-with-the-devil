---
description: >
  Take an existing module from "it works" to "it holds" — cover it, attack it, bound it,
  then gate it. Usage: /workflow:harden <module or path>
---

# Harden

Target: $ARGUMENTS

For code that already works and now has to survive contact with reality: untrusted
input, scale, concurrency, and the 3am page. This changes behavior as little as
possible — hardening that rewrites the module is a rewrite, not a hardening.

If `$ARGUMENTS` is empty, run `.claude/tools/untested.sh` and propose the top candidate.

## 1. Establish the baseline — before you change anything

You cannot claim an improvement without a before.

- `.claude/tools/digest.sh` for the map; `.claude/tools/untested.sh` for what has no test.
- Run the existing suite and record the result. Green now, or fix that first.
- Record the current numbers if this is a hot path: latency p50/p95/p99, memory,
  allocations (`agents/benchmarker.md`). Save the artifact — every later claim cites it.
- **Nothing below is allowed to change behavior.** If a step reveals a behavior change
  is needed, that is a feature: stop and run `/workflow:feature`.

## 2. Cover it first

A hardening pass without tests is a refactor with no seatbelt.

- Use the `write-test` skill in the detected framework (`rules/test-frameworks.md`).
- Characterize what it does **today**, including behavior you think is wrong — record
  it, flag it, do not silently fix it here.
- Boundaries, not just the happy path: empty, zero, one, max, `nil`/`None`/`undefined`,
  duplicate, out-of-order, unicode, and the largest realistic input.
- Property-based tests for anything parsing external input (Hypothesis, proptest,
  fast-check, `testing/quick`) — generated inputs find what hand-picked examples miss.
- **Gate:** the suite is green and covers the module before step 3 touches anything.

## 3. Attack it

- Run `security` on the module. Every input from outside is hostile: injection,
  authz-by-construction, secrets, crypto, resource exhaustion
  (`rules/api-convention.md` for anything on an HTTP surface).
- Every CRITICAL/HIGH is a `rules/risk.md` trigger — it goes to the `devil` before the
  fix ships, and a human approves any cutover.
- Turn each confirmed finding into a failing test first, then fix. A security fix with
  no regression test will regress.

## 4. Bound every resource

The failures that page you are the unbounded ones:

- **Input** — a max size on every read, body, upload and header. A length field from
  outside is a claim, not a size.
- **Time** — a timeout on every network call, lock acquisition and subprocess; a
  deadline propagated through the call chain, not per-hop.
- **Memory** — a cap on every accumulating buffer, queue and cache; an eviction policy,
  not unbounded growth.
- **Concurrency** — a bounded worker pool, not unbounded spawn; backpressure when the
  queue is full rather than a silent drop or an OOM.
- **Retries** — bounded, with exponential backoff and jitter, and only on errors that
  are actually retryable. An unbounded retry loop is a self-inflicted outage.

## 5. Make the failure path as good as the happy path

- Every fallible operation handled explicitly; no silent swallow
  (`rules/refactor-common.md`).
- Every resource released on **every** path, error paths included — that is where the
  leaks are.
- Errors say what failed, why, and what the caller can do — and leak no internals
  (stack, SQL, DSN, file path).
- Degrade rather than collapse where it makes sense, and say in a comment which choice
  was made and why.
- Add the observability you would want at 3am: a log line at the failure with the
  identifiers needed to find the request, and a metric for the failure rate.

## 6. Prove it held

- `.claude/tools/quality.sh --with-tests` green at the strictest flags.
- `reviewer` on the full diff.
- Re-run the step-1 benchmark: hardening costs something, and the honest number is the
  deliverable. A regression over 5% on a hot path needs a stated reason or a fix.
- `.claude/tools/dupes.sh` — hardening often duplicates a guard three times. Extract it.

## 7. Report

| Dimension | Before | After |
| --- | --- | --- |
| Tests covering the module | | |
| Security findings (CRIT/HIGH/MED) | | |
| Unbounded resources | | |
| p95 latency / memory | | |

Plus: behavior deliberately left unchanged but flagged as suspicious, anything you
could not bound and why, and the commands that reproduce every number above.
