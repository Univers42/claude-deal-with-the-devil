# Changelog

Every change worth releasing, in the order it shipped. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The version of record is `.claude-plugin/plugin.json`. This file repeats it as a
`## [x.y.z]` heading and must not become a second source of truth: the marketplace
manifest carries no version at all. `bash tools/release.sh --check` proves the two
agree, and `bash tools/release.sh bump <major|minor|patch>` cuts the next one.

## [Unreleased]

### Removed

- The `ponytail` tombstone skill, retired in 1.0.0 and kept one minor as announced. Use
  `caveat`; `devil caveat` still accepts the legacy `Ponytail:` marker.

### Fixed

- `devil export <harness>` rebuilds `dist/<harness>/` from scratch, so an asset deleted from
  the sources no longer leaves a stale copy behind.

## [1.0.0] - 2026-09-30

### Added

- `DEVIL_AUTONOMY=1`: an opt-in env switch for sessions run unattended. It turns the
  `PreToolUse` ask into no decision, so the irreversible defers to the session's own
  permission mode instead of prompting a session the user meant to leave alone. Only the
  exact value `1` counts, so a typo keeps the prompts; the deny patterns still refuse.
  Set it with `"env": {"DEVIL_AUTONOMY": "1"}` in the host settings
  (`hooks/HOOKS-README.md`).

- `devil export codex` (slice X4): the Codex CLI dialect, generated from the same
  Claude-format sources into `dist/codex/`. Four files: a portable Agent Plugins
  1.0 `plugin.json` (version copied from `.claude-plugin/plugin.json`, never
  written by the generator), `hooks/hooks.json` reduced to the twelve events
  Codex fires with `command` plus `args` folded into the single command string
  it runs and `${CLAUDE_PLUGIN_ROOT}` rewritten to `${PLUGIN_ROOT}`, an
  `AGENTS.md` carrying the twelve always-on rules, and the install contract.
  Skills, agents and commands are deliberately **not** generated: Codex reads a
  plugin's `skills/` natively and rewrites `commands/` into skills itself, so a
  copy would be a second copy of files the harness already reads. Measured on
  `@openai/codex` 0.159.2 in a `node:22-slim` container; the evidence is in
  `doc/HARNESSES.md`, section "codex, measured for X4".
- `devil export copilot`: the GitHub Copilot CLI target. `tools/lib/export-copilot.sh`
  writes `dist/copilot/` from the Claude sources, and `--check` is a `quality.sh`
  gate and a CI step. Four generated files, because Copilot already reads the kit's
  `skills/` and `agents/` as they are and the install symlinks those two rather
  than copying them. The four that are generated each exist because a measurement
  on 1.0.89 found a defect: 10 of the kit's 18 commands carry a `description:`
  plain scalar holding `Usage:`, which is a YAML mapping value that Copilot's
  parser rejects outright, so the descriptions are emitted as folded blocks; the
  Claude hook shape does not run, because Copilot reads `command` as a shell line
  and ignores `args`, so a `command: python3` + `args: [hooks.py]` hook runs
  `python3` with the event JSON as its program; a plugin cannot ship
  always-on instructions at all, so the 12 rules travel as a file the host copies
  to `.github/copilot-instructions.md`; and the manifest's version is copied from
  `.claude-plugin/plugin.json` so a bump that is not re-exported fails `--check`.
  Measured live: the risk gate refuses a force-push through the dist with the
  kit's own wording. Start at `dist/copilot/README.md`; the evidence is in
  `doc/HARNESSES.md`.

- `commands/wayfinder.md` (`/devil:wayfinder`): multi-session planning on the host's
  ticket tracker. The map ticket is the index (one line per ticket with its state
  and blockers, one line per unknown with the question that would clear it, one log
  line per session) and its tickets are decisions, not slices of a build, so
  `/devil:to-tickets` cuts the build from the spec once the map is clear. A session
  takes one ready ticket or one fog patch, reduces it to a fact, a decision or a
  closed ticket, updates the map and stops; it never clears two fog patches in one
  session. `templates/wayfinder-map.md` owns the map's four sections, and both
  tracker adapters gained the five wayfinding verbs (`create-map`, `read-map`,
  `list-tickets`, `claim-ticket`, `close-ticket`) with the local one keeping the
  map at `.scratch/wayfinder/map.md`.
