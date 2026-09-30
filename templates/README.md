# templates/

Files a host project receives, not files the plugin loads.

- `settings.json`: the permissions, `attribution`, `env` and status line the kit
  recommends. Its hook bindings moved to `hooks/hooks.json`, which the plugin does load.
- `mcp.json`: the four MCP servers, `supermemory` meant to stay off (`doc/MEMORY.md`).

Nothing here is read from the plugin root, on purpose: a root `settings.json` is taken
as plugin settings (only `agent` and `subagentStatusLine` survive) and a root `.mcp.json`
would start every server for every host. `/devil:setup` (coming) seeds these into a
host's `.claude/`; until then copy them by hand.
