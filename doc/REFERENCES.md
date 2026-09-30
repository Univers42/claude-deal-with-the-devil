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
| Claude Code loads rules from a **subdirectory** of `.claude/rules/`, not only the flat files the docs show | Measured, not documented: a scratch git repo with a `probe.md` under a `devil/` subdirectory of `.claude/rules/`, containing "The codeword is PERIWINKLE-42.", then `timeout 180 claude -p "What is the codeword? Reply with the codeword only."` (Claude Code 2.1.285, 2026-09-30) answered `PERIWINKLE-42`; with that file moved away the same prompt answered that it had no codeword. The same file flat, as `devil-probe.md` in the rules directory, answered the same. The probe tree is under `target/probe/` | `tools/setup.sh` seeds into `.claude/rules/devil/`, and the OpenCode glob in its `opencode` stage is the same path, so the two never disagree. Recorded as a `Caveat:` in `tools/lib/seed.sh`, naming the three places that would have to change together if a build stopped recursing |

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
