# References

Where the facts in this config came from, and at which commit. A claim whose source
is not recorded is a claim nobody can re-check.

---

## `shanraisshan/claude-code-best-practice`

<https://github.com/shanraisshan/claude-code-best-practice> — read at `bde3f03`
(2026-09-20).

A third-party reference tracking Claude Code's surface area as it changes. It is
**gitignored, not vendored**: it carries its own `.git` and megabytes of generated
audio, and republishing someone else's assets inside this repo would be both wasteful
and rude. Clone it beside this repo if you want it:

```sh
git clone https://github.com/shanraisshan/claude-code-best-practice.git
```

What was taken from it — each of these corrected a real defect here:

| Fact | Where it came from | What it fixed |
|---|---|---|
| Skills take `allowed-tools:`; there is no `tools:` field | `best-practice/claude-skills.md`, 20 documented fields | Both skills here used `tools:`, which Claude Code silently ignores |
| Rules lazy-load via `paths:`; without frontmatter they load every session | `CLAUDE.md`, "Workflow Best Practices" | All 11 rules used Cursor's `globs:`/`alwaysApply:` — 22,018 bytes loading every session |
| Subagents take `memory:`, `effort:`, `isolation:`, `skills:`, `mcpServers:` | `best-practice/claude-subagents.md`, 16 fields | The memory layer in `doc/MEMORY.md` |
| Commands and skills take `context: fork` + `background: false` | `best-practice/claude-commands.md`, 20 fields | The context-budget advice in `skills/context-budget/` |
| The full hook event list and `settings.json` shape | `.claude/settings.json`, `best-practice/claude-settings.md` | `settings.json` and `hooks/` here |
| Agent vs Command vs Skill — when each is right | `reports/claude-agent-command-skill.md` | How the roster is split |
| `/skill-doctor` reports unused skills and their context cost | `best-practice/claude-skills.md` | Paired with `tools/context.sh` |

Its numbers are dated and Claude Code moves. Re-check against
<https://code.claude.com/docs> before relying on a field that matters.

---

## Claude Code docs

<https://code.claude.com/docs/en/plugins/components.md>,
`plugins/manifest-reference.md`, `skills.md`, `claude-directory.md`, read 2026-09-30.

| Fact | Where it came from | What it fixed here |
|---|---|---|
| A plugin ships commands, agents, skills, hooks and MCP, but **not** `.claude/rules/*.md`, `settings.json` permissions or a `CLAUDE.md` fragment | `plugins/components.md` | The 7 path-scoped rules moved to `paths:` skills tagged `stage: rule`; the always-on rules are seeded into a host by `/devil:setup` |
| A skill carries `paths:` and then loads only when matching files are touched, the same mechanism rules use | `skills.md` | The lazy-loading guarantee survived the move; `tools/context.sh` counts those bodies as lazy |
| `SKILL.md` frontmatter takes `paths:`, `user-invocable:` and a `metadata:` map; unknown keys parse and do nothing | `skills.md` | `tools/selfcheck.sh` fails a skill carrying Cursor's `globs:`/`alwaysApply:` |
| Plugin skills are namespaced `plugin:skill`; a `skills` array in the manifest only selects a subset | `plugins/manifest-reference.md` | Assets are cited as `/devil:<name>` throughout |

---

## `Univers42/scripts`

<https://github.com/Univers42/scripts> — pinned at
`2bb05b4f819c7f231ff00fb45cfe0d427af0f399` (`main`, 2026-09-20).

Reached through `tools/scripts.sh`, which fetches it into `cache/scripts/` on demand.
Nothing is copied into this repo. The vetted subset and the reasons for every exclusion
are in `scripts/REGISTRY.md`.

Measured at that sha, and why the wrapper exists:

- **44 of 56** top-level scripts open with the 42 header block instead of a shebang, so
  `./script.sh` runs under whatever shell is current.
- **11 of 149** tracked files carry the executable bit.
- `README.md` is **0 bytes**.
- `norminette.sh` is Python; `comptree.sh` is internally `show-branch-diff.sh`.

