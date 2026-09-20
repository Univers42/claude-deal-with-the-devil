# Ponytail — name what your heuristic gets wrong

*Every best-effort mechanism ships one line saying where it is wrong. Non-negotiable.*

Most useful tools are approximations — regex instead of an AST, a sample instead of a
census, existence instead of coverage, output instead of liveness. That is fine. An
approximation **presented as a fact** is not: it is trusted, it is wrong in a way nobody
wrote down, and the trust is spent before anyone notices.

So the limitation is part of the deliverable.

## The marker

Any heuristic, regex parser, sampler, estimate, timeout or cache carries a comment
starting `Ponytail:` that states **what it gets wrong and when** — in the file header
for a whole-file approximation, above the function for a local one. This is the one
comment that is mandatory rather than earned (`rules/minimalism-markers.md`).

```sh
# Ponytail: liveness is output-based — a genuinely silent long task needs a larger
# --idle (or --idle 0). Wrap builds/tests/installs; never an interactive REPL.
```

A good marker names the **failing input** ("a signature wrapped across two lines", not
"complex code"), the **direction** of failure (under-reporting is dangerous;
over-reporting is merely noisy), and the **escape hatch**.

## It travels with the output

A report built on a heuristic says so **in the report**, not only in the source. A check
that could not run is `SKIP`, never assumed green (`rules/quality-bar.md`). An estimated
number is labelled estimated. A conclusion resting on an unverified assumption names it
(`rules/prompt-contract.md`: UNKNOWN = FAIL).

## Two limits

- **Not on exact code.** A marker on something deterministic trains readers to skip
  markers, which is the one thing that makes the convention useless. If it is correct,
  say so plainly.
- **Not instead of a fix.** "Ponytail: wrong for empty input" is a defect with a label
  on it. Caveats cover *approximation*, never *breakage*.

The `ponytail` skill applies this to a diff. `.claude/tools/ponytail.sh` finds code that
owes a marker — and its own header says how it fails, in both directions.
