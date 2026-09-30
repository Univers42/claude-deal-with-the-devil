# Grill reference

Loaded when the skill reaches step 3. Two things: the test that decides what to ask,
and the exact shape of a question.

## The fact-vs-decision test

Ask one question: **can the repo answer this?**

- A `rg`, a test, a config value, a tool output or a committed record answers it →
  it is a **fact**. Gather it in step 2, cite it, and state it in the contract. It
  never becomes a `Q:`.
- Two defensible answers exist and the repo endorses neither → it is a
  **decision**. It is the only thing worth the user's attention, so it is a `Q:`.
- Both at once: the repo answers the *present*, and you are about to change the
  *future*. Then the fact is stated, and the decision is what you ask.

A fact you ask is an interruption with a known answer. A decision you assume is a
silent default that shows up as a review comment three commits later.

## Four examples

**"Which test runner does this repo use?"** A fact. `devil facts` answers it, and
step 2 already ran. Stated in the contract, never asked.

**"Does the cache key include the tenant id?"** A decision. Both keys work, the tree
has no precedent, and the wrong one leaks across tenants. Ask it; recommend the
tenant-scoped key; cite the lookup that is shared.

**"How many retries on a 503?"** A fact while `config/defaults.yml` says 3, and a
decision the moment you are the one adding the retry. The repo decides the present,
the plan decides the future: state the 3, ask whether the new path keeps it.

**"Is the migration reversible?"** A fact if the down migration exists on disk, a
decision if the plan is to write one. Read the directory first. If it is missing,
the question is not "is it reversible" but "is a down migration in scope", and the
answer is a `rules/risk.md` trigger, not a preference.

## The question format

Three lines per decision, nothing else:

```text
Q: Does the cache key include the tenant id?
Recommended: yes, key on (tenant_id, path)
Why: pkg/cache/lookup.go:44 keys on path alone and is shared by every tenant.
```

What the format buys:

- **`Recommended:` first** means the user can answer "yes" to all three and be done
  in five seconds. A round that can be accepted wholesale is a round that ends.
- **`Why:` must cite** a `file:line`, a measurement or a named source. A
  recommendation you cannot cite is a preference, and it belongs in the contract as
  a stated default, not in a question.
- **One decision per `Q:`** keeps the answer attributable. "Q: should we cache, and
  for how long, and in Redis or in-process?" cannot be answered without three
  decisions, and the user will answer the first and skip the rest.

What it must never become: a preamble restating the request, a numbered list of
options, a question about something `rg` answers, or a second round in the same
message. Rounds are separated by the user's answers, not by your patience.
