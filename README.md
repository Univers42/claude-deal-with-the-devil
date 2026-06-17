# claude-chai — agent configuration for real-engineer code

<p align="center">
  <img src="![alt text](image.png)" alt="claude-chai — the little green devil that does the job" width="320">
</p>

A drop-in `.claude/` configuration that wires Claude Code to produce **high-quality, well-tested,
minimal-but-correct** solutions in **any** programming project — language- and stack-agnostic. It turns
Claude from a fast code writer into a careful engineer: facts before action, tests before code, a verdict
before anything risky, and a strict gate before "done".

---

## Why claude-chai

Claude's strength is writing code. Its **demon** is the fast, plausible answer to an _under-thought_
decision — great syntax, shaky judgment. claude-chai is the counter-demon: a system of **tools, rules,
gates, and specialist agents** that force the reasoning to be explicit, evidence-backed, and finished —
never half-done.

It fixes four recurring failure modes:

- **Guessing instead of looking** → tools pre-digest the repo so agents read _conclusions_, not raw trees.
- **Under-thought risky decisions** → the `devil` rules on a plan (`BLOCK` / `PROCEED`) _before_ code exists.
- **Reinventing & duplicating** → a library-first discipline and a duplication finder keep the code DRY.
- **"Looks done"** → a strict, multi-tool quality gate is the only definition of done.

---

## The arc — how a task flows

```
  /prompt            →   /deal                →   builder              →   /quality
  forge a spec           the devil rules          TDD + library-first      strict gate green
  (facts, done-when)     (BLOCK / PROCEED)        (red → green → refactor)  (lint·SAST·audit·tests)
```

1. **`/prompt`** turns a vague request into a precise, fact-grounded spec — grounded by `digest.sh`, with a
   done-when a test can check.
2. **`/deal`** (for risky work) submits the plan to the **`devil`**, the risk magistrate. It scores blast
   radius / reversibility / cost / confidence, names the failure nobody mentioned, and **pronounces a
   verdict**. `BLOCK` stops the work until resolved. Trivial, reversible work skips this.
3. **`builder`** implements it: brief from `digest.sh`, build the reusable primitive _first_, then write the
   failing test, then the minimum code, then refactor — every step run and observed.
4. **`/quality`** runs every strict gate (format · lint · types · SAST · supply-chain audit · a11y). Green,
   with tests passing in the project's own framework, _is_ done.

Throughout: **facts, not claims** (every assertion cites a command + output or `file:line`), and **green or
reverted** (never a half-built tree left behind).

---

## The six layers

Pick the **smallest scope** that fits the job.

| Layer         | Path                     | What it is                                                   | How it fires                                                |
| ------------- | ------------------------ | ------------------------------------------------------------ | ----------------------------------------------------------- |
| **Rules**     | `rules/*.md`             | Always-on / glob-scoped constraints (the craft discipline)   | auto, by `alwaysApply` or `globs`; also read by `/refactor` |
| **Commands**  | `commands/*.md`          | One focused, single-shot action                              | you type `/<name> <args>`                                   |
| **Skills**    | `skills/<name>/SKILL.md` | A capability that auto-triggers on intent                    | trigger phrase, or by name                                  |
| **Workflows** | `workflows/*.md`         | Multi-phase playbooks that orchestrate the rest              | `/workflow:<name> <args>`                                   |
| **Tools**     | `tools/*.sh`             | Executable digesters, the quality gate, preflight + watchdog | an agent runs `.claude/tools/<name>.sh`                     |
| **Agents**    | `agents/*.md`            | Specialist subagents you delegate to                         | by name, by trigger, or from a workflow                     |

**Rule of thumb:** a constraint that must always hold → **rule**; one shot → **command**; a capability that
fires on intent → **skill**; a gated, multi-phase procedure → **workflow**; a recurring parse or a
checkable rule → a **tool**; a distinct perspective or persona → an **agent**. Multi-agent discipline lives
in [`AGENTS.md`](AGENTS.md).

---

## Tools — stop parsing by hand

Executable `bash` scripts that pre-digest the repo so agents run **one command** and read structured facts
instead of re-reading the tree every session. Output caches to `.claude/cache/`, fingerprinted to git state
(a stale cache rebuilds itself). Pure `bash` + coreutils; `rg`/`jq` used when present. Full index:
[`tools/README.md`](tools/README.md).