- `templates/tracker/gitlab.md`: the GitLab adapter for `to-tickets`, the third of
  the three abstract verbs mapped onto a real tracker (`glab issue create --title
  --description --label ready-for-agent`, `glab issue list --label ready-for-agent`,
  `glab issue note` plus `glab issue close <iid>`). Every command is marked
  UNVERIFIED in the file: it was written on a host with no `glab`, so no
  `--help` output was ever read. `devil setup --tracker gitlab` seeds it, and
  setup now detects it when `glab` is installed and a remote names `gitlab.com`
  (a self-hosted GitLab reads as local until someone passes the flag; a repo with
  both remotes still gets github). The tracker stage moved to
  `tools/lib/seed-tracker.sh`, seed.sh having been at the 300-line ceiling.
  Covered by `tests/test_setup_tracker.sh`, with a negative control per case.

- `tools/index.sh`: the generator behind the README asset tables and the router.
  `--check` (the default) regenerates every block between
  `<!-- devil:index:<kind>:start -->` and `<!-- devil:index:<kind>:end -->` and
  exits 1 with a diff when one has drifted from the frontmatter; `--write`
  rewrites only those blocks, byte-identical everywhere else; `--router` prints
  the same five tables (skills, rule skills, commands, workflows, retired) to
  stdout. The "Use when" column is the text between `Use when` and
  `Auto-triggers on`, so a description off the A14 form says so in its own row.
- `commands/guide.md` (`/devil:guide`): the live index, user-only, with the tables
  injected by `devil index --router` at the moment the command runs. A generated
  router cannot quote a roster that no longer exists; the hand-kept one could, and
  did.
- The README skills, commands, workflows, retired and rule-skill tables are now
  generated (`bash tools/index.sh --write`) instead of hand-maintained, and
  `index.sh --check` runs in `quality.sh` and in CI next to `selfcheck.sh` and
  `skillcheck.sh`.
- `tools/export.sh` (`devil export <harness>`, `devil export --check <harness>`): one
  generator from the Claude-format sources to a harness dialect, with `--check` exiting 1
  on any drift and 2 on an unknown harness. `opencode` is the first target, in
  `tools/lib/export-opencode.sh`.
