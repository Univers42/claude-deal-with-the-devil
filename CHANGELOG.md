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
- `bin/devil`: one dispatcher for every tool, on the agent's PATH when the plugin is
  loaded. `devil <tool>` runs `tools/<tool>.sh`, `devil orch <sub>` the OpenCode
  orchestration scripts; an unknown name exits 2.
- selfcheck FAILs a root `workflows/` file, a tool cited by its old `.claude/tools/`
  path, and a backticked `devil <name>` citation that names no tool.
- This file.

### Changed

- The hook handler moved under `hooks/` and was split into per-phase modules in
  `hooks/scripts/` to stay under the 300-line file limit. Behaviour is identical on the
  payloads it was replayed against; details in
  [`hooks/HOOKS-README.md`](hooks/HOOKS-README.md).
- The seven workflows are commands now (`commands/<name>.md` with
  `metadata.kind: workflow`), so `/devil:deal`, `/devil:feature` and the rest load;
  a plugin never loaded the old `workflows/` directory. Every doc cites `/devil:<name>`
  and `devil <tool>` instead of `/workflow:<name>` and `.claude/tools/<tool>.sh`.
- `architect`, `benchmarker` and `devil` carry `memory: project`, which the docs already
  claimed.
- The host config moved to `templates/settings.json` and `templates/mcp.json`: a plugin
  cannot ship host permissions, and a plugin `.mcp.json` would start the memory server
  for every installer who never asked for it.
- The tool cache is written under the host's `.claude/cache/` instead of beside the
  tools, so the plugin root holds versioned source and no writable state.
- `tools/context.sh` reads descriptions through `fm_desc` and stops counting an asset
  that disables model invocation.
- The hook timeout and the briefing cut are now stated as approximations rather than
  presented as measurements.
- Tests grew with the tree: `tests/test_common.sh` for the frontmatter helpers,
  `tests/test_templates.sh` for the wizard and the hitl harness, plugin-root and
  relative-link cases in the two existing suites.
- CI validates both manifests and `./skills ./agents ./commands` with
  `claude plugin validate --strict`, checks the JSON files parse, and now runs the
  release check.

### Removed

- The root `settings.json` and `.mcp.json`. They are not deleted so much as relocated:
  a plugin may not carry them, and setup seeds them into the host.
- The `workflows/` directory; its files moved to `commands/`.

## [0.9.0] - 2026-09-29

- Last release shipped as a `.claude` submodule mounted into a host repo, with no
  versioned manifest of its own.