| Tool           | Answers                                                                                           |
| -------------- | ------------------------------------------------------------------------------------------------- |
| `digest.sh`    | "What am I working with?" — the start-of-task briefing (composes the five below)                  |
| `facts.sh`     | "How do I build/test/lint? Which gates and **test framework** does this project use?"             |
| `preflight.sh` | "Is the environment ready?" — `.env` / secrets / credentials / toolchain, **before** building     |
| `codemap.sh`   | "Where does X live? What's heavy? What's untested?"                                               |
| `untested.sh`  | "What needs a test before I touch it?" — the TDD worklist                                         |
| `dupes.sh`     | "What should I extract into the library?" — duplication candidates                                |
| `quality.sh`   | "Is it the highest quality — _strictly_?" — the gate (format·lint·types·SAST·audit), verify-only  |
| `watch.sh`     | "Run this without ever hanging" — hard **+ idle** timeouts around any command (exit 124 = killed) |

```sh
.claude/tools/digest.sh                          # brief yourself first (cached)
.claude/tools/quality.sh --with-tests            # the strict gate; exit 1 = a real failure
.claude/tools/watch.sh --idle 60 -- make build   # never wait forever on a stuck process
```

---

## Agents — the roster

Pick the **narrowest** agent for the job; compose them at a gate. Each is defined in `agents/<name>.md`.

**Build & extend**

- **`builder`** — TDD, library-first, fact-driven. Turns a contract into shipped code; _green or reverted, never half_.
- **`forger`** — the toolsmith. Forges the scripts/commands that make rules self-enforcing; iterates on feedback.
- **`innovator`** — vision. 10x ideas grounded in facts, each with a cheap experiment **and a kill criterion**.

**Advise & design**

- **`devil`** — the **risk magistrate**. Scores risk and pronounces `BLOCK` / `PROCEED-WITH-CONDITIONS` / `PROCEED` before risky code exists.
- **`architect`** — boundaries, contracts, data flow; produces decisions and interfaces, not code.
- **`documenter`** — docs only; never touches source, examples copied from tests.

**Verify (converge here)**

- **`reviewer`** — strict merge review: correctness, leaks, contract violations, bloat.
- **`security`** — white-box attacker; finds the exploit, rates it, names the minimal fix.
- **`benchmarker`** — performance in numbers against a baseline; no adjectives.
- **`compat-tester`** — measured behavioral parity against a reference (spec, prior version, competitor).
- **`norminette`** — strict 42 C-norm enforcer (opt-in for C / 42 projects).

---

## Rules — the engineering backbone

Always-on rules (`alwaysApply`) that bind every task:

- **`risk`** — when a decision must face the devil's verdict before becoming code, and how risk is scored.
- **`library-first`** — extract the reusable primitive before duplicating; features are thin glue.
- **`prompt-contract`** — facts in, evidence out: gather facts before acting, return proof not adjectives.
- **`quality-bar`** — strictest mode, every layer (lint · SAST · supply-chain audit · a11y), one command.
- **`dsa-and-memory`** — pick the optimal data structure + algorithm; pool allocations (Rust manages its own).
- **`test-frameworks`** — per-language reference; **detect and use** the project's framework, don't reinvent it.
- **`run-safely`** — verify config before building; bound every command so nothing hangs.
- **`minimalism-ladder`** + **`minimalism-markers`** — the _ponytail_ ladder: YAGNI → stdlib → platform →
  existing dep → one-liner → minimum, with a performance override on hot paths.
- **`refactor-common`** — universal structural / naming / error-handling / testing invariants.

Tech-scoped rules load by glob when you touch that language: `refactor-{c,go,rust,typescript,shell}`,
`api-convention`. `/refactor <tech>` reads `rules/refactor-<tech>.md` directly.

---

## Quick start

1. **Install** — copy these files into your project's `.claude/` directory (this repo _is_ that directory's
   contents). Keep `settings.json` valid JSON.
2. **Brief Claude** — `.claude/tools/digest.sh` to see the stack, toolchain, test framework, untested files,
   and duplication at a glance.
3. **Build something** — describe the feature; Claude runs the arc: `/prompt` → `/deal` (if risky) →
   `builder` (TDD) → `/quality`.
4. **Ship** — land behind your verification gate, green at the strict `quality-bar`.

Everyday handles: `/prompt <request>`, `/deal <plan>`, `/quality [--with-tests]`, `/refactor <tech> <path>`,
`/workflow:feature <desc>`, `/workflow:harden <module>`.