- `dist/gemini/` and `devil export gemini`: the Gemini CLI extension, generated from the
  same Claude sources and measured against `@google/gemini-cli` 0.62.0 in a throwaway
  container. `gemini-extension.json` with the version read from `plugin.json` at export
  time, the 12 always-on rules as its `contextFileName`, 18 commands as TOML with
  `{{args}}`, 23 skills copied verbatim, 11 sub-agents carrying only the keys Gemini's
  `.strict()` schema accepts, and `hooks/hooks.json` in Gemini's event names calling a
  generated translator that puts `hooks/scripts/hooks.py` behind Gemini's hook payload and
  answer shape. `tests/test_export_gemini.sh` runs the CLI's own `gemini extensions
  validate` in a `node:22-slim` container and SKIPs, counted and printed, when docker is
  absent. Every claim and its measurement is in `doc/HARNESSES.md`; the three known gaps
  (no post-edit gate on an edit, no session briefing, no `bin/` on `PATH`) are in
  `dist/gemini/README.md`.
- `dist/opencode/`: the OpenCode 2.x dialect, committed. 11 subagents with their Claude
  `tools:` list mapped to a V2 `permissions:` list over a deny-all base, 13 commands with
  `$ARGUMENTS` kept and `/devil:<name>` rewritten to the `/<name>` V2 registers, the 12
  always-on rules as `AGENTS.md` plus system injection, and `plugins/devil.js`, a bridge
  that runs `hooks/scripts/hooks.py` so the deny, the post-edit gate, the session briefing
  and `bin/` on the agent's `PATH` work outside Claude Code. Its
  [`README.md`](dist/opencode/README.md) is the install contract, including the paths and
  the config key the setup stage has to write.
- `tools/lib/opencode-plugin.js`: the bridge's source. Copied into `dist/`, never edited
  there. `DEVIL_BRIDGE_DEBUG=<file>` makes it log each hook it serves, because a bridge that
  fails open cannot otherwise be diagnosed.
- `tests/test_export.sh` and `tests/opencode-plugin-probe.mjs`: `--check` on the committed
  tree, a hand edit that must fail it, a fixture kit whose new assets must appear, the
  read-only permission mapping, the payload mapping and the deny decision, and a PyYAML
  parse of every generated frontmatter.
- `doc/HARNESSES.md`, section "OpenCode, measured for X1": twenty local runs that answer the
  four questions X0 left open, and corrections to five matrix cells they contradicted. The
  costliest finding is that an unterminated YAML frontmatter block makes every OpenCode agent
  come back a primary agent, silently.
- `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`: the repo root
  now loads as a plugin, `devil`, served by the self-marketplace `univers42`. Every
  asset is namespaced, so `/devil:debug` and the agent `devil:reviewer` can no longer
  be shadowed by a same-named user-level skill.
- `hooks/hooks.json`: the hook manifest a plugin actually reads, calling the handler
  through `${CLAUDE_PLUGIN_ROOT}`.
- Frontmatter helpers in `tools/lib/common.sh`: `fm_meta` for a `metadata:` map value,
  `fm_desc` for a folded or scalar `description:` on one line, and `fm_flag` for a
  top-level `true`.
- `skills/debug/scripts/hitl-loop.sh`: the person-driven reproduction harness, a step
  and a capture helper, wired into the debug skill's bisect step.
- `templates/wizard.sh`: the copy-and-fill library above a `# STAGES` marker for the
  procedures only a person runs.
- `tools/release.sh`: `--check` (the plugin version is semver and equals the first
  released heading here, the marketplace carries no version, every retired asset is
  named with its replacement) and `bump <level>`, which edits, commits
  `chore(release): vX.Y.Z`, tags, and never pushes.
- `commands/handoff.md` (`/devil:handoff`): writes a portable handoff document to
  `${TMPDIR:-/tmp}/devil-handoff-<repo>-<UTC timestamp>.md` and prints the path.
  Pointers, not copies (`file:line`, branch, `git log --oneline -10`, the commands to
  re-run, `devil digest` for the repo facts), the decisions and the open questions, a
  redaction pass that keeps secret names and drops their values, and the return block
  (`status` / `gates` / `changed` / `deviations` / `next`) at the end, which is what
  `devil orch oc-job` greps. The `PreCompact` hook now names it.
- `commands/retro.md` (`/devil:retro [<pr> | <git range>]`): reads a session or a pull
  request, lists what went wrong or cost time with the evidence that made it a
  finding, then splits them. A mechanical finding becomes a brief for the `forger`
  agent naming the check, the tool that owns the concern and the fixture that must
  fail; a judgement finding becomes a proposed one-line bullet and its target file. It
  proposes and writes nothing.
- `templates/handoff.md`: the skeleton `/devil:handoff` fills in.
- `bin/devil`: one dispatcher for every tool, on the agent's PATH when the plugin is
  loaded. `devil <tool>` runs `tools/<tool>.sh`, `devil orch <sub>` the OpenCode
  orchestration scripts; an unknown name exits 2.
