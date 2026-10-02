2026-09-30 · OpenCode v2.0.18 (free tier) · plugin 0.9.0 · fixture an untested flat-file ledger parser

## Scenario

> ledger.py has no tests at all and I am about to change it. Get it some coverage first.

Fixture: `ledger.py`, 5 pure public functions over a `YYYY-MM-DD <amount> <category> <note>`
format, and a 7-line `entries.txt` whose lines 5 and 7 carry no note, so every public function
raises on the shipped sample. No test framework, no config. Both arms run with HOME and the XDG
config roots redirected (no user-level skills, no kit), outside the kit tree, `question` denied.

## Baseline

```text
----------------------------------------------------------------------
Ran 68 tests in 0.001s

OK (expected failures=5)
> build · space-bunny-free
All 68 pass. Now let me verify the coverage is actually complete rather than assume it — using stdlib `trace` since `coverage` isn't installed.
```

## With skill

Skill loaded: yes, `→ Skill "write-test"` on line 4. Run twice, both aborted: the skill's step 2
says "Present the test plan. Wait for approval", the agent asked, `opencode run` has nobody to
answer, and the session died with `Session interrupted: shutdown` both times. No tests were written
in either attempt, so this arm is recorded as not run.

```text
**Proposed plan (~50 cases, pytest, `test_ledger.py`)**

| Target | Cases |
|---|---|
| `parse` | empty input; whitespace-only & blank lines; `#` comments incl. indented; single/multi line; multi-word note; quoted note unwrapped; `""`→`""`; unterminated quote **not** stripped; bare `"` not stripped; trailing `#` stays in note; CRLF; negative & scientific & underscore amounts; leading/trailing line whitespace; plus parametrized `ValueError` for 1/2/3-field lines, double space, tab-separated, non-numeric amount |
| `total` | sums with negatives; empty→`0`; propagates parse errors; float precision via `pytest.approx` |
| `total_by_category` | grouping & summing; empty→`{}`; nets across months; key insertion order = first appearance; propagates errors |
| `net_by_month` | `YYYY-MM` grouping; empty→`{}`; sums across categories; nets negatives; unpadded-date key `'2026-1-'`; propagates errors |
| `busiest_month` | highest positive spend; empty→`None`; all-negative→`None`; zero-amount→`None`; income does **not** offset spend (100 + −100 still = 100); tie→lexicographically **smallest**; 3-way tie; tie independent of input order; propagates errors |

No shared state and no concurrency anywhere in this module, so no threading/sleep concerns.
```

## Verdict

Added: it read the source for edge cases before writing anything, named the `entries.txt` lines
that break all five functions, and produced a per-function case table where the baseline went
straight to 68 tests and only then measured coverage.
Still wrong: the skill blocks on "Present the test plan. Wait for approval", so in any unattended
run it produces a plan and zero tests, and it cites `rules/test-frameworks.md`, which it does not
ship, so framework detection fell back to a hand-rolled guess.
