# claude-deal-with-the-devil

![mascot](image.png)

A drop-in `.claude/` setup that helps Claude Code write code like a careful engineer
instead of a fast one. It works in any project, whatever the language or stack.

The idea is simple: look before guessing, write a test before the code, think twice
before anything risky, and don't call something "done" until it actually passes a real
quality check.

---

## Why this exists

Claude is great at writing code quickly. The trouble is that a quick, confident answer
to a question you haven't fully thought through is often wrong in a way that looks
right.

This config pushes back on that. It nudges the reasoning into the open and asks for
evidence before action. In practice it fixes five habits:

- **Guessing instead of looking.** Small scripts pre-read the repo so Claude works from
  a summary, not a fresh re-read every time.
- **Rushing risky decisions.** The `devil` reviews a plan and says go or stop *before*
  any code gets written — and a hook now blocks the irreversible rather than reminding
  you about it.
- **Reinventing things.** A "reuse first" habit and a duplicate-finder keep the code
  from sprawling.
- **"Looks done."** A strict, multi-tool check is the only thing allowed to call work
  finished.
- **Approximations passed off as facts.** Every heuristic here states what it gets
  wrong, and a tool checks that it does.

---

## How a task flows

```
/prompt          →   /deal           →   builder              →   /quality
write a spec         the devil          test-first, reuse        run the strict gate
                     decides go/stop    red → green → refactor
```

1. **`/prompt`** turns a vague request into a clear spec, with a "done when" that a test
   can actually verify.
2. **`/deal`** sends risky plans to the `devil`, which weighs how much could break, how
   easily it's undone, and how confident the plan really is — then says BLOCK or
   PROCEED. Small, reversible work skips this.
3. **`builder`** does the work: build the reusable piece first, write the failing test,
   write the minimum code to pass, then clean up. Every step gets run and checked.
4. **`/quality`** runs the full gate (config integrity, formatting, lint, types,
   security scan, dependency audit, accessibility). Green, with tests passing, is what
   "done" means.

Two habits run through all of it: back claims with a command and its output (or a
`file:line`), and never leave a half-finished tree behind — it's green or it's reverted.

For the whole arc in one command: `/workflow:feature <description>`. To take existing
code from "it works" to "it holds": `/workflow:harden <module>`. The rest:
`/workflow:deal` (a verdict on a risky plan), `/workflow:onboard-app` (get oriented in a
new codebase), `/workflow:ship` (the release pipeline), `/workflow:migrate-db` (author a
migration, paired with `/migrate`), `/workflow:compat-audit` (endpoint-by-endpoint parity).

---

## Quick start

1. Copy these files into your project's `.claude/` directory — this repo *is* that
   directory's contents.
2. Run `.claude/tools/digest.sh` for the stack, toolchain, test framework, untested
   files and duplication at a glance.
3. Describe a feature and let Claude run the arc: `/prompt` → `/deal` (if risky) →
   `builder` → `/quality`.
4. Optional: `cp settings.local.json.example settings.local.json` for machine-local
   toggles. `settings.json` is committed and shared.

Check it landed correctly:

```sh
.claude/tools/selfcheck.sh     # every documented name resolves; frontmatter is valid
.claude/tools/context.sh       # what this config costs you per session
```

---

## The seven layers

Reach for the smallest one that fits.

| Layer | Where | What it is | How it runs |
| --- | --- | --- | --- |
| **Rules** | `rules/*.md` | Standing constraints, the craft discipline | automatic, by scope |
| **Commands** | `commands/*.md` | One focused action | you type `/<name> <args>` |
| **Skills** | `skills/<name>/SKILL.md` | A capability that triggers on intent | a trigger phrase, or by name |
| **Workflows** | `workflows/*.md` | Multi-step playbooks | `/workflow:<name> <args>` |
| **Tools** | `tools/*.sh` | Scripts: digesters, the quality gate, etc. | Claude runs `.claude/tools/<name>.sh` |
| **Agents** | `agents/*.md` | Specialist personas you delegate to | by name, trigger, or from a workflow |
| **Hooks** | `hooks/` | The part that *enforces* rather than reminds | the harness fires them |

Rough guide: something that must always hold is a **rule**; a one-shot is a **command**;
a capability that fires on intent is a **skill**; a gated multi-step procedure is a
**workflow**; a recurring parse or check is a **tool**; a distinct perspective is an
**agent**; a constraint that should be impossible to ignore is a **hook**. Multi-agent
details live in [`AGENTS.md`](AGENTS.md).

---

## Tools

Small bash scripts that read the repo for you, so Claude runs one command and gets
structured facts instead of re-reading everything each session. Output is cached in
`cache/` and tied to git state, so a stale cache rebuilds itself. Plain bash and
coreutils, with `rg`/`jq` used when they're around. Full list:
[`tools/README.md`](tools/README.md).