- `tools/setup.sh` (`devil setup`, and `/devil:setup`): seeds into a host repo the
  three things a plugin cannot ship, in seven stages. `rules` copies the 12
  always-on rules into `.claude/rules/devil/` and stamps `.version` with the plugin
  version and a sha256 of the copy; `settings` merges `templates/settings.json` with
  the host's own file winning key by key and the permission lists unioned;
  `claude-md` keeps one block between `<!-- devil:start -->` and `<!-- devil:end -->`;
  `opencode` adds the seeded rules glob and the kit's `skills/` to a host that has an
  `opencode.json`, and writes `.claude/devil.env`; `tracker` picks the GitHub or the
  local adapter and writes `.claude/devil/tracker.md`; `mcp` is opt-in behind
  `--seed-mcp`; `gitignore` adds three lines, each at most once. No flag is a dry run,
  `--check` exits 1 when a stage is not applied, `--apply` writes, and all three take
  one code path so the check cannot disagree with the write.
- `templates/claude-md-block.md` and `templates/tracker/{github,local}.md`: the block
  setup writes into a host's `CLAUDE.md`, and the two adapters that turn the abstract
  verbs `create-ticket`, `list-ready` and `close-ticket` into `gh issue` commands or
  files under `.scratch/tickets/`.
- selfcheck FAILs a root `workflows/` file, a tool cited by its old `.claude/tools/`
  path, and a backticked `devil <name>` citation that names no tool.
- `skills/grill/` (`grill`): the frontier interview. It states what is decided and
  what is not, gathers the facts itself (`devil digest`, `devil facts`, a subagent
  for a wide search) instead of asking the user a question the repo can answer, then
  puts at most three decisions per round, each as `Q:` / `Recommended:` / `Why:` with
  a cited fact behind the recommendation. It repeats a round only while the
  done-when is unstateable or a `rules/risk.md` trigger is unresolved, and ends on
  the contract: inputs, outputs, done-when. `skills/grill/reference.md` holds the
  fact-vs-decision test with four worked examples and the question format.
  `commands/prompt.md` now routes to it from its clarification phase instead of
  saying "Don't interrogate", and its spec carries a `Seams` section: boundaries
  named by contract, never by file path.
- `skills/prototype/` (`prototype`): the spike. Question and kill criterion before
  any code (the criterion comes from the `innovator` agent when the question is a
  product bet), a throwaway worktree, every long command under `devil watch`, the
  result measured against the criterion, and an explicit keep or kill. A spike is
  never merged: keep means writing the real thing with `/devil:feature`, which
  rebuilds it test-first. `agents/innovator.md` points at it as the cheapest
  experiment for an idea.
- `tools/skillcheck.sh`: every skill and command carries `metadata.stage` (stable, beta,
  retired, rule) and a quoted `since`; stable skills need a scenario record under
  `tests/scenarios/`; a retired asset names its replacement; a user-only asset is never
  a step in a model-invoked body; descriptions are linted for form and size. A quality
  gate, a CI step, and a PostToolUse check on every kit doc edit.
- `templates/adr.md`: the Architecture Decision Record a host repo writes at
  `docs/adr/NNNN-<slug>.md`, with the three-gate rule in its comment: an ADR is
  written only when the decision is irreversible, changes a public surface, or got
  a `devil` verdict other than PROCEED. Context carries facts with `file:line`,
  alternatives carry what each option would have cost.
- `templates/out-of-scope.md`: the record for a concept the verdict rejected, at
  `.out-of-scope/<concept>.md`. The load-bearing line is the fact that would have
  to change for the answer to change, with the prior requests dated.
- `templates/agent-brief.md`: the brief a subagent receives instead of your memory
  (Objective, Contract with inputs → outputs → done-when, Constraints, Facts as
  `file:line` pointers) and the return block every job ends with, so a caller greps
  it instead of reading a log.
