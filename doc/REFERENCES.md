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