So `scripts.sh` never executes a file directly — it invokes `<runner> <file>` with the
interpreter named in the registry, which makes all of the above harmless.

---

## Claude Code itself

<https://code.claude.com/docs> — the authority for anything above. Where this repo and
the docs disagree, the docs are right and `tools/selfcheck.sh` needs updating.

---

## Claude Code plugin docs

Read on 2026-09-30, for turning this tree into the `devil` plugin. Each row is one page
and the fact it settled; the last column says what changed here because of it.

| Page | What it settled | What it fixed |
|---|---|---|
| <https://code.claude.com/docs/en/plugins/manifest-reference.md> | `plugin.json` documents `name` (required), `displayName`, `version`, `description`, `author.name`, `repository` (not validated), `license`, `keywords`. `hooks/hooks.json` is the default hook location. A root `settings.json` is read as plugin settings and only `agent` and `subagentStatusLine` survive; a root `.mcp.json` loads as plugin MCP servers; a root `CLAUDE.md` is not loaded and warns | `.claude-plugin/plugin.json`; `settings.json` and `.mcp.json` moved to `templates/` |
| <https://code.claude.com/docs/en/plugins/components.md> | Plugin hooks live in `hooks/hooks.json` under a top-level `hooks` key, same shape as the settings object. Every hook process gets `CLAUDE_PLUGIN_ROOT` in its environment. With `args`, each element is one argument and needs no quoting; without `args`, the path must be double-quoted | Exec form (`command` + `args`) in `hooks/hooks.json` |
| <https://code.claude.com/docs/en/plugins/marketplace-reference.md> | `name`, `owner.name` and `plugins` are required; a missing `description` is a warning. An entry takes `name`, `source` (a relative path starting `./`, or `.`), `description`, `category`. An entry `version` warns when `plugin.json` also sets one | `.claude-plugin/marketplace.json`, no `version` on the entry |
| <https://code.claude.com/docs/en/plugins/cli-reference.md> | `claude plugin validate <path> --strict` exits 0, 1 (error, or warning under `--strict`) or 2 (validator failed). On a directory it picks `marketplace.json` first and then does not open the plugins' hook files. `claude plugin marketplace add owner/repo`; `claude plugin install name@marketplace`; `claude --plugin-dir <path>` loads a session-only plugin; `/plugin install` and `/plugin marketplace add` are the in-session forms | The `plugin` CI job validates `plugin.json` by path; README quick start |
| <https://code.claude.com/docs/en/hooks.md> | A plugin `hooks/hooks.json` takes an optional top-level `description`. `timeout` is in seconds: the old `settings.json` wrote `5000`. `once` is honoured only in skill frontmatter. `${CLAUDE_PLUGIN_ROOT}` is substituted in `command` and in each `args` element. A plugin's timeouts never raise the harness budget | `hooks/hooks.json`: timeouts 5, 10 and 30 s; `once` dropped |
| <https://code.claude.com/docs/en/setup.md> | `npm install -g @anthropic-ai/claude-code` is the documented npm install | The `plugin` CI job |

Observed with `claude` 2.1.285, not stated on those pages: `claude plugin validate
.claude-plugin/plugin.json` also reads `hooks/hooks.json` and rejects unparsable JSON and
a bare events map (no `hooks` wrapper); an unknown handler field passes, so field choices
rest on the hooks reference, not on the validator. `validate` runs with an empty `HOME`,
so it needs no login; whether it runs offline was not tested.

---

## The other harnesses

Read 2026-09-30 for `doc/HARNESSES.md`, the capability matrix that decides what the
exporter has to generate per harness. Each row is one page and the fact it
settled; nothing here changed the tree, this slice only recorded facts.

