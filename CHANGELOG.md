# Changelog

Every change worth releasing, in the order it shipped. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The version of record is `.claude-plugin/plugin.json`. This file repeats it as a
`## [x.y.z]` heading and must not become a second source of truth: the marketplace
manifest carries no version at all. `bash tools/release.sh --check` proves the two
agree, and `bash tools/release.sh bump <major|minor|patch>` cuts the next one.

## [Unreleased]

### Added

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
