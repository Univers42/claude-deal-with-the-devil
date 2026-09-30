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
