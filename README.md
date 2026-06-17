# claude-deal-with-the-devil

![mascot](image.png)

A drop-in `.claude/` setup that helps Claude Code write code like a careful engineer instead of a fast one. It works in any project, whatever the language or stack.

The idea is simple: look before guessing, write a test before the code, think twice before anything risky, and don't call something "done" until it actually passes a real quality check.

---

## Why this exists

Claude is great at writing code quickly. The trouble is that a quick, confident answer to a question you haven't fully thought through is often wrong in a way that looks right.

This config pushes back on that. It nudges the reasoning into the open and asks for evidence before action. In practice it fixes four habits:

- **Guessing instead of looking.** Small scripts pre-read the repo so Claude works from a summary, not a fresh re-read every time.
- **Rushing risky decisions.** The `devil` reviews a plan and says go or stop *before* any code gets written.
- **Reinventing things.** A "reuse first" habit and a duplicate-finder keep the code from sprawling.
- **"Looks done."** A strict, multi-tool check is the only thing allowed to call work finished.

---

## How a task flows

```
/prompt          →   /deal           →   builder              →   /quality
write a spec         the devil          test-first, reuse        run the strict gate
                     decides go/stop    red → green → refactor
```

1. **`/prompt`** turns a vague request into a clear spec, with a "done when" that a test can actually verify.
2. **`/deal`** sends risky plans to the `devil`, which weighs how much could break, how easily it's undone, and how confident the plan really is — then says BLOCK or PROCEED. Small, reversible work skips this.
3. **`builder`** does the work: build the reusable piece first, write the failing test, write the minimum code to pass, then clean up. Every step gets run and checked.
4. **`/quality`** runs the full gate (formatting, lint, types, security scan, dependency audit, accessibility). Green, with tests passing, is what "done" means.

Two habits run through all of it: back claims with a command and its output (or a `file:line`), and never leave a half-finished tree behind — it's green or it's reverted.

---

## The six pieces

Reach for the smallest one that fits.

| Layer         | Where                    | What it is                                  | How it runs                          |
| ------------- | ------------------------ | ------------------------------------------- | ------------------------------------ |
| **Rules**     | `rules/*.md`             | Standing constraints, the craft discipline  | automatic, by scope                  |
| **Commands**  | `commands/*.md`          | One focused action                          | you type `/<name> <args>`            |
| **Skills**    | `skills/<name>/SKILL.md` | A capability that triggers on intent        | a trigger phrase, or by name         |
| **Workflows** | `workflows/*.md`         | Multi-step playbooks                        | `/workflow:<name> <args>`            |
| **Tools**     | `tools/*.sh`             | Scripts: digesters, the quality gate, etc.  | Claude runs `.claude/tools/<name>.sh`|
| **Agents**    | `agents/*.md`            | Specialist personas you delegate to         | by name, trigger, or from a workflow |

Rough guide: something that must always hold is a **rule**; a one-shot is a **command**; a capability that fires on intent is a **skill**; a gated multi-step procedure is a **workflow**; a recurring parse or check is a **tool**; a distinct perspective is an **agent**. Multi-agent details live in [`AGENTS.md`](AGENTS.md).

---

## Tools

These are small bash scripts that read the repo for you, so Claude runs one command and gets structured facts instead of re-reading everything each session. Output is cached in `.claude/cache/` and tied to git state, so a stale cache rebuilds itself. Plain bash and coreutils, with `rg`/`jq` used when they're around. Full list: [`tools/README.md`](tools/README.md).

| Tool           | Answers                                                                 |
| -------------- | ---------------------------------------------------------------------- |
| `digest.sh`    | "What am I working with?" — the start-of-task briefing                 |
| `facts.sh`     | "How do I build, test, and lint? Which test framework is this?"        |
| `preflight.sh` | "Is the environment ready?" — env, secrets, toolchain, before building |
| `codemap.sh`   | "Where does X live? What's heavy? What's untested?"                    |
| `untested.sh`  | "What needs a test before I touch it?"                                 |
| `dupes.sh`     | "What should I pull into the shared library?"                          |
| `quality.sh`   | "Is this actually up to standard?" — the gate, read-only               |
| `watch.sh`     | "Run this without letting it hang" — timeouts around any command       |

```sh
.claude/tools/digest.sh                          # brief yourself first (cached)
.claude/tools/quality.sh --with-tests            # the strict gate; exit 1 means a real failure
.claude/tools/watch.sh --idle 60 -- make build   # never wait forever on a stuck process
```

---

## The agents

Pick the narrowest one for the job and combine them when you check the work. Each lives in `agents/<name>.md`.

**Build and extend**

- **`builder`** — test-first, reuse-first. Turns a contract into shipped code; green or reverted, never half.
- **`forger`** — the toolsmith, builds the scripts and commands that make rules enforce themselves.
- **`innovator`** — the ideas person, with a cheap experiment and a clear way to know when to drop it.

**Advise and design**

- **`devil`** — weighs the risk and decides BLOCK / PROCEED-WITH-CONDITIONS / PROCEED before risky code exists.
- **`architect`** — boundaries, contracts, and data flow; produces decisions and interfaces, not code.
- **`documenter`** — docs only, never touches source; examples come from the tests.

**Verify**

- **`reviewer`** — strict merge review: correctness, leaks, broken contracts, bloat.
- **`security`** — thinks like an attacker, finds the exploit, rates it, names the smallest fix.
- **`benchmarker`** — performance as numbers against a baseline, no adjectives.
- **`compat-tester`** — checks behavior matches a reference (a spec, a prior version, a competitor).
- **`norminette`** — strict 42 C-norm enforcer, opt-in for C and 42 projects.

