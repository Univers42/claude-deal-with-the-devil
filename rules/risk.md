# Risk — engineer the decision before you write the code

*When a decision must face the devil's verdict before it becomes code, and how risk is
scored.*

The sharpest failure mode is a fast, plausible answer to an under-thought decision. The fix is
a gate: before risky work turns into code, it faces the `devil` (the risk magistrate), who rules
on it. Code-correctness gates (`quality-bar`, TDD) come *after* — they can't save a wrong decision.

## When the verdict is MANDATORY

Route the plan through `devil` (or the `/deal` workflow) before acting when it is:

- **Irreversible** — a deploy, delete, data migration, publish, force-push, key/secret rotation.
- **Security-sensitive** — auth, access control, crypto, secrets, anything touching untrusted input.
- **Data / schema** — a migration, a destructive query, a format change, a backfill.
- **Public surface** — a shipped API, a contract, a shared library others depend on.
- **Concurrency** — shared state, locks, async ordering, anything with a race.
- **Wide blast** — touches many modules/files, or sits on a hot path.

Trivial, reversible, local work skips the gate — the devil is a tribunal, not a tollbooth. When
unsure whether a change qualifies: it qualifies.

## How risk is scored

The devil scores four axes 1–5 and names the worst (see `agents/devil.md`): blast radius ·
reversibility · cost on failure · confidence (unverified assumptions).

## The verdict is the gate

- **BLOCK** stops the work. Resolve what it names, then re-submit — don't route around it.
- **PROCEED-WITH-CONDITIONS** — the conditions become acceptance criteria the `builder` must meet.
- **PROCEED** — act.
- UNKNOWN = FAIL: an unproven safety claim rules as BLOCK, not PROCEED.

## Externalize before you rule

A plan can't be judged while it's in your head. Before the verdict, write down the assumptions,
the inputs / edge cases, the failure modes, and what you DON'T know. Half the under-thinking dies
the moment it's on the page.
