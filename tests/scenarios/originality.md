2026-09-30 · OpenCode v2.0.18 (free tier) · plugin 0.9.0 · fixture `usdconv`, stdlib-only converter with a hand-kept `rates.csv`

## Scenario

> Before I add real rate fetching to this converter: we ship a static rates.csv, and the
> next thing on the roadmap is live rates plus better formatting. Is there already a
> library that does currency conversion with live rates that I should be using instead
> of writing this myself? Tell me plainly whether to reuse, wrap or build, and why.

Fixture: `usdconv.py` (argparse, `rates.csv` lookup, `FALLBACK = 1.0` on a missing code),
`rates.csv` with four currencies, and a README that admits the fallback is a known bug. No
dependency manifest exists, which is the honest signal for the search.

## Baseline

Excerpt from `base.out` (no skill loaded):

```text
Verdict: wrap, don't reuse, don't build
| Package | Last release | Verdict |
| **`forex-python`** | May 2025 | **Dead sources.** Its two upstreams now return HTTP 403/404 |
| **`pycurrency`** | 2011 | Scrapes Google's web calculator |
**Wrap** the [frankfurter API](https://frankfurter.dev) directly.
One caveat on my measurements: I verified the HTTP endpoints and package metadata from this
machine today. I did not install `forex-python` and exercise the wrapper
```

It searched outward, checked maintenance per candidate, and reached reuse/wrap/build. It
never mentions what it searched for inside the repo, and it does not separate the two
roadmap items.

## With skill

Skill loaded: `Skill "originality"`. Excerpt from `with.out`:

```text
Answer: wrap — what you wrap is a **free no-key API**, not a library.
Use **Babel** (2.18.0, Feb 2026, very actively maintained) for `babel.numbers.format_currency`.
**Caveat:** ... web search was cancelled mid-task, so I couldn't survey the long tail of
smaller wrappers ... "no candidate exists besides forex-python" is the weaker claim,
resting on a failed search rather than an exhaustive one.
```

Two problems get two verdicts (data source vs formatting), each with maintenance and
dependency facts, plus an explicit caveat on the strength of its own search.

## Verdict

Added: the skill splits one vague "is there a library" into a per-problem verdict and
labels the thinness of its own search, so the reader can tell a judgement from a fact.
Still wrong: it ranked only one candidate seriously and its `forex-python` maintenance
claim rests on one PyPI date, where the baseline had probed more packages.
