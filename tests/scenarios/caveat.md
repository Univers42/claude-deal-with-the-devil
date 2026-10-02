2026-09-30 · OpenCode v2.0.18 (free tier) · plugin 0.9.0 · fixture `logsum`, a 44-line regex error counter with a 200k-line cap and a bytes-per-token estimate

## Scenario

> I want to rely on logsum to rank errors from our production logs. Before I do, I need to know what it gets wrong: what are its limitations, and what should I not trust it for? Do not change how it counts.

Fixture: `logsum.py` with one regex, `MAX_LINES = 200000`, `BYTES_PER_TOKEN = 4`,
`errors="replace"`, and message-string keying. A `README.md` claiming the counts are exact
and the cap is "far more than any single day of output". No `Caveat:` marker anywhere.

## Baseline

Excerpt from `base.out` (no skill loaded):

```text
It silently drops most real error volume ... On a 45-line probe, 18 error lines vanished
**Token estimate.** `estimate_tokens` is documented as bytes-per-token but divides `len(str)`
'支付失败：银行拒绝了这张卡'  len=13  true bytes=39  estimate=3
**Separately: the documented command does nothing**
$ python3 logsum.py sample.log
0 # no output
```

It found the same defects with better probes than the with-arm used, and left the source and
the README untouched (`grep -c 'Caveat:' logsum.py` is 0 in `base/`).

## With skill

Skill loaded: `Skill "caveat"` (attempt 1 ended on a stream error, attempt 2 rc=0).
Excerpt from `with.out`:

```text
| `logsum.py:6` (`ERROR_LINE`) | regex stands in for a log parser | 8 error-ish lines in → 1 counted |
| `logsum.py:24` (`MAX_LINES`) | silent prefix cap | 200,001-line file → 200,000 counted |
**Routed to a fix, not a caveat** — two are breakage, which a label would only disguise:
1. **`python3 logsum.py sample.log` prints nothing.** There is no `__main__` block
| Location | Approximation | Measured evidence |
| **1 marked, 0 unmarked** (was 1 unmarked).
```

`logsum.py` went from 0 to 7 `Caveat:` markers and the README's Accuracy section was
rewritten to the measured claims. Counting unchanged, proven by an AST comparison (200
nodes vs 200) and a second reimplementation.

## Verdict

Added: the skill converts a prose audit into shipped artifacts, seven markers plus a
corrected README, and sorts breakage (the missing `__main__`) out of the approximation list.
Still wrong: it marks a source defect with a `Caveat:` line in the fixture the user asked it
not to change, and it verified its own edit with the kit's `tools/caveat.sh` rather than a
check that exists in the fixture.
