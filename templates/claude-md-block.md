## The devil kit

Installed as the Claude Code plugin `devil`.

- `/devil:guide` lists every command, workflow, skill and agent with its stage.
- `devil <tool>` runs a tool: `devil digest`, `devil quality --no-audit`, `devil selfcheck`.
- Its 12 always-on rules are seeded under `.claude/rules/devil/` and load every session.
- After a plugin update, run `/devil:setup --apply` to re-seed them.
