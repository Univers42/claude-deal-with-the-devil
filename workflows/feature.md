---
description: >
  Build a feature end to end — spec, risk verdict, library-first TDD, strict gate.
  The default arc for new work. Usage: /workflow:feature <description>
---

# Feature

Feature: $ARGUMENTS

The full arc from a rough request to shipped, gated code. Use it when the work is more
than a one-line change. For a single obvious edit, skip this and just do it — a
playbook is not a tollbooth.

If `$ARGUMENTS` is empty, ask what to build and stop.

## 1. Ground

- Run `.claude/tools/digest.sh` — toolchain, codemap, untested worklist, duplication
  candidates. Decide from the digest, never from a guess about the tree.
- Run `.claude/tools/preflight.sh` — a missing `.env` or credential fails here, not ten
  minutes into a build (`rules/run-safely.md`).

## 2. Spec

- Run `/prompt $ARGUMENTS`. It returns objective, context, constraints, a done-when a
  test can check, and the output contract.
- Ask only the questions whose answers change the code; state sensible defaults for the
  rest.
- **Gate:** if the done-when is not stateable, the request is underspecified. Sharpen
  it before continuing — do not start building to "discover" the requirement.

## 3. Verdict — only if it is risky

Check the spec against the `rules/risk.md` triggers: irreversible · security-sensitive ·
data or schema · public surface · concurrency · wide blast.

- **Any trigger** → `/workflow:deal` with the spec. BLOCK means stop and resolve what
  it named. PROCEED-WITH-CONDITIONS means the conditions are now acceptance criteria,
  carried into step 5.
- **No trigger** → skip. Small, reversible, local work does not face the tribunal.

## 4. Design the seam — only if it crosses a boundary

New module, new contract, or data flowing across an existing boundary? Get the
`architect`'s decision and interface first. Otherwise skip — you do not need a design
doc for a function.

## 5. Build

Hand the spec (and any conditions from step 3) to `agents/builder.md`:

- **Library-first** — the primitive goes in the library, tested there, before the
  feature glues it together (`rules/library-first.md`). Act on every
  `.claude/tools/dupes.sh` candidate you touch.
- **TDD** — RED (watch it fail for the right reason) → GREEN (minimum code, walk the
  `minimalism-ladder`) → REFACTOR (`rules/refactor-<tech>.md`, tests stay green).
- **Bounded** — every build, test and install runs under `.claude/tools/watch.sh`.
- One commit per logical change, never mixing refactor with feature.

## 6. Converge on the gate

Fan in here; run these against the same tree:

- `.claude/tools/quality.sh --with-tests` — every relevant gate green at the strictest
  flags. A skipped gate is uncovered surface: name it (`rules/quality-bar.md`).
- `reviewer` — correctness, contracts, leaks, bloat.
- `security` — only if the feature touches untrusted input, auth, secrets or crypto.
- `benchmarker` — only if a hot path changed. A number against a baseline, no adjectives.
- Rendered UI? The `browser-testing` skill for real evidence, and the `frontend` skill's
  a11y pass.

A BLOCKER from any of them returns to step 5. **Green or reverted — never a half-built
tree left for someone else.**

## 7. Sync and report

- Docs that describe what you changed get updated (`documenter`, or the `doc-sync`
  skill). Examples come from the tests that now pass.
- Report: what shipped · tests added with their pass output · primitives extracted ·
  duplication before → after · gate status · the commands to reproduce all of it.