- The kit's own `.out-of-scope/`: `openai-sidecars.md` (hand-written per-harness
  sidecars, superseded 2026-09-30 by generated exports, the evidence in
  `doc/HARNESSES.md`), `changesets.md` (one version source in plugin.json plus the
  CHANGELOG, a bash-only kit needs no node runtime), `wizard-interactive.md` (the
  agent never runs a wizard end to end; the static trace is the only honest proof)
  and `skills-array-as-stable-set.md` (the manifest `skills` array adds to the scan
  and cannot exclude a beta skill, so the stage is shown, not enforced by omission).
- `commands/to-tickets.md` (`/devil:to-tickets <spec file | issue number>`): cuts a
  spec into vertical tracer-bullet slices, each with an objective, a done-when that is
  a command a test can run, and the blocking edges to the tickets that gate it. It
  stops rather than guess when the spec has no stateable done-when or when the host
  has no tracker configured, shows the list and the dependency order for approval
  before anything is written, then publishes in blockers-first order through the
  adapter's `create-ticket` verb, plus one map ticket listing every ticket with its
  blockers. A wide mechanical refactor is the documented exception: expand, migrate
  by blast radius, contract.
- `templates/ticket.md`: the body shape a published ticket is filled in from
  (Objective, Done when, Blocks, Seams, Notes). Both tracker adapters reference it
  instead of restating it.
- This file.

### Changed

- `devil release bump` re-exports every `dist/<harness>/` in the release commit, because
  each generated manifest copies the plugin version and its `export --check` gate would go
  red on the tag. The bump half moved to `tools/lib/release-bump.sh` (300-line limit).

- Skill descriptions follow `<what>. Use when <conditions>. Auto-triggers on: ...`.
  A skill is `stable` only with a recorded scenario in `tests/scenarios/<name>.md`
  (a run without the skill, a run with it, and a verdict naming one added behaviour
  and one thing still wrong). Promoted: `api-endpoint`, `brainstorm`, `browser-testing`,
  `caveat`, `commit-craft`, `debug`, `design-review`, `doc-sync`, `frontend`,
  `originality`, `perf-budget`. Recorded and kept `beta`: `write-test` (its approval stop
  ends an unattended run) and `context-budget` (its with-skill run was not run).

- The `devil` agent writes what its verdict owes: a `docs/adr/NNNN-<slug>.md` from
  `templates/adr.md` for a three-gate decision on BLOCK or PROCEED-WITH-CONDITIONS,
  and a `.out-of-scope/<concept>.md` from `templates/out-of-scope.md` for a concept it
  rejected. PROCEED on a reversible, private, single-module decision writes nothing: a
  record that fires on every answer trains people to skip it.
- `/devil:deal` step 6 is a path, not a paragraph: the decision log is
  `docs/adr/NNNN-<slug>.md`, and the command prints what it wrote.
- `architect` designs at least three options under different constraints (minimal,
  extensible, performance-first) and names the ADR path when the three-gate rule
  applies, or says "no ADR, below the three gates" when it does not.
- `reviewer` reports Standards and Spec as two tables that are never reranked against
  each other, and never a combined score: the axes do not share a scale, so a total
  invites a style nit to cancel a correctness blocker.
- `builder` ends every job with the return block from `templates/agent-brief.md`,
  verbatim, and a gate it could not run is a SKIP line rather than an omitted one.
- `/devil:prompt` closes with the agent brief instead of a spec section list.
- The 7 path-scoped rules (`refactor-c`, `refactor-go`, `refactor-rust`,
  `refactor-typescript`, `refactor-shell`, `api-convention`, `script-library`) are
  `skills/<name>/SKILL.md` now, tagged `metadata.stage: rule` with `paths:` on the same
  globs and `user-invocable: false`. A plugin cannot ship `.claude/rules/*.md`, and a
  skill carrying `paths:` loads on exactly the same lazy mechanism, so they still cost
  nothing until a matching file is touched. `rules/` keeps the 12 always-on
  constraints, and `tools/selfcheck.sh` fails a `globs:`/`alwaysApply:` on a skill just
  as it did on a rule.