| Tool | Answers |
| --- | --- |
| `digest.sh` | "What am I working with?" — the start-of-task briefing |
| `facts.sh` | "How do I build, test, and lint? Which test framework is this?" |
| `preflight.sh` | "Is the environment ready?" — env, secrets, toolchain, before building |
| `codemap.sh` | "Where does X live? What's heavy? What's untested?" |
| `untested.sh` | "What needs a test before I touch it?" |
| `dupes.sh` | "What should I pull into the shared library?" |
| `quality.sh` | "Is this actually up to standard?" — the gate, read-only |
| `watch.sh` | "Run this without letting it hang" — timeouts around any command |
| `selfcheck.sh` | "Does this config tell the truth about itself?" — the drift gate |
| `context.sh` | "What does this config cost me every session?" |
| `ponytail.sh` | "Which approximations here don't admit they're approximations?" |
| `scripts.sh` | "Is there already a script for this?" — the pinned external registry |

```sh
.claude/tools/digest.sh                          # brief yourself first (cached)
.claude/tools/quality.sh --with-tests            # the strict gate; exit 1 means a real failure
.claude/tools/watch.sh --idle 60 -- make build   # never wait forever on a stuck process
.claude/tools/scripts.sh list                    # the vetted external script library
```

---

## The agents

Pick the narrowest one for the job and combine them when you check the work. Each lives
in `agents/<name>.md`.

**Build and extend**

- **`builder`** — test-first, reuse-first. Turns a contract into shipped code; green or
  reverted, never half.
- **`forger`** — the toolsmith, builds the scripts and commands that make rules enforce
  themselves.
- **`innovator`** — the ideas person, with a cheap experiment and a clear way to know
  when to drop it.

**Advise and design**

- **`devil`** — weighs the risk and decides BLOCK / PROCEED-WITH-CONDITIONS / PROCEED
  before risky code exists.
- **`architect`** — boundaries, contracts, and data flow; produces decisions and
  interfaces, not code.
- **`documenter`** — docs only, never touches source; examples come from the tests.

**Verify**

- **`reviewer`** — strict merge review: correctness, leaks, broken contracts, bloat.
- **`security`** — thinks like an attacker, finds the exploit, rates it, names the
  smallest fix.
- **`benchmarker`** — performance as numbers against a baseline, no adjectives.
- **`compat-tester`** — checks behavior matches a reference (a spec, a prior version, a
  competitor).
- **`norminette`** — strict 42 C-norm enforcer, opt-in for C and 42 projects.

---

## The skills

Skills are the breadth layer. Only a skill's `description` sits in context until it
fires, so a wide roster is cheap — and `/skill-doctor` prunes what goes unused.

| Skill | What it does |
| --- | --- |
| `debug` | Reproduce, bisect, prove the mechanism, then fix once |
| `write-test` | Generate coverage in the project's own framework |
| `api-endpoint` | Scaffold a REST endpoint across the planes |
| `ponytail` | Make every approximation state what it gets wrong |
| `frontend` | Component and state boundaries, tokens, responsive, theme, a11y |
| `browser-testing` | Drive a real browser via Playwright and come back with evidence |
| `brainstorm` | Diverge wide, converge on evidence, leave with a kill criterion |
| `design-review` | Hierarchy, rhythm, type, states — why it "looks off" |
| `originality` | Prior-art pass: reuse, wrap, borrow, or build — and say which |
| `perf-budget` | Set the number before optimising, then measure against it |
| `context-budget` | Measure and cut what this config costs per session |
| `commit-craft` | Atomic commits, Conventional Commits, never co-authored |
| `doc-sync` | Find the docs a change just made false, and fix those |

---

## Rules

