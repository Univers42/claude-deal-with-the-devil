---
description: Run comparative benchmarks (the project vs the reference baseline) and flag regressions. Usage: /devil:bench [load|capacity|footprint|mem|startup]
metadata:
  kind: command
  stage: beta
  since: "1.0.0"
---

Scope: $ARGUMENTS

Run the canonical benchmark for the given scope on the current branch through the project's task runner
(detect it with `devil facts`, run it under `devil watch`).

## Workflow

### Phase 1 — Run

- Map scope → the project's benchmark target: load | capacity | footprint | mem | startup.
- No scope → run the full suite.

### Phase 2 — Analyze

- Read the benchmark artifact the project writes — every cited number comes from there (measured, not claimed).
- Flag any regression over 5% from the baseline.
- Compare read, write, login, boot time, and memory; compare against the reference baseline where relevant.

### Phase 3 — Report

- A markdown table with before / after / delta columns and a ✅ / ⚠️ / ❌ status per row.
