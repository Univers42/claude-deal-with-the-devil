---
name: perf-budget
description: >
  Set the number before you optimise, then measure against it. Stops both premature
  optimisation and the endless tuning that never ships. Auto-triggers on: "make it
  faster", "is this fast enough", "optimize this", "performance budget", "it feels slow",
  "reduce latency"
allowed-tools: Read, Edit, Bash, Grep, Glob
---

# Performance budget

Two failure modes, and a budget kills both. Without a target you either optimise code
nobody waits on, or you tune forever because "faster" has no end. A budget makes
performance a **pass/fail gate** like every other one.

Pairs with `agents/benchmarker.md`, which measures. This decides what the number should
be *before* the measuring starts.

## 1. Name the number first — before touching anything

Write the budget down **before** you profile, so the measurement cannot quietly become
the target.

- **Who waits, and for what?** "The dashboard renders" is a budget. "The service is
  fast" is not.
- **Which percentile?** p50 is the good day. **p95 or p99 is the product**, because the
  slow tail is what people remember and complain about.
- **What number, from where?** An SLA, a competitor, the previous release, or a human
  threshold — 100ms feels instant, 1s breaks flow, 10s loses the user.
- **Budget the resource too**, not just time: memory ceiling, allocations per request,
  bundle bytes, query count, syscalls.

For a UI, the ones users feel: **LCP** < 2.5s · **INP** < 200ms · **CLS** < 0.1.

## 2. Measure the baseline — before any change

```sh
.claude/tools/facts.sh                              # the project's bench command
.claude/tools/watch.sh --idle 120 -- <bench cmd>    # never hang on it
```

- Same hardware, same data, same conditions as the "after" run will use. A comparison
  across machines is not a comparison.
- Enough iterations to be stable; report **min, p50, p95, p99 and stddev**, not a single
  run.
- Save the artifact. Every later claim cites it (`rules/prompt-contract.md`).
- **Already inside budget? Stop.** That is a complete and successful result. Say so and
  do not optimise — this is the outcome that saves the most time and the one people
  refuse to accept.

## 3. Profile before you change anything

Never optimise from intuition. Intuition is wrong about which line is hot, reliably.

- Go `pprof` · Rust `cargo flamegraph` · Python `cProfile`/`py-spy` · Node `--prof` /
  clinic · C `perf`/`valgrind --tool=callgrind` · Web: the browser's performance panel.
- Find the **dominant** cost. Optimising a 3% line to zero buys 3%.
- Check the algorithm before the constant factor: an O(n²) on growing data is not a
  tuning problem (`rules/dsa-and-memory.md`).
- Look for the free wins first — an N+1 query, a regex compiled per call, a serial loop
  over independent work, a missing index, work done inside a lock.

## 4. Change one thing, re-measure

- **One change per measurement.** Two at once and you cannot attribute the result, and
  one of them is usually making things worse.
- **Under 3% is noise, not an improvement** (`agents/benchmarker.md`). Revert it — you
  paid complexity for nothing.
- **Re-check the resource budget too.** Latency bought with unbounded memory is a
  future outage, not a win.
- Tests stay green. A fast wrong answer is not an optimisation.
- Stop the moment you are inside budget. "Faster than required" is spent complexity
  (`rules/minimalism-ladder.md`).

## 5. Defend it

A budget nobody re-checks decays quietly within two releases.

- Add the benchmark to CI, comparing against the recorded baseline. Fail over 5%
  regression (`/workflow:ship` already gates on this).
- Commit the baseline artifact so the comparison is reproducible.
- Record the budget and its reason where the next person will find it — and in
  `benchmarker`'s project memory (`rules/memory.md`), so it is not re-derived.

## Report

| Metric | Budget | Before | After | Delta | Status |
|---|---:|---:|---:|---:|---|

- The command that reproduces every number, and the hardware it ran on.
- What the profiler named as dominant, and what you actually changed.
- Changes reverted for being inside noise — evidence the discipline held.
- Resource budgets alongside time: memory, allocations, queries, bytes.
- Anything still outside budget, stated plainly, with what it would take.
