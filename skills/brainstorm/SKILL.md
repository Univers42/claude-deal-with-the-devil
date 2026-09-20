---
name: brainstorm
description: >
  Generate options properly — diverge wide before judging, then converge on evidence and
  cost. Ends with one recommendation and a kill criterion, not a list.
  Auto-triggers on: "brainstorm", "what are the options", "how else could we",
  "give me ideas", "explore approaches", "what would you suggest"
allowed-tools: Read, Grep, Glob, Bash, WebSearch, WebFetch
---

# Brainstorm

Two failure modes, opposite and equally common: converging on the first plausible idea,
or producing twelve options and leaving the choice to someone else. This separates the
two phases so neither happens.

The `innovator` agent is the 10x-vision counterpart; this is the structured pass you run
inline. Whatever comes out goes to the `devil` before it becomes code
(`rules/risk.md`).

## 1. Ground it — 5 minutes, not skippable

```sh
.claude/tools/digest.sh
```

Dreaming in a vacuum produces ideas that cannot be built here. Before generating
anything, know: the stack, what already exists that could be reused, the actual
constraint (time? correctness? a quota? someone's patience?), and what has already been
tried and rejected — and why.

Restate the problem in one sentence. Half of all brainstorms are answering a
mis-stated question, and it is cheapest to catch that now.

## 2. Diverge — no judging, quantity first

Generate at least **six** genuinely different options before evaluating any of them.
Not six variations of one idea. Judging while generating kills the unusual options
first, and the unusual one is the reason you ran this.

Force range by attacking the problem from different angles:

- **Do nothing.** What happens if this is never built? Sometimes correct, always a
  useful baseline (`rules/minimalism-ladder.md` rung 0).
- **Delete instead.** Can the need disappear by removing something upstream?
- **Buy / borrow.** Does the platform, the stdlib, or an existing dependency already do
  it? `WebSearch` for prior art — borrow the wheel.
- **The 10x version.** If effort were free, what would this be? Then ask what 10% of it
  gets 80% of the value.
- **The lazy version.** The crudest thing that would work. Manual. Hardcoded. Often
  the right answer for six months.
- **Invert it.** Solve the opposite problem, or push the work to a different layer,
  a different time, or the caller.

Write each as one line. No elaboration yet — elaboration is a commitment.

## 3. Converge — on facts, not enthusiasm

Score each surviving option:

| Option | Impact | Confidence | Cost | Reversibility | Score |
|---|---:|---:|---:|---|---:|

- **Impact** (1–5) — how much better does the world get?
- **Confidence** (1–5) — how much of this rests on an unverified assumption? Every
  UNKNOWN drops it (`rules/prompt-contract.md`).
- **Cost** (1–5) — build plus the maintenance nobody counts. Which ladder rung does it
  land on?
- **Reversibility** — one-way door, or undo in a step? A cheap reversible option beats
  a better irreversible one when confidence is low.
- **Score** = (impact × confidence) ÷ cost.

Say plainly which options are long shots. Ranking everything 4/5 is not a ranking.

## 4. Commit to one

- **Lead with the one you would bet on**, and say why the runner-up lost. A
  recommendation is the deliverable; a menu is homework handed back.
- **The smallest experiment that produces signal** — a spike, a benchmark, a prototype
  behind a flag. Never a big bet up front.
- **The kill criterion**, named *now* while walking away is still cheap: the result
  that means drop it. An idea with no kill criterion is a commitment in disguise.
- **Hand it on.** Risky or irreversible → `/workflow:deal` for a verdict. Crosses a
  boundary → `architect`. Otherwise → `/workflow:feature`.

## Report

- The problem, restated in one sentence.
- All options generated, including the ones you rejected — the rejected set is evidence
  that the search was wide, and someone will ask.
- The scoring table.
- The recommendation, its smallest experiment, its signal, and its kill criterion.
- What you did not know that would most change the ranking.
