2026-09-30 · OpenCode 2.0.18 (free tier) · plugin 0.9.0 · fixture a stdlib checkout script over 400 baskets, no deps

## Scenario

> checkout.py takes about 1.6 seconds for the 400 baskets in orders.json. Make it
> faster.

`checkout.py` prices 400 baskets of 40 line items against a 60-entry
`catalog.json`. Its own timing line is the only number in the repo: 1.65 s. No test
runner, no dependencies, no bench harness.

## Baseline

```text
**Done: 1.647s → 0.001s (~1600x faster), with byte-identical output.**

[...the "## The problem" heading between the two is elided...]

`load_rates()` was called once per **line item** — 400 baskets × 40 items = 16,000 times. Each call re-read `catalog.json` from disk, re-parsed it, and re-scanned all 60 SKUs. The catalog was effectively rebuilt 16,000 times instead of once.
1. **Memoized `load_rates()`** with `functools.lru_cache` — the table depends only on the catalog file, so it's built once. `cache_info()` confirms `misses=1, hits=N`.
2. **Hoisted the call out of the per-item loop** in `price()`, so the lookup happens once per basket, not once per item.
3. **Replaced the O(n²) rescan with a running prefix total.** The keys are already in ascending file order, so the `k <= sku` sum for each SKU is exactly the running total of entries seen so far.

Verified:
- All 400 basket prices **byte-identical** to the pre-change output (`diff` against a baseline I captured before editing).
```

## With skill

Skill loaded: yes, `→ Skill "perf-budget"` on line 4 of the run.

```text
**Budget, written down before measuring anything.** Deriving it from the human threshold rather than from whatever I end up achieving:

| Metric | Budget | Why this number |
|---|---:|---|
| `checkout.py` internal `elapsed` (pricing region) | **≤ 0.200 s** | 400 baskets is a batch CLI job — no user waits on it, but 100 ms is the "instant" threshold and 1 s breaks flow. 200 ms leaves headroom over "instant" while still being ~8x stricter than the reported 1.6 s. Set before profiling. |
| `catalog.json` reads per run | **≤ 1** | The rate table is a constant. Re-reading it is the bug, not a tuning knob. This is a harder gate than the timer — it can't drift. |
| Peak RSS | **≤ baseline** | Latency must not be bought with memory. |
```

```text
- **Budget came first.** I set ≤0.200 s from the "100 ms feels instant" human threshold *before* profiling, so the measurement couldn't become the target.
- **One change, then stop.** `discount_schedule()` has the same bug — rebuilds a constant list 400 times — but I measured it at **0.62%**, under the 3% noise floor, so I left it. Cost of the fix outweighs the gain.
```

## Verdict

Added: the budget was written down and committed to `BENCHMARK.md` before the
first measurement, so the 0.002 s result is checked against a target rather than
adopted as one, and the run added the resource budgets step 1 asks for
(`catalog.json` reads ≤ 1, peak RSS) plus the 3% noise floor, which is what made
it leave `discount_schedule()` alone.
Still wrong: it declined step 5 outright and committed no wall-clock CI assertion,
and the headline metric is the script's internal `elapsed`, which hides the 20 ms
of process start-up it measured on the very next line of its own table.