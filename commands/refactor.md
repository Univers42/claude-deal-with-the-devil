---
description: Deep refactor at the strictest standard for the technology. Usage: /devil:refactor <technology> [file or module path]
metadata:
  kind: command
  stage: beta
  since: "1.0.0"
---

Technology: $ARGUMENTS

Read and apply ALL of the following before touching any code:

1. .claude/rules/refactor-common.md (always)
2. .claude/rules/refactor-<technology>.md (for the specified tech)

If the technology file doesn't exist, stop and say so.

## Workflow

### Phase 1 — Audit

- Read every file in scope
- List every violation of the common + tech-specific rules
- Count violations per category
- DO NOT change anything yet

### Phase 2 — Plan

- Group violations by priority: correctness > norm > clarity > style
- For each group, describe the transformation in one line
- If a refactor changes public API surface, flag it explicitly
- Present the plan. Wait for approval before proceeding.

### Phase 3 — Execute

- One commit per logical transformation, not one mega-commit
- Each commit message: what rule it fixes and why
- Run the norm checker / linter after each transformation
- Run tests after each transformation — if any fail, stop

### Phase 4 — Verify

- Run full test suite
- Run the tech-specific norm checker one final time
- Produce a summary table: violations before → after per category
- If any violation remains, list it explicitly with justification
