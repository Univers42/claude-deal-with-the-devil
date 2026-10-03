2026-09-30 · OpenCode v2.0.18 (free tier) · plugin 0.9.0 · fixture a stdlib money module whose two rounding tests fail

## Scenario

> The money tests are failing and I cannot see why. Can you find out what is actually going on?

Fixture: `till/money.py` holds `parse_amount`, `round_cents` (`round(amount, 2)`) and
`split_bill`; `parse_amount` is the decoy. The test file is stdlib `unittest`, 6 cases, 2 red:
`0.145 → 0.15` and `2.675 → 2.68`. Both arms run with HOME and the XDG config roots redirected (no
user-level skills, no kit), outside the kit tree, `question` tool denied.

## Baseline

````text
- `parse_amount` — fine, both tests pass.
- **`split_bill`'s "losing nothing" promise genuinely holds.** I swept 20,000 amounts × 5 party sizes: zero violations of `share*(p-1) + remainder == amount`. My first sweep appeared to show ~16,000 violations, but that was **my own faulty invariant** (I summed `share*p` instead of `share*(p-1)`), not a defect in your code.
- Minor untested edge: `split_bill(x, 1)` returns `(round(x,2), round(x,2))`, double-counting the amount.
````

## With skill

Skill loaded: yes, `→ Skill "debug"` on line 52 of `with.out`, then "I'll follow the debug skill".

````text
My first hypothesis was Python's banker's rounding (ties-to-even). **That hypothesis is wrong**, and one test kills it:

| input | float value is a true tie? | `HALF_EVEN` on the exact float | result |
|---|---|---|---|
| `2.675` | no, it's *below* midpoint | 2.67 | 2.67 |
| `2.675` as a **Decimal literal** | yes, a true tie | **2.68** | — |

If ties-to-even were the cause, `2.675` would give 2.68 (8 is even). It gives 2.67. The cause is the float representation, not the rounding rule. `0.145` alone is ambiguous — banker's rounding happens to agree there — which is exactly why this looks so confusing.

The failure rate isn't 2 cases; it's a whole class. 6 of 11 common half-cent values are wrong:

```
0.145 old=0.14 new=0.15     0.125 old=0.12 new=0.13
2.675 old=2.67 new=2.68     1.115 old=1.11 new=1.12
1.005 old=1.00 new=1.01     4.045 old=4.04 new=4.05
```
````

## Verdict

Added: it states its first hypothesis, kills it with one discriminating case (`2.675` as a Decimal
literal), then sizes the class (6 of 11 half-cent values wrong) instead of reporting only the 2
failures it was handed; the baseline corrected itself at length but never named a hypothesis.
Still wrong: both arms stopped at diagnosis and asked the user to apply the fix, so the skill's own
done-when (turn the failure on and off) and its step 4 (write the failing test first) never happened.