---

## Rules

Some rules are always on and shape every task:

- **`risk`** — when a decision has to face the devil first, and how risk gets scored.
- **`library-first`** — pull out the reusable piece before duplicating; features are thin glue.
- **`prompt-contract`** — gather facts before acting, return proof instead of adjectives.
- **`quality-bar`** — the strictest check across every layer, in one command.
- **`dsa-and-memory`** — pick the right data structure and algorithm; pool allocations where it matters.
- **`test-frameworks`** — detect and use the project's framework instead of inventing one.
- **`run-safely`** — check config before building, and bound every command so nothing hangs.
- **`minimalism-ladder`** and **`minimalism-markers`** — the ladder: YAGNI → stdlib → platform → existing dep → one-liner → minimum, with a performance override on hot paths.
- **`refactor-common`** — the shared structure, naming, error-handling, and testing basics.

Language-specific rules load when you touch that language: `refactor-{c,go,rust,typescript,shell}` and `api-convention`. `/refactor <tech>` reads `rules/refactor-<tech>.md` directly.

---

## Quick start

1. Copy these files into your project's `.claude/` directory — this repo *is* that directory's contents. Keep `settings.json` as valid JSON.
2. Run `.claude/tools/digest.sh` to see the stack, toolchain, test framework, untested files, and duplication at a glance.
3. Describe a feature and let Claude run the arc: `/prompt` → `/deal` (if risky) → `builder` → `/quality`.
4. Land it behind your verification gate, green at the strict `quality-bar`.

Everyday handles: `/prompt <request>`, `/deal <plan>`, `/quality [--with-tests]`, `/refactor <tech> <path>`, `/workflow:feature <desc>`, `/workflow:harden <module>`.

---

## Binding rules

These hold for everything here, even one-off tasks:

1. **Never co-author** — no `Co-Authored-By` or "Generated with" trailer.
2. **Use the project's own toolchain** — find the real commands with `facts.sh`, run them under `watch.sh`, don't hand-roll what the project already scripts.
3. **Backward-compatible by default** — new behavior is additive and opt-in until proven.
4. **Backend-agnostic** — a fix for one adapter or engine that breaks another isn't done.
5. **Measured, not claimed** — every performance number cites an artifact and the command that reproduces it.
6. **Confirm the irreversible** — pushes, deploys, deletions, data migrations, and security cutovers need an explicit human go-ahead.
7. **Stage risky changes** — prove the new path against the old before deleting the old; if it's unknown, treat it as a failure.
8. **A gate is the unit of "done"** — land work behind the project's verification gate, green at the strict `quality-bar`.

---

## Repository layout

```
.claude/
├── README.md          this file
├── AGENTS.md          multi-agent discipline
├── agents/*.md        specialist personas (builder, forger, innovator, devil, …)
├── rules/*.md         always-on and tech-scoped constraints
├── commands/*.md      single-shot actions (/prompt, /quality, /refactor, …)
├── skills/<n>/SKILL.md  capabilities that trigger on intent (debug, write-test, …)
├── workflows/*.md     multi-phase playbooks (/workflow:deal, feature, harden, …)
├── tools/*.sh         the scripts (digest, quality, watch, …) + lib/common.sh
├── settings.json      committed config (permissions / env / hooks)
└── assets/            the mascot
```

---

## Extending it

When you add something, match the existing examples: `commands/refactor.md`, `rules/refactor-common.md`, `skills/debug/SKILL.md`, `workflows/harden.md`, `tools/quality.sh`. Keep the voice short and direct, use real numbers, and skip filler words like "simply" or "just".

- **Rules** — YAML frontmatter, then a `#` title and `##` sections. Two shapes, never mixed: universal (`description` + `alwaysApply: true`, no globs) or tech-scoped (`globs: ["**/*.ext"]` + `description`). Note: `/refactor <tech>` reads `rules/refactor-<tech>.md` by exact name, so spell the filename carefully.
- **Commands** — frontmatter with one `description:` ending in `Usage: /<name> <args>`; the body opens with `<Label>: $ARGUMENTS` and uses phased `## Workflow` sections; abort if a required file is missing.
- **Skills** — a directory `skills/<name>/` with exactly `SKILL.md`. The directory name matches the frontmatter `name` (lowercase-hyphenated). Frontmatter has `name`, a `description:` ending in `Auto-triggers on: "phrase", "phrase"`, and a minimal `tools:`. The last phase is always `Report`.
- **Workflows** — frontmatter `description:` ending in `Usage: /workflow:<name> <args>`; numbered phases; one clear human gate before any behavior change; a final `## Report`. Workflows reference skills and commands by name rather than re-explaining them.
- **Tools** — executable bash, thin glue over `lib/common.sh`, one concern each. Support `--summary` and `--refresh`, emit markdown, cache to `.claude/cache/`, and exit non-zero on failure. Conventions are in [`tools/README.md`](tools/README.md); the `forger` builds these.
- **Agents** — frontmatter with `name`, a `description:` with triggers, `tools:`, and an optional `model:`. The body is a persona, its principles, what it does and doesn't do, and an output format.

Keep one source of truth per concept and reference it instead of repeating it.

## Settings

- `settings.json` — committed, repo-wide config (permissions, env, hooks). Must be valid JSON; even `{}` is fine, but an empty file won't parse.
- `settings.local.json` — machine-local toggles like `disabledMcpjsonServers`, not shared.
