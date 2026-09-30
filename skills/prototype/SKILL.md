---
name: prototype
description: >
  Answer one feasibility question in a throwaway worktree, time-boxed, and end with
  keep or kill. The spike is measured, never merged.
  Use when an approach's cost, performance or feasibility is unproven, or when a
  spike, benchmark or quick prototype is asked for.
  Auto-triggers on: "prototype this", "spike this", "does this approach work",
  "how fast is this really"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
metadata:
  stage: beta
  since: "1.0.0"
---

# Prototype

A spike answers one question cheaply and is then thrown away. The expensive failure
mode is shipping it: code written to find out whether an approach works was never
reviewed, never held to a contract, and from the outside looks finished. The second
failure mode is the opposite one, keeping a spike because deleting it feels wasteful.
A spike is disposable by definition; the finding is the deliverable.

## 1. The question and the criterion, before any code

- **Question**: one sentence, answered by yes/no or by a number: "does the index
  hold at 10k rows", not "make search faster". A question two answers cannot decide
  is a project.
- **Kill criterion**: the result that says drop it, named now while walking away is
  still cheap. When the question is a product bet rather than a measurement, ask the
  `innovator` agent for the criterion: it is the agent whose job is the smallest
  experiment and the signal that ends it, and a criterion invented to fit the
  experiment you already wanted is not a criterion.
- **Out of scope**: name what the spike will not build: the feature, the error
  paths, the config, the docs. Writing the omissions down is what keeps it small, and
  it is the list you check the result against.

## 2. A throwaway worktree, time-boxed

- Branch off the current HEAD in a worktree outside the repo, so nothing here can
  reach the working tree: `git worktree add ../spike-<slug> -b spike/<slug>`.
- Every long command runs under `devil watch`, which kills a hang with a reason
  instead of waiting it out. Note its verdict: exit 124 is a finding, not a retry.
- State the box up front (a session, an afternoon) and write down when you are at
  the edge of it. Overrunning the box is allowed once; overrunning it silently is
  how a spike becomes a project.

Caveat: a wall-clock box is a proxy for cost, not cost itself. It gets wrong (a)
the spike whose answer arrives in the last five minutes of a long build, which the
box kills for having been honest, and (b) the one that needs a day of profiling and
would have been worth it. The box bounds exploration, not evidence: a number you
need is worth re-running for, once, outside the box. Nothing in the repo tells you
which kind of spike you are in, so say which one you are before the clock starts.

## 3. Measure against the criterion, and keep the notes

- The number, the command that produced it, the machine and the dataset. Paste the
  output; a remembered number is a claim.
- Compare against the kill criterion, explicitly: does the result cross it, and by
  how much. "Promising" is not a comparison.
- Record what you learned as you go, not afterwards: what surprised you, what broke,
  what you would do differently. That note is the thing that survives the worktree.
  Anything you did not measure is named as unknown, never folded into the verdict
  (`rules/prompt-contract.md`).

## 4. Keep or kill, then let it go

- **Keep** means the approach is worth building, not that the code is. Write the
  real thing with `/devil:feature`: it rebuilds it test-first, against a contract,
  and reviews it. The spike is an input to that, not a first draft of it.
- **Kill** means the criterion fired. Say so plainly, with the number that fired it,
  and hand the finding back to `brainstorm` or `innovator`. A killed spike is a
  result; a spike that dies quietly in a branch is a cost.
- Either way, the worktree is deleted and the branch with it. Nothing from a spike
  is merged, and nothing from it is copied forward. A spike that cannot be thrown
  away has stopped being one.

## Report

- **Question**: the one sentence, and the kill criterion it was measured against.
- **Result**: the number or the yes/no, with the command and the output that
  produced it, and the box it was measured in.
- **Verdict**: keep or kill, and what fires next: `/devil:feature`, or back to
  `brainstorm`.
- **Learned**: what surprised you, what broke, what you would do differently.
- **Cleanup**: the worktree path to delete, and confirmation that nothing was
  merged.