- The hook handler moved under `hooks/` and was split into per-phase modules in
  `hooks/scripts/` to stay under the 300-line file limit. Behaviour is identical on the
  payloads it was replayed against; details in
  [`hooks/HOOKS-README.md`](hooks/HOOKS-README.md).
- The seven workflows are commands now (`commands/<name>.md` with
  `metadata.kind: workflow`), so `/devil:deal`, `/devil:feature` and the rest load;
  a plugin never loaded the old `workflows/` directory. Every doc cites `/devil:<name>`
  and `devil <tool>` instead of the old workflow slash names and `.claude/tools/<tool>.sh`.
- `architect`, `benchmarker` and `devil` carry `memory: project`, which the docs already
  claimed.
- The limitation marker is `Caveat:` (rule `rules/caveat.md`, skill `caveat`, tool
  `devil caveat`). The tool matches case-sensitively and still accepts the legacy
  `Ponytail:` marker, reported as INFO; a lowercase `ponytail:` note from another
  tool no longer silences a finding, as the case-insensitive match did.
- The host config moved to `templates/settings.json` and `templates/mcp.json`: a plugin
  cannot ship host permissions, and a plugin `.mcp.json` would start the memory server
  for every installer who never asked for it. The template's two stale allow entries,
  `Bash(.claude/tools/*.sh:*)` and `Bash(./tools/*.sh:*)`, are now the single
  `Bash(devil:*)` a host actually needs, and `Bash(devil orch:*)` is on the `ask` list
  because an orch job can commit and push.
- The SessionStart hook names the drift when a host's seeded rules predate the plugin:
  `seeded devil rules are from <old>, plugin is <new>: run /devil:setup --apply`. A
  plugin cannot ship rules, so the copy in the host would otherwise be enforced forever
  without anyone saying it was old.
- The tool cache is written under the host's `.claude/cache/` instead of beside the
  tools, so the plugin root holds versioned source and no writable state.
- The `opencode` stage of `devil setup` wires the shape OpenCode 2.x actually reads.
  It moved out of `tools/lib/seed.sh` into `tools/lib/seed-opencode.sh` and now
  merges `{"skills": ["<kit>/skills"]}` as the array V2 reads, converting a V1
  `skills.paths` object, and links one symlink per generated agent, per generated
  command and for `plugins/devil.js` under `.opencode/` instead of replacing the
  directories. A host file of the same name is left byte-identical and named in
  the report; a link into `dist/opencode/` whose target is gone is drift that
  `--check` reports and `--apply` removes; `opencode.jsonc` is `cannot` because
  jq reads JSON and not JSONC. It never writes the host's `AGENTS.md` and never
  links `.claude/skills`. The seeded `instructions` rules glob is gone from a
  host that ran the old stage, since V2 resolves nothing in that key and the
  bridge injects the rules; every other entry of it is left as the host wrote it.
- `tools/context.sh` reads descriptions through `fm_desc` and stops counting an asset
  that disables model invocation.
- The hook timeout and the briefing cut are now stated as approximations rather than
  presented as measurements.
- Tests grew with the tree: `tests/test_common.sh` for the frontmatter helpers,
  `tests/test_templates.sh` for the wizard and the hitl harness, plugin-root and
  relative-link cases in the two existing suites, and the three decision templates
  with their required headings (a copy with one heading deleted has to fail the same
  assertion, or the assertion is not a gate).
- CI validates both manifests and `./skills ./agents ./commands` with
  `claude plugin validate --strict`, checks the JSON files parse, and now runs the
  release check.

### Removed

- The root `settings.json` and `.mcp.json`. They are not deleted so much as relocated:
  a plugin may not carry them, and setup seeds them into the host.
- The `workflows/` directory; its files moved to `commands/`.
- The `ponytail` skill: retired in 1.0.0, replaced by `caveat`. A tombstone stays for one minor.

## [0.9.0] - 2026-09-29

- Last release shipped as a `.claude` submodule mounted into a host repo, with no
  versioned manifest of its own.