---

## Binding rules

These bind every rule, command, skill, workflow, tool, and subagent — even one-off tasks:

1. **Never co-author** — no `Co-Authored-By` / "Generated with" trailer.
2. **Use the project's own toolchain** — detect lifecycle commands with `.claude/tools/facts.sh` and run them
   under `.claude/tools/watch.sh`; don't assume a runtime or hand-roll what the project already scripts.
3. **Backward-compatible by default** — new behavior is additive / opt-in until proven; don't break existing callers.
4. **Backend-agnostic** — a fix for one adapter, platform, or engine that breaks another is not done.
5. **Measured, not claimed** — every perf number cites an artifact + the command that reproduces it (`benchmarker`).
6. **Confirm the irreversible** — pushes, deploys, deletions, data migrations, security cutovers need an explicit human trigger.
7. **Stage risky changes** — verify the new path against the old before deleting the old; UNKNOWN = FAIL.
8. **A gate is the unit of "done"** — land work behind the project's verification gate (a `scripts/verify/`
   check or CI job), green at the strict `quality-bar`.

---

## Repository layout

```
.claude/
├── README.md          this file — orientation
├── AGENTS.md          multi-agent / subagent discipline
├── agents/*.md        specialist personas (builder, forger, innovator, devil, …)
├── rules/*.md         always-on + tech-scoped constraints
├── commands/*.md      single-shot actions (/prompt, /quality, /refactor, …)
├── skills/<n>/SKILL.md auto-triggering capabilities (debug, write-test, …)
├── workflows/*.md      multi-phase playbooks (/workflow:deal, feature, harden, …)
├── tools/*.sh          the executable layer (digest, quality, watch, …) + lib/common.sh
├── settings.json       committed harness config (permissions / env / hooks)
└── assets/             the mascot
```

---

## Extending claude-chai (authoring conventions)

Match the exemplars: `commands/refactor.md`, `rules/refactor-common.md`, `skills/debug/SKILL.md`,
`workflows/harden.md`, `tools/quality.sh`. **Voice everywhere:** terse, imperative, present-tense, hard
numbers, no filler (`simply` / `just` / `easy` are banned). Em-dash `—` for clauses. Tool names in backticks.

- **Rules** — YAML frontmatter, then `#` title + `##` sections. Two shapes, never mixed: universal
  (`description` + `alwaysApply: true`, no globs — the discipline rules) or tech-scoped
  (`globs: ["**/*.ext"]` + `description`, shaped `## Idioms` / `## Patterns` / `## After refactoring`).
  **Load-bearing:** `/refactor <tech>` reads `rules/refactor-<tech>.md` literally — spell the filename exactly.
- **Commands** — frontmatter with one `description:` ending in `Usage: /<name> <args>`; body opens with
  `<Label>: $ARGUMENTS`; phased `## Workflow` / `### Phase N — <verb>`; self-abort if a required file is missing.
- **Skills** — a directory `skills/<name>/` holding exactly `SKILL.md`. **Directory name = frontmatter
  `name`** (lowercase-hyphenated, no `.md`). Frontmatter: `name`, `description: >` ending in
  `Auto-triggers on: "phrase", "phrase"`, `tools:` (minimal). Body: preamble, numbered `## N. <Verb>` phases,
  last phase is `Report`.
- **Workflows** — frontmatter `description: >` ending in `Usage: /workflow:<name> <args>`; numbered
  `## N. <Phase>`; **one bold human gate** before any behavior change; final `## N. Report` naming a dated
  artifact. Workflows **reference** skills/commands by name — never re-explain them.
- **Tools** — executable `bash`, thin glue over `lib/common.sh` (one concern each, no duplication). Support
  `--summary` + `--refresh`, emit markdown, cache to `.claude/cache/`; gates exit non-zero on failure.
  Conventions + index in [`tools/README.md`](tools/README.md). The `forger` builds these.
- **Agents** — frontmatter `name` / `description: >` (with triggers) / `tools:` / optional `model:`. Body: a
  persona ("You are…"), principles, what-you-do / what-you-don't, and an output format.

Keep **one source of truth per concept** — reference it, don't re-document it.

## Settings

- `settings.json` — committed, repo-wide config (permissions / env / hooks). **Must be valid JSON**
  (`{}` at minimum — an empty file fails to parse).
- `settings.local.json` — machine-local toggles (e.g. `disabledMcpjsonServers`); not shared.