Always on, shaping every task: **`risk`** (when a decision must face the devil) ·
**`library-first`** (extract before you duplicate) · **`prompt-contract`** (facts in,
evidence out) · **`quality-bar`** (the strictest check, one command) ·
**`dsa-and-memory`** (the right structure, pooled allocations) · **`test-frameworks`**
(detect, don't invent) · **`run-safely`** (preflight, and never hang) ·
**`minimalism-ladder`** and **`minimalism-markers`** (climb only as high as you must;
the same for words) · **`refactor-common`** (the shared craft discipline) ·
**`ponytail`** (name what your heuristic gets wrong) · **`memory`** (remember the
expensive facts, nothing else).

Loaded only when you touch matching files, so they cost nothing otherwise:
`refactor-c` · `refactor-go` · `refactor-rust` · `refactor-typescript` ·
`refactor-shell` · `api-convention` · `script-library`.
`/refactor <tech>` reads `rules/refactor-<tech>.md` by exact filename.

---

## Settings, hooks and MCP

- **`settings.json`** — committed and shared: permissions (read-only tooling allowed,
  destructive Bash asks), `env`, status line, and `attribution` set to empty strings so
  binding rule #1 is enforced rather than merely stated.
- **`settings.local.json`** — machine-local, gitignored. Start from
  `settings.local.json.example`.
- **`hooks/`** — where rules stop being reminders. `PreToolUse` denies the catastrophic
  and asks on the irreversible; `PostToolUse` gates the file you just edited;
  `SessionStart` hands over the briefing; `PreCompact` protects the facts worth keeping.
  Details and limits in [`hooks/HOOKS-README.md`](hooks/HOOKS-README.md).
- **`.mcp.json`** — `playwright`, `context7`, `deepwiki`, and `supermemory`
  (**off by default** — see [`doc/MEMORY.md`](doc/MEMORY.md) for what it costs you).

---

## The script library

`tools/scripts.sh` reaches a curated, sha-pinned subset of
[`Univers42/scripts`](https://github.com/Univers42/scripts) — valgrind wrappers, a
comment stripper, C-norm helpers, header-cycle detection, markdown-to-PDF.

```sh
.claude/tools/scripts.sh list
.claude/tools/scripts.sh show valgrind-check
.claude/tools/scripts.sh run strip-comments -- src/ --stats
```

Only names in [`scripts/REGISTRY.md`](scripts/REGISTRY.md) run, and each is invoked with
an explicit interpreter rather than its shebang — 44 of 56 upstream scripts don't have
one. Everything runs under `watch.sh`. The registry records what was vetted, what was
only read, and what was deliberately excluded.

---

## Binding rules

These hold for everything here, even one-off tasks:

1. **Never co-author** — no `Co-Authored-By` or "Generated with" trailer.
2. **Use the project's own toolchain** — find the real commands with `facts.sh`, run
   them under `watch.sh`, don't hand-roll what the project already scripts.
3. **Backward-compatible by default** — new behavior is additive and opt-in until
   proven.
4. **Backend-agnostic** — a fix for one adapter or engine that breaks another isn't done.
5. **Measured, not claimed** — every performance number cites an artifact and the
   command that reproduces it.
6. **Confirm the irreversible** — pushes, deploys, deletions, data migrations, and
   security cutovers need an explicit human go-ahead.
7. **Stage risky changes** — prove the new path against the old before deleting the old;
   if it's unknown, treat it as a failure.
8. **A gate is the unit of "done"** — land work behind the project's verification gate,
   green at the strict `quality-bar`.
9. **Say what you get wrong** — every approximation ships its limitation
   (`rules/ponytail.md`).

---

## Repository layout

```
.claude/
├── README.md          this file
├── AGENTS.md          multi-agent discipline
├── settings.json      committed config (permissions / env / hooks)
├── .mcp.json          MCP servers
├── agents/*.md        specialist personas (builder, forger, devil, reviewer, …)
├── rules/*.md         always-on and path-scoped constraints
├── commands/*.md      single-shot actions (/prompt, /quality, /refactor, …)
├── skills/<n>/SKILL.md  capabilities that trigger on intent (debug, frontend, …)
├── workflows/*.md     multi-phase playbooks (/workflow:feature, harden, deal, …)
├── tools/*.sh         the scripts (digest, quality, selfcheck, …) + lib/common.sh
├── hooks/             the enforcement + notification handler
├── scripts/           REGISTRY.md — the vetted external script library
├── tests/             regression tests for the tools and hooks
├── doc/               MEMORY.md, REFERENCES.md
└── cache/             tool output, gitignored, fingerprinted to git state
```

---

## Extending it

When you add something, match the existing examples: `agents/devil.md`,
`rules/refactor-common.md`, `commands/refactor.md`, `skills/debug/SKILL.md`,
`workflows/harden.md`, `tools/quality.sh`. Keep the voice short and direct, use real
numbers, and skip filler words like "simply" or "just".

- **Rules** — a universal rule has **no frontmatter** (that is the signal for
  always-load). A path-scoped rule has `paths:` and nothing else. `globs:` and
  `alwaysApply:` are Cursor fields — Claude Code ignores them, and the rule then loads
  every session anyway.
- **Commands** — frontmatter with one `description:` ending in `Usage: /<name> <args>`;
  the body opens with `<Label>: $ARGUMENTS` and uses phased `## Workflow` sections.
- **Skills** — a directory `skills/<name>/` whose `SKILL.md` frontmatter `name` matches
  the directory. `description:` ends in `Auto-triggers on: "phrase", "phrase"`. Tool
  restriction is `allowed-tools:` — **not** `tools:`, which is an agent field. Keep the
  body short and put depth in a sibling `reference.md`.
- **Workflows** — `description:` ending in `Usage: /workflow:<name> <args>`; numbered
  phases; one clear human gate before any behavior change; a final `## Report`.
- **Tools** — executable bash, shebang on line 1, thin glue over `lib/common.sh`, one
  concern each. Support `--summary` and `--refresh`, emit markdown, cache to `cache/`,
  exit non-zero on failure. The `forger` builds these.
- **Agents** — frontmatter with `name` (matching the filename), a `description:` with
  triggers, `tools:`, and optionally `model:` and `memory:`.

Then run `tools/selfcheck.sh`. It fails on a documented name that doesn't exist, a
frontmatter field Claude Code doesn't read, and a tool without a shebang — the three
ways this config has drifted before.

```sh
bash tools/selfcheck.sh
bash tools/ponytail.sh --strict
for t in tests/test_*.sh; do bash "$t" || echo "FAILED: $t"; done
bash tools/quality.sh --no-audit
```

Keep one source of truth per concept and reference it instead of repeating it.
