---
description: >
  Deal with the devil — submit a risky plan to the risk magistrate before it becomes code.
  The decision-quality gate. Usage: /devil:deal <the plan or decision>
metadata:
  kind: workflow
---

# Deal with the devil

Plan: $ARGUMENTS

The bargain: trade a little speed for a verdict you can trust. A risky decision faces the `devil`
BEFORE the code exists (see `rules/risk.md`). Trivial, reversible, local work skips this — don't
summon the tribunal for a one-line fix.

## 1. Externalize the plan

- Restate the decision as inputs → outputs → done-when.
- Write down explicitly: the assumptions, the edge cases, the failure modes, and the UNKNOWNS.
- A plan that stays in your head can't be judged — put it on the page.

## 2. Gather the evidence

- Run `devil digest` (and `devil quality` / `devil dupes` if relevant). Facts, not vibes.
- Note which `risk.md` triggers this decision hits.

## 3. Submit to the devil

- Invoke the `devil` agent with the plan + the evidence.
- It steel-mans, scores the risk (blast / reversibility / cost / confidence), names the failure
  nobody mentioned, and **pronounces a verdict**.

## 4. Honor the sentence

- **BLOCK** → resolve what it named, then return to step 1. Do not route around the verdict.
- **PROCEED-WITH-CONDITIONS** → the conditions are now acceptance criteria; carry them into the build.
- **PROCEED** → proceed.
- For anything irreversible, the **human** gives the final go — the devil advises, it doesn't deploy.

## 5. Build under the verdict

- Hand the verdict + conditions to the `builder`: TDD + library-first, meeting every condition, the
  quality gate green before "done".

## 6. Record

- For an irreversible or high-blast decision, note the verdict and its conditions in the PR / decision
  log — one short paragraph. Future-you needs to know why this was safe.
