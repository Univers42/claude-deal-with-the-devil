# templates/

Files a host project receives, not files the plugin loads.

- `settings.json`: the permissions, `attribution`, `env` and status line the kit
  recommends. Its hook bindings moved to `hooks/hooks.json`, which the plugin does load.
- `mcp.json`: the four MCP servers, `supermemory` meant to stay off (`doc/MEMORY.md`).

Nothing here is read from the plugin root, on purpose: a root `settings.json` is taken
as plugin settings (only `agent` and `subagentStatusLine` survive) and a root `.mcp.json`
would start every server for every host. `/devil:setup` (coming) seeds these into a
host's `.claude/`; until then copy them by hand.

- `wizard.sh`: the copy-and-fill library above a `# STAGES` marker, for a procedure
  only a person can drive.
- `handoff.md`: the skeleton `/devil:handoff` fills in and writes to
  `${TMPDIR:-/tmp}/devil-handoff-<repo>-<ts>.md`. It is read by that command, not
  copied into a host.

The three decision skeletons are written into the HOST repo, not read from here:

- `adr.md`: `docs/adr/NNNN-<slug>.md`, written from `/devil:deal` when the
  three-gate rule fires (irreversible, public surface, or a `devil` verdict other
  than PROCEED). Its comment carries the rule.
- `out-of-scope.md`: `.out-of-scope/<concept>.md`, for a concept the verdict
  rejected. The load-bearing line is the fact that would have to change for the
  answer to change.
- `agent-brief.md`: what `/devil:prompt` emits, and the return block
  (`status` / `gates` / `changed` / `deviations` / `next`) every job ends with, so
  a caller greps it instead of reading a log.

`tests/test_templates.sh` holds each skeleton's required headings, so a template
that loses a section is a red test rather than a template nobody notices is short
one heading.
