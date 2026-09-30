---
description: Run or inspect the project's migrations across backends. Usage: /devil:migrate <status|all|backend>
metadata:
  kind: command
---

Action: $ARGUMENTS

Drive the migration lifecycle through the project's task runner (detect it with `devil facts`,
run it under `devil watch`). Do NOT hand-edit migrations here — to
AUTHOR a new migration use `/devil:migrate-db`.

## Workflow

### Phase 1 — Inspect

- Run the project's migrate-status command — applied vs pending.
- Locate the migration files in the project (note any gaps in the numbering).

### Phase 2 — Apply (confirm first — DB writes are irreversible)

- `status`  → the project's migrate-status command
- `all`     → the project's migrate-all command
- `backend` → the project's per-backend migrate command   (needs that backend's services up)
- no arg    → the project's default migrate command

### Phase 3 — Verify

- Re-run the migrate-status command; confirm idempotency (re-applying is a no-op).