| Page | What it settled |
|---|---|
| <https://opencode.ai/v2/docs/skills/> | OpenCode V2 reads `.opencode/skills`, `.claude/skills` and `.agents/skills`; the ID is the path, the frontmatter `name` is a display label; `paths:` is not interpreted |
| <https://opencode.ai/v2/docs/instructions/> | V2 recognises `AGENTS.md` only, `CLAUDE.md` is not a fallback, and the config `instructions` array is accepted but not loaded |
| <https://opencode.ai/v2/docs/agents/> | Agents are `.opencode/agents/*.md` with `mode:` and an ordered `permissions:` list; `.claude/agents` is not a source |
| <https://opencode.ai/v2/docs/commands/> | Commands are `.opencode/commands/*.md`, nested paths become `/a/b`, `$ARGUMENTS` and `$1` work, the shell block is `` !`cmd` `` |
| <https://opencode.ai/v2/docs/config/> | `opencode.json` precedence and the V2 shape of `permissions`, `skills`, `commands`, `plugins` |
| <https://opencode.ai/v2/docs/plugins/> | No plugin manifest; `.opencode/plugins/` plus npm packages, `opencode plugin add/update/list`, git specs and `::path:` subdirectories |
| <https://opencode.ai/v2/docs/build/plugins> | The plugin API: `Plugin.define` with `id` and `setup`, `ctx.tool.hook("execute.before")`, `ctx.permission.hook("evaluate")`, `ctx.session.hook("context")`, and which of them can deny |
| <https://opencode.ai/v2/docs/mcp-servers/> | MCP lives under `mcp.servers` in V2, a plugin registers one through `ctx.mcp.transform` |
| <https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-cli-plugins> | Copilot plugins exist and there are two formats: Agent Plugins 1.0 (root `plugin.json`, `skills/`, `mcp.json`) and the legacy one with configurable component paths |
| <https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference> | The legacy manifest is read from `.plugin/plugin.json`, `plugin.json`, `.github/plugin/plugin.json` **or `.claude-plugin/plugin.json`**; `marketplace.json` likewise; `${PLUGIN_ROOT}` (alias `${CLAUDE_PLUGIN_ROOT}`) is documented for MCP, LSP and agent `mcp-servers` but not for hooks; loading order puts `.claude/skills`, `.claude/agents` and `.claude/commands` ahead of plugins |
| <https://docs.github.com/en/copilot/concepts/agents/hooks> | Hooks are `.github/hooks/*.json` plus `~/.copilot/hooks/*.json`, shaped `{version, hooks}` |
| <https://docs.github.com/en/copilot/reference/hooks-reference> | Full event list, the snake_case payload, `permissionDecision: deny` on stdout, exit 2 blocks, a command hook is fail-closed on a crash and fail-open on a timeout, and `preToolUse` inherits Claude matcher semantics when the event is PascalCase |
| <https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions> | Copilot CLI reads `CLAUDE.md`, `.claude/CLAUDE.md`, `AGENTS.md`, `GEMINI.md` and `.github/copilot-instructions.md`; path scoping is `applyTo:` in `*.instructions.md` |
| <https://docs.github.com/en/copilot/concepts/agents/about-agent-skills> | Skill directories: `.github/skills`, `.claude/skills`, `.agents/skills`, `~/.copilot/skills`, `~/.agents/skills` |
| <https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-custom-agents> | Agent profiles are Markdown with `name`, `description`, optional `tools` and `mcp-servers` |
| <https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli> | The CLI surface: custom instructions, MCP, agents, hooks, skills, `--allow-tool` / `--deny-tool` |
| <https://geminicli.com/docs/extensions/> | Gemini extensions package prompts, MCP, commands, themes, hooks, sub-agents and skills, installed from a GitHub URL |
| <https://geminicli.com/docs/extensions/reference/> | `gemini-extension.json` at the extension root with `name` required; `commands/*.toml`, `hooks/hooks.json`, `skills/`, `agents/`; `${extensionPath}` is the plugin-root variable; `excludeTools` can block a shell command |
| <https://geminicli.com/docs/hooks/> | Gemini hook events are `BeforeTool` / `AfterTool` / `SessionStart` and friends, matchers are regex, deny is `{"decision":"deny"}` or exit 2, and the environment is sanitised |
| <https://geminicli.com/docs/cli/custom-commands/> | Commands are TOML with a required `prompt`, `{{args}}` placeholders, `!{...}` shell blocks and `@{...}` file injection; a subdirectory becomes `/a:b` |
| <https://developers.openai.com/codex/config-file/config-basic> | Codex layers `~/.codex/config.toml` and trusted `.codex/config.toml`, and the `hooks` feature flag |
| <https://developers.openai.com/codex/hooks> | Codex hook events are Claude's plus `PermissionRequest`, `PostCompact` and `Interrupt`; `PreToolUse` denies with `hookSpecificOutput.permissionDecision` or exit 2; a plugin's default is `hooks/hooks.json`; `PLUGIN_ROOT` and `CLAUDE_PLUGIN_ROOT` are exported to plugin hooks |
| <https://developers.openai.com/codex/agent-configuration/rules> | Codex "rules" are `.rules` files in a Starlark dialect controlling commands run outside the sandbox, not markdown |
| <https://developers.openai.com/codex/build-skills> | Codex reads skills from `.agents/skills` at several levels, `$HOME/.agents/skills` and `/etc/codex/skills`, and only `name` and `description` are required |
| <https://developers.openai.com/codex/agent-configuration/subagents> | Codex custom agents are standalone TOML files in `.codex/agents/` requiring `name`, `description` and `developer_instructions` |
| <https://developers.openai.com/plugins/build/plugins> | The portable package is root `plugin.json` plus `skills/` and `mcp.json`, `.codex-plugin/plugin.json` is a compatibility fallback, marketplaces are `.agents/plugins/marketplace.json` and the desktop app also reads `.claude-plugin/marketplace.json` |
| <https://agentskills.io/specification> | The portable `SKILL.md` contract: `name` and `description` required, optional `license`, `compatibility`, `metadata`, experimental `allowed-tools` |
| <https://agentskills.io/home> | Which products implement the standard, and that Copilot, Gemini CLI, OpenCode and Codex are all on it |

