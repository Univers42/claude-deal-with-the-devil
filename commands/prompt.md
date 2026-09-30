---
description: Turn a rough request into a precise, fact-grounded spec the builder can execute. Usage: /devil:prompt <rough request>
metadata:
  kind: command
  stage: beta
  since: "1.0.0"
---

Request: $ARGUMENTS

Forge the best version of this request — grounded in real repo facts, with a
done-when a test can check. If $ARGUMENTS is empty, ask for the request and stop.

## Workflow

### Phase 1 — Ground

- Run `devil digest` for the real toolchain, codemap, untested list, and
  duplication candidates. Don't guess the stack — read it.
- If digest reports no source (not a code repo), say so and proceed with what's known.

### Phase 2 — Clarify

- List the ambiguities that change the implementation: scope, inputs/outputs, edge
  cases, the success signal.
- Ask ONLY the questions whose answers change the code. Assume sensible defaults for
  the rest and state them. Don't interrogate.

### Phase 3 — Forge

Emit the refined prompt, ready to hand to `agents/builder.md`:

- **Objective** — one sentence, the goal in the user's terms.
- **Context** — grounding facts from digest: languages, build/test commands, files in
  scope, primitives that already exist.
- **Constraints** — the binding rules that apply (`library-first`, `quality-bar`,
  `dsa-and-memory`, `test-frameworks`, the per-tech `refactor-<tech>`).
- **Done-when** — the verifiable gate: the test that must pass, `devil quality` green.
- **Output contract** — what the builder returns (`rules/prompt-contract.md`).

### Phase 4 — Handoff

- Offer to execute it with the builder. Don't start building from `/devil:prompt` — this
  command produces the spec; the builder consumes it.
