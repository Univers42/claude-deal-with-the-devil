# templates/

Files a host project receives, not files the plugin loads.

- `settings.json`: the permissions, `attribution`, `env` and status line the kit
  recommends. Its hook bindings moved to `hooks/hooks.json`, which the plugin does load.
  The allow list names `Bash(devil:*)` and the ask list `Bash(devil orch:*)`: a host
  reaches the tools by name, and an orch job can commit and push.
- `mcp.json`: the four MCP servers, `supermemory` meant to stay off (`doc/MEMORY.md`).
- `claude-md-block.md`: the block `/devil:setup` writes into a host's `CLAUDE.md`,
  between `<!-- devil:start -->` and `<!-- devil:end -->`. It is a pointer, not a
  source of truth: what it points at is `/devil:guide` and the seeded rule directory.
- `tracker/github.md` and `tracker/local.md`: the same three verbs (`create-ticket`,
  `list-ready`, `close-ticket`) as the commands they become, for a host on GitHub
  issues or on files under `.scratch/tickets/`.
- `wizard.sh`: the copy-and-fill library for a procedure only a person runs.

Nothing here is read from the plugin root, on purpose: a root `settings.json` is taken
as plugin settings (only `agent` and `subagentStatusLine` survive) and a root `.mcp.json`
would start every server for every host.

`bash tools/setup.sh` seeds all of it into a host repo. Run it with no flag first: it
prints what each stage would change and writes nothing. `--apply` writes, `--check` is
the same computation with an exit code for CI, and `--seed-mcp` is the one stage that is
opt-in, because a server is a network call and a supply-chain surface. Until you run it,
copy `settings.json` and `mcp.json` by hand.