`opencode.ai/docs/` documents V1 and `opencode.ai/v2/docs/` documents V2. The installed
binary is 2.0.18, so only the V2 pages were used for it. Gemini CLI and Codex CLI are not
installed here, so their rows are documentation-only.

### Measured on this machine

`target/probe/` holds the scratch projects; the commands and the output line each one
settled are listed as `[L1]` to `[L11]` in `doc/HARNESSES.md`.

- `opencode run --standalone --auto -m 'opencode/space-bunny-free#max' --agent build "<ask>"`,
  in `target/probe/oc`: `.claude/skills` loads, `.claude/agents` does not, `AGENTS.md` loads,
  and `opencode run "/probecmd"` does not expand a command template or its shell block.
- `opencode serve --port 7790` plus `curl -u opencode:<password> /api/config`: a project
  `opencode.json` is read by walking up from the working directory, and its V1 `permission`
  object is rewritten into the V2 `permissions` array.
- Two `.opencode/plugins/*.js` probes: a `ctx.tool.hook("execute.before")` that throws, and
  a `ctx.permission.hook("evaluate")` that sets `effect: "deny"`. Both refused the bash
  command `echo DEVIL_PROBE_DENY`; the same command ran with no plugin present, which is the
  negative control.
- `COPILOT_HOME=target/probe/copilot-home copilot plugin install ./fake-claude-plugin`, where
  the only manifest was `.claude-plugin/plugin.json`: installed, `Plugin "devil-probe"
  installed successfully.` A local-path `copilot plugin marketplace add` failed, because
  1.0.59 parsed `./fake-marketplace` as a GitHub shorthand.
- Copilot behaviour probes are **SKIP**: `copilot -p` returned `model_not_supported` and every
  `--model` value was refused, so this machine has no Copilot entitlement. A SKIP is not a pass.

---

## Supermemory

<https://supermemory.ai/mcp/> — checked 2026-09-20. Declared in `.mcp.json` and
**disabled by default**; `doc/MEMORY.md` covers what it does and what it costs you in
privacy.

---

## Keeping this honest

When you take a fact from an outside source, add the row and the commit or access date.
When you find a fact here that is now wrong, fix it and say which source moved. The
point of this file is that someone can re-run the check — `tools/selfcheck.sh` keeps the
tree honest, and this keeps the reasoning honest.
