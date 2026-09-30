---
name: grill
description: >
  Close the frontier between what is decided and what is still open: the facts are
  gathered from the repo, the decisions go to the user in short rounds, each with a
  recommended answer.
  Use when a request is underspecified, the done-when is not stateable, or a
  rules/risk.md trigger is unresolved before code starts.
  Auto-triggers on: "grill me", "what have we decided", "ask me the hard questions"
allowed-tools: Read, Grep, Glob, Bash
metadata:
  stage: beta
  since: "1.0.0"
---

# Grill

A frontier is the line between what the repo already settles and what is still a
choice. Two failure modes sit on it, one at each end: asking a person for something
the code can answer, and building on a decision nobody noticed was a decision. This
walks the line in rounds and stops the moment the done-when is stateable.

`reference.md` holds the test that separates a fact from a decision, and the question
format with worked examples. Read it when you reach step 3.

## 1. State the frontier

Two short columns, filled from what you read and not from what you assume:

| Decided | Undecided |
| --- | --- |
| <what, with where it is decided> | <what, with who has to choose> |

Every left-hand cell cites: a `file:line`, a test, a committed record. Anything with
no citation goes right, including what looks obvious. A frontier nobody can cite is a
mood, not a frontier, and the right-hand column is the work.

## 2. Facts are gathered, never asked

Before a single question reaches the user:

- `devil digest` for the toolchain, the codemap, the untested surface.
- `devil facts` for the build, test and lint commands that actually run here.
- Read the files the request names; `rg` the ones it implies.
- A wide search (a whole subsystem, every caller of something) goes to a subagent
  and returns the conclusion, never the file dumps.

Never put a question the repo can answer in front of the user. It is an interruption
with a known answer, and it spends the scarcest input in the session on something
`rg` already had. A fact that changes the implementation is stated as a default in
the contract, not asked.

## 3. One round, at most three decisions

Each decision is exactly three lines, in this order:

```text
Q: <the decision to be made>
Recommended: <the answer you would pick>
Why: <one line, naming the fact behind it>
```

Then stop and wait for the answers. No follow-up question in the same message, no
"and one more thing". A decision the user can answer in one word is a good question;
one needing a paragraph is a fact you have not gathered yet.

Caveat: three decisions per round is a bound on attention, not on the work. It gets
wrong (a) a frontier that genuinely holds seven decisions, which then takes three
rounds and loses momentum, and (b) decisions that depend on each other, where the
later one gets asked on a wrong premise. Two is safer than three when the questions
are entangled; there is no signal in the repo that tells you which case you are in.

`reference.md` has the fact-vs-decision test and four worked examples. The three-line
format is the whole interface: no preamble, no options list, no recommendation
without a fact behind it.

## 4. Stop, and restate the contract

Run another round only while one of these is still true:

- The done-when cannot be written as a gate a test can check
  (`rules/prompt-contract.md`).
- A `rules/risk.md` trigger is unresolved (irreversible, security, data or schema,
  public surface, concurrency, wide blast).

The moment neither holds, stop asking. Restate the contract: **inputs → outputs →
done-when**. That restatement is what this skill exists to produce. A frontier that
never collapses into it was an interrogation, and the cheapest fix is a default
stated rather than a question asked.

## Report

- **Frontier**: decided and undecided, each decided cell with where it is decided.
- **Decisions**: one row each: the decision, the answer, and who made it (the user,
  or you under a stated default).
- **Facts**: what each answer rests on, cited.
- **Contract**: inputs, outputs, done-when.
- **Still open**: a `rules/risk.md` trigger you did not resolve, or nothing.
