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

```text
/devil:prompt   →   /devil:deal       →   builder                  →   /devil:quality
write a spec        the devil             test-first, reuse            run the strict gate
                    decides go/stop       red → green → refactor
```

1. **`/devil:prompt`** turns a vague request into a clear spec, with a "done when" that a test
   can actually verify.
2. **`/devil:deal`** sends risky plans to the `devil`, which weighs how much could break, how
   easily it's undone, and how confident the plan really is — then says BLOCK or
   PROCEED. Small, reversible work skips this.
3. **`builder`** does the work: build the reusable piece first, write the failing test,
   write the minimum code to pass, then clean up. Every step gets run and checked.
4. **`/devil:quality`** runs the full gate (config integrity, formatting, lint, types,
   security scan, dependency audit, accessibility). Green, with tests passing, is what
   "done" means.

Two habits run through all of it: back claims with a command and its output (or a
`file:line`), and never leave a half-finished tree behind — it's green or it's reverted.

For the whole arc in one command: `/devil:feature <description>`. To take existing
code from "it works" to "it holds": `/devil:harden <module>`. The rest:
`/devil:deal` (a verdict on a risky plan), `/devil:onboard-app` (move an external app
onto the project's backend, with a go/no-go gate after recon), `/devil:ship` (the release pipeline), `/devil:migrate-db` (author a
migration, paired with `/devil:migrate`), `/devil:compat-audit` (endpoint-by-endpoint parity),
`/devil:handoff` (the portable document a fresh session, or another harness, continues from),
`/devil:retro` (a session or a PR turned into checks to build and rules to propose),
`/devil:to-tickets` (a spec cut into vertical-slice tickets with blocking edges, published
to the host's tracker once you approve the list).

---

## Quick start

This repo is a Claude Code plugin named `devil`, served by the `univers42` marketplace
that lives in the same tree (`.claude-plugin/`).

```sh
claude plugin marketplace add Univers42/claude-deal-with-the-devil
claude plugin install devil@univers42        # add --scope project to share it with a repo
```

Inside a session the same two steps are `/plugin marketplace add
Univers42/claude-deal-with-the-devil` and `/plugin install devil@univers42`. Every
asset is namespaced by the plugin: `/devil:prompt`, `/devil:quality`, the agents
`devil:builder`, `devil:reviewer`, and so on. The bindings in `hooks/hooks.json` start
enforcing as soon as the plugin is enabled.

Then seed the repo, because the plugin cannot carry the always-on rules, the
permissions, or a `CLAUDE.md` fragment:

```sh
devil setup --check      # one row per stage, exit 1 if this repo is not seeded yet
devil setup --apply      # write it; re-run after every plugin update
```

To work on the kit itself, load the checkout for one session without installing it:

```sh
claude --plugin-dir .
```

A plugin cannot carry `rules/` (there is no rules component), the permissions and other
keys of `settings.json`, or a `CLAUDE.md` fragment. It can carry MCP servers, but this
kit keeps its four in `templates/` as well: a server the plugin ships is on for every
host, and the `supermemory` opt-out lives in the host's settings. `devil setup` seeds
`rules/`, `templates/settings.json` and the rest into a host's `.claude/`
(`templates/README.md` names every file); `--seed-mcp` adds the MCP servers, opt-in,
because a server is a network call.

Check the plugin is well-formed:

```sh
claude plugin validate .claude-plugin/plugin.json --strict   # manifest and hooks/hooks.json
bash tools/selfcheck.sh        # every documented name resolves; frontmatter is valid
bash tools/context.sh          # what this config costs you per session
```

---

## Other harnesses

The canonical sources are the Claude-format files. A harness that cannot read them gets a
generated dialect under `dist/<harness>/`, produced by one tool, and `--check` keeps the
copy from drifting.

| Harness | State |
| --- | --- |
| **OpenCode 2.x** | supported. `devil export opencode` writes `dist/opencode/`: 11 subagents with their `tools:` list mapped to V2 permissions, 13 commands, the 12 always-on rules, and a plugin that bridges `hooks/scripts/hooks.py` so the deny, the post-edit gate, the session briefing and `bin/` on the agent's `PATH` all work. Verified live on 2.0.18. Start at [`dist/opencode/README.md`](dist/opencode/README.md) |
| Copilot CLI, Gemini CLI, Codex CLI | planned. What each one can and cannot read is measured in [`doc/HARNESSES.md`](doc/HARNESSES.md); the exporters are not written yet |

```sh
devil export opencode            # write dist/opencode
devil export --check opencode    # exit 1 on drift; CI runs this
```

---

## The seven layers

Reach for the smallest one that fits.

| Layer | Where | What it is | How it runs |
| --- | --- | --- | --- |
| **Rules** | `rules/*.md` | Standing constraints, the craft discipline | automatic, every session |
| **Commands** | `commands/*.md` | One focused action | you type `/devil:<name> <args>` |
| **Skills** | `skills/<name>/SKILL.md` | A capability that triggers on intent | a trigger phrase, or by name |
| **Workflows** | `commands/*.md` tagged `metadata.kind: workflow` | Multi-step playbooks | `/devil:<name> <args>` |
| **Tools** | `tools/*.sh`, dispatched by `bin/devil` | Scripts: digesters, the quality gate, etc. | Claude runs `devil <name>` |
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
the host's `.claude/cache/` and tied to git state, so a stale cache rebuilds itself.
Plain bash and coreutils, with `rg`/`jq` used when they're around. Full list:
[`tools/README.md`](tools/README.md).

Every tool is reached by name through `bin/devil`: `devil digest` runs
`tools/digest.sh`, `devil orch oc-status` runs `tools/orch/oc-status.sh`, and a bare
`devil` lists them all. An enabled plugin puts its `bin/` on the Bash tool's `PATH`
(checked with `claude --plugin-dir`, where `command -v devil` printed the checkout's
`bin/devil`). Your own terminal does not get that entry: run the checkout's
`bin/devil` by path, or add its directory to `PATH`. The tool runs in your current
directory, so `devil digest` describes the project you are in.

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
| `caveat.sh` | "Which approximations here don't admit they're approximations?" |
| `export.sh` | "Has another harness's generated copy drifted from these sources?" |
| `scripts.sh` | "Is there already a script for this?" — the pinned external registry |

```sh
devil digest                         # brief yourself first (cached)
devil quality --with-tests           # the strict gate; exit 1 means a real failure
devil watch --idle 60 -- make build  # never wait forever on a stuck process
devil scripts list                   # the vetted external script library
```

---

## The agents

Pick the narrowest one for the job and combine them when you check the work. Each lives
in `agents/<name>.md`.

### Build and extend

- **`builder`** — test-first, reuse-first. Turns a contract into shipped code; green or
  reverted, never half.
- **`forger`** — the toolsmith, builds the scripts and commands that make rules enforce
  themselves.
- **`innovator`** — the ideas person, with a cheap experiment and a clear way to know
  when to drop it.

### Advise and design

- **`devil`** — weighs the risk and decides BLOCK / PROCEED-WITH-CONDITIONS / PROCEED
  before risky code exists.
- **`architect`** — boundaries, contracts, and data flow; produces decisions and
  interfaces, not code.
- **`documenter`** — docs only, never touches source; examples come from the tests.

### Verify

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
The table below is generated from the frontmatter (`bash tools/index.sh --write`),
so it cannot drift from the tree; `/devil:guide` prints the same rows live. The
seven path-scoped skills are listed under [Rules](#rules) instead, since they load
only on a matching file.

<!-- devil:index:skills:start -->

| Skill | Stage | Use when |
| --- | --- | --- |
| `api-endpoint` | stable | a route is missing, a handler needs wiring, a resource has to be reachable over HTTP, or a client calls the API by hand |
| `brainstorm` | beta | Generate options properly — diverge wide before judging, then converge on evidence and cost (no Use when yet) |
| `browser-testing` | beta | Verify a change in a real browser and come back with evidence — navigate, interact, snapshot, read the console (no Use when yet) |
| `caveat` | beta | a change adds a heuristic, a sample, a bounded read, a timeout, a cache or a derived number, or when you need to know what a piece of code is bad at |
| `commit-craft` | stable | changes are uncommitted, one commit mixes several concerns, a message does not say what changed, or a branch needs tidying before review |
| `context-budget` | beta | Measure and cut what this config costs in context every session — always-on rules, skill descriptions, unused skills (no Use when yet) |
| `debug` | stable | a test fails, a build breaks, a crash has no obvious cause, behaviour differs between machines, or a fix that worked yesterday stopped working |
| `design-review` | beta | Judge an interface the way a design engineer does — hierarchy, rhythm, type, states, and the empty/loading/error cases nobody built (no Use when yet) |
| `doc-sync` | beta | Find the documentation a change just made false, and fix it — examples copied from passing tests, never composed (no Use when yet) |
| `frontend` | beta | Build UI that holds up — component and state boundaries, design tokens, responsive and theme behaviour, and the accessibility gate (no Use when yet) |
| `grill` | beta | a request is underspecified, the done-when is not stateable, or a rules/risk.md trigger is unresolved before code starts |
| `originality` | beta | Prior-art pass before writing something new — find what already does this, in the repo and outside it, then say plainly whether to reuse, wrap, or build and why (no Use when yet) |
| `perf-budget` | beta | Set the number before you optimise, then measure against it (no Use when yet) |
| `prototype` | beta | an approach's cost, performance or feasibility is unproven, or when a spike, benchmark or quick prototype is asked for |
| `write-test` | beta | a module has no tests, coverage is thin, a fix needs a regression test, or a change should land with proof it still works |

<!-- devil:index:skills:end -->

---

## Commands and workflows

A command is one focused action, a workflow a gated multi-step procedure; both are
`commands/<name>.md`, told apart by `metadata.kind`, and both are typed as
`/devil:<name>`. Generated like the skills table above.

<!-- devil:index:commands:start -->

| Command | Stage | Does | Usage |
| --- | --- | --- | --- |
| `bench` | beta | Run comparative benchmarks (the project vs the reference baseline) and flag regressions. | /devil:bench [load\|capacity\|footprint\|mem\|startup] |
| `compat` | beta | Run the feature-parity comparison against the reference baseline for the project. | /devil:compat [feature-area] |
| `guide` | beta | Print every asset this plugin ships, with its stage and what it is for. (you run it) | /devil:guide |
| `handoff` | beta | Write a portable handoff document so a fresh session, or another harness, can continue the work. (you run it) | /devil:handoff |
| `migrate` | beta | Run or inspect the project's migrations across backends. | /devil:migrate <status\|all\|backend> |
| `prompt` | beta | Turn a rough request into a precise, fact-grounded spec the builder can execute. | /devil:prompt <rough request> |
| `quality` | beta | Run every strict quality gate in the repo and report PASS/FAIL/SKIP. | /devil:quality [--no-audit] [--with-tests] |
| `refactor` | beta | Deep refactor at the strictest standard for the technology. | /devil:refactor <technology> [file or module path] |
| `retro` | beta | Turn what went wrong in a session or a pull request into checks to build and rules to propose. (you run it) | /devil:retro [<pr> \| <git range>] |
| `setup` | beta | Seed into this repo what the plugin cannot ship: the always-on rules, the permissions, the CLAUDE.md block, the OpenCode wiring and the gitignore lines. (you run it) | /devil:setup [--check] [--apply] [--tracker github\|gitlab\|local] [--seed-mcp] [--skip <stage>] |
| `to-tickets` | beta | Split a spec into vertical-slice tickets with blocking edges and publish them to the tracker. (you run it) | /devil:to-tickets <spec file or issue> |

<!-- devil:index:commands:end -->

<!-- devil:index:workflows:start -->

| Command | Stage | Does | Usage |
| --- | --- | --- | --- |
| `compat-audit` | beta | Behavioral parity audit against a reference spec. | /devil:compat-audit |
| `deal` | beta | Deal with the devil — submit a risky plan to the risk magistrate before it becomes code. The decision-quality gate. | /devil:deal <the plan or decision> |
| `feature` | beta | Build a feature end to end — spec, risk verdict, library-first TDD, strict gate. The default arc for new work. | /devil:feature <description> |
| `harden` | beta | Take an existing module from "it works" to "it holds" — cover it, attack it, bound it, then gate it. | /devil:harden <module or path> |
| `migrate-db` | beta | Author and land a new database migration safely. (you run it) | /devil:migrate-db <what the migration does> |
| `onboard-app` | beta | Take an external app and migrate it to run entirely on the project. | /devil:onboard-app <repo-url-or-path> |
| `ship` | beta | Full release pipeline. (you run it) | /devil:ship <major\|minor\|patch> |

<!-- devil:index:workflows:end -->

### Retired

A retired name stays resolvable so an old reference answers instead of dead-ending,
and points at what replaced it. Nothing here is invocable.

<!-- devil:index:retired:start -->

| Retired | In | Use instead |
| --- | --- | --- |
| `ponytail` | 1.0.0 | `caveat` |

<!-- devil:index:retired:end -->

---

## Rules

Always on, shaping every task: **`risk`** (when a decision must face the devil) ·
**`library-first`** (extract before you duplicate) · **`prompt-contract`** (facts in,
evidence out) · **`quality-bar`** (the strictest check, one command) ·
**`dsa-and-memory`** (the right structure, pooled allocations) · **`test-frameworks`**
(detect, don't invent) · **`run-safely`** (preflight, and never hang) ·
**`minimalism-ladder`** and **`minimalism-markers`** (climb only as high as you must;
the same for words) · **`refactor-common`** (the shared craft discipline) ·
**`caveat`** (name what your heuristic gets wrong) · **`memory`** (remember the
expensive facts, nothing else).

Loaded only when you touch matching files, so they cost nothing otherwise. They are
`paths:` skills tagged `metadata.stage: rule`, because a plugin cannot ship `rules/`.
`/devil:refactor <tech>` invokes the `refactor-<tech>` skill. Generated like the
tables above.

<!-- devil:index:rules:start -->

| Rule skill | Loads for |
| --- | --- |
| `api-convention` | **/routes/**, **/handlers/**, **/controllers/**, **/api/**, **/*router*, **/*controller* |
| `refactor-c` | **/*.c, **/*.h |
| `refactor-go` | **/*.go |
| `refactor-rust` | **/*.rs |
| `refactor-shell` | **/*.sh, **/*.bash |
| `refactor-typescript` | **/*.ts, **/*.tsx |
| `script-library` | **/*.sh, **/*.bash, **/*.py, **/Makefile, **/makefile |

<!-- devil:index:rules:end -->

---

## Settings, hooks and MCP

The plugin loads `hooks/hooks.json` itself. Settings and MCP servers are files a host
receives, so they live in `templates/` ([`templates/README.md`](templates/README.md)):

- **`templates/settings.json`**: copied to the host's `.claude/settings.json`. It
  holds permissions (read-only tooling allowed, destructive Bash asks), `env`, status line,
  and `attribution` set to empty strings so binding rule #1 is enforced rather than
  merely stated.
- **`settings.local.json`**: the host's machine-local file, gitignored. Start from
  `settings.local.json.example`.
- **`hooks/`**: where rules stop being reminders. `hooks/hooks.json` binds the events
  to `hooks/scripts/hooks.py`: `PreToolUse` denies the catastrophic and asks on the
  irreversible; `PostToolUse` gates the file you just edited; `SessionStart` hands over
  the briefing; `PreCompact` protects the facts worth keeping, and names
  `/devil:handoff` for work that must continue in another session. Details and limits in
  [`hooks/HOOKS-README.md`](hooks/HOOKS-README.md).
- **`templates/mcp.json`**: copied to the host's `.mcp.json`. It declares
  `playwright`, `context7`, `deepwiki`, and `supermemory` (**off by default**, see
  [`doc/MEMORY.md`](doc/MEMORY.md) for what it costs you).

---

## Decisions

A verdict that lives only in the session gets re-argued in six months, so two of
the three records are files, written from skeletons in
[`templates/`](templates/README.md):

- **The ADR**: `docs/adr/NNNN-<slug>.md` in the host repo, from
  [`templates/adr.md`](templates/adr.md). Status, Context (facts with
  `file:line`), Decision, the alternatives and why each lost, Consequences. Only
  under the **three-gate rule**: the decision is irreversible, it changes a public
  surface, or the `devil` returned something other than PROCEED. Below all three a
  commit message carries it.
- **The out-of-scope record**: `.out-of-scope/<concept>.md` in the host, from
  [`templates/out-of-scope.md`](templates/out-of-scope.md), for a concept the
  verdict rejected. The load-bearing line is the fact that would have to change for
  the answer to change. This kit keeps its own four in
  [`.out-of-scope/`](.out-of-scope/openai-sidecars.md).
- **The agent brief**: [`templates/agent-brief.md`](templates/agent-brief.md),
  Objective, Contract (inputs → outputs → done-when, plus out of scope),
  Constraints, Facts as pointers. `/devil:prompt` emits one; every job ends with
  its return block (`status` / `gates` / `changed` / `deviations` / `next`) so a
  caller greps it instead of reading a log.

Who writes what: the `devil` writes the ADR and the out-of-scope record with its
verdict, the `architect` designs three options under different constraints
(minimal, extensible, performance-first) and names the ADR path, the `builder`
returns the block, the `reviewer` reports two axes as two tables that are never
reranked against each other.

---

## The script library

`tools/scripts.sh` reaches a curated, sha-pinned subset of
[`Univers42/scripts`](https://github.com/Univers42/scripts) — valgrind wrappers, a
comment stripper, C-norm helpers, header-cycle detection, markdown-to-PDF.

```sh
devil scripts list
devil scripts show valgrind-check
devil scripts run strip-comments -- src/ --stats
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
   (`rules/caveat.md`).

---

## Repository layout

```text
./                     the plugin root (installed as `devil`, or loaded with --plugin-dir)
├── README.md          this file
├── AGENTS.md          multi-agent discipline
├── .claude-plugin/    plugin.json and marketplace.json
├── agents/*.md        specialist personas (builder, forger, devil, reviewer, …)
├── rules/*.md         always-on constraints (12)
├── commands/*.md      actions and multi-phase workflows, all /devil:<name>
│                      (kind: command → /devil:prompt, /devil:quality, …;
│                       kind: workflow → /devil:feature, /devil:harden, /devil:deal, …)
├── skills/<n>/SKILL.md  capabilities that trigger on intent (debug, frontend, …);
│                      the 7 path-scoped constraints ship here too (stage: rule)
├── bin/devil          the dispatcher: `devil <tool>`, `devil orch <sub>`
├── tools/*.sh         the scripts (digest, quality, selfcheck, …) + lib/common.sh
├── tools/orch/        headless OpenCode jobs and their gate (`devil orch …`)
├── hooks/             hooks.json bindings and hooks/scripts/hooks.py, the handler
├── templates/         what a host receives: settings.json, mcp.json, wizard.sh,
│                      plus the skeletons a command fills in (handoff.md, adr.md,
│                      out-of-scope.md, agent-brief.md)
├── .out-of-scope/     the concepts this kit refused, and the fact that decides it
├── settings.local.json.example  machine-local toggles for a host
├── scripts/           REGISTRY.md — the vetted external script library
├── tests/             regression tests for the tools, hooks, dispatcher and templates
└── doc/               MEMORY.md, REFERENCES.md, HARNESSES.md
```

---

## Releasing

`.claude-plugin/plugin.json` is the only version source; `CHANGELOG.md` repeats it as a
`## [x.y.z]` heading and `tools/release.sh --check` proves the two agree.

```sh
bash tools/release.sh bump patch     # edit, commit chore(release): vX.Y.Z, tag vX.Y.Z
```

The bump never pushes. Push the branch first, then the tag, by hand.

---

## Extending it

When you add something, match the existing examples: `agents/devil.md`,
`rules/refactor-common.md`, `commands/refactor.md`, `skills/debug/SKILL.md`,
`commands/harden.md`, `tools/quality.sh`. Keep the voice short and direct, use real
numbers, and skip filler words like "simply" or "just".

- **Rules** — a universal rule has **no frontmatter** (that is the signal for
  always-load) and lives in `rules/`. A constraint scoped to file types is a
  `paths:` skill under `skills/<name>/` tagged `metadata.stage: rule` with
  `user-invocable: false`, because a plugin cannot ship `rules/` and a skill with
  `paths:` lazy-loads on exactly the same mechanism. `globs:` and `alwaysApply:`
  are Cursor fields: Claude Code ignores them, and the file then loads every
  session anyway.
- **Commands** — frontmatter with one `description:` ending in `Usage: /devil:<name> <args>`
  and a block map `metadata:` holding `kind: command` (written as two lines; the
  selfcheck reader skips a flow map). The body opens with `<Label>: $ARGUMENTS` and uses
  phased `## Workflow` sections. A command only a person may run adds
  `argument-hint:` and `disable-model-invocation: true` (`commands/handoff.md`,
  `commands/retro.md`), and no other asset's body may `/`-reference one, because the
  Skill tool cannot reach it.
- **Skills** — a directory `skills/<name>/` whose `SKILL.md` frontmatter `name` matches
  the directory. `description:` ends in `Auto-triggers on: "phrase", "phrase"`. Tool
  restriction is `allowed-tools:` — **not** `tools:`, which is an agent field. Keep the
  body short and put depth in a sibling `reference.md`.
- **Workflows** — a command file `commands/<name>.md` whose `metadata:` holds
  `kind: workflow`, with `description:` ending in `Usage: /devil:<name> <args>`;
  numbered phases; one clear human gate before any behavior change; a final `## Report`.
  There is no `workflows/` directory: selfcheck fails on one.
- **Tools** — executable bash, shebang on line 1, thin glue over `lib/common.sh`, one
  concern each. Support `--summary` and `--refresh`, emit markdown, cache via
  `emit_cached`, exit non-zero on failure. A new `tools/<name>.sh` is `devil <name>` with
  no registration; docs cite it that way and selfcheck fails on a `devil <name>` that
  has no file. The `forger` builds these.
- **Agents** — frontmatter with `name` (matching the filename), a `description:` with
  triggers, `tools:`, and optionally `model:` and `memory:`.
- **Templates** are copy-and-fill scripts for the steps only a person can do. Edit only
  below the `# STAGES` marker; the library above it stays byte-identical in every copy.
  `templates/wizard.sh` is a provisioning procedure (dashboards, credentials, CI secrets,
  cutovers): the agent never runs one, `bash tests/test_templates.sh --trace <file>` is
  its static proof. `skills/debug/scripts/hitl-loop.sh` is a reproduction a person drives;
  the agent parses its `KEY=VALUE` tail and never wraps it in `tools/watch.sh`.
- **Decision templates** are the other kind: markdown skeletons a host repo receives and
  the kit never reads. `templates/adr.md`, `templates/out-of-scope.md` and
  `templates/agent-brief.md` are the three. Each stays at or under 40 lines and its
  required headings are asserted by `tests/test_templates.sh`, so dropping a section is a
  red test. A new heading means adding its pattern in the same change.

### The frontmatter, in full

`tools/skillcheck.sh` fails anything other than these shapes. All `metadata` values are
strings, so `since` is quoted: YAML reads a bare `1.0.0` as a float.

A skill, model-invocoked:

```yaml
---
name: debug
description: >
  Find the actual cause of a failure instead of guessing at fixes. Use when a test fails,
  a build breaks, a crash has no obvious cause, or behaviour differs between machines.
  Auto-triggers on: "why is this failing", "debug this", "this test is flaky",
  "it works locally", "fix this bug", "this crashes"
allowed-tools: Read, Grep, Glob, Bash
metadata:
  stage: stable
  since: "1.0.0"
---
```

A command (`kind: command`) or a workflow (`kind: workflow`) adds `argument-hint` and
`metadata.kind` on top of that. A user-only asset (one a person types, the model never
reaches) adds `disable-model-invocation: true`, and then no other asset may `/`-reference
it: a reference the model cannot follow is a dead step.

A retired tombstone keeps the name resolvable and points at what replaced it:

```yaml
---
name: old-name
description: Retired in 1.0.0. It became `replacement`, which is the live skill.
disable-model-invocation: true
metadata:
  stage: retired
  since: "0.9.0"
  retired-in: "1.0.0"
  replaced-by: replacement
---
Retired. Nothing here is invocable; the replacement is named above.
```

The four stages, one line each:

- **stable** — earned, not declared: `tests/scenarios/<name>.md` holds a recorded run
  (`## Scenario`, `## Baseline`, `## With skill`, `## Verdict`). Promote after the record
  exists; the gate fails the other order.
- **beta** — the default, and where all 13 skills start. The description form is a warning
  here, a failure at stable.
- **retired** — `replaced-by` naming an asset that exists and is itself not retired, plus
  `disable-model-invocation: true`.
- **rule** — a skill, never a command: `paths:` and `user-invocable: false`, so it
  lazy-loads on its globs instead of costing a chunk of every session.

Then run `tools/selfcheck.sh`, `tools/skillcheck.sh` and `tools/index.sh --write`. Selfcheck
fails on a documented name that doesn't exist, a frontmatter field Claude Code doesn't read, a
tool without a shebang, and a leftover of the old layout (a `workflows/` file, or a tool cited
by its old host path instead of `devil <name>`). Skillcheck fails on an untagged or misspelt
stage, an unquoted `since`, a description off the A14 form or over 1024 bytes, a body with no
report heading, a `/devil:<name>` reaching nothing, a stable skill with no recorded run, a
tombstone pointing nowhere, a rule skill that loads every session, and a model-invocable asset
pointing at a user-only one. `index.sh --write` regenerates the tables above from the
frontmatter you just edited, so a new asset appears in them without a hand-written row.

```sh
bash tools/selfcheck.sh
bash tools/skillcheck.sh
bash tools/index.sh --check
bash tools/caveat.sh --strict
for t in tests/test_*.sh; do bash "$t" || echo "FAILED: $t"; done
bash tools/quality.sh --no-audit
```

Keep one source of truth per concept and reference it instead of repeating it.
