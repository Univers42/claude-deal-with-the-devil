---
name: ponytail
description: >
  Make an approximation admit it is one. Find the heuristics, samples, regex parsers,
  caches and timeouts in a change and give each the one line saying what it gets wrong.
  Auto-triggers on: "is this exact", "add a caveat", "what are the limitations",
  "ponytail", "document the limits", "how accurate is this"
allowed-tools: Read, Edit, Grep, Glob, Bash
---

# Ponytail

Most useful tools are approximations. That is fine. An approximation **presented as a
fact** is not: the reader trusts the output, it is wrong in a way nobody wrote down, and
the trust is spent before anyone notices.

The rule is `rules/ponytail.md`. This is how to apply it to a diff.

## 1. Find what owes a line

```sh
.claude/tools/ponytail.sh            # whole tree
.claude/tools/ponytail.sh path/to/changed.go
```

It flags a file that reads as best-effort and carries no `Ponytail:` marker. Read its
own header first — it over-reports on hedge words in ordinary prose and under-reports
badly on approximations written without any tell, so treat every row as a prompt to
look, never a verdict.

Then check what the tool cannot see in the change itself:

- Parsing source with a regex instead of an AST.
- A sample, a `head -n`, a `LIMIT`, a partial scan standing in for a full one.
- Existence used as a proxy for a property — a test file's *name* standing in for
  coverage.
- A timeout, a retry bound, a cache TTL: each one is a guess about how long is too long.
- A number that is derived rather than measured — bytes÷4 for tokens, a ratio, an
  extrapolation.
- A default chosen because it worked on your machine.

## 2. Write the line

Not "this is regex-based" — that tells the reader nothing. State **what fails, in which
direction, and what to do instead**:

```
# Ponytail: matches the import line, so a conditional or dynamic import is missed.
# It under-reports, so an empty result means "found nothing", not "there is nothing" —
# confirm against the real dependency graph before deleting anything.
```

Four things make it good:

- **The failing input**, concretely. "a signature wrapped across two lines", not
  "complex code".
- **The direction.** Under-reporting is dangerous, over-reporting is merely noisy.
  Which is this? A gate that silently passes is the one that hurts.
- **The escape hatch.** The flag that widens it, the real tool, the manual confirmation.
- **A number where you have one.** "3/20 runs on a cold cache" beats "sometimes".

Place it in the file header for a whole-file approximation, immediately above the
function for a local one.

## 3. Carry it into the output

The caveat belongs where the reader is, not only in the source:

- A report built on a heuristic says so **in the report**.
- A check that could not run is `SKIP`, never assumed green (`rules/quality-bar.md`).
- A number you estimated is labelled estimated.
- A conclusion resting on an unverified assumption names it
  (`rules/prompt-contract.md`: UNKNOWN = FAIL).

## 4. Don't over-apply

- No marker on exact code. A marker on something deterministic trains readers to skip
  markers, which is the one thing that makes the whole convention useless.
- A caveat is not a substitute for a fix. "Ponytail: returns the wrong answer for empty
  input" is a defect with a label on it. Caveats cover *approximation*, never
  *breakage* — fix that instead.
- If the thing is correct, say so plainly. Hedging exact work is its own dishonesty.

## Report

- Each approximation found, at `file:line`, and the marker added.
- Anything flagged that turned out to be exact — and why you left it alone.
- Anything that was breakage rather than approximation, routed to a fix instead.
- `.claude/tools/ponytail.sh` before → after.
